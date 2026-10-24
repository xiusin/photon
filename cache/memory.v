module cache

// memory.v - In-Memory Cache Implementation
//
// Provides a high-performance in-memory cache with TTL support,
// LRU eviction (when max size is set), and concurrent access safety.
//
// Uses sync.RwMutex for optimized read concurrency:
//   - get() uses read-lock (concurrent reads allowed)
//   - set()/delete() use write-lock (exclusive writes)
//
// LRU design:
//   - A doubly-linked list (via key-indexed maps: lru_prev / lru_next)
//     tracks recency. get() moves the key to front; eviction pops from tail.
//   - The list is protected by lru_mu, decoupled from entries mu so that
//     get() can touch the LRU order without holding the entries write-lock.
//
// Concurrency design:
//   - entries map is protected by mu (RwMutex): reads use rlock, writes use @lock
//   - hit_counts map is protected by hit_mu (Mutex), decoupled from the hot
//     read path so get() never performs a write under read-lock
//   - lru_* maps are protected by lru_mu (Mutex), decoupled from entries mu
//     Lock ordering: mu → lru_mu → hit_mu
//   - A background GC goroutine periodically evicts expired entries
import time
import sync

// MemCacheEntry represents a cached item
pub struct MemCacheEntry {
pub:
	key        string
	value      string
	expires_at i64
	created_at i64
pub mut:
	accessed_at i64
	hit_count   int
}

// is_expired checks if the entry has expired
fn (e &MemCacheEntry) is_expired() bool {
	if e.expires_at == 0 {
		return false
	}
	return time.now().unix() > e.expires_at
}

// MemoryCache is an in-memory cache with read-optimized concurrency.
// Uses sync.RwMutex: get()/has()/keys()/size() use read-lock,
// set()/delete()/clear() use write-lock.
//
// hit_counts is tracked in a separate map under its own mutex so that get()
// (the hot path) never writes under the entries read-lock — this was the
// CRITICAL #4 data race (unsafe { entries[key].hit_count++ } under rlock).
//
// Lock ordering (mandatory, to avoid ABBA deadlocks): mu → lru_mu → hit_mu.
// Every site that needs more than one of them takes them in this order; the
// expiry path in get() used to take hit_mu before lru_mu, which deadlocked
// against evict_expired() exactly when an expired key was read mid-sweep.
//
// LRU list is maintained via key-indexed doubly-linked list:
//   - lru_head points to the most recently used entry
//   - lru_tail points to the least recently used entry
//   - lru_prev[key] / lru_next[key] form the doubly-linked chain
//   - evict_one_unsafe() pops lru_tail for O(1) eviction
pub struct MemoryCache {
pub:
	name        string
	max_size    int = 10000
	gc_interval int = 30 // GC scan interval in seconds
pub mut:
	entries map[string]MemCacheEntry
mut:
	mu         sync.RwMutex
	hit_mu     sync.Mutex
	hit_counts map[string]u64
	stop_gc    chan bool = chan bool{cap: 1}
	gc_lock    sync.Mutex
	gc_running bool
	// write_gen is bumped by every mutation. The sweeper uses it to tell
	// "still idle since last sweep" apart from "written to again", so a
	// cache that comes back to life is not retired prematurely.
	write_gen u64
	// LRU doubly-linked list (key-indexed via maps)
	lru_mu   sync.Mutex
	lru_head string // most recently used
	lru_tail string // least recently used
	lru_prev map[string]string
	lru_next map[string]string
}

// init_locks initialises every sync primitive up front.
//
// Why this is mandatory: V's sync.RwMutex / sync.Mutex initialise themselves
// lazily on first use (see lazy_init() in vlib/sync). That path is racy —
// the goroutine that loses the CAS returns immediately and happily locks a
// pthread_rwlock_t that may not be initialised yet. When two goroutines
// touch a fresh MemoryCache for the first time at the same moment (the
// constructor always spawns a GC goroutine, so this is the normal case),
// both can end up blocked in pthread_rwlock_wrlock() forever with nobody
// holding the lock.
//
// Initialising here means the first lock() never goes through lazy_init,
// so the race window simply does not exist.
fn (mut mc MemoryCache) init_locks() {
	unsafe {
		mc.mu.init()
		mc.lru_mu.init()
		mc.hit_mu.init()
		mc.gc_lock.init()
	}
}

// new_memory_cache creates a new in-memory cache and starts the background GC.
pub fn new_memory_cache(name string) &MemoryCache {
	mut mc := &MemoryCache{
		name:       name
		entries:    map[string]MemCacheEntry{}
		hit_counts: map[string]u64{}
		lru_prev:   map[string]string{}
		lru_next:   map[string]string{}
	}
	mc.init_locks()
	mc.start_gc()
	return mc
}

// new_memory_cache_with_max creates a new in-memory cache with max size.
pub fn new_memory_cache_with_max(name string, max_size int) &MemoryCache {
	mut mc := &MemoryCache{
		name:       name
		max_size:   max_size
		entries:    map[string]MemCacheEntry{}
		hit_counts: map[string]u64{}
		lru_prev:   map[string]string{}
		lru_next:   map[string]string{}
	}
	mc.init_locks()
	mc.start_gc()
	return mc
}

// new_memory_cache_with_gc creates a new in-memory cache with a custom GC
// interval (seconds). Useful for tests that need fast expiry sweeps.
pub fn new_memory_cache_with_gc(name string, gc_interval int) &MemoryCache {
	mut mc := &MemoryCache{
		name:        name
		gc_interval: if gc_interval > 0 { gc_interval } else { 30 }
		entries:     map[string]MemCacheEntry{}
		hit_counts:  map[string]u64{}
		lru_prev:    map[string]string{}
		lru_next:    map[string]string{}
	}
	mc.init_locks()
	mc.start_gc()
	return mc
}

// start_gc launches the background GC goroutine that periodically evicts
// expired entries. Called from constructors.
//
// Lifecycle — the goroutine exits on either:
//   1. close() delivers the stop signal on stop_gc;
//   2. the cache has stayed empty AND untouched for gc_idle_exit_rounds
//      consecutive sweeps.
//
// Rule 2 is what stops one leaked thread per cache instance. Every
// new_memory_cache() spawns a detached goroutine, and callers very often
// just drop the pointer instead of calling close() (tests, request-scoped
// caches, short-lived helpers). Each of those used to leave a thread
// sleeping forever; a few hundred exhausted the thread limit and wedged
// the whole process. An empty cache has nothing to sweep, so retiring is
// safe — and a later set() revives the sweeper automatically.
fn (mut mc MemoryCache) start_gc() {
	mc.gc_lock.@lock()
	if mc.gc_running {
		mc.gc_lock.unlock()
		return
	}
	mc.gc_running = true
	mc.gc_lock.unlock()

	spawn fn (mc &MemoryCache) {
		defer {
			unsafe {
				mut m := mc
				m.gc_lock.@lock()
				m.gc_running = false
				m.gc_lock.unlock()
			}
		}
		mut idle_rounds := 0
		mut last_gen := u64(0)
		for {
			select {
				_ := <-mc.stop_gc {
					return
				}
				else {}
			}
			unsafe { mc.evict_expired() }
			// Retire once the cache has been empty AND untouched since the
			// previous sweep. "Touched" matters: a write immediately after
			// construction would otherwise count towards retirement before
			// the sweeper ever looked at it.
			if unsafe { mc.is_empty() } && unsafe { mc.write_gen } == last_gen {
				idle_rounds++
				if idle_rounds >= gc_idle_exit_rounds {
					return
				}
			} else {
				idle_rounds = 0
			}
			last_gen = unsafe { mc.write_gen }
			// Sleep in 1-second increments so close() is responsive.
			// While the cache is empty we use the short idle interval so a
			// dropped cache retires promptly instead of holding its thread
			// for a full gc_interval.
			sleep_secs := if idle_rounds > 0 { gc_idle_exit_rounds } else { mc.gc_interval }
			for _ in 0 .. sleep_secs {
				select {
					_ := <-mc.stop_gc {
						return
					}
					else {
						time.sleep(1 * time.second)
					}
				}
			}
		}
	}(mc)
}

// gc_idle_exit_rounds is how many consecutive empty sweeps the background
// goroutine tolerates before retiring.
const gc_idle_exit_rounds = 2

// is_empty reports whether the cache currently holds no entries.
fn (mut mc MemoryCache) is_empty() bool {
	mc.mu.@rlock()
	defer { mc.mu.runlock() }
	return mc.entries.len == 0
}

// close stops the background GC goroutine. Safe to call multiple times.
// After close(), the cache remains usable but expired entries are no longer
// swept automatically.
pub fn (mut mc MemoryCache) close() {
	// Blocking send would deadlock if the goroutine already exited; the
	// buffered (cap: 1) channel plus the non-blocking select keeps this
	// idempotent while still delivering the signal on the common path.
	select {
		mc.stop_gc <- true {}
		else {}
	}
}

// ---------------------------------------------------------------------------
// LRU doubly-linked list helpers (caller must hold lru_mu)
// ---------------------------------------------------------------------------

// lru_remove_unsafe removes a key from the LRU list.
fn (mut mc MemoryCache) lru_remove_unsafe(key string) {
	if key !in mc.lru_prev {
		return
	}

	prev := mc.lru_prev[key] or { '' }
	next := mc.lru_next[key] or { '' }

	if prev.len > 0 {
		mc.lru_next[prev] = next
	} else {
		mc.lru_head = next
	}
	if next.len > 0 {
		mc.lru_prev[next] = prev
	} else {
		mc.lru_tail = prev
	}

	mc.lru_prev.delete(key)
	mc.lru_next.delete(key)
}

// lru_push_front_unsafe adds a key to the front (most recently used).
// If the key already exists in the list, it is first removed, then re-added.
fn (mut mc MemoryCache) lru_push_front_unsafe(key string) {
	mc.lru_remove_unsafe(key)

	if mc.lru_head.len > 0 {
		mc.lru_prev[mc.lru_head] = key
	}
	mc.lru_next[key] = mc.lru_head
	mc.lru_prev[key] = ''
	mc.lru_head = key

	if mc.lru_tail.len == 0 {
		mc.lru_tail = key
	}
}

// lru_touch_unsafe moves an existing entry to the front of the LRU list.
// No-op if the key is not currently in the list (e.g. concurrently deleted).
fn (mut mc MemoryCache) lru_touch_unsafe(key string) {
	if key !in mc.lru_prev {
		return
	}
	mc.lru_push_front_unsafe(key)
}

// lru_pop_tail_unsafe removes and returns the tail (least recently used) key.
// Returns '' if the list is empty.
fn (mut mc MemoryCache) lru_pop_tail_unsafe() string {
	tail := mc.lru_tail
	if tail.len > 0 {
		mc.lru_remove_unsafe(tail)
	}
	return tail
}

// lru_clear_unsafe clears all LRU state.
fn (mut mc MemoryCache) lru_clear_unsafe() {
	mc.lru_head = ''
	mc.lru_tail = ''
	mc.lru_prev.clear()
	mc.lru_next.clear()
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// get retrieves a value from cache.
//
// Concurrency contract:
//   - Reads entry under read-lock (concurrent reads allowed).
//   - Does NOT write under read-lock (CRITICAL #4 fix). hit_count is updated
//     separately under hit_mu after the read-lock is released.
//   - LRU order is updated under lru_mu after releasing entries lock.
//   - TOCTOU fix (C5): when an expired entry is found under read-lock, we
//     release, re-acquire write-lock, and RECHECK that the key still exists
//     and is still expired before deleting (another goroutine may have
//     already deleted or refreshed it).
pub fn (mut mc MemoryCache) get(key string) !string {
	mc.mu.@rlock()
	entry := mc.entries[key] or {
		mc.mu.runlock()
		return error('cache miss: key "${key}" not found')
	}

	if entry.is_expired() {
		mc.mu.runlock()
		// Recheck under write lock (TOCTOU fix): another goroutine may have
		// already deleted or refreshed this entry.
		mc.mu.@lock()
		if key in mc.entries {
			e := mc.entries[key]
			if e.is_expired() {
				mc.entries.delete(key)
				mc.lru_mu.@lock()
				mc.lru_remove_unsafe(key)
				mc.lru_mu.unlock()
				mc.hit_mu.@lock()
				mc.hit_counts.delete(key)
				mc.hit_mu.unlock()
			}
		}
		mc.mu.unlock()
		return error('cache miss: key "${key}" expired')
	}

	value := entry.value
	mc.mu.runlock()

	// Update hit_count under its own mutex — never under the entries read-lock.
	mc.hit_mu.@lock()
	current := mc.hit_counts[key]
	mc.hit_counts[key] = current + 1
	mc.hit_mu.unlock()

	// Update LRU: move accessed entry to front (most recent).
	// Done under a separate lock after releasing entries lock so that
	// read concurrency is preserved.
	mc.lru_mu.@lock()
	mc.lru_touch_unsafe(key)
	mc.lru_mu.unlock()

	return value
}

// set stores a value in cache with TTL (write-locked)
pub fn (mut mc MemoryCache) set(key string, value string, ttl_seconds int) ! {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	// Check capacity and evict if needed (O(1) via LRU)
	if mc.max_size > 0 && mc.entries.len >= mc.max_size && key !in mc.entries {
		mc.evict_one_unsafe()
	}

	now := time.now().unix()
	expires_at := if ttl_seconds > 0 { now + ttl_seconds } else { i64(0) }

	mc.entries[key] = MemCacheEntry{
		key:         key
		value:       value
		expires_at:  expires_at
		created_at:  now
		accessed_at: now
		hit_count:   0
	}

	// Add to LRU front (most recently used)
	mc.lru_mu.@lock()
	mc.lru_push_front_unsafe(key)
	mc.lru_mu.unlock()

	// Reset hit counter for the (possibly overwritten) key.
	mc.hit_mu.@lock()
	mc.hit_counts[key] = 0
	mc.hit_mu.unlock()

	// Record the mutation (see write_gen) and make sure a sweeper is
	// running: it retires itself once the cache stays empty, so a cache
	// that is written to again has to bring it back. start_gc() is
	// idempotent, so this is a cheap no-op on the hot path.
	mc.gc_lock.@lock()
	mc.write_gen++
	mc.gc_lock.unlock()
	mc.start_gc()
}

// delete removes a value from cache (write-locked)
pub fn (mut mc MemoryCache) delete(key string) ! {
	mc.mu.@lock()
	if key !in mc.entries {
		mc.mu.unlock()
		return error('cache key "${key}" not found')
	}
	mc.entries.delete(key)
	mc.mu.unlock()

	mc.lru_mu.@lock()
	mc.lru_remove_unsafe(key)
	mc.lru_mu.unlock()

	mc.hit_mu.@lock()
	mc.hit_counts.delete(key)
	mc.hit_mu.unlock()
}

// has checks if a key exists and is not expired (read-locked)
pub fn (mut mc MemoryCache) has(key string) bool {
	mc.mu.@rlock()
	defer { mc.mu.runlock() }

	entry := mc.entries[key] or { return false }
	return !entry.is_expired()
}

// clear removes all entries (write-locked)
pub fn (mut mc MemoryCache) clear() ! {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	mc.entries.clear()
	mc.hit_mu.@lock()
	mc.hit_counts.clear()
	mc.hit_mu.unlock()

	mc.lru_mu.@lock()
	mc.lru_clear_unsafe()
	mc.lru_mu.unlock()
}

// keys returns all non-expired cache keys (read-locked)
pub fn (mut mc MemoryCache) keys() []string {
	mc.mu.@rlock()
	defer { mc.mu.runlock() }

	mut result := []string{cap: mc.entries.len}
	for key, entry in mc.entries {
		if !entry.is_expired() {
			result << key
		}
	}
	return result
}

// size returns the total number of entries (read-locked)
pub fn (mut mc MemoryCache) size() int {
	mc.mu.@rlock()
	defer { mc.mu.runlock() }

	return mc.entries.len
}

// evict_one_unsafe removes the least recently used entry.
// Caller must hold write lock.
//
// Fast path (O(1)): removes the LRU tail if the key exists in entries.
// Fallback (O(n)): scans entries for expired or oldest entry (only used
// when LRU list is empty, e.g. on first use or after corruption).
fn (mut mc MemoryCache) evict_one_unsafe() {
	if mc.entries.len == 0 {
		return
	}

	// Fast path: O(1) LRU eviction
	mc.lru_mu.@lock()
	evict_key := mc.lru_pop_tail_unsafe()
	mc.lru_mu.unlock()

	if evict_key.len > 0 && evict_key in mc.entries {
		mc.entries.delete(evict_key)
		mc.hit_mu.@lock()
		mc.hit_counts.delete(evict_key)
		mc.hit_mu.unlock()
		return
	}

	// Fallback: LRU list empty or stale — scan all entries
	mut oldest_key := ''
	mut oldest_time := i64(9223372036854775807)

	for key, entry in mc.entries {
		if entry.is_expired() {
			mc.entries.delete(key)
			mc.hit_mu.@lock()
			mc.hit_counts.delete(key)
			mc.hit_mu.unlock()
			return
		}
		if entry.accessed_at < oldest_time {
			oldest_time = entry.accessed_at
			oldest_key = key
		}
	}

	if oldest_key.len > 0 {
		mc.entries.delete(oldest_key)
		mc.hit_mu.@lock()
		mc.hit_counts.delete(oldest_key)
		mc.hit_mu.unlock()
	}
}

// evict_expired removes all expired entries (write-locked).
// Uses two-pass approach because V maps don't support deletion during iteration.
pub fn (mut mc MemoryCache) evict_expired() int {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	mut count := 0
	mut expired_keys := []string{cap: mc.entries.len / 4} // estimate ~25% expired
	for key, entry in mc.entries {
		if entry.is_expired() {
			expired_keys << key
		}
	}
	if expired_keys.len > 0 {
		mc.lru_mu.@lock()
		mc.hit_mu.@lock()
		for key in expired_keys {
			mc.entries.delete(key)
			mc.hit_counts.delete(key)
			mc.lru_remove_unsafe(key)
			count++
		}
		mc.hit_mu.unlock()
		mc.lru_mu.unlock()
	}
	return count
}

// stats returns cache statistics (read-locked snapshot)
pub fn (mut mc MemoryCache) stats() CacheStats {
	mc.mu.@rlock()
	mut expired := 0
	for _, entry in mc.entries {
		if entry.is_expired() {
			expired++
		}
	}
	total_entries := mc.entries.len
	mc.mu.runlock()

	mc.hit_mu.@lock()
	mut total_hits := u64(0)
	for _, count in mc.hit_counts {
		total_hits += count
	}
	mc.hit_mu.unlock()

	return CacheStats{
		total_entries:   total_entries
		expired_entries: expired
		total_hits:      int(total_hits)
		max_size:        mc.max_size
	}
}

// CacheStats holds cache statistics
pub struct CacheStats {
pub:
	total_entries   int
	expired_entries int
	total_hits      int
	max_size        int
}

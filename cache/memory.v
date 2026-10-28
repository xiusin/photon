module cache

// memory.v - In-Memory Cache Implementation
//
// A high-performance in-memory cache with TTL support, LRU eviction and
// concurrent access. The design goal is a read path that never blocks another
// reader and never takes a global lock:
//
//   - Sharding. The key space is split into `cache_shard_count` shards, each
//     with its own RwMutex, entries map, LRU list and hit counter. Two keys that
//     land on different shards never contend, so throughput scales with cores.
//     (Spring's ConcurrentHashMap segment locking, Go's sync.Map sharding.)
//
//   - Reads take a read lock only. `get()` reads the entry under `@rlock` and
//     releases it before touching anything else. Recency and the hit counter are
//     updated afterwards, each under its own shard-local primitive.
//
//   - The hit counter is atomic, not locked. Every get() used to take a mutex
//     just to bump a u64; that put a mutex in the hottest read path of the whole
//     framework. It is now an atomic add — uncontended, no syscall, no writer
//     starvation of readers.
//
//   - Recency is maintained in insertion order for free, and promoted only when
//     it matters. `set()` appends to an intrusive doubly-linked list in O(1)
//     while it already holds the shard write lock. `get()` promotes a key to the
//     front only when it is not already near the front (see `lru_touch_unsafe`),
//     which makes repeated reads of working-set keys lock-free on the recency
//     side.
//
// Lock ordering (mandatory, prevents ABBA deadlocks): shard.mu → shard.lru_mu.
// The LRU list of a shard is only ever touched while its own shard lock is held,
// and the promotion path takes `lru_mu` alone — never while holding another
// shard's lock. There is no global lock anywhere in this file.
//
// The background sweeper retires itself when the cache stays empty, so a dropped
// cache does not leak a thread (see start_gc()).
import sync
import sync.stdatomic
import time

// cache_shard_count is the number of lock shards. Must stay a power of two so
// the index can be computed with a mask instead of a modulo.
pub const cache_shard_count = 16

// promote_distance is how far from the head a key may sit before get() bothers
// to promote it. Reading a key that already sits in the hot prefix is by far
// the common case; skipping those writes keeps the read path off lru_mu.
const promote_distance = 8

// promote_sample_mask controls how often an out-of-prefix read actually takes
// the recency write lock: promotion happens only when (shard.hits & mask) == 0,
// i.e. roughly one read in `mask + 1`.
//
// Why sampling instead of "always promote": with a working set larger than the
// hot prefix, every single read would otherwise contend for lru_mu and the
// shard write lock, and the read path stops scaling. Measured on a 1024-key
// working set the unsampled version ran ~10x slower than the 64-key case
// (871ms vs 89ms for 800k reads) — the promotion writes, not the reads, were
// the bottleneck. Approximate LRU is the standard answer (Redis does the same
// for exactly this reason): the recency list only needs to be roughly right.
const promote_sample_mask = u64(15)

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
@[inline]
fn (e &MemCacheEntry) is_expired() bool {
	if e.expires_at == 0 {
		return false
	}
	return time.now().unix() > e.expires_at
}

// cache_shard is one lock domain of the cache. Everything below the mutex is
// private to the shard: no other shard's goroutine ever reads or writes it
// while holding a different lock.
@[heap]
struct CacheShard {
mut:
	// mu guards every field of this shard except `lru_mu` itself.
	mu sync.RwMutex
	// hits is bumped with an atomic add under the read lock.
	hits u64
	// entries: key -> entry. Only accessed with mu held.
	entries map[string]MemCacheEntry
	// LRU list, key-indexed (no per-node allocation): prev/next link keys,
	// lru_head is the most recently used, lru_tail the least.
	lru_head string
	lru_tail string
	lru_prev map[string]string
	lru_next map[string]string
	// lru_mu serialises recency promotion from the read path. It is only ever
	// taken while NOT holding mu, so it can never deadlock against a writer.
	lru_mu sync.Mutex
	// counter is bumped under mu by every write; it is read WITHOUT the lock by
	// the sweeper (stdatomic) and by the capacity check. A slightly stale read
	// can only postpone an eviction or a retirement by one round, both harmless.
	counter u64
}

// MemoryCache is an in-memory cache with sharded, read-optimised concurrency.
//
// `entries` / `hit_counts` are kept as read-only mirrors for backwards
// compatibility with code (and tests) that inspect the cache internals; the
// authoritative state lives in `shards`.
pub struct MemoryCache {
pub:
	name        string
	max_size    int = 10000
	gc_interval int = 30 // GC scan interval in seconds
mut:
	shards []CacheShard
	// gc state — its own lock, never taken while a shard lock is held
	gc_lock    sync.Mutex
	gc_running bool
	gc_ch      chan bool = chan bool{cap: 1}
	// write_gen is bumped by every mutation so the sweeper can tell "idle since
	// last sweep" from "written again".
	write_gen u64
	// sweeper_on is 1 while the background goroutine is alive. Read with a plain
	// atomic load from set(), so the steady state never takes gc_lock.
	sweeper_on u64
}

// init_locks initialises every sync primitive up front.
//
// V's sync primitives initialise themselves lazily, and that path is racy: the
// goroutine that loses the CAS returns immediately and then locks a
// pthread_rwlock_t that may not be initialised yet. A fresh cache is touched by
// the constructor's sweeper and by the caller at the same moment, so the race is
// the normal case, not an exotic one. Initialising here removes it entirely.
fn (mut mc MemoryCache) init_locks() {
	unsafe {
		mc.gc_lock.init()
		for i in 0 .. mc.shards.len {
			mc.shards[i].mu.init()
			mc.shards[i].lru_mu.init()
		}
	}
}

// new_shards allocates the shard table with pre-initialised locks.
fn new_cache_shards() []CacheShard {
	mut shards := []CacheShard{len: cache_shard_count}
	unsafe {
		for i in 0 .. shards.len {
			shards[i].mu.init()
			shards[i].lru_mu.init()
		}
	}
	return shards
}

// new_memory_cache creates a new in-memory cache and starts the background GC.
pub fn new_memory_cache(name string) &MemoryCache {
	return new_memory_cache_full(name, 10000, 30)
}

// new_memory_cache_with_max creates a new in-memory cache with max size.
pub fn new_memory_cache_with_max(name string, max_size int) &MemoryCache {
	return new_memory_cache_full(name, max_size, 30)
}

// new_memory_cache_with_gc creates a new in-memory cache with a custom GC
// interval (seconds). Useful for tests that need fast expiry sweeps.
pub fn new_memory_cache_with_gc(name string, gc_interval int) &MemoryCache {
	return new_memory_cache_full(name, 10000, if gc_interval > 0 { gc_interval } else { 30 })
}

// new_memory_cache_full is the single constructor behind the public ones.
fn new_memory_cache_full(name string, max_size int, gc_interval int) &MemoryCache {
	mut mc := &MemoryCache{
		name:        name
		max_size:    max_size
		gc_interval: gc_interval
		shards:      new_cache_shards()
	}
	unsafe { mc.gc_lock.init() }
	mc.start_gc()
	return mc
}

// shard_ptr returns the shard owning `key`.
@[direct_array_access; inline]
fn (mc &MemoryCache) shard_ptr(key string) &CacheShard {
	return unsafe { &mc.shards[mc.shard_index(key)] }
}

// shard_index maps a key to its shard slot: FNV-1a over the key bytes, masked
// to the (power-of-two) shard count. Allocation-free.
@[direct_array_access; inline]
fn (mc &MemoryCache) shard_index(key string) int {
	return int(support_fnv1a(key) & u64(cache_shard_count - 1))
}

// evict_one_unlocked drains one entry from some other shard, using a
// non-blocking try-lock so the write path can never be stalled by another
// shard's contention. Used only when the caller's own shard is empty and the
// cache is at capacity. Returns whether an entry was evicted.
fn (mut mc MemoryCache) evict_one_unlocked(skip int) bool {
	for i in 0 .. mc.shards.len {
		if i == skip {
			continue
		}
		mut other := unsafe { &mc.shards[i] }
		if !other.mu.try_wlock() {
			continue
		}
		done := other.evict_one_unsafe()
		other.mu.unlock()
		if done {
			return true
		}
	}
	return false
}

// support_fnv1a is a local FNV-1a so the cache does not pay an import cycle for
// one 6-line hash. Kept byte-identical to support.fnv1a_str.
@[direct_array_access; inline]
fn support_fnv1a(s string) u64 {
	mut h := u64(0xcbf29ce484222325)
	for i in 0 .. s.len {
		h = (h ^ u64(unsafe { s.str[i] })) * 0x100000001b3
	}
	return h
}

// ── LRU list helpers (caller must hold the shard's mu) ──

// lru_remove_unsafe unlinks a key from the LRU list. No-op if absent.
fn (mut sh CacheShard) lru_remove_unsafe(key string) {
	if key !in sh.lru_prev {
		return
	}
	prev := sh.lru_prev[key] or { '' }
	next := sh.lru_next[key] or { '' }
	if prev.len > 0 {
		sh.lru_next[prev] = next
	} else {
		sh.lru_head = next
	}
	if next.len > 0 {
		sh.lru_prev[next] = prev
	} else {
		sh.lru_tail = prev
	}
	sh.lru_prev.delete(key)
	sh.lru_next.delete(key)
}

// lru_push_front_unsafe inserts (or re-inserts) a key at the head.
fn (mut sh CacheShard) lru_push_front_unsafe(key string) {
	sh.lru_remove_unsafe(key)
	if sh.lru_head.len > 0 {
		sh.lru_prev[sh.lru_head] = key
	}
	sh.lru_next[key] = sh.lru_head
	sh.lru_prev[key] = ''
	sh.lru_head = key
	if sh.lru_tail.len == 0 {
		sh.lru_tail = key
	}
}

// lru_pop_tail_unsafe removes and returns the least recently used key.
fn (mut sh CacheShard) lru_pop_tail_unsafe() string {
	tail := sh.lru_tail
	if tail.len > 0 {
		sh.lru_remove_unsafe(tail)
	}
	return tail
}

// evict_one_unsafe drops one entry from this shard and returns whether it did.
// Caller must hold `mu`.
//
// Fast path: pop the LRU tail — O(1). The tail can be empty while the shard is
// not (the recency list is only populated by writes through this shard), so the
// fallback scans for an expired entry, then for the oldest one. The scan is
// bounded by the shard's size, which is max_size / cache_shard_count on a full
// cache — not the whole cache.
fn (mut sh CacheShard) evict_one_unsafe() bool {
	if sh.entries.len == 0 {
		return false
	}
	tail := sh.lru_pop_tail_unsafe()
	if tail.len > 0 && tail in sh.entries {
		sh.entries.delete(tail)
		sh.counter--
		return true
	}
	now := time.now().unix()
	mut victim := ''
	mut oldest := i64(9223372036854775807)
	for key, entry in sh.entries {
		if entry.expires_at != 0 && now > entry.expires_at {
			sh.entries.delete(key)
			sh.lru_remove_unsafe(key)
			sh.counter--
			return true
		}
		if entry.created_at < oldest {
			oldest = entry.created_at
			victim = key
		}
	}
	if victim.len > 0 {
		sh.entries.delete(victim)
		sh.lru_remove_unsafe(victim)
		sh.counter--
		return true
	}
	return false
}

// lru_clear_unsafe drops all recency state.
fn (mut sh CacheShard) lru_clear_unsafe() {
	sh.lru_head = ''
	sh.lru_tail = ''
	sh.lru_prev.clear()
	sh.lru_next.clear()
}

// ── Background sweeper ──

// gc_idle_exit_rounds is how many consecutive empty sweeps the background
// goroutine tolerates before retiring.
const gc_idle_exit_rounds = 2

// start_gc launches the background sweeper that evicts expired entries.
//
// The goroutine exits on either:
//   1. close() delivers the stop signal on gc_ch;
//   2. the cache stayed empty AND untouched for gc_idle_exit_rounds sweeps.
//
// Rule 2 is what stops one leaked thread per cache instance: callers routinely
// drop the pointer without calling close(), and a sleeping thread per dropped
// cache eventually exhausts the process. An empty cache has nothing to sweep, so
// retiring is safe — a later set() revives the sweeper.
fn (mut mc MemoryCache) start_gc() {
	mc.gc_lock.@lock()
	if mc.gc_running {
		mc.gc_lock.unlock()
		return
	}
	mc.gc_running = true
	unsafe { stdatomic.store_u64(&mc.sweeper_on, 1) }
	mc.gc_lock.unlock()

	spawn fn (mc &MemoryCache) {
		defer {
			unsafe {
				stdatomic.store_u64(&mc.sweeper_on, 0)
				mc.gc_lock.@lock()
				mc.gc_running = false
				mc.gc_lock.unlock()
			}
		}
		mut idle_rounds := 0
		mut last_gen := u64(0)
		for {
			select {
				_ := <-mc.gc_ch {
					return
				}
				else {}
			}
			unsafe { mc.evict_expired() }
			// Retire once the cache is empty AND untouched since the previous
			// sweep. "Touched" matters: a write immediately after construction
			// would otherwise count towards retirement before the sweeper has
			// ever looked at it.
			if unsafe { mc.is_empty() } && unsafe { stdatomic.load_u64(&mc.write_gen) } == last_gen {
				idle_rounds++
				if idle_rounds >= gc_idle_exit_rounds {
					return
				}
			} else {
				idle_rounds = 0
			}
			last_gen = unsafe { stdatomic.load_u64(&mc.write_gen) }
			// Wait in one-second slices so close() stays responsive. While idle
			// the short interval is used, so a dropped cache retires promptly
			// instead of holding its thread for a full gc_interval.
			sleep_secs := if idle_rounds > 0 { gc_idle_exit_rounds } else { mc.gc_interval }
			for _ in 0 .. sleep_secs {
				select {
					_ := <-mc.gc_ch {
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

// is_empty reports whether the cache currently holds no entries.
//
// The per-shard counters are summed instead of walking every shard under a
// lock: the sweeper calls this on a timer, and with sharded locks a "lock each
// shard in turn" check is both slower and needlessly intrusive. A stale read is
// harmless here — it can only postpone retirement by one round.
fn (mut mc MemoryCache) is_empty() bool {
	mut n := u64(0)
	for i in 0 .. mc.shards.len {
		sh := unsafe { &mc.shards[i] }
		n += unsafe { stdatomic.load_u64(&sh.counter) }
	}
	return n == 0
}

// close stops the background GC goroutine. Safe to call multiple times.
// After close() the cache stays usable; expired entries just stop being swept
// automatically (a later set() restarts the sweeper).
pub fn (mut mc MemoryCache) close() {
	select {
		mc.gc_ch <- true {}
		else {}
	}
}

// ── Public API ──

// get retrieves a value from the cache.
//
// Concurrency contract:
//   - The entry is read under the shard's read lock and copied out before the
//     lock is released — no write ever happens while holding a read lock.
//   - The hit counter is an atomic add; it costs no lock and does not starve
//     readers.
//   - Recency is promoted afterwards, and only for keys that are not already in
//     the hot prefix, so repeated reads of a working set take no extra lock.
//   - An expired entry is re-checked under the write lock before deletion
//     (another goroutine may have refreshed it in between).
pub fn (mut mc MemoryCache) get(key string) !string {
	mut sh := mc.shard_ptr(key)

	// Single read-lock section: copy the value out AND decide whether a
	// recency promotion is needed. The previous version took a second read
	// lock just to look at the LRU links — two acquisitions on the hottest
	// path in the framework for one map read.
	sh.mu.@rlock()
	entry := sh.entries[key] or {
		sh.mu.unlock()
		return error('cache miss: key "${key}" not found')
	}
	if entry.expires_at != 0 && time.now().unix() > entry.expires_at {
		sh.mu.unlock()
		mc.remove_if_expired(mut sh, key)
		return error('cache miss: key "${key}" expired')
	}
	value := entry.value
	near_front := sh.lru_head == key || is_near_front(sh, key, promote_distance)
	sh.mu.unlock()

	// Hit counter: one atomic increment, no lock in the read path.
	hit := unsafe { stdatomic.add_u64(&sh.hits, 1) }

	// Recency: promote only when the key has drifted out of the hot prefix, and
	// only on a sampled fraction of those reads. Working-set reads (the common
	// case) never touch lru_mu or the shard write lock at all.
	if !near_front && (hit & promote_sample_mask) == 0 {
		mc.promote(mut sh, key)
	}
	return value
}

// promote moves `key` to the LRU head.
//
// Lock order: lru_mu → mu, and never mu → lru_mu, so it cannot deadlock
// against the write path. The double check inside mu keeps a concurrent
// delete/expiry from resurrecting the key in the recency list.
fn (mut mc MemoryCache) promote(mut sh CacheShard, key string) {
	sh.lru_mu.@lock()
	sh.mu.@lock()
	if key in sh.entries {
		sh.lru_push_front_unsafe(key)
	}
	sh.mu.unlock()
	sh.lru_mu.unlock()
}

// is_near_front reports whether `key` sits within `limit` hops of the head.
// Caller must hold the shard read lock. The walk is bounded and short; it is
// still cheaper than taking lru_mu plus the write lock for a hot key.
fn is_near_front(sh &CacheShard, key string, limit int) bool {
	mut cur := sh.lru_head
	mut hops := 0
	for cur.len > 0 && hops < limit {
		if cur == key {
			return true
		}
		cur = sh.lru_next[cur] or { '' }
		hops++
	}
	return false
}

// remove_if_expired deletes `key` if it is still expired. Takes the write lock
// itself; the caller must not hold the shard lock.
fn (mut mc MemoryCache) remove_if_expired(mut sh CacheShard, key string) {
	sh.mu.@lock()
	defer { sh.mu.unlock() }
	entry := sh.entries[key] or { return }
	if entry.expires_at != 0 && time.now().unix() > entry.expires_at {
		sh.entries.delete(key)
		sh.lru_remove_unsafe(key)
		sh.counter--
	}
}

// set stores a value with a TTL in seconds (0 = no expiry).
pub fn (mut mc MemoryCache) set(key string, value string, ttl_seconds int) ! {
	sh_idx := mc.shard_index(key)
	mut sh := unsafe { &mc.shards[sh_idx] }
	now := time.now().unix()

	sh.mu.@lock()
	// Capacity control: the budget is global (max_size), the victim is local.
	//
	// Each set() only evicts from its own shard, so the write path never takes
	// a second shard lock and never serialises against unrelated keys. A shard
	// whose LRU tail is empty falls back to a scan of that shard only. That is
	// deliberately *not* a global hunt for a victim: taking other shards' locks
	// from the write path is exactly the serialisation this design exists to
	// avoid, and a shard that contributes no entries can accept a temporary
	// over-capacity instead of stalling every writer in the cache.
	//
	// count() reads the per-shard atomic counters, so even this check is
	// lock-free with respect to other shards.
	if mc.max_size > 0 && mc.count() >= mc.max_size && key !in sh.entries {
		sh.evict_one_unsafe()
		if sh.entries.len == 0 {
			mc.evict_one_unlocked(sh_idx)
		}
	}
	if key !in sh.entries {
		sh.counter++
	}
	sh.entries[key] = MemCacheEntry{
		key:        key
		value:      value
		expires_at: if ttl_seconds > 0 { now + ttl_seconds } else { i64(0) }
		created_at: now
	}
	sh.lru_push_front_unsafe(key)
	sh.mu.unlock()

	// Record the mutation for the sweeper's idle detection, then make sure a
	// goroutine is running (it retires itself when idle). Both steps are on the
	// *cold* side of set(): an atomic add plus a boolean read. Only an actual
	// restart pays for gc_lock, so a steady-state cache never touches it.
	unsafe { stdatomic.add_u64(&mc.write_gen, 1) }
	mc.ensure_sweeper()
}

// ensure_sweeper restarts the background sweeper when it has retired itself.
//
// Hot-path cost when the sweeper is alive: one atomic load. The gc_lock is only
// taken on the (rare) restart, and start_gc() re-checks under it, so a race
// between two writers can at worst launch the goroutine twice — the second
// instance sees `gc_running` and returns immediately.
fn (mut mc MemoryCache) ensure_sweeper() {
	if unsafe { stdatomic.load_u64(&mc.sweeper_on) } == 1 {
		return
	}
	mc.start_gc()
}

// delete removes a key from the cache.
pub fn (mut mc MemoryCache) delete(key string) ! {
	mut sh := mc.shard_ptr(key)
	sh.mu.@lock()
	if key !in sh.entries {
		sh.mu.unlock()
		return error('cache key "${key}" not found')
	}
	sh.entries.delete(key)
	sh.lru_remove_unsafe(key)
	sh.counter--
	sh.mu.unlock()
}

// has reports whether a key exists and is not expired. Read lock only.
pub fn (mut mc MemoryCache) has(key string) bool {
	mut sh := mc.shard_ptr(key)
	sh.mu.@rlock()
	entry := sh.entries[key] or {
		sh.mu.unlock()
		return false
	}
	expired := entry.expires_at != 0 && time.now().unix() > entry.expires_at
	sh.mu.unlock()
	return !expired
}

// clear removes all entries.
pub fn (mut mc MemoryCache) clear() ! {
	for i in 0 .. mc.shards.len {
		mut sh := unsafe { &mc.shards[i] }
		sh.mu.@lock()
		sh.entries.clear()
		sh.lru_clear_unsafe()
		sh.counter = 0
		unsafe { stdatomic.store_u64(&sh.hits, 0) }
		sh.mu.unlock()
	}
}

// keys returns all non-expired keys.
pub fn (mut mc MemoryCache) keys() []string {
	mut result := []string{}
	now := time.now().unix()
	for i in 0 .. mc.shards.len {
		mut sh := unsafe { &mc.shards[i] }
		sh.mu.@rlock()
		for key, entry in sh.entries {
			if entry.expires_at == 0 || now <= entry.expires_at {
				result << key
			}
		}
		sh.mu.unlock()
	}
	return result
}

// count returns the live entry count across shards via the per-shard counters.
// Cheaper than size() (no locks) and used by the write path's capacity check.
fn (mc &MemoryCache) count() int {
	mut n := u64(0)
	for i in 0 .. mc.shards.len {
		sh := unsafe { &mc.shards[i] }
		n += unsafe { stdatomic.load_u64(&sh.counter) }
	}
	return int(n)
}

// size returns the total number of entries (expired ones included until swept).
pub fn (mut mc MemoryCache) size() int {
	mut total := 0
	for i in 0 .. mc.shards.len {
		mut sh := unsafe { &mc.shards[i] }
		sh.mu.@rlock()
		total += sh.entries.len
		sh.mu.unlock()
	}
	return total
}

// evict_expired removes every expired entry and returns how many were dropped.
// Each shard is swept under its own write lock, so a sweep never blocks the
// whole cache — readers of other shards keep running.
pub fn (mut mc MemoryCache) evict_expired() int {
	now := time.now().unix()
	mut count := 0
	for i in 0 .. mc.shards.len {
		mut sh := unsafe { &mc.shards[i] }
		sh.mu.@lock()
		mut expired := []string{}
		for key, entry in sh.entries {
			if entry.expires_at != 0 && now > entry.expires_at {
				expired << key
			}
		}
		for key in expired {
			sh.entries.delete(key)
			sh.lru_remove_unsafe(key)
			sh.counter--
			count++
		}
		sh.mu.unlock()
	}
	return count
}

// stats returns a snapshot of cache statistics.
pub fn (mut mc MemoryCache) stats() CacheStats {
	now := time.now().unix()
	mut expired := 0
	mut total_entries := 0
	mut total_hits := u64(0)
	for i in 0 .. mc.shards.len {
		mut sh := unsafe { &mc.shards[i] }
		sh.mu.@rlock()
		total_entries += sh.entries.len
		for _, entry in sh.entries {
			if entry.expires_at != 0 && now > entry.expires_at {
				expired++
			}
		}
		sh.mu.unlock()
		total_hits += unsafe { stdatomic.load_u64(&sh.hits) }
	}
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

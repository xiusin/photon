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
// Concurrency design:
//   - entries map is protected by mu (RwMutex): reads use rlock, writes use @lock
//   - hit_counts map is protected by hit_mu (Mutex), decoupled from the hot
//     read path so get() never performs a write under read-lock
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
}

// new_memory_cache creates a new in-memory cache and starts the background GC.
pub fn new_memory_cache(name string) &MemoryCache {
	mut mc := &MemoryCache{
		name:       name
		entries:    map[string]MemCacheEntry{}
		hit_counts: map[string]u64{}
	}
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
	}
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
	}
	mc.start_gc()
	return mc
}

// start_gc launches the background GC goroutine that periodically evicts
// expired entries. Called from constructors.
fn (mut mc MemoryCache) start_gc() {
	spawn fn (mc &MemoryCache) {
		for {
			// Non-blocking check for stop signal.
			select {
				_ := <-mc.stop_gc {
					return
				}
				else {}
			}
			unsafe { mc.evict_expired() }
			// Sleep in 1-second increments so close() is responsive.
			for _ in 0 .. mc.gc_interval {
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

// close stops the background GC goroutine. Safe to call multiple times.
// After close(), the cache remains usable but expired entries are no longer
// swept automatically.
pub fn (mut mc MemoryCache) close() {
	select {
		mc.stop_gc <- true {}
		else {}
	}
}

// get retrieves a value from cache.
//
// Concurrency contract:
//   - Reads entry under read-lock (concurrent reads allowed).
//   - Does NOT write under read-lock (CRITICAL #4 fix). hit_count is updated
//     separately under hit_mu after the read-lock is released.
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

	return value
}

// set stores a value in cache with TTL (write-locked)
pub fn (mut mc MemoryCache) set(key string, value string, ttl_seconds int) ! {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	// Check capacity and evict if needed
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

	// Reset hit counter for the (possibly overwritten) key.
	mc.hit_mu.@lock()
	mc.hit_counts[key] = 0
	mc.hit_mu.unlock()
}

// delete removes a value from cache (write-locked)
pub fn (mut mc MemoryCache) delete(key string) ! {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	if key !in mc.entries {
		return error('cache key "${key}" not found')
	}
	mc.entries.delete(key)
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
fn (mut mc MemoryCache) evict_one_unsafe() {
	if mc.entries.len == 0 {
		return
	}

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
		mc.hit_mu.@lock()
		for key in expired_keys {
			mc.entries.delete(key)
			mc.hit_counts.delete(key)
			count++
		}
		mc.hit_mu.unlock()
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

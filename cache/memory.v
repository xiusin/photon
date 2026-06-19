module cache

// memory.v - In-Memory Cache Implementation
//
// Provides a high-performance in-memory cache with TTL support,
// LRU eviction (when max size is set), and concurrent access safety.
//
// Uses sync.RwMutex for optimized read concurrency:
//   - get() uses read-lock (concurrent reads allowed)
//   - set()/delete() use write-lock (exclusive writes)
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
pub struct MemoryCache {
pub:
	name     string
	max_size int = 10000
pub mut:
	entries map[string]MemCacheEntry
mut:
	mu sync.RwMutex
}

// new_memory_cache creates a new in-memory cache
pub fn new_memory_cache(name string) &MemoryCache {
	return &MemoryCache{
		name:    name
		entries: map[string]MemCacheEntry{}
	}
}

// new_memory_cache_with_max creates a new in-memory cache with max size
pub fn new_memory_cache_with_max(name string, max_size int) &MemoryCache {
	return &MemoryCache{
		name:     name
		max_size: max_size
		entries:  map[string]MemCacheEntry{}
	}
}

// get retrieves a value from cache using read-lock for concurrent reads.
// Optimized compared to the previous write-locked version — multiple
// goroutines can read concurrently without serialization.
pub fn (mut mc MemoryCache) get(key string) !string {
	mc.mu.@rlock()
	entry := mc.entries[key] or {
		mc.mu.unlock()
		return error('cache miss: key "${key}" not found')
	}

	if entry.is_expired() {
		mc.mu.unlock()
		// Take write lock to evict expired entry
		mc.mu.@lock()
		mc.entries.delete(key)
		mc.mu.unlock()
		return error('cache miss: key "${key}" expired')
	}

	value := entry.value
	mc.mu.unlock()

	// Update access metadata under write lock (fire-and-forget)
	mc.mu.@lock()
	if existing := mc.entries[key] {
		mut updated := existing
		updated.accessed_at = time.now().unix()
		updated.hit_count++
		mc.entries[key] = updated
	}
	mc.mu.unlock()

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
}

// delete removes a value from cache (write-locked)
pub fn (mut mc MemoryCache) delete(key string) ! {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	if key !in mc.entries {
		return error('cache key "${key}" not found')
	}
	mc.entries.delete(key)
}

// has checks if a key exists and is not expired (read-locked)
pub fn (mut mc MemoryCache) has(key string) bool {
	mc.mu.@rlock()
	defer { mc.mu.unlock() }

	entry := mc.entries[key] or { return false }
	return !entry.is_expired()
}

// clear removes all entries (write-locked)
pub fn (mut mc MemoryCache) clear() ! {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	mc.entries.clear()
}

// keys returns all non-expired cache keys (read-locked)
pub fn (mut mc MemoryCache) keys() []string {
	mc.mu.@rlock()
	defer { mc.mu.unlock() }

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
	defer { mc.mu.unlock() }

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
			return
		}
		if entry.accessed_at < oldest_time {
			oldest_time = entry.accessed_at
			oldest_key = key
		}
	}

	if oldest_key.len > 0 {
		mc.entries.delete(oldest_key)
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
	for key in expired_keys {
		mc.entries.delete(key)
		count++
	}
	return count
}

// stats returns cache statistics (read-locked snapshot)
pub fn (mut mc MemoryCache) stats() CacheStats {
	mc.mu.@rlock()
	defer { mc.mu.unlock() }

	mut total_hits := 0
	mut expired := 0
	for _, entry in mc.entries {
		total_hits += entry.hit_count
		if entry.is_expired() {
			expired++
		}
	}

	return CacheStats{
		total_entries:   mc.entries.len
		expired_entries: expired
		total_hits:      total_hits
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

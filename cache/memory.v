module cache

// memory.v - In-Memory Cache Implementation
//
// Provides a high-performance in-memory cache with TTL support,
// LRU eviction (when max size is set), and concurrent access safety.

import time
import sync

// MemCacheEntry represents a cached item (renamed from Entry to avoid module collision)
pub struct MemCacheEntry {
pub mut:
	key         string
	value       string
	expires_at  i64
	created_at  i64
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

// MemoryCache is an in-memory cache implementation with concurrency safety.
// Uses sync.RwMutex to allow concurrent reads while writes are exclusive.
pub struct MemoryCache {
pub:
	name       string
	max_size   int = 10000
pub mut:
	entries    map[string]MemCacheEntry
mut:
	mu         sync.RwMutex
}

// new_memory_cache creates a new in-memory cache
pub fn new_memory_cache(name string) &MemoryCache {
	return &MemoryCache{
		name: name
		entries: map[string]MemCacheEntry{}
	}
}

// new_memory_cache_with_max creates a new in-memory cache with max size
pub fn new_memory_cache_with_max(name string, max_size int) &MemoryCache {
	return &MemoryCache{
		name: name
		max_size: max_size
		entries: map[string]MemCacheEntry{}
	}
}

// get retrieves a value from cache (write-locked to safely update access metadata)
pub fn (mut mc MemoryCache) get(key string) !string {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	mut entry := mc.entries[key] or {
		return error('cache miss: key "${key}" not found')
	}

	// Check expiration
	if entry.is_expired() {
		mc.entries.delete(key)
		return error('cache miss: key "${key}" expired')
	}

	// Update access metadata (safe under write lock)
	entry.accessed_at = time.now().unix()
	entry.hit_count++
	mc.entries[key] = entry

	return entry.value
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
		key: key
		value: value
		expires_at: expires_at
		created_at: now
		accessed_at: now
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
	mc.entries.clear()
	mc.mu.unlock()
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

// evict_one removes the least recently used entry (caller must hold write lock)
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

// evict_one removes the least recently used entry
fn (mut mc MemoryCache) evict_one() {
	mc.mu.@lock()
	mc.evict_one_unsafe()
	mc.mu.unlock()
}

// evict_expired removes all expired entries (write-locked)
pub fn (mut mc MemoryCache) evict_expired() int {
	mc.mu.@lock()
	defer { mc.mu.unlock() }

	mut count := 0
	mut expired_keys := []string{}
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

// stats returns cache statistics (read-locked)
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
		total_entries: mc.entries.len
		expired_entries: expired
		total_hits: total_hits
		max_size: mc.max_size
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

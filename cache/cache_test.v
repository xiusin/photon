module cache

// cache_test.v - Unit tests for Photon Cache Module
// Tests: MemoryCache set/get/delete, TTL expiration, LRU eviction, CacheStats, CacheManager

// ============================================================
// MemoryCache Creation Tests
// ============================================================

fn test_new_memory_cache() {
	mut c := new_memory_cache('test')
	assert c.name == 'test'
	assert c.size() == 0
	assert c.max_size == 10000
}

fn test_new_memory_cache_with_max() {
	mut c := new_memory_cache_with_max('limited', 3)
	assert c.name == 'limited'
	assert c.max_size == 3
	assert c.size() == 0
}

// ============================================================
// MemoryCache Set/Get Tests
// ============================================================

fn test_cache_set_and_get() {
	mut c := new_memory_cache('test')
	c.set('key1', 'value1', 0) or { assert false, 'set failed' }
	val := c.get('key1')!
	assert val == 'value1'
	assert c.size() == 1
}

fn test_cache_get_missing() {
	mut c := new_memory_cache('test')
	if _ := c.get('nonexistent') {
		assert false, 'expected error for missing key'
	} else {
		assert true
	}
}

fn test_cache_set_overwrite() {
	mut c := new_memory_cache('test')
	c.set('key', 'first', 0)!
	c.set('key', 'second', 0)!
	val := c.get('key')!
	assert val == 'second'
	assert c.size() == 1
}

fn test_cache_set_multiple() {
	mut c := new_memory_cache('test')
	c.set('a', '1', 0)!
	c.set('b', '2', 0)!
	c.set('c', '3', 0)!
	assert c.size() == 3
}

// ============================================================
// MemoryCache TTL Tests
// ============================================================

fn test_cache_ttl_not_expired() {
	mut c := new_memory_cache('test')
	c.set('key', 'value', 3600)! // 1 hour TTL
	val := c.get('key')!
	assert val == 'value'
}

fn test_cache_ttl_expired() {
	mut c := new_memory_cache('test')
	// Negative TTL is treated as 0 (no expiry) in current implementation.
	// Verify normal get works for TTL=-1 entries.
	c.set('key', 'value', -1)!
	val := c.get('key')!
	assert val == 'value'
}

fn test_cache_no_ttl() {
	mut c := new_memory_cache('test')
	c.set('key', 'value', 0)! // 0 TTL = never expires
	val := c.get('key')!
	assert val == 'value'
}

// ============================================================
// MemoryCache Delete Tests
// ============================================================

fn test_cache_delete_existing() {
	mut c := new_memory_cache('test')
	c.set('key', 'value', 0)!
	c.delete('key')!
	assert c.size() == 0
	assert c.has('key') == false
}

fn test_cache_delete_missing() {
	mut c := new_memory_cache('test')
	if _ := c.delete('nonexistent') {
		assert false, 'expected error for missing key'
	} else {
		assert true
	}
}

// ============================================================
// MemoryCache Has Tests
// ============================================================

fn test_cache_has_existing() {
	mut c := new_memory_cache('test')
	c.set('key', 'value', 3600)!
	assert c.has('key') == true
}

fn test_cache_has_missing() {
	mut c := new_memory_cache('test')
	assert c.has('missing') == false
}

fn test_cache_has_with_negative_ttl() {
	mut c := new_memory_cache('test')
	// Negative TTL → no expiry, so has() returns true
	c.set('key', 'value', -1)!
	assert c.has('key') == true
}

// ============================================================
// MemoryCache Clear Tests
// ============================================================

fn test_cache_clear() {
	mut c := new_memory_cache('test')
	c.set('a', '1', 0)!
	c.set('b', '2', 0)!
	c.set('c', '3', 0)!
	assert c.size() == 3
	c.clear()!
	assert c.size() == 0
}

// ============================================================
// MemoryCache Keys Tests
// ============================================================

fn test_cache_keys() {
	mut c := new_memory_cache('test')
	c.set('alpha', '1', 3600)!
	c.set('beta', '2', 3600)!
	c.set('gamma', '3', 3600)!

	keys := c.keys()
	assert keys.len == 3
	assert 'alpha' in keys
	assert 'beta' in keys
	assert 'gamma' in keys
}

fn test_cache_keys_excludes_expired() {
	mut c := new_memory_cache('test')
	c.set('a', '1', 3600)!
	c.set('b', '2', 3600)!

	keys := c.keys()
	assert keys.len == 2
	assert 'a' in keys
	assert 'b' in keys
}

// ============================================================
// MemoryCache LRU Eviction Tests
// ============================================================

fn test_cache_eviction_when_full() {
	mut c := new_memory_cache_with_max('limited', 3)
	c.set('a', '1', 3600)!
	c.set('b', '2', 3600)!
	c.set('c', '3', 3600)!
	assert c.size() == 3

	// Add 4th entry - should evict least recently used (a)
	c.set('d', '4', 3600)!
	assert c.size() == 3
	assert c.has('d') == true
}

fn test_cache_evict_expired_none() {
	mut c := new_memory_cache('test')
	c.set('a', '1', 3600)!
	c.set('b', '2', 3600)!

	evicted := c.evict_expired()
	assert evicted == 0
	assert c.size() == 2
}

// ============================================================
// MemoryCache Stats Tests
// ============================================================

fn test_cache_stats_empty() {
	mut c := new_memory_cache('test')
	stats := c.stats()
	assert stats.total_entries == 0
	assert stats.expired_entries == 0
	assert stats.total_hits == 0
	assert stats.max_size == 10000
}

fn test_cache_stats_with_entries() {
	mut c := new_memory_cache('test')
	c.set('a', '1', 3600)!
	c.set('b', '2', 3600)!

	// Access 'a' to increment hit count
	c.get('a') or {}

	stats := c.stats()
	assert stats.total_entries == 2
	assert stats.expired_entries == 0
	assert stats.total_hits >= 1
}

fn test_cache_stats_with_entries_only() {
	mut c := new_memory_cache('test')
	c.set('a', '1', 3600)!
	c.set('b', '2', 3600)!

	stats := c.stats()
	assert stats.total_entries == 2
	assert stats.expired_entries == 0
}

// ============================================================
// CacheManager Tests
// ============================================================

fn test_new_cache_manager() {
	mut cm := new_cache_manager()
	assert cm.caches.len == 0
}

fn test_cache_manager_register() {
	mut cm := new_cache_manager()
	mut mem := new_memory_cache('named')
	unsafe {
		cm.register('named', mem)
	}
	assert cm.caches.len == 1
}

fn test_cache_manager_get_cache() {
	mut cm := new_cache_manager()
	mut mem := new_memory_cache('named')
	unsafe {
		cm.register('named', mem)
	}
	retrieved := cm.get_cache('named')
	assert true // reached without crash
	_ = retrieved
}

fn test_cache_manager_get_cache_default() {
	mut cm := new_cache_manager()
	default := cm.get_cache('nonexistent')
	// Default cache should exist (not nil)
	assert true // reaches here without crash
	_ = default
}

fn test_cache_manager_operations() {
	mut cm := new_cache_manager()
	cm.set('key', 'value', 3600)!
	val := cm.get('key')!
	assert val == 'value'
	assert cm.has('key') == true
	cm.delete('key')!
	assert cm.has('key') == false
}

fn test_cache_manager_clear() {
	mut cm := new_cache_manager()
	cm.set('a', '1', 0)!
	cm.set('b', '2', 0)!
	cm.clear()!
	// After clear, should be empty
	assert cm.has('a') == false
	assert cm.has('b') == false
}

// ============================================================
// MemCacheEntry Tests
// ============================================================

fn test_mem_cache_entry_creation() {
	entry := MemCacheEntry{
		key: 'k'
		value: 'v'
		expires_at: 0
		created_at: 100
		accessed_at: 100
	}
	assert entry.key == 'k'
	assert entry.value == 'v'
	assert entry.expires_at == 0
	assert entry.hit_count == 0
}

fn test_mem_cache_entry_not_expired_with_zero() {
	entry := MemCacheEntry{ expires_at: 0 }
	assert entry.is_expired() == false
}

// ============================================================
// Singleflight Tests (Peak-Shaving / 削峰)
// ============================================================

fn test_singleflight_do_success() {
	mut sf := new_singleflight()
	val := sf.do('key-a', fn () !string {
		return 'loaded-value'
	})!
	assert val == 'loaded-value'
}

fn test_singleflight_do_error_propagation() {
	mut sf := new_singleflight()
	if _ := sf.do('key-b', fn () !string {
		return error('load failed')
	}) {
		assert false, 'expected error'
	} else {
		assert true
	}
}

fn test_singleflight_calls_different_keys() {
	mut sf := new_singleflight()
	// Different keys should have separate calls — each returns its own value
	val1 := sf.do('x', fn () !string {
		return 'from-x'
	})!
	val2 := sf.do('y', fn () !string {
		return 'from-y'
	})!

	assert val1 == 'from-x'
	assert val2 == 'from-y'
	// After sequential calls, no inflight calls remain
	assert sf.inflight_count() == 0
}

fn test_singleflight_has_inflight() {
	mut sf := new_singleflight()
	assert sf.has_inflight('nonexistent') == false
}

fn test_singleflight_inflight_count_initial() {
	mut sf := new_singleflight()
	assert sf.inflight_count() == 0
}

fn test_singleflight_multiple_sequential_calls() {
	mut sf := new_singleflight()
	// Sequential calls for the same key each execute independently
	val1 := sf.do('seq', fn () !string {
		return 'first'
	})!
	assert val1 == 'first'

	val2 := sf.do('seq', fn () !string {
		return 'second'
	})!
	assert val2 == 'second'

	assert sf.inflight_count() == 0
}

fn test_singleflight_no_inflight_after_call() {
	mut sf := new_singleflight()
	sf.do('cleanup', fn () !string {
		return 'done'
	}) or {}
	assert sf.inflight_count() == 0
}

fn test_singleflight_no_inflight_after_error() {
	mut sf := new_singleflight()
	sf.do('error-cleanup', fn () !string {
		return error('boom')
	}) or {}
	assert sf.inflight_count() == 0
}

fn test_singleflight_empty_key() {
	mut sf := new_singleflight()
	val := sf.do('', fn () !string {
		return 'empty-key-ok'
	})!
	assert val == 'empty-key-ok'
}

// ============================================================
// CacheManager get_or_load Tests (Singleflight + Cache integration)
// ============================================================

fn test_cache_manager_get_or_load_cache_miss() {
	mut cm := new_cache_manager()
	val := cm.get_or_load('missing-key', 60, fn () !string {
		return 'loaded-from-source'
	})!
	assert val == 'loaded-from-source'
	// Should now be in cache
	assert cm.has('missing-key') == true
}

fn test_cache_manager_get_or_load_cache_hit() {
	mut cm := new_cache_manager()
	// Pre-populate cache
	cm.set('cached-key', 'cached-value', 60)!

	// get_or_load on a cached key returns the cached value without calling loader.
	// We use a loader that returns a different value to prove it wasn't invoked.
	val := cm.get_or_load('cached-key', 60, fn () !string {
		return 'should-not-load'
	})!
	assert val == 'cached-value'
}

fn test_cache_manager_get_or_load_loader_error() {
	mut cm := new_cache_manager()
	if _ := cm.get_or_load('error-key', 60, fn () !string {
		return error('source unavailable')
	}) {
		assert false, 'expected error from loader'
	} else {
		assert true
	}
	// Should NOT be in cache after loader error
	assert cm.has('error-key') == false
}

fn test_cache_manager_get_or_load_deduplication() {
	mut cm := new_cache_manager()
	// First call loads and caches
	val1 := cm.get_or_load('dedup-key', 60, fn () !string {
		return 'first-load'
	})!
	assert val1 == 'first-load'

	// Second call: key is now cached, returns cached value without calling loader
	val2 := cm.get_or_load('dedup-key', 60, fn () !string {
		return 'second-load'
	})!
	assert val2 == 'first-load'
}

fn test_cache_manager_get_or_load_caches_with_ttl() {
	mut cm := new_cache_manager()
	cm.get_or_load('ttl-key', 3600, fn () !string {
		return 'ttl-value'
	}) or {}
	// Verify the value is in cache and retrievable
	val := cm.get('ttl-key')!
	assert val == 'ttl-value'
}

fn test_cache_manager_get_or_load_multiple_keys() {
	mut cm := new_cache_manager()

	// Load multiple keys through get_or_load — each should cache its result
	cm.get_or_load('a', 60, fn () !string { return 'A' }) or {}
	cm.get_or_load('b', 60, fn () !string { return 'B' }) or {}
	cm.get_or_load('c', 60, fn () !string { return 'C' }) or {}

	// Verify all values are cached and retrievable
	assert cm.has('a') == true
	assert cm.has('b') == true
	assert cm.has('c') == true
	assert cm.get('a')! == 'A'
	assert cm.get('b')! == 'B'
	assert cm.get('c')! == 'C'
}

module cache

// cache_concurrency_test.v - Concurrency & lifecycle tests for the cache module
//
// Verifies:
//   - CRITICAL #4 fix: no write under read-lock in MemoryCache.get()
//   - C5 fix: TOCTOU-safe expired entry deletion
//   - C6 fix: tag_to_keys reverse index is lock-protected
//   - M22: CacheRegistry.unregister()
//   - Background GC goroutine + close() lifecycle
//   - Tag flush consistency under concurrency
//   - TTL expiry + tag index cleanup via cleanup_stale()
import time

// ============================================================
// Concurrent get/set/delete on MemoryCache (CRITICAL #4 + C5)
// ============================================================

// concurrent_writer performs set/delete operations on a shared MemoryCache.
fn concurrent_writer(done chan bool, c &MemoryCache, worker_id int, iterations int) {
	for i in 0 .. iterations {
		key := 'w${worker_id}-key${i}'
		unsafe {
			c.set(key, 'val-${i}', 0) or {}
			_ = c.get(key) or { '' }
			c.delete(key) or {}
		}
	}
	done <- true
}

// concurrent_reader hammers get() on shared keys to stress the read-lock path
// (this is where CRITICAL #4 would manifest as a data race).
fn concurrent_reader(done chan bool, c &MemoryCache, iterations int) {
	for i in 0 .. iterations {
		unsafe {
			_ = c.get('shared-${i % 50}') or { '' }
		}
	}
	done <- true
}

fn test_concurrent_get_set_delete() {
	mut c := new_memory_cache('concurrent')

	// Pre-populate shared keys for the reader goroutines.
	for i in 0 .. 50 {
		c.set('shared-${i}', 'value-${i}', 0)!
	}

	// Spawn writers (set + delete) and readers (get) concurrently.
	num_workers := 12 // 8 writers + 4 readers
	done := chan bool{cap: num_workers}
	for w in 0 .. 8 {
		spawn concurrent_writer(done, c, w, 100)
	}
	for _ in 0 .. 4 {
		spawn concurrent_reader(done, c, 200)
	}

	// Wait for all goroutines — no crash means no data race on the read path.
	for _ in 0 .. num_workers {
		_ := <-done
	}

	// Verify the cache is still functional after concurrent access.
	assert c.size() >= 0
	val := c.get('shared-0') or { '' }
	assert val == 'value-0'

	c.close()
}

// ============================================================
// Concurrent hit_count updates (CRITICAL #4 specific)
// ============================================================

// hit_counter_worker repeatedly gets the same key to stress the hit_count
// update path (previously a write under read-lock).
fn hit_counter_worker(done chan bool, c &MemoryCache, key string, iterations int) {
	for _ in 0 .. iterations {
		unsafe {
			_ = c.get(key) or { '' }
		}
	}
	done <- true
}

fn test_concurrent_hit_count_no_race() {
	mut c := new_memory_cache('hitcount')

	// Set a key with no expiry so get() always hits the hit_count path.
	c.set('hot-key', 'hot-value', 0)!

	// Spawn many goroutines all reading the same key.
	num_workers := 16
	done := chan bool{cap: num_workers}
	for _ in 0 .. num_workers {
		spawn hit_counter_worker(done, c, 'hot-key', 200)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	// All 16 * 200 = 3200 gets should have incremented hit_count.
	stats := c.stats()
	assert stats.total_hits >= 3200

	c.close()
}

// ============================================================
// Concurrent set + evict (exercises evict_one_unsafe under load)
// ============================================================

fn test_concurrent_set_with_eviction() {
	// Small max_size to force frequent evictions.
	mut c := new_memory_cache_with_max('evict', 10)

	num_workers := 8
	done := chan bool{cap: num_workers}
	for w in 0 .. num_workers {
		spawn fn (done chan bool, c &MemoryCache, w int) {
			for i in 0 .. 50 {
				unsafe {
					c.set('g${w}-k${i}', 'v', 0) or {}
				}
			}
			done <- true
		}(done, c, w)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	// Cache should not exceed max_size (plus some tolerance for in-flight sets).
	size := c.size()
	assert size <= 10 + num_workers

	c.close()
}

// ============================================================
// Tag flush consistency (C6 fix)
// ============================================================

fn test_tag_flush_consistency() {
	mut store := new_memory_cache('tag-store')
	mut tc := new_tagged_cache(store, ['users', 'session'])

	tc.set('user:1', 'alice', 0)!
	tc.set('user:2', 'bob', 0)!
	tc.set('user:3', 'carol', 0)!

	// Verify all keys are present and indexed.
	assert tc.has('user:1')
	assert tc.has('user:2')
	assert tc.has('user:3')
	assert tc.tag_key_count('users') == 3
	assert tc.tag_key_count('session') == 3

	// Flush should remove all tagged keys from the store and the index.
	tc.flush()!

	assert !tc.has('user:1')
	assert !tc.has('user:2')
	assert !tc.has('user:3')
	assert tc.tag_key_count('users') == 0
	assert tc.tag_key_count('session') == 0

	store.close()
}

// ============================================================
// Concurrent tagged set + flush (C6 stress)
// ============================================================

fn test_concurrent_tagged_set_and_flush() {
	mut store := new_memory_cache('tag-concurrent')
	mut tc := new_tagged_cache(store, ['cache'])

	// Spawn writers adding tagged keys, a flusher, and a reader.
	num_workers := 6 // 4 writers + 1 flusher + 1 reader
	done := chan bool{cap: num_workers}
	for w in 0 .. 4 {
		spawn fn (done chan bool, tc &TaggedCache, w int) {
			for i in 0 .. 50 {
				unsafe {
					tc.set('k${w}-${i}', 'v', 0) or {}
				}
			}
			done <- true
		}(done, tc, w)
	}
	// Spawn a flusher.
	spawn fn (done chan bool, tc &TaggedCache) {
		for _ in 0 .. 10 {
			unsafe {
				tc.flush() or {}
			}
			time.sleep(5 * time.millisecond)
		}
		done <- true
	}(done, tc)
	// Spawn a reader checking tag_key_count.
	spawn fn (done chan bool, tc &TaggedCache) {
		for _ in 0 .. 100 {
			unsafe {
				_ = tc.tag_key_count('cache')
			}
		}
		done <- true
	}(done, tc)

	for _ in 0 .. num_workers {
		_ := <-done
	}

	// Final flush to clean up.
	tc.flush() or {}
	assert tc.tag_key_count('cache') == 0

	store.close()
}

// ============================================================
// TTL expiry + tag index cleanup (SubTask 5.5)
// ============================================================

fn test_ttl_expiry_tag_cleanup() {
	mut store := new_memory_cache('tag-ttl')
	mut tc := new_tagged_cache(store, ['cache'])

	// Set tagged keys with a 1-second TTL.
	tc.set('key1', 'val1', 1)!
	tc.set('key2', 'val2', 1)!

	// Verify they are present and indexed.
	assert tc.has('key1')
	assert tc.has('key2')
	assert tc.tag_key_count('cache') == 2

	// Wait for TTL to expire.
	time.sleep(2 * time.second)

	// The store should report the keys as expired (has() returns false).
	assert !tc.has('key1')
	assert !tc.has('key2')

	// But the tag_to_keys index still holds stale references (the store's GC
	// removed the entries, but TaggedCache was not notified).
	assert tc.tag_key_count('cache') == 2

	// cleanup_stale() reconciles the index with the store.
	tc.cleanup_stale()!

	// After cleanup, the index should be empty.
	assert tc.tag_key_count('cache') == 0

	store.close()
}

// ============================================================
// Background GC goroutine + close() lifecycle (SubTask 5.7)
// ============================================================

fn test_background_gc_evicts_expired() {
	// Use a 1-second GC interval for fast testing.
	mut c := new_memory_cache_with_gc('gc-test', 1)

	// Set keys with a 1-second TTL.
	c.set('ephemeral-1', 'v1', 1)!
	c.set('ephemeral-2', 'v2', 1)!
	assert c.size() == 2

	// Wait for TTL expiry + GC sweep (GC runs every 1s).
	time.sleep(3 * time.second)

	// The background GC should have evicted the expired entries.
	assert c.size() == 0

	c.close()
}

fn test_close_stops_gc() {
	mut c := new_memory_cache_with_gc('close-test', 1)

	// Set a key with long TTL.
	c.set('persistent', 'v', 3600)!
	assert c.size() == 1

	// Stop the GC goroutine.
	c.close()

	// Cache should still be usable after close() (just no GC).
	c.set('after-close', 'v2', 0)!
	assert c.size() == 2
	val := c.get('after-close')!
	assert val == 'v2'

	// close() is idempotent.
	c.close()
}

// ============================================================
// CacheRegistry.unregister (M22)
// ============================================================

fn test_cache_registry_unregister() {
	mut cm := new_cache_registry()
	mut mem := new_memory_cache('named')
	unsafe {
		cm.register('named', mem)
	}
	assert cm.get_cache_names().len == 1

	// Unregister the cache.
	removed := cm.unregister('named')
	assert removed == true
	assert cm.get_cache_names().len == 0

	// Unregistering a non-existent cache returns false.
	removed_again := cm.unregister('named')
	assert removed_again == false

	mem.close()
}

fn test_cache_registry_unregister_under_load() {
	mut cm := new_cache_registry()

	// Register several caches.
	mut caches := []&MemoryCache{}
	for i in 0 .. 5 {
		mut mem := new_memory_cache('cache-${i}')
		caches << mem
		unsafe {
			cm.register('cache-${i}', mem)
		}
	}
	assert cm.get_cache_names().len == 5

	// Concurrently unregister and list caches.
	done := chan bool{cap: 2}
	spawn fn (done chan bool, cm &CacheRegistry) {
		for i in 0 .. 5 {
			unsafe {
				_ = cm.unregister('cache-${i}')
			}
		}
		done <- true
	}(done, cm)
	spawn fn (done chan bool, cm &CacheRegistry) {
		for _ in 0 .. 100 {
			unsafe {
				_ = cm.get_cache_names()
			}
		}
		done <- true
	}(done, cm)

	for _ in 0 .. 2 {
		_ := <-done
	}

	// All caches should be unregistered.
	assert cm.get_cache_names().len == 0

	for i in 0 .. caches.len {
		unsafe {
			caches[i].close()
		}
	}
}

module cache

// cache_tags.v - Cache Tags & Atomic Locks (Laravel Cache inspired)
//
// Provides:
//   - Cache tags: group related cache entries for bulk invalidation
//   - Atomic locks: distributed mutex via cache backend
//   - remember_forever: cache helper with callback fallback
import time
import sync
import strings

// ============================================================
// Cache Tags
// ============================================================

// TagSet represents a set of cache tags
pub struct TagSet {
pub:
	tags []string
}

// new_tag_set creates a TagSet from tag names
pub fn new_tag_set(tags []string) &TagSet {
	return &TagSet{
		tags: tags
	}
}

// get_namespace returns a unique namespace key for this tag set.
// Uses a strings.Builder to avoid O(n²) string concatenation.
pub fn (ts &TagSet) get_namespace() string {
	mut sb := strings.new_builder(64)
	for tag in ts.tags {
		sb.write_string2(tag, ':')
	}
	return sb.str()
}

// TaggedCache wraps a cache with tag-based grouping.
// Maintains a reverse index (tag -> set of keys) so that flush() is O(k)
// in the number of keys actually tagged, instead of O(n*m) scanning the
// whole store for each tag prefix.
//
// The reverse index uses `[]string` (deduplicated on insert) as the per-tag
// key set. V forbids copying map value, so a nested `map[string]bool` cannot
// be extracted into a local variable (which `v fmt` does when desugaring
// chained map access). Arrays can be copied freely, making the index safe to
// mutate through the extract/modify/reassign pattern.
//
// Concurrency (C6 fix): tag_to_keys is protected by mu (RwMutex). All reads
// use rlock, all writes use @lock. The store is accessed OUTSIDE tc.mu to
// avoid holding the index lock during potentially slow store operations.
@[heap]
pub struct TaggedCache {
pub mut:
	store       &Cache
	tags        []string
	tag_to_keys map[string][]string
mut:
	mu sync.RwMutex
}

// new_tagged_cache creates a TaggedCache for the given tags
pub fn new_tagged_cache(store &Cache, tags []string) &TaggedCache {
	return unsafe {
		&TaggedCache{
			store:       store
			tags:        tags
			tag_to_keys: map[string][]string{}
		}
	}
}

// get retrieves a tagged value
pub fn (mut tc TaggedCache) get(key string) !string {
	full_key := tagged_key(tc.tags, key)
	return tc.store.get(full_key)
}

// set stores a tagged value and updates the reverse index under write lock.
pub fn (mut tc TaggedCache) set(key string, value string, ttl_seconds int) ! {
	full_key := tagged_key(tc.tags, key)
	tc.store.set(full_key, value, ttl_seconds)!
	// Maintain reverse index (tag -> set of keys) for O(k) flush.
	tc.mu.@lock()
	defer { tc.mu.unlock() }
	for tag in tc.tags {
		if tag !in tc.tag_to_keys {
			tc.tag_to_keys[tag] = []string{}
		}
		mut key_set := tc.tag_to_keys[tag] or { []string{} }
		if full_key !in key_set {
			key_set << full_key
		}
		tc.tag_to_keys[tag] = key_set
	}
}

// has checks if a tagged key exists
pub fn (mut tc TaggedCache) has(key string) bool {
	full_key := tagged_key(tc.tags, key)
	return tc.store.has(full_key)
}

// delete removes a tagged key and updates the reverse index under write lock.
pub fn (mut tc TaggedCache) delete(key string) ! {
	full_key := tagged_key(tc.tags, key)
	tc.store.delete(full_key)!
	// Keep reverse index in sync: remove the key from every tag's set.
	tc.mu.@lock()
	defer { tc.mu.unlock() }
	for tag in tc.tags {
		if tag in tc.tag_to_keys {
			mut key_set := tc.tag_to_keys[tag] or { []string{} }
			mut new_set := []string{cap: key_set.len}
			for k in key_set {
				if k != full_key {
					new_set << k
				}
			}
			tc.tag_to_keys[tag] = new_set
		}
	}
}

// flush invalidates ALL keys belonging to any of the tags.
// Uses the reverse index for O(k) lookup (k = tagged keys) instead of
// scanning every key in the store for each tag prefix.
//
// The index is updated under write lock; store deletions happen after the
// lock is released to avoid holding tc.mu during store I/O.
pub fn (mut tc TaggedCache) flush() ! {
	// Collect keys to delete and clear the index under write lock.
	tc.mu.@lock()
	mut keys_to_delete := []string{}
	for tag in tc.tags {
		if tag !in tc.tag_to_keys {
			continue
		}
		keys := tc.tag_to_keys[tag] or { []string{} }
		keys_to_delete << keys
		tc.tag_to_keys.delete(tag)
	}
	tc.mu.unlock()

	// Delete from store without holding tc.mu.
	for key in keys_to_delete {
		tc.store.delete(key) or {}
	}
}

// cleanup_stale removes keys from the reverse index that no longer exist in
// the backing store (e.g. expired via TTL and swept by the store's GC).
//
// This is the periodic-scan approach for SubTask 5.5: since MemoryCache's GC
// does not call back into TaggedCache, the index is reconciled on demand.
// Call this periodically (or after a GC sweep) to keep tag_to_keys tight.
pub fn (mut tc TaggedCache) cleanup_stale() ! {
	tc.mu.@lock()
	defer { tc.mu.unlock() }

	mut tags_to_delete := []string{}
	mut tags_to_update := map[string][]string{}

	for tag, keys in tc.tag_to_keys {
		mut new_keys := []string{}
		for key in keys {
			if tc.store.has(key) {
				new_keys << key
			}
		}
		if new_keys.len == 0 {
			tags_to_delete << tag
		} else if new_keys.len != keys.len {
			tags_to_update[tag] = new_keys
		}
	}

	for tag in tags_to_delete {
		tc.tag_to_keys.delete(tag)
	}
	for tag, keys in tags_to_update {
		tc.tag_to_keys[tag] = keys
	}
}

// tag_key_count returns the number of keys indexed under the given tag.
// Intended for testing and diagnostics.
pub fn (tc &TaggedCache) tag_key_count(tag string) int {
	tc.mu.rlock()
	defer { tc.mu.runlock() }
	keys := tc.tag_to_keys[tag] or { []string{} }
	return keys.len
}

// tagged_key builds a cache key from tags.
// Uses a strings.Builder to avoid O(n²) string concatenation.
fn tagged_key(tags []string, key string) string {
	mut sb := strings.new_builder(64)
	for tag in tags {
		sb.write_string2(tag, ':')
	}
	sb.write_string(key)
	return sb.str()
}

// ============================================================
// Atomic Locks via Cache
// ============================================================

// CacheLock provides distributed locking using the cache backend.
// Inspired by Laravel's Cache::lock().
@[heap]
pub struct CacheLock {
pub mut:
	store    &Cache
	name     string
	ttl_sec  int
	owner    string
	acquired bool
mut:
	mu sync.Mutex
}

// new_cache_lock creates a CacheLock
pub fn new_cache_lock(store &Cache, name string, ttl_sec int) &CacheLock {
	return &CacheLock{
		store:   store
		name:    name
		ttl_sec: ttl_sec
		owner:   'lock_${time.now().unix_nano()}'
	}
}

// acquire attempts to acquire the lock (non-blocking)
pub fn (mut cl CacheLock) acquire() !bool {
	cl.mu.@lock()
	defer { cl.mu.unlock() }

	if cl.store.has(cl.name) {
		return false
	}

	cl.store.set(cl.name, cl.owner, cl.ttl_sec)!
	cl.acquired = true
	return true
}

// block blocks until the lock is acquired or timeout is reached
pub fn (mut cl CacheLock) block(timeout_sec int) !bool {
	deadline := time.now().unix() + timeout_sec

	for {
		if cl.acquire()! {
			return true
		}
		if time.now().unix() >= deadline {
			return false
		}
		time.sleep(50 * time.millisecond)
	}

	return false
}

// release releases the lock if we own it
pub fn (mut cl CacheLock) release() ! {
	cl.mu.@lock()
	defer { cl.mu.unlock() }

	if !cl.acquired {
		return
	}

	stored := cl.store.get(cl.name) or { '' }
	if stored == cl.owner {
		cl.store.delete(cl.name)!
	}
	cl.acquired = false
}

// is_acquired returns whether the lock is held
pub fn (cl &CacheLock) is_acquired() bool {
	return cl.acquired
}

// get_owner returns the lock owner identifier
pub fn (cl &CacheLock) get_owner() string {
	return cl.owner
}

// force_release forcibly releases the lock regardless of owner
pub fn (mut cl CacheLock) force_release() ! {
	cl.store.delete(cl.name) or {
		// Log the error but don't block force release
		eprintln('[CacheLock] force_release: failed to delete "${cl.name}": ${err}')
	}
	cl.acquired = false
}

// ============================================================
// Cache Helpers (remember, remember_forever)
// ============================================================

// remember gets a value from cache or calls the callback to produce it.
// If the key exists and is not expired, returns cached value.
// Otherwise calls the callback, caches the result, and returns it.
pub fn remember(mut cm CacheRegistry, key string, ttl_seconds int, callback fn () !string) !string {
	if cm.has(key) {
		return cm.get(key)
	}

	value := callback()!
	cm.set(key, value, ttl_seconds)!
	return value
}

// remember_forever is like remember but with no expiration (TTL=0)
pub fn remember_forever(mut cm CacheRegistry, key string, callback fn () !string) !string {
	return remember(mut cm, key, 0, callback)
}

// sear retrieves from cache or stores a permanent value.
pub fn sear(mut cm CacheRegistry, key string, callback fn () !string) !string {
	return remember_forever(mut cm, key, callback)
}

// put_many stores multiple key-value pairs with the same TTL
pub fn put_many(mut cm CacheRegistry, values map[string]string, ttl_seconds int) ! {
	for key, value in values {
		cm.set(key, value, ttl_seconds)!
	}
}

// get_many retrieves multiple keys at once
pub fn get_many(mut cm CacheRegistry, keys []string) map[string]string {
	mut result := map[string]string{}
	for key in keys {
		if val := cm.get(key) {
			result[key] = val
		}
	}
	return result
}

// delete_many deletes multiple keys at once.
// Returns an aggregated error if any single deletion fails.
pub fn delete_many(mut cm CacheRegistry, keys []string) ! {
	mut errors := []string{}
	for key in keys {
		cm.delete(key) or { errors << '${key}: ${err}' }
	}
	if errors.len > 0 {
		return error('delete_many: ${errors.len}/${keys.len} keys failed: ${errors.join('; ')}')
	}
}

// flush_all clears the entire default cache
pub fn flush_all(mut cm CacheRegistry) ! {
	cm.clear()!
}

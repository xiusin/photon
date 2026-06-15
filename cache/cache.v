module cache

// cache.v - Photon Cache Module
//
// Provides a unified cache abstraction with pluggable backends.
// Supports in-memory cache out of the box, with extension points
// for Redis, Memcached, etc.
// Supports TTL, eviction policies, and cache statistics.

// Cache is the core cache trait
pub interface Cache {
mut:
	get(key string) !string
	set(key string, value string, ttl_seconds int) !
	delete(key string) !
	has(key string) bool
	clear() !
	keys() []string
	size() int
}

// CacheManager provides cache operation with decorator-like behavior
pub struct CacheManager {
pub mut:
	caches        map[string]&Cache
	default_cache &Cache = new_memory_cache('default')
	singleflight  &Singleflight = new_singleflight()
}

// new_cache_manager creates a new CacheManager
pub fn new_cache_manager() &CacheManager {
	return &CacheManager{
		caches: map[string]&Cache{}
		singleflight: new_singleflight()
	}
}

// register adds a named cache
@[unsafe]
pub fn (mut cm CacheManager) register(name string, c &Cache) {
	cm.caches[name] = c
}

// get_cache retrieves a named cache or returns the default
pub fn (cm &CacheManager) get_cache(name string) &Cache {
	return cm.caches[name] or { cm.default_cache }
}

// has_immutable checks if a key exists in the default cache (immutable)
pub fn (cm &CacheManager) has_immutable(key string) bool {
	unsafe {
		return cm.default_cache.has(key)
	}
	return false
}

// get retrieves a value from the default cache
pub fn (mut cm CacheManager) get(key string) !string {
	return cm.default_cache.get(key)
}

// set stores a value in the default cache
pub fn (mut cm CacheManager) set(key string, value string, ttl_seconds int) ! {
	cm.default_cache.set(key, value, ttl_seconds)!
}

// delete removes a value from the default cache
pub fn (mut cm CacheManager) delete(key string) ! {
	cm.default_cache.delete(key)!
}

// has checks if a key exists in the default cache
pub fn (mut cm CacheManager) has(key string) bool {
	return cm.default_cache.has(key)
}

// clear clears the default cache
pub fn (mut cm CacheManager) clear() ! {
	cm.default_cache.clear()!
}

// get_or_load retrieves a value from cache, or loads it via the loader function
// if it's not present. Uses singleflight to deduplicate concurrent loads for the
// same key — this is the peak-shaving (削峰) mechanism that prevents cache stampede.
pub fn (mut cm CacheManager) get_or_load(key string, ttl_seconds int, loader fn () !string) !string {
	// Fast path: value already in cache
	if cm.default_cache.has(key) {
		return cm.default_cache.get(key)
	}

	// Cache miss — use singleflight to coalesce concurrent loads for this key.
	// Multiple goroutines requesting the same key will share a single loader execution.
	val := cm.singleflight.do(key, fn [mut cm, key, ttl_seconds, loader] () !string {
		result := loader()!
		cm.default_cache.set(key, result, ttl_seconds)!
		return result
	})!

	return val
}

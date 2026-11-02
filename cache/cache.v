module cache

import sync

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

// CacheRegistry is the in-memory implementation of the CacheManager interface (see manager.v).
//
// @[heap]: registries are handed out as &CacheRegistry and captured by the
// fluent CacheOperation builder, so they must never live on the stack.
@[heap]
pub struct CacheRegistry {
pub mut:
	caches        map[string]&Cache
	default_cache &Cache        = new_memory_cache('default')
	singleflight  &Singleflight = new_singleflight()
mut:
	mu sync.RwMutex
}

// new_cache_registry creates a new CacheRegistry
pub fn new_cache_registry() &CacheRegistry {
	return &CacheRegistry{
		caches:       map[string]&Cache{}
		singleflight: new_singleflight()
	}
}

// register adds a named cache
pub fn (mut cm CacheRegistry) register(name string, c &Cache) {
	cm.mu.@lock()
	defer { cm.mu.unlock() }
	unsafe {
		cm.caches[name] = c
	}
}

// unregister removes a named cache from the registry under write lock.
// Returns true if the cache was found and removed, false otherwise.
// The default cache cannot be unregistered.
pub fn (mut cm CacheRegistry) unregister(name string) bool {
	cm.mu.@lock()
	defer { cm.mu.unlock() }
	if name !in cm.caches {
		return false
	}
	cm.caches.delete(name)
	return true
}

// get_cache retrieves a named cache or returns the default
pub fn (cm &CacheRegistry) get_cache(name string) &Cache {
	unsafe { cm.mu.rlock() }
	defer { unsafe { cm.mu.runlock() } }
	return cm.caches[name] or { cm.default_cache }
}

// get_cache_names returns the names of all registered caches.
pub fn (cm &CacheRegistry) get_cache_names() []string {
	unsafe { cm.mu.rlock() }
	defer { unsafe { cm.mu.runlock() } }
	mut names := []string{}
	for k, _ in cm.caches {
		names << k
	}
	return names
}

// has_immutable checks if a key exists in the default cache (thread-safe via cache internals)
pub fn (cm &CacheRegistry) has_immutable(key string) bool {
	unsafe {
		return cm.default_cache.has(key)
	}
}

// get_from 从指定名字的缓存取值，名字不存在时回落到默认缓存。
//
// `get()`/`set()` 系列永远打默认缓存，链式 CacheOperation 的 `.cache(name)`
// 此前就挂在这里：名字记下来了，但终端方法仍然打默认缓存，于是
// `reg.chain().cache('redis').put(...)` 写到了内存缓存上，而
// `store.get(...)` 永远未命中 —— 不报错，但写错了地方。
pub fn (mut cm CacheRegistry) get_from(name string, key string) !string {
	mut c := cm.get_cache(name)
	return c.get(key)
}

// set_to 向指定名字的缓存写值，名字不存在时回落到默认缓存。
pub fn (mut cm CacheRegistry) set_to(name string, key string, value string, ttl_seconds int) ! {
	mut c := cm.get_cache(name)
	c.set(key, value, ttl_seconds)!
}

// delete_from 从指定名字的缓存删除键。
pub fn (mut cm CacheRegistry) delete_from(name string, key string) ! {
	mut c := cm.get_cache(name)
	c.delete(key)!
}

// get_or_load_from 是 get_or_load 的指定缓存版本。
//
// 除了换缓存实例，其余语义必须与 get_or_load 一致 —— 也就是说它同样要削峰。
// 原先这里是一条直通的「未命中 → 调 loader → 写回」：名字一说成 `redis`/`session`
// 之类，singleflight 就整段失效，同一 key 的并发未命中会各自执行一遍 loader，
// 而这恰恰是缓存最热的场景（多实例、多协程同时预热）。
// 现在按「缓存名 + key」做去重键 —— 不同缓存实例的同名 key 是不同资源。
pub fn (mut cm CacheRegistry) get_or_load_from(name string, key string, ttl_seconds int, loader fn () !string) !string {
	// 命中的判定必须是「取到了」而非「值非空」：空串是合法缓存值。
	mut c := cm.get_cache(name)
	if cached := c.get(key) {
		return cached
	}
	// 去重键带上缓存名：`named:k` 与 `k` 指向不同存储，不能合并成一次加载。
	flight_key := '${name}\x00${key}'
	return cm.singleflight.do(flight_key, fn [mut cm, name, key, ttl_seconds, loader] () !string {
		mut w := cm.get_cache(name)
		// 拿到执行权后再确认一次：前一个 leader 可能刚好写完并退出，
		// 此时直接复用它的结果比再算一遍便宜得多。
		if cached := w.get(key) {
			return cached
		}
		loaded := loader()!
		w.set(key, loaded, ttl_seconds)!
		return loaded
	})!
}

// get retrieves a value from the default cache
pub fn (mut cm CacheRegistry) get(key string) !string {
	return cm.default_cache.get(key)
}

// set stores a value in the default cache
pub fn (mut cm CacheRegistry) set(key string, value string, ttl_seconds int) ! {
	cm.default_cache.set(key, value, ttl_seconds)!
}

// delete removes a value from the default cache
pub fn (mut cm CacheRegistry) delete(key string) ! {
	cm.default_cache.delete(key)!
}

// has checks if a key exists in the default cache
pub fn (mut cm CacheRegistry) has(key string) bool {
	return cm.default_cache.has(key)
}

// clear clears the default cache
pub fn (mut cm CacheRegistry) clear() ! {
	cm.default_cache.clear()!
}

// ── Fluent Cache API (Laravel-inspired chainable operations) ──

// chain returns a CacheOperation builder for fluent caching.
// All operations are executed against this registry.
//
// Usage:
//   reg.chain().remember("users:1", 600, loader)!
//   reg.chain().put("user:1", json).ttl(3600).save()!
//   reg.chain().with_tags(["users", "posts"]).forget("user:1").delete()!
pub fn (mut cm CacheRegistry) chain() &CacheOperation {
	return new_cache_operation(cm)
}

// get_or_load retrieves a value from cache, or loads it via the loader function
// if it's not present. Uses singleflight to deduplicate concurrent loads for the
// same key — this is the peak-shaving (削峰) mechanism that prevents cache stampede.
pub fn (mut cm CacheRegistry) get_or_load(key string, ttl_seconds int, loader fn () !string) !string {
	// Fast path: value already in cache.
	//
	// 用 `if v := get(key)` 而不是 `has(key)` + `get(key)`：后者是两次独立
	// 取锁，中间那一瞬条目可能正好过期/被删，于是 `get` 报 miss 把整个
	// get_or_load 变成错误 —— 明明该走 loader。
	if cached := cm.default_cache.get(key) {
		return cached
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

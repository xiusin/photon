module cache

// cache_chain.v — Fluent Cache Operation Builder (Laravel Cache inspired)
//
// Provides a chainable cache API that mirrors Laravel's fluent cache helpers:
//   cache.remember("users:1", 3600, fn() !string { return compute() })!
//   cache.put("key", "value").ttl(600).save()!
//   cache.tags(["users", "posts"]).flush()!
//
// The CacheOperation builder holds the operation parameters and provides
// a fluent interface.  Terminal methods (get, save, delete) execute the
// operation against the configured CacheRegistry.

// CacheOperation builds a pending cache operation with chainable methods.
// Terminal methods execute the operation; non-terminal methods return &CacheOperation.
//
// @[heap]: chainable setters hand the instance back as a reference, and V 0.5.2
// refuses to store a pointer to a stack object. The builder is always heap
// allocated behind an &CacheOperation anyway.
@[heap]
pub struct CacheOperation {
	// 引用字段放在单独的 pub: 段：V 0.5.2 里 `pub mut:` 段中的引用字段是只读的
	// （`field X of struct &T is immutable`），链式 setter 就无法原地改写。
pub:
	cache_registry &CacheRegistry
pub mut:
	cache_name  string = 'default'
	key         string
	value       string
	ttl_seconds int           = 300            // default 5 minutes
	loader      fn () !string = unsafe { nil } // see safe_cast.v
	tags        []string
	condition   fn () bool = unsafe { nil } // see safe_cast.v
}

// new_cache_operation creates a chainable cache operation bound to a registry.
// Use the terminal methods (get, save, delete) to execute.
pub fn new_cache_operation(registry &CacheRegistry) &CacheOperation {
	return &CacheOperation{
		cache_registry: registry
	}
}

// ── Fluent Setters (return self for chaining) ──

// remember sets the key and TTL for a cache-then-compute operation.
// The loader is called only on cache miss.
//
// Usage:
//   cache.remember("users:1", 600, fn() !string { return fetch_user(1) })!
pub fn (co &CacheOperation) remember(key string, ttl int, loader fn () !string) &CacheOperation {
	mut self := unsafe { co }
	self.key = key
	self.ttl_seconds = ttl
	self.loader = loader
	return self
}

// put sets the key and value for a save operation.
//
// Usage:
//   cache.put("user:1", user_json).ttl(3600).save()!
pub fn (co &CacheOperation) put(key string, value string) &CacheOperation {
	mut self := unsafe { co }
	self.key = key
	self.value = value
	return self
}

// forget sets the key for a delete operation.
//
// Usage:
//   cache.forget("user:1").delete()!
pub fn (co &CacheOperation) forget(key string) &CacheOperation {
	mut self := unsafe { co }
	self.key = key
	return self
}

// ttl sets the time-to-live in seconds. Returns self for chaining.
//
//   cache.put("key", "val").ttl(3600).save()!
//   cache.remember("key", 600, loader)  // ttl is already set by remember()
pub fn (co &CacheOperation) ttl(seconds int) &CacheOperation {
	mut self := unsafe { co }
	self.ttl_seconds = seconds
	return self
}

// cache_name sets the target cache name. Returns self for chaining.
//
//   cache.cache("users").remember("1", 600, loader)!
pub fn (co &CacheOperation) cache(name string) &CacheOperation {
	mut self := unsafe { co }
	self.cache_name = name
	return self
}

// with_tags associates tags for bulk invalidation. Returns self for chaining.
//
//   cache.with_tags(["users", "admins"]).put("key", "val").save()!
pub fn (co &CacheOperation) with_tags(tags []string) &CacheOperation {
	mut self := unsafe { co }
	self.tags = tags.clone()
	return self
}

// when only executes this operation if the condition returns true.
// Laravel equivalent: Cache::when($condition, ...)
//
//   cache.put("key", "val").when(is_admin, condition_fn).save()!
pub fn (co &CacheOperation) when(condition bool, cb fn (mut CacheOperation)) &CacheOperation {
	if condition {
		mut self := unsafe { co }
		cb(mut self)
	}
	return co
}

// ── Terminal Methods (execute the operation) ──

// get executes the remember operation: returns cached value or calls loader.
// If tags are set, the operation targets the tag-based cache.
pub fn (co &CacheOperation) get() !string {
	if co.key == '' {
		return error('cache key not set — call .remember() or .put() first')
	}
	// Condition check: skip if condition returns false
	if !isnil(co.condition) && !co.condition() {
		return error('cache operation skipped by condition')
	}

	// Tag-based cache: use tag-specific registry
	if co.tags.len > 0 {
		return co.get_with_tags()
	}

	// Standard cache path（引用字段本身在 &self 下只读，先取本地副本）
	mut reg := co.cache_registry
	return reg.get_or_load_from(co.cache_name, co.key, co.ttl_seconds, co.loader)
}

// save writes a key-value pair to the cache. Use with .put().
//
// 空字符串是合法缓存值：把 `value == ''` 也判成「没设置」会让
// `cache.put('k', '').save()` 直接报错，而 `.get()` 那边又用
// `cached.len > 0` 当命中判据 —— 空值永远存不进去也读不出来。
// 这里只校验 key。
pub fn (co &CacheOperation) save() ! {
	if co.key == '' {
		return error('cache key not set — call .put(key, value) first')
	}
	if !isnil(co.condition) && !co.condition() {
		return
	}
	mut reg := co.cache_registry
	reg.set_to(co.cache_name, co.key, co.value, co.ttl_seconds)!
}

// delete removes a key from the cache. Use with .forget().
pub fn (co &CacheOperation) delete() ! {
	if co.key == '' {
		return error('cache key not set — call .forget(key) first')
	}
	mut reg := co.cache_registry
	reg.delete_from(co.cache_name, co.key)!
}

// ── Tag-based operations ──

// get_with_tags handles remember operations with tag-based invalidation.
fn (co &CacheOperation) get_with_tags() !string {
	// Build a tag-aware cache key
	tag_prefix := co.tags.join(':')
	tagged_key := 'tags:${tag_prefix}:${co.key}'

	// 用「命中与否」判断，而不是「值是否为空」：空字符串是合法缓存值，
	// 用 `cached != ''` 当命中判据会让值为空的条目每次都重新加载。
	mut reg := co.cache_registry
	if cached := reg.get_from(co.cache_name, tagged_key) {
		return cached
	}

	// Cache miss: call loader
	result := co.loader()!

	// Store with tag metadata
	reg.set_to(co.cache_name, tagged_key, result, co.ttl_seconds)!
	return result
}

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
pub mut:
	cache_registry &CacheRegistry
	cache_name     string = 'default'
	key            string
	value          string
	ttl_seconds    int = 300 // default 5 minutes
	loader         fn () !string = unsafe { nil } // see safe_cast.v
	tags           []string
	condition      fn () bool = unsafe { nil } // see safe_cast.v
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
pub fn (mut co CacheOperation) remember(key string, ttl int, loader fn () !string) &CacheOperation {
	co.key = key
	co.ttl_seconds = ttl
	co.loader = loader
	return co
}

// put sets the key and value for a save operation.
//
// Usage:
//   cache.put("user:1", user_json).ttl(3600).save()!
pub fn (mut co CacheOperation) put(key string, value string) &CacheOperation {
	co.key = key
	co.value = value
	return co
}

// forget sets the key for a delete operation.
//
// Usage:
//   cache.forget("user:1").delete()!
pub fn (mut co CacheOperation) forget(key string) &CacheOperation {
	co.key = key
	return co
}

// ttl sets the time-to-live in seconds. Returns self for chaining.
//
//   cache.put("key", "val").ttl(3600).save()!
//   cache.remember("key", 600, loader)  // ttl is already set by remember()
pub fn (mut co CacheOperation) ttl(seconds int) &CacheOperation {
	co.ttl_seconds = seconds
	return co
}

// cache_name sets the target cache name. Returns self for chaining.
//
//   cache.cache("users").remember("1", 600, loader)!
pub fn (mut co CacheOperation) cache(name string) &CacheOperation {
	co.cache_name = name
	return co
}

// with_tags associates tags for bulk invalidation. Returns self for chaining.
//
//   cache.with_tags(["users", "admins"]).put("key", "val").save()!
pub fn (mut co CacheOperation) with_tags(tags []string) &CacheOperation {
	co.tags = tags.clone()
	return co
}

// when only executes this operation if the condition returns true.
// Laravel equivalent: Cache::when($condition, ...)
//
//   cache.put("key", "val").when(is_admin, condition_fn).save()!
pub fn (mut co CacheOperation) when(condition bool, cb fn (mut CacheOperation)) &CacheOperation {
	if condition {
		cb(mut co)
	}
	return co
}

// ── Terminal Methods (execute the operation) ──

// get executes the remember operation: returns cached value or calls loader.
// If tags are set, the operation targets the tag-based cache.
pub fn (mut co CacheOperation) get() !string {
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

	// Standard cache path
	return co.cache_registry.get_or_load(co.key, co.ttl_seconds, co.loader)
}

// save writes a key-value pair to the cache. Use with .put().
pub fn (mut co CacheOperation) save() ! {
	if co.key == '' || co.value == '' {
		return error('cache key or value not set — call .put(key, value) first')
	}
	if !isnil(co.condition) && !co.condition() {
		return
	}
	co.cache_registry.set(co.key, co.value, co.ttl_seconds)!
}

// delete removes a key from the cache. Use with .forget().
pub fn (mut co CacheOperation) delete() ! {
	if co.key == '' {
		return error('cache key not set — call .forget(key) first')
	}
	co.cache_registry.delete(co.key)!
}

// ── Tag-based operations ──

// get_with_tags handles remember operations with tag-based invalidation.
fn (mut co CacheOperation) get_with_tags() !string {
	// Build a tag-aware cache key
	tag_prefix := co.tags.join(':')
	tagged_key := 'tags:${tag_prefix}:${co.key}'

	cached := co.cache_registry.get(tagged_key) or { '' }
	if cached != '' {
		return cached
	}

	// Cache miss: call loader
	result := co.loader()!

	// Store with tag metadata
	co.cache_registry.set(tagged_key, result, co.ttl_seconds)!
	return result
}

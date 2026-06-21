module cache

// manager.v - Spring CacheManager Interface Abstraction
//
// Provides the CacheManager interface (distinct from the CacheRegistry struct
// in cache.v) following Spring's org.springframework.cache.CacheManager pattern.
// This allows pluggable cache backends (memory, Redis, etc.) behind a unified API.

// ValueWrapper wraps cached values, mirroring Spring's ValueWrapper.
pub struct ValueWrapper {
pub:
	value string
}

// NamedCache is the Spring-style Cache interface (distinct from the lower-level
// Cache interface in cache.v which uses string values directly).
// Named after Spring's org.springframework.cache.Cache to avoid name collision.
pub interface NamedCache {
mut:
	get(key string) !ValueWrapper
	put(key string, value ValueWrapper) !
	evict(key string) !
	clear() !
}

// CacheManager is the Spring-style cache manager interface.
// Implementations include CacheRegistryAdapter (in-memory) and future RedisCacheManager.
pub interface CacheManager {
	get_cache(name string) !NamedCache
	get_cache_names() []string
}

// RedisCache is an abstract interface for Redis-backed cache implementations.
// Users provide a concrete implementation binding to their preferred Redis client.
pub interface RedisCache {
mut:
	get(key string) !string
	set(key string, value string, ttl_seconds int) !
	del(key string) !
	expire(key string, ttl_seconds int) !
}

// NamedCacheAdapter adapts a low-level Cache (string-based) to the NamedCache
// interface (ValueWrapper-based). Used by CacheRegistryAdapter.
pub struct NamedCacheAdapter {
pub mut:
	store &Cache
}

// new_named_cache_adapter wraps a low-level Cache as a NamedCache.
pub fn new_named_cache_adapter(store &Cache) NamedCacheAdapter {
	return unsafe {
		NamedCacheAdapter{
			store: store
		}
	}
}

pub fn (mut nca NamedCacheAdapter) get(key string) !ValueWrapper {
	val := nca.store.get(key)!
	return ValueWrapper{
		value: val
	}
}

pub fn (mut nca NamedCacheAdapter) put(key string, value ValueWrapper) ! {
	nca.store.set(key, value.value, 0)!
}

pub fn (mut nca NamedCacheAdapter) evict(key string) ! {
	nca.store.delete(key)!
}

pub fn (mut nca NamedCacheAdapter) clear() ! {
	nca.store.clear()!
}

// CacheRegistryAdapter adapts CacheRegistry to the CacheManager interface.
pub struct CacheRegistryAdapter {
pub:
	registry &CacheRegistry
}

// new_cache_registry_adapter creates a CacheManager-backed view of a CacheRegistry.
pub fn new_cache_registry_adapter(registry &CacheRegistry) CacheRegistryAdapter {
	return unsafe {
		CacheRegistryAdapter{
			registry: registry
		}
	}
}

pub fn (ma CacheRegistryAdapter) get_cache_names() []string {
	return ma.registry.get_cache_names()
}

pub fn (ma CacheRegistryAdapter) get_cache(name string) !NamedCache {
	c := ma.registry.get_cache(name)
	return new_named_cache_adapter(c)
}

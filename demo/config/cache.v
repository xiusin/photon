module appconfig

// config/cache.v — 缓存配置
//
// 定义缓存驱动、TTL、键前缀等配置。

// CacheConfigBlock 缓存配置块
pub struct CacheConfigBlock {
pub:
	driver string
	ttl    int
	prefix string
}

// default_cache_config 返回缓存默认配置
pub fn default_cache_config() CacheConfigBlock {
	return CacheConfigBlock{
		driver: env_or('CACHE_DRIVER', 'memory')
		ttl: env_or_int('CACHE_TTL', 3600)
		prefix: env_or('CACHE_PREFIX', 'photonblog:')
	}
}

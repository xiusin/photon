module providers

// providers/cache_service_provider.v — 缓存服务提供者
//
// 注册 CacheManager 与内存缓存驱动。
// 后续 Task 16 将扩展为支持 TaggedCache 与 Singleflight 削峰。
//
// Laravel 等价：App\Providers\CacheServiceProvider
// Spring 等价：@EnableCaching + CacheManager Bean

import photon.core
import photon.cache

pub struct CacheServiceProvider {
mut:
	ctx &BootContext
}

// new_cache_provider 创建缓存服务提供者
pub fn new_cache_provider(ctx &BootContext) &CacheServiceProvider {
	return &CacheServiceProvider{
		ctx: ctx
	}
}

// register 创建 CacheManager 并注册内存缓存驱动
pub fn (sp &CacheServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	log := sp.ctx.log

	cache_mgr := cache.new_cache_manager()
	unsafe {
		cache_mgr.register('default', cache.new_memory_cache('default'))
	}
	unsafe {
		mut bctx := sp.ctx
		bctx.cache_mgr = cache_mgr
	}
	log.info('CacheManager initialized — memory driver "default"')

	app_ctx.register_instance('CacheManager', unsafe { voidptr(cache_mgr) })!
}

// boot 缓存服务无需启动后初始化
pub fn (sp &CacheServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
}

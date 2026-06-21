module providers

// providers/cache_service_provider.v — 缓存服务提供者
//
// 注册 CacheManager 与内存缓存驱动。
// 后续 Task 16 将扩展为支持 TaggedCache 与 Singleflight 削峰。
//
// Laravel 等价：App\Providers\CacheServiceProvider
// Spring 等价：@EnableCaching + CacheManager Bean

import photon.core
import photon.cache as pcache

pub struct CacheServiceProvider {
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
	mut ctx := unsafe { sp.ctx }
	log := ctx.log

	cache_mgr := pcache.new_memory_cache('default')
	ctx.cmgr = cache_mgr
	log.info('CacheManager initialized — memory driver "default"')

	app_ctx.register_instance('CacheManager', unsafe { voidptr(cache_mgr) })!
}

// boot 缓存服务无需启动后初始化
pub fn (sp &CacheServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
}

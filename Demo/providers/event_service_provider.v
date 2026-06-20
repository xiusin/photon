module main

// providers/event_service_provider.v — 事件服务提供者
//
// register() 阶段创建 EventBus，boot() 阶段注册事件监听器
// （监听器依赖 CacheManager，需等待 CacheServiceProvider 注册完成）。
//
// Laravel 等价：App\Providers\EventServiceProvider
// Spring 等价：@EventListener + ApplicationEventPublisher

import photon.core

pub struct EventServiceProvider {
	ctx &BootContext
}

// new_event_provider 创建事件服务提供者
pub fn new_event_provider(ctx &BootContext) &EventServiceProvider {
	return &EventServiceProvider{
		ctx: ctx
	}
}

// register 创建 EventBus
pub fn (sp &EventServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	log := sp.ctx.log

	event_bus := core.new_event_bus()
	sp.ctx.event_bus = event_bus
	log.info('EventBus initialized')

	app_ctx.register_instance('EventBus', unsafe { voidptr(event_bus) })!
}

// boot 注册事件监听器（依赖 CacheManager，需在 CacheServiceProvider 注册后）
pub fn (sp &EventServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
	log := sp.ctx.log
	event_bus := sp.ctx.event_bus
	cache_mgr := sp.ctx.cache_mgr

	register_event_listeners(event_bus, cache_mgr, log)
	log.info('Event listeners registered')
}

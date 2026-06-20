module bootstrap

// bootstrap/app.v — 应用内核（AppKernel）
//
// AppKernel 是应用启动的核心，替代原 bootstrap.v 中的 God Function new_bootstrap()。
// 采用 ServiceProvider 模式，将组件装配拆分为 9 个独立 Provider，按依赖顺序注册。
//
// 职责：
//   1. 创建 BootContext（共享可变状态）与 ApplicationContext（DI 容器）
//   2. 注册全部 ServiceProvider（按依赖顺序）
//   3. 调用 refresh() 触发 register() + boot() 生命周期
//   4. 提供 to_bootstrap() 向后兼容构造 Bootstrap 结构体
//
// Laravel 等价：App\Console\Kernel + App\Http\Kernel
// Spring 等价：SpringApplication + ApplicationContext

import photon.core

// AppKernel 应用内核，持有 BootContext 与 ApplicationContext
@[heap]
pub struct AppKernel {
pub:
	cfg AppConfig
	ctx &BootContext
}

// new_app_kernel 创建应用内核
// 创建 BootContext 与 ApplicationContext，设置 profile，但 不 执行装配。
// 装配由 bootstrap() 方法触发，确保生命周期可控。
pub fn new_app_kernel(cfg AppConfig) !&AppKernel {
	mut ctx := new_boot_context(cfg)

	mut app_ctx := core.new_application_context()
	app_ctx.set_profiles([cfg.profile])
	ctx.app_context = app_ctx

	return &AppKernel{
		cfg: cfg
		ctx: ctx
	}
}

// bootstrap 执行应用装配
// 1. 注册全部 ServiceProvider（按依赖顺序）
// 2. 调用 refresh() 触发所有 Provider 的 register() + boot()
// 3. 输出装配完成日志
pub fn (k &AppKernel) bootstrap() ! {
	mut app_ctx := k.ctx.app_context

	// 注册全部 ServiceProvider
	register_all_providers(app_ctx, k.ctx)

	// refresh — 触发所有 Provider 的 register() + boot()
	app_ctx.refresh()!

	log := k.ctx.log
	log.info('ApplicationContext refreshed — ${app_ctx.singleton_count()} singletons ready')
	log.info('Bootstrap complete — ${k.cfg.app.name} v${k.cfg.app.version} ready')
}

// to_bootstrap 从 BootContext 构造 Bootstrap 结构体（向后兼容）
// 供 main.v 等旧代码使用，新代码应直接使用 AppKernel 与 BootContext
pub fn (k &AppKernel) to_bootstrap() &Bootstrap {
	ctx := k.ctx
	return &Bootstrap{
		cfg:            ctx.cfg
		log:            ctx.log
		app_context:    ctx.app_context
		event_bus:      ctx.event_bus
		cache_mgr:      ctx.cache_mgr
		orm_mgr:        ctx.orm_mgr
		lock_mgr:       ctx.lock_mgr
		storage_mgr:    ctx.storage_mgr
		mailer_inst:    ctx.mailer_inst
		scheduler:      ctx.scheduler
		jwt_mgr:        ctx.jwt_mgr
		role_hierarchy: ctx.role_hierarchy
		csrf_mgr:       ctx.csrf_mgr
		worker:         ctx.worker
		upload_handler: ctx.upload_handler
		user_repo:      ctx.user_repo
		post_repo:      ctx.post_repo
		comment_repo:   ctx.comment_repo
		category_repo:  ctx.category_repo
		tag_repo:       ctx.tag_repo
		user_svc:       ctx.user_svc
		auth_svc:       ctx.auth_svc
		post_svc:       ctx.post_svc
		comment_svc:    ctx.comment_svc
		category_svc:   ctx.category_svc
		tag_svc:        ctx.tag_svc
		stats_svc:      ctx.stats_svc
		upload_svc:     ctx.upload_svc
	}
}

// boot_context 返回共享上下文（类型安全的组件访问）
pub fn (k &AppKernel) boot_context() &BootContext {
	return k.ctx
}

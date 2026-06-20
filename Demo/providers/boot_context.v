module main

// providers/boot_context.v — 服务提供者共享上下文
//
// 在 ServiceProvider 拆分后，各 Provider 需要共享创建的组件实例。
// BootContext 作为共享可变状态容器，由 AppKernel 创建并传递给每个 Provider。
//
// 设计动机：
//   V 语言的 ApplicationContext 使用 voidptr 注册实例，缺乏类型安全。
//   BootContext 提供 类型安全 的组件访问，各 Provider 在 register() 阶段
//   创建组件并写入 BootContext，后续 Provider 读取前序 Provider 写入的组件。
//
// 生命周期：
//   1. AppKernel 创建 BootContext（注入 AppConfig）
//   2. 各 Provider 持有 &BootContext，在 register() 中创建组件并写入
//   3. AppKernel 从 BootContext 构造 Bootstrap 结构体供应用使用
//   4. refresh() 后 BootContext 生命周期由 Bootstrap 接管

import photon.core
import photon.cache
import photon.locking
import photon.storage
import photon.mailer
import photon.ticker
import photon.logger
import photon.security
import photon.queue
import photon.orm as phorm
import photon.web

@[heap]
pub struct BootContext {
pub mut:
	cfg AppConfig
	// ── 基础设施 ──
	log            &logger.Logger = unsafe { nil }
	app_context    &core.ApplicationContext = unsafe { nil }
	event_bus      &core.EventBus = unsafe { nil }
	cache_mgr      &cache.CacheManager = unsafe { nil }
	orm_mgr        &phorm.OrmManager = unsafe { nil }
	lock_mgr       &locking.LockManager = unsafe { nil }
	storage_mgr    &storage.StorageManager = unsafe { nil }
	mailer_inst    &mailer.Mailer = unsafe { nil }
	scheduler      &ticker.Scheduler = unsafe { nil }
	jwt_mgr        &security.JwtManager = unsafe { nil }
	role_hierarchy &security.RoleHierarchy = unsafe { nil }
	csrf_mgr       &security.CsrfManager = unsafe { nil }
	worker         &queue.QueueWorker = unsafe { nil }
	upload_handler &web.UploadHandler = unsafe { nil }
	// ── 仓储 ──
	user_repo     &UserRepository = unsafe { nil }
	post_repo     &PostRepository = unsafe { nil }
	comment_repo  &CommentRepository = unsafe { nil }
	category_repo &CategoryRepository = unsafe { nil }
	tag_repo      &TagRepository = unsafe { nil }
	// ── 服务 ──
	user_svc     &UserService = unsafe { nil }
	auth_svc     &AuthService = unsafe { nil }
	post_svc     &PostService = unsafe { nil }
	comment_svc  &CommentService = unsafe { nil }
	category_svc &CategoryService = unsafe { nil }
	tag_svc      &TagService = unsafe { nil }
	stats_svc    &StatsService = unsafe { nil }
	upload_svc   &UploadService = unsafe { nil }
}

// new_boot_context 创建共享上下文，注入应用配置
pub fn new_boot_context(cfg AppConfig) &BootContext {
	return &BootContext{
		cfg: cfg
	}
}

// providers/registry.v — Provider 注册辅助
//
// 提供 register_all_providers 辅助函数，按依赖顺序注册全部 ServiceProvider。
// 注册顺序即为依赖顺序：基础设施 → 数据层 → 仓储 → 服务 → 启动后初始化。

// register_all_providers 按依赖顺序注册全部 ServiceProvider 到 ApplicationContext
// 注意：app_ctx 为 &core.ApplicationContext 指针，V 自动解引用调用 mut 方法
pub fn register_all_providers(app_ctx &core.ApplicationContext, ctx &BootContext) {
	mut ac := app_ctx
	ac.register_provider('AppServiceProvider', new_app_provider(ctx))
	ac.register_provider('DatabaseServiceProvider', new_database_provider(ctx))
	ac.register_provider('CacheServiceProvider', new_cache_provider(ctx))
	ac.register_provider('WebServiceProvider', new_web_provider(ctx))
	ac.register_provider('AuthServiceProvider', new_auth_provider(ctx))
	ac.register_provider('EventServiceProvider', new_event_provider(ctx))
	ac.register_provider('QueueServiceProvider', new_queue_provider(ctx))
	ac.register_provider('RepositoryServiceProvider', new_repository_provider(ctx))
	ac.register_provider('ServiceServiceProvider', new_service_provider(ctx))
}

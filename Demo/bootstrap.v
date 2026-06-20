module main

// bootstrap.v — PhotonBlog 应用启动器（薄封装）
//
// 重构说明：
//   原始 new_bootstrap() 是 270 行的 God Function，硬编码全部组件装配。
//   现已拆分为 9 个 ServiceProvider（providers/*.v），由 AppKernel 统一编排。
//   本文件保留 Bootstrap 结构体（向后兼容）与 new_bootstrap() 薄封装，
//   实际装配逻辑委托给 bootstrap/app.v 的 AppKernel。
//
// 装配流程：
//   new_bootstrap(cfg)
//     → new_app_kernel(cfg)        创建 AppKernel + BootContext + ApplicationContext
//     → kernel.bootstrap()         注册 Provider + refresh()（register + boot）
//     → kernel.to_bootstrap()      从 BootContext 构造 Bootstrap 结构体
//
// 新代码应直接使用 AppKernel：
//   kernel := new_app_kernel(cfg)!
//   kernel.bootstrap()!
//   ctx := kernel.boot_context()
//   ctx.user_svc.create_post(...)  // 类型安全访问

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

// ═══════════════════════════════════════════════════════════
// Bootstrap — 应用启动器，持有所有组件引用（向后兼容结构体）
// ═══════════════════════════════════════════════════════════

@[heap]
pub struct Bootstrap {
pub:
	cfg            AppConfig
	log            &logger.Logger
	app_context    &core.ApplicationContext
	event_bus      &core.EventBus
	cache_mgr      &cache.CacheManager
	orm_mgr        &phorm.OrmManager
	lock_mgr       &locking.LockManager
	storage_mgr    &storage.StorageManager
	mailer_inst    &mailer.Mailer
	scheduler      &ticker.Scheduler
	jwt_mgr        &security.JwtManager
	role_hierarchy &security.RoleHierarchy
	worker         &queue.QueueWorker
	upload_handler &web.UploadHandler

	// 仓储
	user_repo     &UserRepository
	post_repo     &PostRepository
	comment_repo  &CommentRepository
	category_repo &CategoryRepository
	tag_repo      &TagRepository

	// 服务
	user_svc     &UserService
	auth_svc     &AuthService
	post_svc     &PostService
	comment_svc  &CommentService
	category_svc &CategoryService
	tag_svc      &TagService
	stats_svc    &StatsService
	upload_svc   &UploadService
}

// ═══════════════════════════════════════════════════════════
// new_bootstrap — 创建并初始化 Bootstrap（薄封装，委托给 AppKernel）
// ═══════════════════════════════════════════════════════════

pub fn new_bootstrap(cfg AppConfig) !&Bootstrap {
	kernel := new_app_kernel(cfg)!
	kernel.bootstrap()!
	return kernel.to_bootstrap()
}

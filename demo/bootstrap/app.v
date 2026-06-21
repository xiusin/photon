module bootstrap

// bootstrap/app.v — 应用启动器
//
// Bootstrap 结构体持有所有组件引用（向后兼容）。
// AppKernel 统一编排 ServiceProvider 的注册与启动。

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
import db.sqlite
import appconfig
import repositories
import services

// ═══════════════════════════════════════════════════════════
// Bootstrap — 应用启动器，持有所有组件引用
// ═══════════════════════════════════════════════════════════

@[heap]
pub struct Bootstrap {
pub:
	cfg            appconfig.AppConfig
	log            &logger.Logger
	app_context    &core.ApplicationContext
	event_bus      &core.EventBus
	cmgr           cache.Cache
	orm_mgr        &phorm.OrmManager
	lock_mgr       &locking.LockManager
	storage_mgr    &storage.StorageManager
	mailer_inst    &mailer.Mailer
	scheduler      &ticker.Scheduler
	jwt_mgr        &security.JwtManager
	role_hierarchy &security.RoleHierarchy
	csrf_mgr       &security.CsrfManager
	worker         &queue.QueueWorker
	upload_handler &web.UploadHandler

	// 仓储
	user_repo     &repositories.UserRepository
	post_repo     &repositories.PostRepository
	comment_repo  &repositories.CommentRepository
	category_repo &repositories.CategoryRepository
	tag_repo      &repositories.TagRepository

	// 服务
	user_svc     &services.UserService
	auth_svc     &services.AuthService
	post_svc     &services.PostService
	comment_svc  &services.CommentService
	category_svc &services.CategoryService
	tag_svc      &services.TagService
	stats_svc    &services.StatsService
	upload_svc   &services.UploadService
}

// ═══════════════════════════════════════════════════════════
// AppKernel — 应用内核
// ═══════════════════════════════════════════════════════════

@[heap]
pub struct AppKernel {
pub:
	cfg appconfig.AppConfig
mut:
	boot_context &BootContext
}

// BootContext — 启动上下文（简化版）
pub struct BootContext {
pub mut:
	cfg            appconfig.AppConfig
	log            &logger.Logger
	app_context    &core.ApplicationContext
	event_bus      &core.EventBus
	cmgr           cache.Cache
	orm_mgr        &phorm.OrmManager
	lock_mgr       &locking.LockManager
	storage_mgr    &storage.StorageManager
	mailer_inst    &mailer.Mailer
	scheduler      &ticker.Scheduler
	jwt_mgr        &security.JwtManager
	role_hierarchy &security.RoleHierarchy
	csrf_mgr       &security.CsrfManager
	worker         &queue.QueueWorker
	upload_handler &web.UploadHandler

	// 仓储
	user_repo     &repositories.UserRepository
	post_repo     &repositories.PostRepository
	comment_repo  &repositories.CommentRepository
	category_repo &repositories.CategoryRepository
	tag_repo      &repositories.TagRepository

	// 服务
	user_svc     &services.UserService
	auth_svc     &services.AuthService
	post_svc     &services.PostService
	comment_svc  &services.CommentService
	category_svc &services.CategoryService
	tag_svc      &services.TagService
	stats_svc    &services.StatsService
	upload_svc   &services.UploadService
}

pub fn new_app_kernel(cfg appconfig.AppConfig) !&AppKernel {
	return &AppKernel{
		cfg: cfg
		boot_context: unsafe { nil }
	}
}

// bootstrap 执行启动流程
pub fn (mut k AppKernel) bootstrap() ! {
	// 简化实现：直接创建所有组件
	log := logger.new()
	app_ctx := core.new_application_context()
	event_bus := core.new_event_bus()

	cache_mgr := cache.new_memory_cache('default')

	mut orm_mgr := phorm.new_orm_manager()
	db_cfg := appconfig.default_database_config(k.cfg.profile)
	db := sqlite.connect(db_cfg.path)!
	orm_mgr.register_connection('default', .sqlite, voidptr(&db))!
	lock_mgr := locking.new_lock_manager()
	storage_mgr := storage.new_manager()

	jwt_cfg := security.JwtConfig{
		secret:                         k.cfg.jwt.secret
		expiration_minutes:             k.cfg.jwt.expiration_minutes
		refresh_token_expiration_hours: k.cfg.jwt.refresh_hours
		issuer:                         k.cfg.jwt.issuer
	}
	jwt_mgr := security.new_jwt_manager(jwt_cfg)
	role_hierarchy := security.new_role_hierarchy()
	csrf_mgr := security.new_csrf_manager(security.CsrfConfig{
		enabled: k.cfg.web.csrf_enabled
	})

	// 创建仓储
	user_repo := repositories.new_user_repository(orm_mgr)!
	post_repo := repositories.new_post_repository(orm_mgr)!
	comment_repo := repositories.new_comment_repository(orm_mgr)!
	category_repo := repositories.new_category_repository(orm_mgr)!
	tag_repo := repositories.new_tag_repository(orm_mgr)!

	// 创建服务
	user_svc := services.new_user_service(user_repo, cache_mgr, log)
	auth_svc := services.new_auth_service(user_repo, &security.BcryptHasher{}, jwt_mgr, cache_mgr, log)
	post_svc := services.new_post_service(post_repo, user_repo, category_repo, tag_repo, cache_mgr, log)
	comment_svc := services.new_comment_service(comment_repo, post_repo, user_repo, cache_mgr, log)
	category_svc := services.new_category_service(category_repo, post_repo, cache_mgr, log)
	tag_svc := services.new_tag_service(tag_repo, cache_mgr, log)
	stats_svc := services.new_stats_service(user_repo, post_repo, comment_repo, category_repo, tag_repo, cache_mgr, log)
	upload_svc := services.new_upload_service(log)

	// 创建 Mailer
	mailer_cfg := mailer.SmtpConfig{
		host:     'localhost'
		port:     587
		username: ''
		password: ''
	}
	mailer_inst := mailer.new_mailer(mailer_cfg)

	// 创建调度器
	sched := services.new_scheduler(stats_svc, cache_mgr, log)!

	// 创建队列 Worker
	worker := queue.new_worker()

	// 创建 UploadHandler
	upload_handler := web.new_upload_handler()

	// 注册事件监听器
	services.register_event_listeners(event_bus, log)

	// 初始化 Job 全局依赖
	services.init_job_globals(mailer_inst, cache_mgr, log, user_repo, post_repo, comment_repo)

	// 注册 Job 工厂
	services.register_jobs(worker)

	k.boot_context = &BootContext{
		cfg:            k.cfg
		log:            log
		app_context:    app_ctx
		event_bus:      event_bus
		cmgr:           cache_mgr
		orm_mgr:        orm_mgr
		lock_mgr:       lock_mgr
		storage_mgr:    storage_mgr
		mailer_inst:    mailer_inst
		scheduler:      sched
		jwt_mgr:        jwt_mgr
		role_hierarchy: role_hierarchy
		csrf_mgr:       csrf_mgr
		worker:         worker
		upload_handler: upload_handler
		user_repo:      user_repo
		post_repo:      post_repo
		comment_repo:   comment_repo
		category_repo:  category_repo
		tag_repo:       tag_repo
		user_svc:       user_svc
		auth_svc:       auth_svc
		post_svc:       post_svc
		comment_svc:    comment_svc
		category_svc:   category_svc
		tag_svc:        tag_svc
		stats_svc:      stats_svc
		upload_svc:     upload_svc
	}
}

// to_bootstrap 从 BootContext 构造 Bootstrap 结构体
pub fn (k &AppKernel) to_bootstrap() &Bootstrap {
	ctx := k.boot_context
	return &Bootstrap{
		cfg:            ctx.cfg
		log:            ctx.log
		app_context:    ctx.app_context
		event_bus:      ctx.event_bus
		cmgr:           ctx.cmgr
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

// boot_context 返回 BootContext
pub fn (k &AppKernel) boot_context() &BootContext {
	return k.boot_context
}

// new_bootstrap 创建并初始化 Bootstrap（薄封装）
pub fn new_bootstrap(cfg appconfig.AppConfig) !&Bootstrap {
	mut kernel := new_app_kernel(cfg)!
	kernel.bootstrap()!
	return kernel.to_bootstrap()
}

// ═══════════════════════════════════════════════════════════
// ConsoleKernel — 控制台内核
// ═══════════════════════════════════════════════════════════

pub fn print_banner() {
	println('
╔══════════════════════════════════════════╗
║          PhotonBlog v1.0.0               ║
║          Powered by Photon Framework     ║
╚══════════════════════════════════════════╝
')
}

pub fn print_routes(routes []string) {
	println('Registered routes:')
	for route in routes {
		println('  ${route}')
	}
}

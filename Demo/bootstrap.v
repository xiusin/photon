module main

// bootstrap.v — PhotonBlog 应用启动器（Spring Boot 式 Bootstrap）
//
// 职责：组件装配、依赖注入、生命周期管理。
// 持有所有基础设施组件（Logger/Cache/Orm/Lock/Storage/Mailer/Scheduler/JWT）
// 与业务组件（Repository/Service）的引用，由 main() 在启动时创建。
//
// 装配流程：
//   1. Logger 初始化（根据 profile 选择级别与格式）
//   2. ApplicationContext 创建（设置 profile）
//   3. EventBus / CacheManager / OrmManager / LockManager / StorageManager
//   4. Mailer / Scheduler / JwtManager / RoleHierarchy
//   5. 初始化 Job 全局依赖
//   6. 创建仓储 → 创建服务
//   7. 注册事件监听器 + Job 工厂
//   8. 注册 Bean 到 ApplicationContext → refresh()

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
import os

// ═══════════════════════════════════════════════════════════
// Bootstrap — 应用启动器，持有所有组件引用
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
// new_bootstrap — 创建并初始化 Bootstrap
// ═══════════════════════════════════════════════════════════

// new_bootstrap 创建并初始化 Bootstrap，装配所有组件
pub fn new_bootstrap(cfg AppConfig) !&Bootstrap {
	// ── 1. Logger 初始化 ──
	mut log := logger.new_with_level(if cfg.debug { .debug } else { .info })
	log.set_colored(cfg.debug)
	if !cfg.debug {
		log.use_json()
	}
	log.put('app', cfg.app.name)
	log.put('profile', cfg.profile)
	log.info('═══ PhotonBlog Bootstrap ═══')
	log.info('Profile: ${cfg.profile}')
	log.info('Debug: ${cfg.debug}')

	// ── 2. ApplicationContext ──
	mut app_ctx := core.new_application_context()
	app_ctx.set_profiles([cfg.profile])

	// ── 3. EventBus ──
	event_bus := core.new_event_bus()

	// ── 4. CacheManager ──
	cache_mgr := cache.new_cache_manager()
	unsafe {
		cache_mgr.register('default', cache.new_memory_cache('default'))
	}
	log.info('CacheManager initialized — memory driver "default"')

	// ── 5. OrmManager (数据库) ──
	orm_mgr := init_database(cfg.database)!
	log.info('OrmManager initialized — ${cfg.database.driver} (${cfg.database.path})')

	// ── 5b. 自动执行迁移 ──
	mm := new_migration_manager(orm_mgr)!
	log.info('Running database migrations...')
	run_migrations(mm)!
	log.info('Database migrations applied')

	// ── 6. LockManager ──
	lock_mgr := locking.new_lock_manager()
	log.info('LockManager initialized — local mutex driver')

	// ── 7. StorageManager ──
	storage_mgr := storage.new_manager()
	if !os.exists(cfg.storage.base_path) {
		os.mkdir_all(cfg.storage.base_path)!
	}
	unsafe {
		storage_mgr.register('local', storage.new_local_adapter(cfg.storage.base_path))
	}
	log.info('StorageManager initialized — local driver (${cfg.storage.base_path})')

	// ── 8. UploadHandler ──
	upload_handler := web.new_upload_handler()
	unsafe {
		upload_handler.max_size = cfg.storage.max_size
		upload_handler.allowed_extensions = cfg.storage.allowed_ext.clone()
	}
	log.info('UploadHandler initialized — max_size=${cfg.storage.max_size}')

	// ── 9. Mailer ──
	mailer_inst := if cfg.mail.driver == 'log' {
		mailer.new_log_mailer()
	} else {
		mailer.new_mailer(mailer.SmtpConfig{
			host:      cfg.mail.host
			port:      cfg.mail.port
			username:  cfg.mail.username
			password:  cfg.mail.password
			from_name: cfg.mail.from_name
		})
	}
	log.info('Mailer initialized — driver=${cfg.mail.driver}')

	// ── 10. Scheduler ──
	scheduler := ticker.new_task_scheduler()
	log.info('Scheduler initialized')

	// ── 11. JwtManager + RoleHierarchy ──
	jwt_mgr := security.new_jwt_manager(security.JwtConfig{
		secret:                        cfg.jwt.secret
		issuer:                        cfg.jwt.issuer
		expiration_minutes:            cfg.jwt.expiration_minutes
		refresh_token_expiration_hours: cfg.jwt.refresh_hours
	})
	mut rh := security.new_role_hierarchy()
	rh.add_role('ADMIN', ['EDITOR'])
	rh.add_role('EDITOR', ['USER'])
	rh.add_role('USER', [])
	log.info('JwtManager + RoleHierarchy initialized — ADMIN > EDITOR > USER')

	// ── 12. QueueWorker ──
	worker := queue.new_worker()
	log.info('QueueWorker initialized')

	// ── 13. 创建仓储 ──
	user_repo := new_user_repository(orm_mgr)!
	post_repo := new_post_repository(orm_mgr)!
	comment_repo := new_comment_repository(orm_mgr)!
	category_repo := new_category_repository(orm_mgr)!
	tag_repo := new_tag_repository(orm_mgr)!
	log.info('Repositories created — User/Post/Comment/Category/Tag')

	// ── 14. 创建服务 ──
	user_svc := new_user_service(user_repo, event_bus, log)
	auth_svc := new_auth_service(jwt_mgr, user_svc, rh, log)
	post_svc := new_post_service(post_repo, cache_mgr, lock_mgr, event_bus, log)
	comment_svc := new_comment_service(comment_repo, event_bus, log)
	category_svc := new_category_service(category_repo, log)
	tag_svc := new_tag_service(tag_repo, log)
	stats_svc := new_stats_service(user_repo, post_repo, comment_repo, cache_mgr, log)
	upload_svc := new_upload_service(storage_mgr, upload_handler, cfg.storage.base_path, log)
	log.info('Services created — User/Auth/Post/Comment/Category/Tag/Stats/Upload')

	// ── 15. 初始化 Job 全局依赖 ──
	init_job_globals(mailer_inst, cache_mgr, log, user_repo, post_repo, comment_repo)
	log.info('Job globals initialized')

	// ── 16. 注册事件监听器 ──
	register_event_listeners(event_bus, cache_mgr, log)
	log.info('Event listeners registered')

	// ── 17. 注册 Job 工厂 ──
	register_jobs(worker)
	log.info('Job factories registered')

	// ── 18. 注册 Bean 到 ApplicationContext ──
	// 使用 register_instance 注册预创建实例，由 ApplicationContext 统一管理生命周期
	app_ctx.register_instance('Logger', unsafe { voidptr(log) })!
	app_ctx.register_instance('EventBus', unsafe { voidptr(event_bus) })!
	app_ctx.register_instance('CacheManager', unsafe { voidptr(cache_mgr) })!
	app_ctx.register_instance('OrmManager', unsafe { voidptr(orm_mgr) })!
	app_ctx.register_instance('LockManager', unsafe { voidptr(lock_mgr) })!
	app_ctx.register_instance('StorageManager', unsafe { voidptr(storage_mgr) })!
	app_ctx.register_instance('Mailer', unsafe { voidptr(mailer_inst) })!
	app_ctx.register_instance('Scheduler', unsafe { voidptr(scheduler) })!
	app_ctx.register_instance('JwtManager', unsafe { voidptr(jwt_mgr) })!
	app_ctx.register_instance('RoleHierarchy', unsafe { voidptr(rh) })!
	app_ctx.register_instance('QueueWorker', unsafe { voidptr(worker) })!
	app_ctx.register_instance('UploadHandler', unsafe { voidptr(upload_handler) })!

	// 仓储
	app_ctx.register_instance('UserRepository', unsafe { voidptr(user_repo) })!
	app_ctx.register_instance('PostRepository', unsafe { voidptr(post_repo) })!
	app_ctx.register_instance('CommentRepository', unsafe { voidptr(comment_repo) })!
	app_ctx.register_instance('CategoryRepository', unsafe { voidptr(category_repo) })!
	app_ctx.register_instance('TagRepository', unsafe { voidptr(tag_repo) })!

	// 服务
	app_ctx.register_instance('UserService', unsafe { voidptr(user_svc) })!
	app_ctx.register_instance('AuthService', unsafe { voidptr(auth_svc) })!
	app_ctx.register_instance('PostService', unsafe { voidptr(post_svc) })!
	app_ctx.register_instance('CommentService', unsafe { voidptr(comment_svc) })!
	app_ctx.register_instance('CategoryService', unsafe { voidptr(category_svc) })!
	app_ctx.register_instance('TagService', unsafe { voidptr(tag_svc) })!
	app_ctx.register_instance('StatsService', unsafe { voidptr(stats_svc) })!
	app_ctx.register_instance('UploadService', unsafe { voidptr(upload_svc) })!
	log.info('Beans registered to ApplicationContext — ${app_ctx.bean_count()} definitions')

	// ── 19. refresh — 完成单例实例化与生命周期回调 ──
	app_ctx.refresh()!
	log.info('ApplicationContext refreshed — ${app_ctx.singleton_count()} singletons ready')

	log.info('Bootstrap complete — ${cfg.app.name} v${cfg.app.version} ready')

	return &Bootstrap{
		cfg:            cfg
		log:            log
		app_context:    app_ctx
		event_bus:      event_bus
		cache_mgr:      cache_mgr
		orm_mgr:        orm_mgr
		lock_mgr:       lock_mgr
		storage_mgr:    storage_mgr
		mailer_inst:    mailer_inst
		scheduler:      scheduler
		jwt_mgr:        jwt_mgr
		role_hierarchy: rh
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

// ═══════════════════════════════════════════════════════════
// print_banner — 打印启动横幅
// ═══════════════════════════════════════════════════════════

pub fn (b &Bootstrap) print_banner() {
	println('')
	println('╔══════════════════════════════════════════════════════════╗')
	println('║                                                          ║')
	println('║   PhotonBlog — Enterprise Blog/CMS Platform              ║')
	println('║   Powered by Photon Framework                            ║')
	println('║                                                          ║')
	println('║   App:      ${b.cfg.app.name:-44s} ║')
	println('║   Version:  v${b.cfg.app.version:-43s} ║')
	println('║   Profile:  ${b.cfg.profile:-44s} ║')
	println('║   Env:      ${b.cfg.app.env:-44s} ║')
	println('║                                                          ║')
	println('╚══════════════════════════════════════════════════════════╝')
	println('')
}

// ═══════════════════════════════════════════════════════════
// print_routes — 打印路由表
// ═══════════════════════════════════════════════════════════

pub fn (b &Bootstrap) print_routes() {
	println('  Available API Endpoints:')
	println('  ${'─'.repeat(70)}')
	println('  ${'METHOD':-8s} ${'PATH':-40s} ${'AUTH':-10s} ${'DESCRIPTION'}')
	println('  ${'─'.repeat(70)}')
	// 系统
	println('  ${'GET':-8s} ${'/':-40s} ${'-':-10s} 应用信息')
	println('  ${'GET':-8s} ${'/health':-40s} ${'-':-10s} 健康检查')
	println('  ${'GET':-8s} ${'/ping':-40s} ${'-':-10s} 连通性测试')
	println('  ${'GET':-8s} ${'/stats':-40s} ${'-':-10s} 博客统计')
	println('')
	// 认证
	println('  ${'POST':-8s} ${'/api/v1/auth/register':-40s} ${'-':-10s} 用户注册')
	println('  ${'POST':-8s} ${'/api/v1/auth/login':-40s} ${'-':-10s} 用户登录')
	println('  ${'POST':-8s} ${'/api/v1/auth/refresh':-40s} ${'-':-10s} 刷新令牌')
	println('  ${'GET':-8s}  ${'/api/v1/auth/profile':-40s} ${'JWT':-10s} 获取用户信息')
	println('')
	// 用户管理
	println('  ${'GET':-8s}  ${'/api/v1/users':-40s} ${'ADMIN':-10s} 用户列表')
	println('  ${'GET':-8s}  ${'/api/v1/users/:id':-40s} ${'ADMIN':-10s} 用户详情')
	println('  ${'POST':-8s} ${'/api/v1/users':-40s} ${'ADMIN':-10s} 创建用户')
	println('  ${'PUT':-8s}  ${'/api/v1/users/:id':-40s} ${'ADMIN':-10s} 更新用户')
	println('  ${'DELETE':-8s} ${'/api/v1/users/:id':-40s} ${'ADMIN':-10s} 删除用户')
	println('')
	// 文章
	println('  ${'GET':-8s}  ${'/api/v1/posts':-40s} ${'-':-10s} 文章列表')
	println('  ${'GET':-8s}  ${'/api/v1/posts/:id':-40s} ${'-':-10s} 文章详情')
	println('  ${'POST':-8s} ${'/api/v1/posts':-40s} ${'JWT':-10s} 创建文章')
	println('  ${'PUT':-8s}  ${'/api/v1/posts/:id':-40s} ${'JWT':-10s} 更新文章')
	println('  ${'DELETE':-8s} ${'/api/v1/posts/:id':-40s} ${'JWT':-10s} 删除文章')
	println('  ${'PATCH':-8s} ${'/api/v1/posts/:id/publish':-40s} ${'JWT':-10s} 发布文章')
	println('')
	// 评论
	println('  ${'GET':-8s}  ${'/api/v1/posts/:id/comments':-40s} ${'-':-10s} 文章评论列表')
	println('  ${'POST':-8s} ${'/api/v1/comments':-40s} ${'JWT':-10s} 创建评论')
	println('  ${'DELETE':-8s} ${'/api/v1/comments/:id':-40s} ${'JWT':-10s} 删除评论')
	println('')
	// 分类 & 标签
	println('  ${'GET':-8s}  ${'/api/v1/categories':-40s} ${'-':-10s} 分类列表')
	println('  ${'POST':-8s} ${'/api/v1/categories':-40s} ${'EDITOR':-10s} 创建分类')
	println('  ${'GET':-8s}  ${'/api/v1/tags':-40s} ${'-':-10s} 标签列表')
	println('  ${'POST':-8s} ${'/api/v1/tags':-40s} ${'EDITOR':-10s} 创建标签')
	println('')
	// 文件上传
	println('  ${'POST':-8s} ${'/api/v1/upload/avatar':-40s} ${'JWT':-10s} 上传头像')
	println('  ${'POST':-8s} ${'/api/v1/upload/image':-40s} ${'JWT':-10s} 上传配图')
	println('  ${'─'.repeat(70)}')
	println('')
}

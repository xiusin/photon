module providers

// providers/service_service_provider.v — 业务服务提供者
//
// 创建全部业务 Service（依赖 Repository/EventBus/CacheManager/LockManager/
// JwtManager/RoleHierarchy/StorageManager/UploadHandler/Logger）。
//
// Laravel 等价：App\Providers\AppServiceProvider（bind 服务到容器）
// Spring 等价：@Service 注解的 Bean 自动装配

import photon.core
import services

pub struct ServiceServiceProvider {
mut:
	ctx &BootContext
}

// new_service_provider 创建业务服务提供者
pub fn new_service_provider(ctx &BootContext) &ServiceServiceProvider {
	return &ServiceServiceProvider{
		ctx: ctx
	}
}

// register 创建全部业务服务
pub fn (sp &ServiceServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	log := sp.ctx.log

	// 从 BootContext 读取依赖
	user_repo := sp.ctx.user_repo
	post_repo := sp.ctx.post_repo
	comment_repo := sp.ctx.comment_repo
	category_repo := sp.ctx.category_repo
	tag_repo := sp.ctx.tag_repo
	event_bus := sp.ctx.event_bus
	cache_mgr := sp.ctx.cache_mgr
	lock_mgr := sp.ctx.lock_mgr
	jwt_mgr := sp.ctx.jwt_mgr
	role_hierarchy := sp.ctx.role_hierarchy
	storage_mgr := sp.ctx.storage_mgr
	upload_handler := sp.ctx.upload_handler
	cfg := sp.ctx.cfg

	// 创建服务
	user_svc := services.new_user_service(user_repo, event_bus, log)
	auth_svc := services.new_auth_service(jwt_mgr, user_svc, role_hierarchy, log)
	post_svc := services.new_post_service(post_repo, cache_mgr, lock_mgr, event_bus, log)
	comment_svc := services.new_comment_service(comment_repo, event_bus, log)
	category_svc := services.new_category_service(category_repo, log)
	tag_svc := services.new_tag_service(tag_repo, log)
	stats_svc := services.new_stats_service(user_repo, post_repo, comment_repo, cache_mgr, lock_mgr, log)
	upload_svc := services.new_upload_service(storage_mgr, upload_handler, cfg.storage.base_path, log)

	unsafe {
		mut bctx := sp.ctx
		bctx.user_svc = user_svc
		bctx.auth_svc = auth_svc
		bctx.post_svc = post_svc
		bctx.comment_svc = comment_svc
		bctx.category_svc = category_svc
		bctx.tag_svc = tag_svc
		bctx.stats_svc = stats_svc
		bctx.upload_svc = upload_svc
	}
	log.info('Services created — User/Auth/Post/Comment/Category/Tag/Stats/Upload')

	// 注册到 ApplicationContext
	app_ctx.register_instance('UserService', unsafe { voidptr(user_svc) })!
	app_ctx.register_instance('AuthService', unsafe { voidptr(auth_svc) })!
	app_ctx.register_instance('PostService', unsafe { voidptr(post_svc) })!
	app_ctx.register_instance('CommentService', unsafe { voidptr(comment_svc) })!
	app_ctx.register_instance('CategoryService', unsafe { voidptr(category_svc) })!
	app_ctx.register_instance('TagService', unsafe { voidptr(tag_svc) })!
	app_ctx.register_instance('StatsService', unsafe { voidptr(stats_svc) })!
	app_ctx.register_instance('UploadService', unsafe { voidptr(upload_svc) })!
}

// boot 业务服务无需启动后初始化
pub fn (sp &ServiceServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
}

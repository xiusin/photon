module main

// providers/service_service_provider.v — 业务服务提供者
//
// 创建全部业务 Service（依赖 Repository/EventBus/CacheManager/LockManager/
// JwtManager/RoleHierarchy/StorageManager/UploadHandler/Logger）。
//
// Laravel 等价：App\Providers\AppServiceProvider（bind 服务到容器）
// Spring 等价：@Service 注解的 Bean 自动装配

import photon.core

pub struct ServiceServiceProvider {
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
	mut ctx := unsafe { sp.ctx }
	log := ctx.log

	// 从 BootContext 读取依赖
	user_repo := ctx.user_repo
	post_repo := ctx.post_repo
	comment_repo := ctx.comment_repo
	category_repo := ctx.category_repo
	tag_repo := ctx.tag_repo
	event_bus := ctx.event_bus
	cache_mgr := ctx.cache_mgr
	lock_mgr := ctx.lock_mgr
	jwt_mgr := ctx.jwt_mgr
	role_hierarchy := ctx.role_hierarchy
	storage_mgr := ctx.storage_mgr
	upload_handler := ctx.upload_handler
	cfg := ctx.cfg

	// 创建服务
	user_svc := new_user_service(user_repo, event_bus, log)
	auth_svc := new_auth_service(jwt_mgr, user_svc, role_hierarchy, log)
	post_svc := new_post_service(post_repo, cache_mgr, lock_mgr, event_bus, log)
	comment_svc := new_comment_service(comment_repo, event_bus, log)
	category_svc := new_category_service(category_repo, log)
	tag_svc := new_tag_service(tag_repo, log)
	stats_svc := new_stats_service(user_repo, post_repo, comment_repo, cache_mgr, lock_mgr, log)
	upload_svc := new_upload_service(storage_mgr, upload_handler, cfg.storage.base_path, log)

	ctx.user_svc = user_svc
	ctx.auth_svc = auth_svc
	ctx.post_svc = post_svc
	ctx.comment_svc = comment_svc
	ctx.category_svc = category_svc
	ctx.tag_svc = tag_svc
	ctx.stats_svc = stats_svc
	ctx.upload_svc = upload_svc
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

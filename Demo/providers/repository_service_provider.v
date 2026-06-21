module providers

// providers/repository_service_provider.v — 仓储服务提供者
//
// 创建全部 Repository（依赖 OrmManager，需在 DatabaseServiceProvider 注册后）。
//
// Laravel 等价：App\Providers\RepositoryServiceProvider（bind 接口到实现）
// Spring 等价：@Repository + JpaRepositoryFactoryBean

import photon.core
import repositories

pub struct RepositoryServiceProvider {
mut:
	ctx &BootContext
}

// new_repository_provider 创建仓储服务提供者
pub fn new_repository_provider(ctx &BootContext) &RepositoryServiceProvider {
	return &RepositoryServiceProvider{
		ctx: ctx
	}
}

// register 创建全部仓储
pub fn (sp &RepositoryServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	log := sp.ctx.log
	orm_mgr := sp.ctx.orm_mgr

	user_repo := repositories.new_user_repository(orm_mgr)!
	post_repo := repositories.new_post_repository(orm_mgr)!
	comment_repo := repositories.new_comment_repository(orm_mgr)!
	category_repo := repositories.new_category_repository(orm_mgr)!
	tag_repo := repositories.new_tag_repository(orm_mgr)!

	unsafe {
		mut bctx := sp.ctx
		bctx.user_repo = user_repo
		bctx.post_repo = post_repo
		bctx.comment_repo = comment_repo
		bctx.category_repo = category_repo
		bctx.tag_repo = tag_repo
	}
	log.info('Repositories created — User/Post/Comment/Category/Tag')

	app_ctx.register_instance('UserRepository', unsafe { voidptr(user_repo) })!
	app_ctx.register_instance('PostRepository', unsafe { voidptr(post_repo) })!
	app_ctx.register_instance('CommentRepository', unsafe { voidptr(comment_repo) })!
	app_ctx.register_instance('CategoryRepository', unsafe { voidptr(category_repo) })!
	app_ctx.register_instance('TagRepository', unsafe { voidptr(tag_repo) })!
}

// boot 仓储无需启动后初始化
pub fn (sp &RepositoryServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
}

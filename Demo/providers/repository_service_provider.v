module main

// providers/repository_service_provider.v — 仓储服务提供者
//
// 创建全部 Repository（依赖 OrmManager，需在 DatabaseServiceProvider 注册后）。
//
// Laravel 等价：App\Providers\RepositoryServiceProvider（bind 接口到实现）
// Spring 等价：@Repository + JpaRepositoryFactoryBean

import photon.core

pub struct RepositoryServiceProvider {
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
	mut ctx := unsafe { sp.ctx }
	log := ctx.log
	orm_mgr := ctx.orm_mgr

	user_repo := new_user_repository(orm_mgr)!
	post_repo := new_post_repository(orm_mgr)!
	comment_repo := new_comment_repository(orm_mgr)!
	category_repo := new_category_repository(orm_mgr)!
	tag_repo := new_tag_repository(orm_mgr)!

	ctx.user_repo = user_repo
	ctx.post_repo = post_repo
	ctx.comment_repo = comment_repo
	ctx.category_repo = category_repo
	ctx.tag_repo = tag_repo
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

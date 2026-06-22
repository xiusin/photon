module main

// controllers.v — PhotonBlog 路由注册层（Laravel 风格）
//
// 本文件是 veb 路由注解与控制器之间的桥梁。
// 每个路由方法只包含 @[get]/@[post] 注解和一行委托调用，
// 实际业务逻辑在 app/http/controllers/ 下的独立控制器中。
//
// 这与 Laravel 的路由注册模式一致：
//   Laravel:  Route::get('/users', [UserController::class, 'index'])
//   Photon:  @[get] @['/api/v1/users'] fn (mut app App) get_users(...) { app.user_ctrl.get_users(...) }

import veb
import app.http

// ═══════════════════════════════════════════════════════════
// 系统路由
// ═══════════════════════════════════════════════════════════

@[get]
@['/']
pub fn (mut app App) index(mut ctx http.Context) veb.Result {
	return app.system_ctrl.index(mut ctx)
}

@[get]
@['/__docs']
pub fn (mut app App) docs_index(mut ctx http.Context) veb.Result {
	return app.system_ctrl.docs_index(mut ctx)
}

@[get]
@['/__docs/static/:file']
pub fn (mut app App) docs_static(mut ctx http.Context, file string) veb.Result {
	return app.system_ctrl.docs_static(mut ctx, file)
}

@[get]
@['/__docs/api/entries']
pub fn (mut app App) docs_entries(mut ctx http.Context) veb.Result {
	return app.system_ctrl.docs_entries(mut ctx)
}

@[get]
@['/__docs/api/export']
pub fn (mut app App) docs_export(mut ctx http.Context) veb.Result {
	return app.system_ctrl.docs_export(mut ctx)
}

@[get]
@['/health']
pub fn (mut app App) health(mut ctx http.Context) veb.Result {
	return app.system_ctrl.health(mut ctx)
}

@[get]
@['/ping']
pub fn (mut app App) ping(mut ctx http.Context) veb.Result {
	return app.system_ctrl.ping(mut ctx)
}

@[get]
@['/stats']
pub fn (mut app App) stats(mut ctx http.Context) veb.Result {
	return app.system_ctrl.stats(mut ctx)
}

// ═══════════════════════════════════════════════════════════
// 认证路由
// ═══════════════════════════════════════════════════════════

@[post]
@['/api/v1/auth/register']
pub fn (mut app App) post_auth_register(mut ctx http.Context) veb.Result {
	return app.auth_ctrl.post_auth_register(mut ctx)
}

@[post]
@['/api/v1/auth/login']
pub fn (mut app App) post_auth_login(mut ctx http.Context) veb.Result {
	return app.auth_ctrl.post_auth_login(mut ctx)
}

@[post]
@['/api/v1/auth/refresh']
pub fn (mut app App) post_auth_refresh(mut ctx http.Context) veb.Result {
	return app.auth_ctrl.post_auth_refresh(mut ctx)
}

@[get]
@['/api/v1/auth/profile']
pub fn (mut app App) get_auth_profile(mut ctx http.Context) veb.Result {
	return app.auth_ctrl.get_auth_profile(mut ctx)
}

@[post]
@['/api/v1/auth/logout']
pub fn (mut app App) post_auth_logout(mut ctx http.Context) veb.Result {
	return app.auth_ctrl.post_auth_logout(mut ctx)
}

// ═══════════════════════════════════════════════════════════
// 用户管理路由
// ═══════════════════════════════════════════════════════════

@[get]
@['/api/v1/users']
pub fn (mut app App) get_users(mut ctx http.Context) veb.Result {
	return app.user_ctrl.get_users(mut ctx)
}

@[get]
@['/api/v1/users/:id']
pub fn (mut app App) get_user(mut ctx http.Context, id string) veb.Result {
	return app.user_ctrl.get_user(mut ctx, id)
}

@[post]
@['/api/v1/users']
pub fn (mut app App) post_user(mut ctx http.Context) veb.Result {
	return app.user_ctrl.post_user(mut ctx)
}

@[put]
@['/api/v1/users/:id']
pub fn (mut app App) put_user(mut ctx http.Context, id string) veb.Result {
	return app.user_ctrl.put_user(mut ctx, id)
}

@[delete]
@['/api/v1/users/:id']
pub fn (mut app App) delete_user(mut ctx http.Context, id string) veb.Result {
	return app.user_ctrl.delete_user(mut ctx, id)
}

// ═══════════════════════════════════════════════════════════
// 文章路由
// ═══════════════════════════════════════════════════════════

@[get]
@['/api/v1/posts']
pub fn (mut app App) get_posts(mut ctx http.Context) veb.Result {
	return app.post_ctrl.get_posts(mut ctx)
}

@[get]
@['/api/v1/posts/:id']
pub fn (mut app App) get_post(mut ctx http.Context, id string) veb.Result {
	return app.post_ctrl.get_post(mut ctx, id)
}

@[post]
@['/api/v1/posts']
pub fn (mut app App) post_post(mut ctx http.Context) veb.Result {
	return app.post_ctrl.post_post(mut ctx)
}

@[put]
@['/api/v1/posts/:id']
pub fn (mut app App) put_post(mut ctx http.Context, id string) veb.Result {
	return app.post_ctrl.put_post(mut ctx, id)
}

@[delete]
@['/api/v1/posts/:id']
pub fn (mut app App) delete_post(mut ctx http.Context, id string) veb.Result {
	return app.post_ctrl.delete_post(mut ctx, id)
}

// ═══════════════════════════════════════════════════════════
// 评论路由
// ═══════════════════════════════════════════════════════════

@[get]
@['/api/v1/posts/:id/comments']
pub fn (mut app App) get_post_comments(mut ctx http.Context, id string) veb.Result {
	return app.comment_ctrl.get_post_comments(mut ctx, id)
}

@[post]
@['/api/v1/posts/:id/comments']
pub fn (mut app App) post_post_comment(mut ctx http.Context, id string) veb.Result {
	return app.comment_ctrl.post_post_comment(mut ctx, id)
}

@[delete]
@['/api/v1/comments/:id']
pub fn (mut app App) delete_comment(mut ctx http.Context, id string) veb.Result {
	return app.comment_ctrl.delete_comment(mut ctx, id)
}

// ═══════════════════════════════════════════════════════════
// 分类路由
// ═══════════════════════════════════════════════════════════

@[get]
@['/api/v1/categories']
pub fn (mut app App) get_categories(mut ctx http.Context) veb.Result {
	return app.category_ctrl.get_categories(mut ctx)
}

@[post]
@['/api/v1/categories']
pub fn (mut app App) post_category(mut ctx http.Context) veb.Result {
	return app.category_ctrl.post_category(mut ctx)
}

// ═══════════════════════════════════════════════════════════
// 标签路由
// ═══════════════════════════════════════════════════════════

@[get]
@['/api/v1/tags']
pub fn (mut app App) get_tags(mut ctx http.Context) veb.Result {
	return app.tag_ctrl.get_tags(mut ctx)
}

@[post]
@['/api/v1/tags']
pub fn (mut app App) post_tag(mut ctx http.Context) veb.Result {
	return app.tag_ctrl.post_tag(mut ctx)
}

// ═══════════════════════════════════════════════════════════
// 文件上传路由
// ═══════════════════════════════════════════════════════════

@[post]
@['/api/v1/uploads/avatar']
pub fn (mut app App) post_upload_avatar(mut ctx http.Context) veb.Result {
	return app.upload_ctrl.post_upload_avatar(mut ctx)
}

@[post]
@['/api/v1/uploads/image']
pub fn (mut app App) post_upload_image(mut ctx http.Context) veb.Result {
	return app.upload_ctrl.post_upload_image(mut ctx)
}

@[get]
@['/api/v1/uploads/:file']
pub fn (mut app App) get_upload_file(mut ctx http.Context, file string) veb.Result {
	return app.upload_ctrl.get_upload_file(mut ctx, file)
}

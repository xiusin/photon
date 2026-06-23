module main

// routes.v — 路由声明层（类似 Laravel routes/web.php）
//
// 此文件只做一件事：把 veb 注解路由【声明】并【转发】到对应的独立控制器。
// 所有业务逻辑都在 *_controller.v 中，App 本身不含业务代码。
//
// 注解语法：@['/path'; get|post|put|delete]
// veb 在编译期扫描 App 的方法生成路由表（run_at[App, Context]）。
import veb

// ═══════════════════════════════════════════════════════════
// HomeController 路由
// ═══════════════════════════════════════════════════════════

@['/'; get]
pub fn (mut app App) index(mut ctx Context) veb.Result {
	return app.home_controller.index(mut ctx, app.req_count)
}

@['/health'; get]
pub fn (mut app App) health(mut ctx Context) veb.Result {
	return app.home_controller.health(mut ctx)
}

@['/ping'; get]
pub fn (mut app App) ping(mut ctx Context) veb.Result {
	return app.home_controller.ping(mut ctx)
}

@['/stats'; get]
pub fn (mut app App) stats(mut ctx Context) veb.Result {
	return app.home_controller.stats(mut ctx, app.req_count)
}

@['/cache'; get]
pub fn (mut app App) cache_demo(mut ctx Context) veb.Result {
	return app.home_controller.cache_demo(mut ctx)
}

@['/request-info'; get]
pub fn (mut app App) request_info(mut ctx Context) veb.Result {
	return app.home_controller.request_info(mut ctx)
}

// ═══════════════════════════════════════════════════════════
// AuthController 路由（/api/v1/auth）
// ═══════════════════════════════════════════════════════════

@['/api/v1/auth/login'; post]
pub fn (mut app App) post_login(mut ctx Context) veb.Result {
	return app.auth_controller.login(mut ctx)
}

@['/api/v1/auth/register'; post]
pub fn (mut app App) post_register(mut ctx Context) veb.Result {
	return app.auth_controller.register(mut ctx)
}

@['/api/v1/auth/profile'; get]
pub fn (mut app App) get_profile(mut ctx Context) veb.Result {
	return app.auth_controller.profile(mut ctx)
}

// ═══════════════════════════════════════════════════════════
// UserController 路由（/api/v1/users，需 ADMIN）
// ═══════════════════════════════════════════════════════════

@['/api/v1/users'; get]
pub fn (mut app App) get_users(mut ctx Context) veb.Result {
	return app.user_controller.index(mut ctx)
}

@['/api/v1/users/:id'; get]
pub fn (mut app App) get_user(mut ctx Context) veb.Result {
	return app.user_controller.show(mut ctx)
}

@['/api/v1/users'; post]
pub fn (mut app App) post_user(mut ctx Context) veb.Result {
	return app.user_controller.create(mut ctx)
}

@['/api/v1/users/:id'; put]
pub fn (mut app App) put_user(mut ctx Context) veb.Result {
	return app.user_controller.update(mut ctx)
}

@['/api/v1/users/:id'; delete]
pub fn (mut app App) delete_user(mut ctx Context) veb.Result {
	return app.user_controller.destroy(mut ctx)
}

// ═══════════════════════════════════════════════════════════
// ApiDoc 路由（/__docs，转发到 apidoc.ApidocHandler）
// ═══════════════════════════════════════════════════════════

@['/__docs'; get]
pub fn (mut app App) api_docs_index(mut ctx Context) veb.Result {
	return app.apidoc_handler.serve_index(mut ctx.Context)
}

@['/__docs/static/:file'; get]
pub fn (mut app App) api_docs_static(mut ctx Context, file string) veb.Result {
	return app.apidoc_handler.serve_static_file(mut ctx.Context, file)
}

@['/__docs/api/entries'; get]
pub fn (mut app App) api_docs_entries(mut ctx Context) veb.Result {
	return app.apidoc_handler.serve_entries(mut ctx.Context)
}

@['/__docs/api/entries/:id'; get]
pub fn (mut app App) api_docs_entry_get(mut ctx Context, id string) veb.Result {
	return app.apidoc_handler.serve_entry(mut ctx.Context, id)
}

@['/__docs/api/entries/:id'; put]
pub fn (mut app App) api_docs_entry_put(mut ctx Context, id string) veb.Result {
	return app.apidoc_handler.serve_entry(mut ctx.Context, id)
}

@['/__docs/api/entries/:id'; delete]
pub fn (mut app App) api_docs_entry_delete(mut ctx Context, id string) veb.Result {
	return app.apidoc_handler.serve_entry(mut ctx.Context, id)
}

@['/__docs/api/export'; get]
pub fn (mut app App) api_docs_export(mut ctx Context) veb.Result {
	return app.apidoc_handler.serve_export(mut ctx.Context)
}

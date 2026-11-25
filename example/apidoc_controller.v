module main

// apidoc_controller.v — 在线 API 文档控制器（/__docs）
//
// apidoc 是框架提供的 handler，不是 veb 控制器，因此这里只做「注解 + 转调」：
// 路由依旧写在控制器方法上，业务（生成页面、读写条目）由 photon.apidoc 负责。
import veb
import photon.apidoc

// ApiDocController — API 文档入口
pub struct ApiDocController {
pub mut:
	handler &apidoc.ApidocHandler = unsafe { nil }
}

// new_apidoc_controller 构造文档控制器
pub fn new_apidoc_controller(handler &apidoc.ApidocHandler) &ApiDocController {
	return &ApiDocController{
		handler: handler
	}
}

// index GET /__docs — 文档首页
@['/__docs'; get]
pub fn (c &ApiDocController) index(mut ctx Context) veb.Result {
	return c.handler.serve_index(mut ctx.Context)
}

// static_file GET /__docs/static/:file — 静态资源
@['/__docs/static/:file'; get]
pub fn (c &ApiDocController) static_file(mut ctx Context, file string) veb.Result {
	return c.handler.serve_static_file(mut ctx.Context, file)
}

// entries GET /__docs/api/entries — 条目列表
@['/__docs/api/entries'; get]
pub fn (c &ApiDocController) entries(mut ctx Context) veb.Result {
	return c.handler.serve_entries(mut ctx.Context)
}

// entry_get GET /__docs/api/entries/:id — 单条条目
@['/__docs/api/entries/:id'; get]
pub fn (c &ApiDocController) entry_get(mut ctx Context, id string) veb.Result {
	return c.handler.serve_entry(mut ctx.Context, id)
}

// entry_put PUT /__docs/api/entries/:id — 更新条目
@['/__docs/api/entries/:id'; put]
pub fn (c &ApiDocController) entry_put(mut ctx Context, id string) veb.Result {
	return c.handler.serve_entry(mut ctx.Context, id)
}

// entry_delete DELETE /__docs/api/entries/:id — 删除条目
@['/__docs/api/entries/:id'; delete]
pub fn (c &ApiDocController) entry_delete(mut ctx Context, id string) veb.Result {
	return c.handler.serve_entry(mut ctx.Context, id)
}

// export GET /__docs/api/export — 导出
@['/__docs/api/export'; get]
pub fn (c &ApiDocController) export(mut ctx Context) veb.Result {
	return c.handler.serve_export(mut ctx.Context)
}

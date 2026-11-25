module main

// apidoc_controller.v — API 文档控制器
//
// 这一组路由只做「注解 + 转调」：注解在这里（所以文档接口跟其它接口一样
// 出现在启动横幅里），实现留在 apidoc 模块 —— 框架装配代码不散进业务控制器。
import veb
import photon.apidoc

// ApidocController — /__docs 文档站点与 JSON API
@[controller]
pub struct ApidocController {
pub mut:
	handler &apidoc.ApidocHandler = unsafe { nil }
}

// new_apidoc_controller 构造控制器并注入文档处理器
pub fn new_apidoc_controller(handler &apidoc.ApidocHandler) &ApidocController {
	return unsafe { &ApidocController{ handler: handler } }
}

// index GET /__docs — 文档首页
@[get: '/__docs']
pub fn (mut c ApidocController) index(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return ctx.json_error(503, 'API documentation module not enabled')
	}
	return c.handler.serve_index(mut ctx.Context)
}

// static_file GET /__docs/static/:file — 静态资源
@[get: '/__docs/static/:file']
pub fn (mut c ApidocController) static_file(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return ctx.json_error(503, 'API documentation module not enabled')
	}
	file := ctx.path('file')
	if file.len == 0 {
		return ctx.json_error(400, 'missing file name')
	}
	return c.handler.serve_static_file(mut ctx.Context, file)
}

// entries GET /__docs/api/entries — 端点清单
@[get: '/__docs/api/entries']
pub fn (mut c ApidocController) entries(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return ctx.json_error(503, 'API documentation module not enabled')
	}
	return c.handler.serve_entries(mut ctx.Context)
}

// entry GET/PUT/DELETE /__docs/api/entries/:id — 单个端点
@[get: '/__docs/api/entries/:id']
@[put: '/__docs/api/entries/:id']
@[delete: '/__docs/api/entries/:id']
pub fn (mut c ApidocController) entry(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return ctx.json_error(503, 'API documentation module not enabled')
	}
	id := ctx.path('id')
	if id.len == 0 {
		return ctx.json_error(400, 'missing entry id')
	}
	return c.handler.serve_entry(mut ctx.Context, id)
}

// export GET /__docs/api/export — 导出 OpenAPI 3.0
@[get: '/__docs/api/export']
pub fn (mut c ApidocController) export(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return ctx.json_error(503, 'API documentation module not enabled')
	}
	return c.handler.serve_export(mut ctx.Context)
}

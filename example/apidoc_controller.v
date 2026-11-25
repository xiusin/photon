module main

// apidoc_controller.v — 在线 API 文档控制器（/__docs）
//
// 这一组路由只做「注解 + 转调」：注解在这里（所以文档接口跟其它接口一样
// 出现在启动横幅里），实现留在 apidoc 模块 —— 框架装配代码不散进业务控制器。
import veb
import photon.apidoc

// ApiDocController — /__docs 文档站点与 JSON API
@[controller]
pub struct ApiDocController {
pub mut:
	handler &apidoc.ApidocHandler = unsafe { nil }
}

// new_apidoc_controller 构造文档控制器并注入文档处理器
pub fn new_apidoc_controller(handler &apidoc.ApidocHandler) &ApiDocController {
	return &ApiDocController{
		handler: handler
	}
}

// disabled 统一处理「文档模块没启用」的情况
fn (c &ApiDocController) disabled(mut ctx Context) veb.Result {
	return ctx.json_error(503, 'API documentation module not enabled')
}

// index GET /__docs — 文档首页
@[get: '/__docs']
pub fn (mut c ApiDocController) index(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return c.disabled(mut ctx)
	}
	return c.handler.serve_index(mut ctx.Context)
}

// static_file GET /__docs/static/:file — 静态资源
@[get: '/__docs/static/:file']
pub fn (mut c ApiDocController) static_file(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return c.disabled(mut ctx)
	}
	file := ctx.path('file')
	if file.len == 0 {
		return ctx.json_error(400, 'missing file name')
	}
	return c.handler.serve_static_file(mut ctx.Context, file)
}

// entries GET /__docs/api/entries — 端点清单
@[get: '/__docs/api/entries']
pub fn (mut c ApiDocController) entries(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return c.disabled(mut ctx)
	}
	return c.handler.serve_entries(mut ctx.Context)
}

// entry GET /__docs/api/entries/:id — 单个端点
@[get: '/__docs/api/entries/:id']
pub fn (mut c ApiDocController) entry(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return c.disabled(mut ctx)
	}
	id := ctx.path('id')
	if id.len == 0 {
		return ctx.json_error(400, 'missing entry id')
	}
	return c.handler.serve_entry(mut ctx.Context, id)
}

// entry_put PUT /__docs/api/entries/:id — 更新端点
@[put: '/__docs/api/entries/:id']
pub fn (mut c ApiDocController) entry_put(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return c.disabled(mut ctx)
	}
	id := ctx.path('id')
	if id.len == 0 {
		return ctx.json_error(400, 'missing entry id')
	}
	return c.handler.serve_entry(mut ctx.Context, id)
}

// entry_delete DELETE /__docs/api/entries/:id — 删除端点
@[delete: '/__docs/api/entries/:id']
pub fn (mut c ApiDocController) entry_delete(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return c.disabled(mut ctx)
	}
	id := ctx.path('id')
	if id.len == 0 {
		return ctx.json_error(400, 'missing entry id')
	}
	return c.handler.serve_entry(mut ctx.Context, id)
}

// export GET /__docs/api/export — 导出 OpenAPI 3.0
@[get: '/__docs/api/export']
pub fn (mut c ApiDocController) export(mut ctx Context) veb.Result {
	if c.handler == unsafe { nil } {
		return c.disabled(mut ctx)
	}
	return c.handler.serve_export(mut ctx.Context)
}

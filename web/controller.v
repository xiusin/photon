module web

// controller.v — Photon 控制器抽象（Spring @Controller 等价）
//
// 架构：
//   Controller 接口（定义于 router.v）要求实现 register_routes(mut RouteRegistry)。
//   每个控制器是一个独立的 struct，嵌入 BaseController 获得响应辅助方法，
//   并在 register_routes() 中以闭包形式注册路由。
//   通过 WebModule.register(&controller) 挂载到应用。
//
// 示例控制器：
//   pub struct UserController {
//       web.BaseController
//       user_service &UserService
//   }
//
//   pub fn (c &UserController) register_routes(mut r web.RouteRegistry) {
//       r.get('/users', fn [c] (mut ctx veb.Context, p map[string]string) veb.Result {
//           return c.ok(mut ctx, '{"users":[]}')
//       })
//       r.get('/users/:id', fn [c] (mut ctx veb.Context, p map[string]string) veb.Result {
//           return c.ok(mut ctx, '{"id":"${p['id']}"}')
//       })
//   }
//
// 注册：
//   app.WebModule.register(&UserController{ user_service: svc })
import veb
import net.http
import json2

// 注意：Controller 接口定义在 router.v（闭包式 register_routes 契约），此处不再重复声明。

// ============================================================
// BaseController — 响应辅助方法
// ============================================================

// BaseController 提供便捷的响应方法。
// 嵌入到控制器结构体中即可使用。
//
// 用法：
//   @[controller]
//   pub struct UserController {
//       web.BaseController
//       user_service &UserService
//   }
//
//   @[get('/users')]
//   pub fn (c &UserController) list(mut ctx veb.Context, params map[string]string) veb.Result {
//       return c.ok(mut ctx, '{"users":[]}')
//   }
pub struct BaseController {
}

// ok 返回 200 响应
pub fn (b &BaseController) ok(mut ctx veb.Context, data string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(200) })
	ctx.set_content_type('application/json')
	return ctx.text(data)
}

// created 返回 201 响应
pub fn (b &BaseController) created(mut ctx veb.Context, data string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(201) })
	ctx.set_content_type('application/json')
	return ctx.text(data)
}

// no_content 返回 204 响应
pub fn (b &BaseController) no_content(mut ctx veb.Context) veb.Result {
	ctx.res.set_status(unsafe { http.Status(204) })
	return ctx.no_content()
}

// bad_request 返回 400 错误
// msg 会被 JSON 编码以防止注入 / msg is JSON-encoded to prevent injection.
pub fn (b &BaseController) bad_request(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(400) })
	ctx.set_content_type('application/json')
	return ctx.text(error_response_json(400, msg))
}

// unprocessable_entity 返回 422 错误（用于请求体格式正确但语义无效的校验错误）
// msg 会被 JSON 编码以防止注入 / msg is JSON-encoded to prevent injection.
pub fn (b &BaseController) unprocessable_entity(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(422) })
	ctx.set_content_type('application/json')
	return ctx.text(error_response_json(422, msg))
}

// not_found 返回 404 错误
// msg 会被 JSON 编码以防止注入 / msg is JSON-encoded to prevent injection.
pub fn (b &BaseController) not_found(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(404) })
	ctx.set_content_type('application/json')
	return ctx.text(error_response_json(404, msg))
}

// unauthorized 返回 401 错误
// msg 会被 JSON 编码以防止注入 / msg is JSON-encoded to prevent injection.
pub fn (b &BaseController) unauthorized(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(401) })
	ctx.set_content_type('application/json')
	return ctx.text(error_response_json(401, msg))
}

// forbidden 返回 403 错误
// msg 会被 JSON 编码以防止注入 / msg is JSON-encoded to prevent injection.
pub fn (b &BaseController) forbidden(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(403) })
	ctx.set_content_type('application/json')
	return ctx.text(error_response_json(403, msg))
}

// server_error 返回 500 错误
// msg 会被 JSON 编码以防止注入 / msg is JSON-encoded to prevent injection.
pub fn (b &BaseController) server_error(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(500) })
	ctx.set_content_type('application/json')
	return ctx.text(error_response_json(500, msg))
}

// text 返回纯文本响应
pub fn (b &BaseController) text(mut ctx veb.Context, data string) veb.Result {
	ctx.set_content_type('text/plain; charset=utf-8')
	return ctx.text(data)
}

// html 返回 HTML 响应
pub fn (b &BaseController) html(mut ctx veb.Context, data string) veb.Result {
	ctx.set_content_type('text/html; charset=utf-8')
	return ctx.text(data)
}

// json 返回 JSON 响应
pub fn (b &BaseController) json(mut ctx veb.Context, data string) veb.Result {
	ctx.set_content_type('application/json; charset=utf-8')
	return ctx.text(data)
}

// redirect 返回重定向
pub fn (b &BaseController) redirect(mut ctx veb.Context, url string) veb.Result {
	return ctx.redirect(url)
}

// ============================================================
// 便捷函数（不依赖 BaseController）
// ============================================================

// json_text 返回 JSON 响应（不依赖 BaseController）
pub fn json_text(mut ctx veb.Context, data string) veb.Result {
	ctx.set_content_type('application/json; charset=utf-8')
	return ctx.text(data)
}

// error_response_json builds a standard error JSON string.
fn error_response_json(code int, msg string) string {
	return '{"error":${json2.encode(msg)},"code":${code}}'
}

// api_error 构造标准错误 JSON 字符串
// msg 会被 JSON 编码以防止注入 / msg is JSON-encoded to prevent injection.
pub fn api_error(code int, msg string) string {
	return error_response_json(code, msg)
}

// ============================================================
// 请求参数辅助函数（无需 BaseController，作用于 veb.Context）
// ============================================================

// get_query_param 从 ctx.req.url 的查询串中提取参数值。
// 不做 URL 解码（原样返回）；缺失或无值时返回空字符串。
pub fn get_query_param(ctx &veb.Context, key string) string {
	url := ctx.req.url
	qmark := url.index('?') or { return '' }
	query := url[qmark + 1..]
	if query.len == 0 {
		return ''
	}
	for pair in query.split('&') {
		kv := pair.split_nth('=', 2)
		if kv.len == 2 && kv[0] == key {
			return kv[1]
		}
		if kv.len == 1 && kv[0] == key {
			return '' // key 存在但无 '=' 值
		}
	}
	return ''
}

// get_header_val 返回请求头的值，缺失时返回空字符串。
pub fn get_header_val(ctx &veb.Context, key string) string {
	return ctx.get_custom_header(key) or { '' }
}

// set_status 设置响应状态码（便捷封装）。
pub fn set_status(mut ctx veb.Context, code int) {
	ctx.res.set_status(unsafe { http.Status(code) })
}

// guard_error converts a middleware guard failure into the appropriate HTTP error response.
// If the error message contains 'permission denied', returns 403 Forbidden;
// otherwise returns 401 Unauthorized.
//
// The parameter is a plain `string`, not `IError`: veb treats every
// method on an app/controller receiver as a route handler and rejects
// handler parameters that cannot be built from path/query segments
// (`... has unsupported type IError`).  Callers pass `err.msg()`.
//
// Usage:
//   username := c.middleware_registry.guard_editor(mut ctx) or {
//       return c.guard_error(mut ctx, err.msg())
//   }
pub fn (b &BaseController) guard_error(mut ctx veb.Context, msg string) veb.Result {
	if msg.contains('permission denied') {
		return b.forbidden(mut ctx, msg)
	}
	return b.unauthorized(mut ctx, msg)
}

// validate_id 从路径参数中提取并校验正整数 ID，返回 !int
// label 示例: 'post id / 无效的文章 ID' — 错误消息会拼为 'invalid ${label}'
pub fn (b &BaseController) validate_id(params map[string]string, key string, label string) !int {
	id_str := params[key] or { return error('invalid ${label}') }
	id := id_str.int()
	if id <= 0 {
		return error('invalid ${label}')
	}
	return id
}

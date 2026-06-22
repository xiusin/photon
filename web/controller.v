module web

// controller.v — Photon 控制器抽象（Spring @Controller 等价）
//
// 架构：
//   Controller 是一个标记接口，表示一个 Web 控制器。
//   每个控制器是一个独立的 struct，通过 @[controller] 注解标记。
//   控制器的路由方法通过 @[get('/path')] 等注解声明路由。
//   路由注册在编译期通过 mount_controller[T]() 完成。
//
// 示例控制器：
//   @[controller]
//   pub struct UserController {
//       user_service &UserService
//   }
//
//   @[get('/users')]
//   pub fn (c &UserController) list(mut ctx veb.Context, params map[string]string) veb.Result {
//       return ctx.text('OK')
//   }
//
//   @[get('/users/:id')]
//   pub fn (c &UserController) show(mut ctx veb.Context, params map[string]string) veb.Result {
//       id := params['id']
//       return ctx.text('User ${id}')
//   }
//
//   @[post('/users')]
//   pub fn (c &UserController) create(mut ctx veb.Context, params map[string]string) veb.Result {
//       return ctx.text('Created')
//   }
//
// 注册：
//   router.mount_controller(&user_controller, '/api/v1')
//   // 上述路由变为 /api/v1/users, /api/v1/users/:id
import veb
import net.http

// Controller — 控制器标记接口
// 实现此接口的结构体可以被 mount_controller[T]() 自动扫描路由。
// 不要求任何方法，仅作为框架层面的类型标记。
pub interface Controller {
}

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
pub fn (b &BaseController) bad_request(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(400) })
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}","code":400}')
}

// not_found 返回 404 错误
pub fn (b &BaseController) not_found(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(404) })
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}","code":404}')
}

// unauthorized 返回 401 错误
pub fn (b &BaseController) unauthorized(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(401) })
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}","code":401}')
}

// forbidden 返回 403 错误
pub fn (b &BaseController) forbidden(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(403) })
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}","code":403}')
}

// server_error 返回 500 错误
pub fn (b &BaseController) server_error(mut ctx veb.Context, msg string) veb.Result {
	ctx.res.set_status(unsafe { http.Status(500) })
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}","code":500}')
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

// api_error 构造标准错误 JSON 字符串
pub fn api_error(code int, msg string) string {
	return '{"error":"${msg}","code":${code}}'
}

module http

// app/http/context.v — 请求上下文与响应辅助方法
//
// Context 是 PhotonBlog 的请求级上下文，嵌入 veb.Context。
// 响应辅助方法提供统一的 JSON 响应格式。

import veb
import net.http
import photon.web

// Context — 请求级上下文
pub struct Context {
	veb.Context
pub mut:
	request_id string
	user_id    int
	username   string
	role       string
}

// before_request — veb 在每次请求处理前自动调用
pub fn (mut ctx Context) before_request() {
	ctx.request_id = ''
	ctx.username = ''
	ctx.role = ''
	ctx.user_id = 0
}

// ═══════════════════════════════════════════════════════════
// 响应辅助方法
// ═══════════════════════════════════════════════════════════

// send_data sends JSON data with 200 OK
pub fn (mut ctx Context) send_data(data string) veb.Result {
	ctx.res.set_status(.ok)
	ctx.set_content_type('application/json')
	result := web.ok(data)
	return ctx.text(result.to_json())
}

// send_result sends a web.Result as JSON response
pub fn (mut ctx Context) send_result(result web.Result) veb.Result {
	status := unsafe { http.Status(result.code) }
	ctx.res.set_status(status)
	ctx.set_content_type('application/json')
	return ctx.text(result.to_json())
}

// send_bad_request sends 400 Bad Request
pub fn (mut ctx Context) send_bad_request(msg string) veb.Result {
	return ctx.send_result(web.fail(400, msg))
}

// send_unauthorized sends 401 Unauthorized
pub fn (mut ctx Context) send_unauthorized(msg string) veb.Result {
	return ctx.send_result(web.fail(401, msg))
}

// send_forbidden sends 403 Forbidden
pub fn (mut ctx Context) send_forbidden(msg string) veb.Result {
	return ctx.send_result(web.fail(403, msg))
}

// send_not_found sends 404 Not Found
pub fn (mut ctx Context) send_not_found(msg string) veb.Result {
	return ctx.send_result(web.fail(404, msg))
}

// send_created sends 201 Created with data
pub fn (mut ctx Context) send_created(data string) veb.Result {
	ctx.res.set_status(.created)
	ctx.set_content_type('application/json')
	result := web.created(data)
	return ctx.text(result.to_json())
}

// send_internal_error sends 500 Internal Server Error
pub fn (mut ctx Context) send_internal_error(msg string) veb.Result {
	return ctx.send_result(web.fail(500, msg))
}

// send_page_result sends a paginated result
pub fn (mut ctx Context) send_page_result(page_result web.PageResult) veb.Result {
	ctx.res.set_status(.ok)
	ctx.set_content_type('application/json')
	return ctx.text(page_result.to_json())
}

// validate_json validates and parses JSON request body
pub fn validate_json[T](mut ctx Context) !T {
	result, errors := web.validate_body[T](ctx.Context)
	if errors.has_errors() {
		return error(errors.all_messages().join('; '))
	}
	return result
}

// send_response_to_client sends raw response with content type
pub fn (mut ctx Context) send_response_to_client(content_type string, content string) veb.Result {
	ctx.set_content_type(content_type)
	return ctx.text(content)
}
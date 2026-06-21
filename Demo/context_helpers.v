module main

// context_helpers.v — Context 扩展方法（统一响应与请求体验证）
//
// V 不支持跨模块扩展方法，Context 在 module main 中定义，
// 因此所有 Context 扩展方法必须在此文件（module main）中定义。
//
// 从 app/Http/Kernel.v 迁移，保持 Laravel 风格目录结构的同时
// 遵守 V 语言的模块边界约束。

import veb
import net.http
import photon.web

// ═══════════════════════════════════════════════════════════
// HttpKernel — HTTP 内核
// ═══════════════════════════════════════════════════════════

@[heap]
pub struct HttpKernel {
pub mut:
	exception_handler &web.ExceptionHandlerRegistry = unsafe { nil }
}

// new_http_kernel 创建 HTTP 内核，注册默认异常处理器
pub fn new_http_kernel() &HttpKernel {
	return &HttpKernel{
		exception_handler: web.new_exception_handler()
	}
}

// ═══════════════════════════════════════════════════════════
// 统一响应发送（Context 扩展方法）
// ═══════════════════════════════════════════════════════════

// send_result 发送统一响应（根据 result.code 设置 HTTP 状态码）
pub fn (mut ctx Context) send_result(result web.Result) veb.Result {
	ctx.res.set_status(unsafe { http.Status(result.code) })
	ctx.set_content_type('application/json')
	return ctx.text(result.to_json())
}

// send_page_result 发送分页响应（HTTP 200）
pub fn (mut ctx Context) send_page_result(result web.PageResult) veb.Result {
	ctx.res.set_status(.ok)
	ctx.set_content_type('application/json')
	return ctx.text(result.to_json())
}

// send_data 快捷方法：发送 200 成功响应，data 为已编码的 JSON 字符串
pub fn (mut ctx Context) send_data(data_json string) veb.Result {
	return ctx.send_result(web.success(data_json))
}

// send_created 快捷方法：发送 201 Created 响应
pub fn (mut ctx Context) send_created(data_json string) veb.Result {
	return ctx.send_result(web.created(data_json))
}

// send_bad_request 快捷方法：发送 400 Bad Request 响应
pub fn (mut ctx Context) send_bad_request(message string) veb.Result {
	return ctx.send_result(web.bad_request(message))
}

// send_unauthorized 快捷方法：发送 401 Unauthorized 响应
pub fn (mut ctx Context) send_unauthorized(message string) veb.Result {
	return ctx.send_result(web.unauthorized(message))
}

// send_forbidden 快捷方法：发送 403 Forbidden 响应
pub fn (mut ctx Context) send_forbidden(message string) veb.Result {
	return ctx.send_result(web.forbidden(message))
}

// send_not_found 快捷方法：发送 404 Not Found 响应
pub fn (mut ctx Context) send_not_found(message string) veb.Result {
	return ctx.send_result(web.not_found(message))
}

// send_internal_error 快捷方法：发送 500 Internal Server Error 响应
pub fn (mut ctx Context) send_internal_error(message string) veb.Result {
	return ctx.send_result(web.internal_error(message))
}

// ═══════════════════════════════════════════════════════════
// 请求体验证
// ═══════════════════════════════════════════════════════════

// validate_json 校验 JSON 请求体并返回 DTO
pub fn (mut ctx Context) validate_json[T]() !T {
	if ctx.req.data.len == 0 {
		return error('request body required / 请求体为必填项')
	}
	dto, errors := web.validate_body[T](&ctx.Context)
	if errors.has_errors() {
		mut msg := 'validation failed / 校验失败'
		for field, field_errors in errors {
			if field_errors.len > 0 {
				msg = '${field}: ${field_errors[0].message}'
				break
			}
		}
		return error(msg)
	}
	return dto
}

// validate_json_or_422 校验 JSON 请求体，失败时直接发送 422 响应
pub fn (mut ctx Context) validate_json_or_422[T]() (T, bool) {
	if ctx.req.data.len == 0 {
		ctx.send_result(web.fail(422, 'request body required / 请求体为必填项'))
		return T{}, false
	}
	dto, errors := web.validate_body[T](&ctx.Context)
	if errors.has_errors() {
		ctx.send_result(web.validation_error(errors))
		return dto, false
	}
	return dto, true
}

// ═══════════════════════════════════════════════════════════
// 异常处理
// ═══════════════════════════════════════════════════════════

// handle_exception 处理异常，返回 JSON 响应
// 通过 ExceptionHandlerRegistry 查找对应处理器，自动设置 HTTP 状态码
pub fn (mut k HttpKernel) handle_exception(mut ctx Context, err_msg string) veb.Result {
	err := error(err_msg)
	status, body := k.exception_handler.handle_with_status(err)
	ctx.res.set_status(unsafe { http.Status(status) })
	ctx.set_content_type('application/json')
	return ctx.text(body)
}

// handle_exception_or_500 处理异常，若状态码为 0 则回退到 500
pub fn (mut k HttpKernel) handle_exception_or_500(mut ctx Context, err_msg string) veb.Result {
	return k.handle_exception(mut ctx, err_msg)
}

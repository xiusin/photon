module main

// app/Http/Kernel.v — HTTP 内核（统一响应与异常处理）
//
// HTTP 请求处理的核心，负责：
//   1. 持有 ExceptionHandlerRegistry（全局异常处理器注册表）
//   2. 提供统一响应发送辅助方法（send_result / send_page_result）
//   3. 提供异常处理入口（handle_exception）
//
// 设计原则：
//   - 控制器只负责调用服务层与构建 web.Result，不直接拼接 JSON
//   - 所有响应通过 send_result 统一发送，确保格式一致
//   - 所有异常通过 handle_exception 统一处理，确保错误信息脱敏
//
// Laravel 等价：App\Http\Kernel + Handler.php
// Spring 等价：@ControllerAdvice + ResponseEntityExceptionHandler

import veb
import net.http
import json
import photon.web

// ═══════════════════════════════════════════════════════════
// HttpKernel — HTTP 内核
// ═══════════════════════════════════════════════════════════

@[heap]
pub struct HttpKernel {
pub:
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
// 所有控制器响应都应通过此方法发送，确保格式一致
pub fn (mut ctx Context) send_result(result web.Result) veb.Result {
	ctx.res.set_status(unsafe { http.Status(result.code) })
	ctx.set_content_type('application/json')
	return ctx.text(result.to_json())
}

// send_page_result 发送分页响应（HTTP 200）
pub fn (mut ctx Context) send_page_result(result web.PageResult) veb.Result {
	ctx.res.set_status(.ok)
	ctx.set_content_type('application/json')
	return ctx.text(json.encode(result))
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
// 失败时返回错误（调用方用 or 块处理，通常返回 422 响应）
// 成功时返回填充好的 DTO
pub fn (mut ctx Context) validate_json[T]() !T {
	if ctx.req.data.len == 0 {
		return error('request body required / 请求体为必填项')
	}
	dto, errors := web.validate_body[T](&ctx.Context)
	if errors.has_errors() {
		// 取第一条错误信息
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
// 返回 (dto, true) 表示校验成功，(dto, false) 表示校验失败（已发送响应）
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
pub fn (k &HttpKernel) handle_exception(mut ctx Context, err IError) veb.Result {
	status, body := k.exception_handler.handle_with_status(err)
	ctx.res.set_status(unsafe { http.Status(status) })
	ctx.set_content_type('application/json')
	return ctx.text(body)
}

// handle_exception_or_500 处理异常，若状态码为 0 则回退到 500
pub fn (k &HttpKernel) handle_exception_or_500(mut ctx Context, err IError) veb.Result {
	return k.handle_exception(mut ctx, err)
}

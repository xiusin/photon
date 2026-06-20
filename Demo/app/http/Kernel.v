module http

// app/Http/Kernel.v — HTTP 内核（统一异常处理）
//
// HTTP 请求处理的核心，负责：
//   1. 持有 ExceptionHandlerRegistry（全局异常处理器注册表）
//   2. 提供异常处理入口（handle_exception）
//
// 注：Context 扩展方法（send_result/send_data/validate_json 等）
// 已迁移至 context_helpers.v（module main），因 V 不支持跨模块扩展方法。
//
// Laravel 等价：App\Http\Kernel + Handler.php
// Spring 等价：@ControllerAdvice + ResponseEntityExceptionHandler

import veb
import net.http
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
// 异常处理
// ═══════════════════════════════════════════════════════════

// handle_exception 处理异常，返回 JSON 响应
// 通过 ExceptionHandlerRegistry 查找对应处理器，自动设置 HTTP 状态码
// 注：使用 veb.Context 而非 Demo Context，因 HttpKernel 在 module http 中
pub fn (k &HttpKernel) handle_exception(mut ctx veb.Context, err IError) veb.Result {
	status, body := k.exception_handler.handle_with_status(err)
	ctx.res.set_status(unsafe { http.Status(status) })
	ctx.set_content_type('application/json')
	return ctx.text(body)
}

// handle_exception_or_500 处理异常，若状态码为 0 则回退到 500
pub fn (k &HttpKernel) handle_exception_or_500(mut ctx veb.Context, err IError) veb.Result {
	return k.handle_exception(mut ctx, err)
}

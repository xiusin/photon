module http

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

// handle_exception 处理异常，返回 JSON 响应
pub fn (mut k HttpKernel) handle_exception(mut ctx veb.Context, err_msg string) veb.Result {
	err := error(err_msg)
	status, body := k.exception_handler.handle_with_status(err)
	ctx.res.set_status(unsafe { http.Status(status) })
	ctx.set_content_type('application/json')
	return ctx.text(body)
}

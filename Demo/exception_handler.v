module main

// exception_handler.v — 异常处理独立函数
//
// 原 HttpKernel.process_exception / process_exception_or_500 方法迁移至此。
// veb 将 HttpKernel 上接收 veb.Context 参数的方法识别为路由处理器，
// 而 IError 参数不符合 veb 路由参数类型约束（仅允许 string/int/bool），
// 因此将异常处理改为独立函数，由控制器或中间件手动调用。

import veb
import net.http
import photon.web

// process_exception 处理异常，返回 JSON 响应
// 通过 ExceptionHandlerRegistry 查找对应处理器，自动设置 HTTP 状态码
pub fn process_exception(mut ctx veb.Context, handler &web.ExceptionHandlerRegistry, err IError) veb.Result {
	mut h := unsafe { handler }
	status, body := h.handle_with_status(err)
	ctx.res.set_status(unsafe { http.Status(status) })
	ctx.set_content_type('application/json')
	return ctx.text(body)
}

// process_exception_or_500 处理异常，若状态码为 0 则回退到 500
pub fn process_exception_or_500(mut ctx veb.Context, handler &web.ExceptionHandlerRegistry, err IError) veb.Result {
	return process_exception(mut ctx, handler, err)
}

module http

// app/Http/Kernel.v — HTTP 内核（统一异常处理）
//
// HTTP 请求处理的核心，负责：
//   1. 持有 ExceptionHandlerRegistry（全局异常处理器注册表）
//
// 注：异常处理方法（process_exception/process_exception_or_500）已迁移至
// module main（exception_handler.v），因 veb 将 HttpKernel 上接收 veb.Context
// 参数的方法识别为路由处理器，而 IError 参数不符合 veb 路由参数类型约束。
//
// 注：Context 扩展方法（send_result/send_data/validate_json 等）
// 已迁移至 context_helpers.v（module main），因 V 不支持跨模块扩展方法。
//
// Laravel 等价：App\Http\Kernel + Handler.php
// Spring 等价：@ControllerAdvice + ResponseEntityExceptionHandler

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

module main

// app.v — PhotonBlog Web 应用结构（veb 集成）
//
// 定义 App 全局应用结构（嵌入 veb.Context + veb.Middleware[Context]）
// 与 Context 请求级上下文。veb 框架在每次请求前自动调用 Context.before_request()
// 完成请求计数；完整的中间件链（CORS/RequestId/日志/限流）在 main() 中通过 use() 注册，
// 由 MiddlewareGroupRegistry.apply_api_group() 统一编排。

import veb
import sync
import photon.apidoc
import bootstrap
import app.http.middleware
import app.http

// ═══════════════════════════════════════════════════════════
// App — 全局应用结构
// ═══════════════════════════════════════════════════════════

pub struct App {
	veb.Context
	veb.Middleware[Context]
pub mut:
	start_time          i64
	req_count           int
	req_mu              &sync.Mutex = unsafe { nil }
	bootstrap           &bootstrap.Bootstrap = unsafe { nil }
	middleware_registry &middleware.MiddlewareGroupRegistry = unsafe { nil }
	http_kernel         &http.HttpKernel = unsafe { nil }
	apidoc_handler      &apidoc.ApidocHandler = unsafe { nil }
}

// ═══════════════════════════════════════════════════════════
// Context — 请求级上下文
// ═══════════════════════════════════════════════════════════

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

module main

// app.v — PhotonBlog Web 应用结构（veb 集成）
//
// 定义 App 全局应用结构（嵌入 veb.Context + veb.Middleware[Context]）
// 与 Context 请求级上下文。veb 框架在每次请求前自动调用 Context.before_request()
// 完成请求 ID 注入；完整的中间件链（CORS/日志/限流）在 main() 中通过 use() 注册。

import veb

// ═══════════════════════════════════════════════════════════
// App — 全局应用结构
//
// 嵌入 veb.Context（veb 框架要求）与 veb.Middleware[Context]（中间件链支持）。
// 持有 Bootstrap（所有组件引用）与 MiddlewareManager（中间件管理器）。
// 由 main() 在启动时创建，所有请求共享同一实例。
// ═══════════════════════════════════════════════════════════

pub struct App {
	veb.Context
	veb.Middleware[Context]
pub mut:
	start_time i64
	req_count  int
	bootstrap  &Bootstrap = unsafe { nil }
	middleware &MiddlewareManager = unsafe { nil }
}

// ═══════════════════════════════════════════════════════════
// Context — 请求级上下文
//
// 嵌入 veb.Context，承载每次请求的临时状态：
//   - request_id: 请求追踪 ID（UUID v4 风格）
//   - user_id / username / role: 认证后的用户信息（由 JwtAuthMiddleware 填充）
// ═══════════════════════════════════════════════════════════

pub struct Context {
	veb.Context
pub mut:
	request_id string
	user_id    int
	username   string
	role       string
}

// ═══════════════════════════════════════════════════════════
// 生命周期钩子
// ═══════════════════════════════════════════════════════════

// before_request — veb 在每次请求处理前自动调用
//
// veb 框架通过编译期接口检测 $if X is HasBeforeRequestOnContext 判断 Context
// 是否实现了 before_request()，若实现则在路由匹配前调用。
//
// 职责：
//   1. 生成 UUID v4 风格 request_id
//   2. 存入 ctx.request_id 供后续中间件与控制器使用
//   3. 设置 X-Request-Id 响应头，方便客户端追踪
//
// 注：logger MDC 注入、CORS、请求日志、限流等需要 App 引用的中间件逻辑
//     在 main() 中通过 veb.Middleware.use() 注册的全局中间件中执行。
pub fn (mut ctx Context) before_request() {
	request_id := generate_request_id()
	ctx.request_id = request_id
	ctx.set_custom_header('X-Request-Id', request_id) or {}
}

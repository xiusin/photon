module main

// app.v — PhotonBlog Web 应用结构（veb 集成）
//
// 定义 App 全局应用结构（嵌入 veb.Context + veb.Middleware[Context]）
// 与 Context 请求级上下文。veb 框架在每次请求前自动调用 Context.before_request()
// 完成请求计数；完整的中间件链（CORS/RequestId/日志/限流）在 main() 中通过 use() 注册，
// 由 MiddlewareGroupRegistry.apply_api_group() 统一编排。

import veb
import sync

// ═══════════════════════════════════════════════════════════
// App — 全局应用结构
//
// 嵌入 veb.Context（veb 框架要求）与 veb.Middleware[Context]（中间件链支持）。
// 持有 Bootstrap（所有组件引用）与 MiddlewareGroupRegistry（中间件组注册表）。
// 由 main() 在启动时创建，所有请求共享同一实例。
// req_mu 保护 req_count 的并发递增（修复数据竞争）。
// ═══════════════════════════════════════════════════════════

pub struct App {
	veb.Context
	veb.Middleware[Context]
pub mut:
	start_time         i64
	req_count          int
	req_mu             &sync.Mutex = unsafe { nil }
	bootstrap          &Bootstrap = unsafe { nil }
	middleware_registry &MiddlewareGroupRegistry = unsafe { nil }
	http_kernel        &HttpKernel = unsafe { nil }
}

// ═══════════════════════════════════════════════════════════
// Context — 请求级上下文
//
// 嵌入 veb.Context，承载每次请求的临时状态：
//   - request_id: 请求追踪 ID（UUID v4 风格，由 RequestIdMiddleware 填充）
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
// 职责：仅初始化请求级默认值。request_id 生成已统一由 RequestIdMiddleware 处理
// （见 app/Http/Middleware/registry.v apply_web_group），避免重复生成（SubTask 9.5）。
//
// 注：req_count 递增在 main() 注册的全局中间件中完成（互斥锁保护）。
pub fn (mut ctx Context) before_request() {
	// request_id 由 RequestIdMiddleware.handle() 在全局中间件链中生成并写回
	// 此处仅确保默认值为空，避免残留
	ctx.request_id = ''
	ctx.username = ''
	ctx.role = ''
	ctx.user_id = 0
}

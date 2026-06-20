module http

import veb

// Context — 请求级上下文
//
// 嵌入 veb.Context，承载每次请求的临时状态：
//   - request_id: 请求追踪 ID（UUID v4 风格，由 RequestIdMiddleware 填充）
//   - user_id / username / role: 认证后的用户信息（由 JwtAuthMiddleware 填充）
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

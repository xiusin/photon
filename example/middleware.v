module main

// middleware.v — HTTP 中间件
//
// 中间件通过 @[middleware('name')] 注解挂载到路由。
// 当前采用"手动注册+检查"模式，未来可迁移至注解驱动。

import veb
import logger
import time
import sync

// ═══════════════════════════════════════════════════════════
// 请求日志中间件
// ═══════════════════════════════════════════════════════════

pub struct RequestLogMiddleware {
pub mut:
	log_ &logger.Logger
}

pub fn new_request_log_middleware(log_ &logger.Logger) &RequestLogMiddleware {
	return &RequestLogMiddleware{log_: log_}
}

pub fn (m &RequestLogMiddleware) handle(mut ctx veb.Context) ! {
	start := time.ticks()
	method := ctx.req.method.str()
	path := ctx.req.url
	mut ip := '-'
	if ctx.conn != unsafe { nil } {
		addr := ctx.conn.peer_ip() or { return }
		ip = addr.str()
	}
	// 请求结束时记录（通过 defer）
	defer {
		elapsed := time.ticks() - start
		m.log_.info('[HTTP] ${method} ${path} | ${ip} | ${elapsed}ms')
	}
}

// ═══════════════════════════════════════════════════════════
// CORS 中间件
// ═══════════════════════════════════════════════════════════

pub struct CorsMiddleware {
pub mut:
	allowed_origins []string
	allowed_methods string = 'GET, POST, PUT, DELETE, PATCH, OPTIONS'
	allowed_headers string = 'Content-Type, Authorization, X-CSRF-TOKEN'
}

pub fn new_cors_middleware() &CorsMiddleware {
	return &CorsMiddleware{
		allowed_origins: ['*']
	}
}

pub fn (m &CorsMiddleware) handle(mut ctx veb.Context) ! {
	mut origin := ''
	if header := ctx.get_custom_header('Origin') {
		origin = header
	}
	if origin.len > 0 {
		mut allowed := false
		for o in m.allowed_origins {
			if o == '*' || o == origin {
				allowed = true
				break
			}
		}
		if allowed {
			ctx.set_custom_header('Access-Control-Allow-Origin', if m.allowed_origins[0] == '*' { '*' } else { origin }) or {}
			ctx.set_custom_header('Access-Control-Allow-Methods', m.allowed_methods) or {}
			ctx.set_custom_header('Access-Control-Allow-Headers', m.allowed_headers) or {}
			ctx.set_custom_header('Access-Control-Allow-Credentials', 'true') or {}
		}
	}
	// OPTIONS 预检请求直接返回
	if ctx.req.method == .options {
		ctx.send_response_to_client('text/plain', '')
		return
	}
}

// ═══════════════════════════════════════════════════════════
// JWT 认证中间件
// ═══════════════════════════════════════════════════════════

pub struct AuthMiddleware {
pub mut:
	auth_svc   &AuthService
	required_role string // 空字符串=仅需登录, 非空=需要指定角色
}

pub fn new_auth_middleware(auth_svc &AuthService) &AuthMiddleware {
	return unsafe { &AuthMiddleware{auth_svc: auth_svc} }
}

// authenticate 提取并验证 JWT token，返回用户名和角色
pub fn (m &AuthMiddleware) authenticate(mut ctx veb.Context) !(string, string) {
	auth_header := ctx.get_custom_header('Authorization') or {
		return error('Authorization header required')
	}
	if !auth_header.starts_with('Bearer ') {
		return error('Authorization must be Bearer <token>')
	}
	token := auth_header[7..]
	return m.auth_svc.jwt_mgr.validate_token(token)
}

// authorize_role 检查角色是否满足要求
pub fn (m &AuthMiddleware) authorize_role(role string, required_role string) bool {
	if required_role.len == 0 {
		return true // 不需要特定角色
	}
	// required层级：ADMIN > MODERATOR > USER
	mut hierarchy := map[string][]string{}
	hierarchy['ADMIN'] = ['ADMIN', 'MODERATOR', 'USER']
	hierarchy['MODERATOR'] = ['MODERATOR', 'USER']
	hierarchy['USER'] = ['USER']
	allowed := hierarchy[required_role] or { return role == required_role }
	for r in allowed {
		if role == r {
			return true
		}
	}
	return false
}

// ═══════════════════════════════════════════════════════════
// 限流中间件（内存滑动窗口）
// ═══════════════════════════════════════════════════════════

pub struct RateLimitMiddleware {
pub mut:
	limits map[string][]i64
	max_requests int = 60
	window_secs  int = 60
mut:
	mu sync.Mutex
}

pub fn new_rate_limit_middleware(max_requests int, window_secs int) &RateLimitMiddleware {
	return &RateLimitMiddleware{
		max_requests: max_requests
		window_secs: window_secs
	}
}

pub fn (mut m RateLimitMiddleware) handle(ip string) ! {
	m.mu.@lock()
	defer { m.mu.unlock() }
	now := time.now().unix()
	// 清理过期记录
	mut timestamps := m.limits[ip] or { []i64{} }
	mut valid := []i64{}
	for ts in timestamps {
		if now - ts < i64(m.window_secs) {
			valid << ts
		}
	}
	if valid.len >= m.max_requests {
		return error('rate limit exceeded, try again in ${m.window_secs} seconds')
	}
	valid << now
	m.limits[ip] = valid
}

// ═══════════════════════════════════════════════════════════
// 中间件管理器 — 统一挂载和编排
// ═══════════════════════════════════════════════════════════

pub struct MiddlewareManager {
pub mut:
	request_log  &RequestLogMiddleware
	cors         &CorsMiddleware
	auth         &AuthMiddleware
	rate_limit   &RateLimitMiddleware
}

pub fn new_middleware_manager(log_ &logger.Logger, auth_svc &AuthService) &MiddlewareManager {
	return &MiddlewareManager{
		request_log: new_request_log_middleware(log_)
		cors: new_cors_middleware()
		auth: new_auth_middleware(auth_svc)
		rate_limit: new_rate_limit_middleware(120, 60) // 每分钟 120 次
	}
}

// apply_global 执行全局中间件（每次请求都执行）
pub fn (m &MiddlewareManager) apply_global(mut ctx veb.Context) ! {
	m.cors.handle(mut ctx)!
	m.request_log.handle(mut ctx)!
}

// apply_auth 执行认证中间件
pub fn (m &MiddlewareManager) apply_auth(mut ctx veb.Context) !(string, string) {
	return m.auth.authenticate(mut ctx)
}

// apply_role 执行角色授权
pub fn (m &MiddlewareManager) apply_role(mut ctx veb.Context, role string) !(string, string) {
	username, user_role := m.auth.authenticate(mut ctx)!
	if !m.auth.authorize_role(user_role, role) {
		return error('permission denied, role ${role} required')
	}
	return username, user_role
}

// apply_rate_limit 执行限流
pub fn (mut m MiddlewareManager) apply_rate_limit(ip string) ! {
	m.rate_limit.handle(ip)!
}

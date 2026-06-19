module main

// middleware.v — PhotonBlog HTTP 中间件链
//
// 实现 6 个中间件 + 1 个统一管理器：
//   1. RequestLogMiddleware  — 请求日志 + 耗时统计
//   2. CorsMiddleware        — CORS 跨域，可配置 allowed_origins/methods/headers
//   3. RequestIdMiddleware   — 生成 UUID 风格 request_id，注入 logger MDC
//   4. RateLimitMiddleware   — 基于 IP 的滑动窗口限流，60 次/分钟
//   5. JwtAuthMiddleware     — 提取 Bearer token，调用 AuthService.validate_token
//   6. RoleAuthMiddleware    — 基于 RoleHierarchy 的角色校验，ADMIN > EDITOR > USER
//
// MiddlewareManager 统一管理所有中间件，提供 apply_global/apply_auth/apply_role/apply_rate_limit 方法。

import veb
import photon.security
import photon.logger
import photon.web
import time
import sync
import crypto.rand
import encoding.hex

// ═══════════════════════════════════════════════════════════
// RequestLogMiddleware — 请求日志 + 耗时统计
// ═══════════════════════════════════════════════════════════

pub struct RequestLogMiddleware {
pub:
	log &logger.Logger
}

pub fn new_request_log_middleware(log &logger.Logger) &RequestLogMiddleware {
	return &RequestLogMiddleware{
		log: log
	}
}

// handle 记录请求日志（方法、路径、IP）并在请求结束时统计耗时
pub fn (m &RequestLogMiddleware) handle(mut ctx veb.Context) {
	start := time.ticks()
	method := ctx.req.method.str()
	path := ctx.req.url
	ip := web.client_ip(&ctx)

	defer {
		elapsed := time.ticks() - start
		status := ctx.res.status_code
		m.log.info('[HTTP] ${method} ${path} | IP: ${ip} | ${status} | ${elapsed}ms')
	}
}

// ═══════════════════════════════════════════════════════════
// CorsMiddleware — CORS 跨域
// ═══════════════════════════════════════════════════════════

pub struct CorsMiddleware {
pub mut:
	allowed_origins []string
	allowed_methods string = 'GET, POST, PUT, DELETE, PATCH, OPTIONS'
	allowed_headers string = 'Content-Type, Authorization, X-Requested-With, X-CSRF-TOKEN, X-Request-Id'
}

pub fn new_cors_middleware() &CorsMiddleware {
	return &CorsMiddleware{
		allowed_origins: ['*']
	}
}

// handle 设置 CORS 响应头，处理 OPTIONS 预检请求
pub fn (m &CorsMiddleware) handle(mut ctx veb.Context) {
	origin := ctx.get_custom_header('Origin') or { '' }

	if origin.len > 0 {
		mut allowed := false
		for o in m.allowed_origins {
			if o == '*' || o == origin {
				allowed = true
				break
			}
		}
		if allowed {
			allow_origin := if m.allowed_origins[0] == '*' { '*' } else { origin }
			ctx.set_custom_header('Access-Control-Allow-Origin', allow_origin) or {}
			ctx.set_custom_header('Access-Control-Allow-Methods', m.allowed_methods) or {}
			ctx.set_custom_header('Access-Control-Allow-Headers', m.allowed_headers) or {}
			ctx.set_custom_header('Access-Control-Allow-Credentials', 'true') or {}
			ctx.set_custom_header('Access-Control-Max-Age', '3600') or {}
		}
	}

	// OPTIONS 预检请求直接返回
	if ctx.req.method == .options {
		ctx.send_response_to_client('text/plain', '')
	}
}

// ═══════════════════════════════════════════════════════════
// RequestIdMiddleware — 生成 UUID 风格 request_id
// ═══════════════════════════════════════════════════════════

pub struct RequestIdMiddleware {
pub:
	log &logger.Logger
}

pub fn new_request_id_middleware(log &logger.Logger) &RequestIdMiddleware {
	return &RequestIdMiddleware{
		log: log
	}
}

// handle 生成 UUID v4 风格 request_id，注入 logger MDC 并设置响应头
pub fn (m &RequestIdMiddleware) handle(mut ctx veb.Context) string {
	request_id := generate_request_id()

	// 注入到 logger MDC（Mapped Diagnostic Context）
	mut log := m.log
	log.put('request_id', request_id)

	// 设置响应头，方便客户端追踪
	ctx.set_custom_header('X-Request-Id', request_id) or {}

	return request_id
}

// generate_request_id 生成 UUID v4 风格的请求 ID
// 格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
fn generate_request_id() string {
	mut bytes := rand.read(16) or {
		// Fallback: 基于时间戳生成
		mut fallback := []u8{len: 16}
		ts := time.now().unix_nano()
		for i in 0 .. 16 {
			fallback[i] = u8((ts >> ((i % 8) * 8)) & 0xff)
		}
		fallback
	}

	// 设置 version 4 和 variant 位（UUID v4 规范）
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	hex_str := hex.encode(bytes)
	// 格式化为 UUID：8-4-4-4-12
	return '${hex_str[0..8]}-${hex_str[8..12]}-${hex_str[12..16]}-${hex_str[16..20]}-${hex_str[20..32]}'
}

// ═══════════════════════════════════════════════════════════
// RateLimitMiddleware — 基于 IP 的滑动窗口限流
// ═══════════════════════════════════════════════════════════

pub struct RateLimitMiddleware {
pub mut:
	max_requests int = 60 // 每分钟最大请求数
	window_secs  int = 60 // 滑动窗口大小（秒）
mut:
	limits map[string][]i64 // IP -> 请求时间戳列表
	mu     sync.Mutex
}

pub fn new_rate_limit_middleware() &RateLimitMiddleware {
	return &RateLimitMiddleware{
		max_requests: 60
		window_secs:  60
	}
}

// handle 滑动窗口限流：清理过期记录 → 检查阈值 → 记录本次请求
pub fn (mut m RateLimitMiddleware) handle(ip string) ! {
	m.mu.@lock()
	defer { m.mu.unlock() }

	now := time.now().unix()

	// 获取该 IP 的历史请求时间戳
	mut timestamps := m.limits[ip] or { []i64{} }

	// 清理过期记录（超出滑动窗口）
	mut valid := []i64{}
	for ts in timestamps {
		if now - ts < i64(m.window_secs) {
			valid << ts
		}
	}

	// 检查是否超过阈值
	if valid.len >= m.max_requests {
		m.limits[ip] = valid
		return error('rate limit exceeded — try again in ${m.window_secs} seconds (limit: ${m.max_requests}/min)')
	}

	// 记录本次请求
	valid << now
	m.limits[ip] = valid
}

// ═══════════════════════════════════════════════════════════
// JwtAuthMiddleware — JWT 认证
// ═══════════════════════════════════════════════════════════

pub struct JwtAuthMiddleware {
pub:
	auth_svc &AuthService
}

pub fn new_jwt_auth_middleware(auth_svc &AuthService) &JwtAuthMiddleware {
	return unsafe {
		&JwtAuthMiddleware{
			auth_svc: auth_svc
		}
	}
}

// authenticate 提取 Bearer token 并验证，返回 (username, roles)
pub fn (m &JwtAuthMiddleware) authenticate(mut ctx veb.Context) !(string, []string) {
	auth_header := ctx.get_custom_header('Authorization') or {
		return error('Authorization header required / 缺少认证头')
	}

	if !auth_header.starts_with('Bearer ') {
		return error('Authorization must be Bearer <token> / 认证格式错误，需 Bearer 令牌')
	}

	token := auth_header[7..]

	// 验证 token，获取用户名
	username := m.auth_svc.validate_token(token) or {
		return error('invalid or expired token / 令牌无效或已过期: ${err}')
	}

	// 解析 token 获取角色信息
	claims := m.auth_svc.parse_token(token) or {
		return error('failed to parse token / 令牌解析失败: ${err}')
	}

	return username, claims.roles
}

// ═══════════════════════════════════════════════════════════
// RoleAuthMiddleware — 基于 RoleHierarchy 的角色校验
// ═══════════════════════════════════════════════════════════

pub struct RoleAuthMiddleware {
pub:
	role_hierarchy &security.RoleHierarchy
}

pub fn new_role_auth_middleware(rh &security.RoleHierarchy) &RoleAuthMiddleware {
	return unsafe {
		&RoleAuthMiddleware{
			role_hierarchy: rh
		}
	}
}

// authorize 基于 RoleHierarchy 校验用户是否拥有所需角色中的任一个
// 角色层级：ADMIN > EDITOR > USER（ADMIN 继承 EDITOR 和 USER 的权限）
pub fn (m &RoleAuthMiddleware) authorize(required_roles []string, user_roles []string) ! {
	if required_roles.len == 0 {
		return // 无角色要求，直接通过
	}

	if m.role_hierarchy.has_any_role(user_roles, required_roles) {
		return
	}

	return error('permission denied — required roles: ${required_roles.join(', ')} / 权限不足，需要角色: ${required_roles.join(', ')}')
}

// ═══════════════════════════════════════════════════════════
// MiddlewareManager — 统一中间件管理器
// ═══════════════════════════════════════════════════════════

pub struct MiddlewareManager {
pub mut:
	request_log    &RequestLogMiddleware
	cors           &CorsMiddleware
	request_id     &RequestIdMiddleware
	rate_limit     &RateLimitMiddleware
	jwt_auth       &JwtAuthMiddleware
	role_auth      &RoleAuthMiddleware
	auth_svc       &AuthService
	logger         &logger.Logger
	role_hierarchy &security.RoleHierarchy
}

// new_middleware_manager 创建中间件管理器，装配所有中间件
pub fn new_middleware_manager(auth_svc &AuthService, rh &security.RoleHierarchy, log &logger.Logger) &MiddlewareManager {
	return unsafe {
		&MiddlewareManager{
			request_log: new_request_log_middleware(log)
			cors: new_cors_middleware()
			request_id: new_request_id_middleware(log)
			rate_limit: new_rate_limit_middleware()
			jwt_auth: new_jwt_auth_middleware(auth_svc)
			role_auth: new_role_auth_middleware(rh)
			auth_svc: auth_svc
			logger: log
			role_hierarchy: rh
		}
	}
}

// apply_global 应用全局中间件（CORS + 请求ID + 请求日志）
// 每次请求都执行，不涉及认证与限流
pub fn (mm &MiddlewareManager) apply_global(mut ctx veb.Context) ! {
	// 1. 生成 request_id 并注入 logger MDC
	mm.request_id.handle(mut ctx)

	// 2. CORS 跨域头
	mm.cors.handle(mut ctx)

	// 3. 请求日志 + 耗时统计
	mm.request_log.handle(mut ctx)
}

// apply_auth 应用 JWT 认证，返回 (username, roles)
pub fn (mm &MiddlewareManager) apply_auth(mut ctx veb.Context) !(string, []string) {
	return mm.jwt_auth.authenticate(mut ctx)
}

// apply_role 应用角色校验，基于 RoleHierarchy 检查用户是否拥有所需角色
pub fn (mm &MiddlewareManager) apply_role(required_roles []string, user_roles []string) ! {
	mm.role_auth.authorize(required_roles, user_roles)!
}

// apply_rate_limit 应用限流（基于 IP 的滑动窗口，60 次/分钟）
pub fn (mut mm MiddlewareManager) apply_rate_limit(ip string) ! {
	mm.rate_limit.handle(ip)!
}

module main

// middleware.v — PhotonBlog HTTP 中间件
//
// 实现 6 个中间件（由 MiddlewareGroupRegistry 统一编排，见 app/Http/Middleware/registry.v）：
//   1. RequestLogMiddleware  — 请求日志 + 耗时统计
//   2. CorsMiddleware        — CORS 跨域，参数从 config/web.v 读取
//   3. RequestIdMiddleware   — 生成 UUID 风格 request_id，注入 logger MDC + 写回 Context
//   4. RateLimitMiddleware   — 基于 IP 的滑动窗口限流，参数从 config/web.v 读取
//   5. JwtAuthMiddleware     — 提取 Bearer token，调用 AuthService.validate_token
//   6. RoleAuthMiddleware    — 基于 RoleHierarchy 的角色校验，ADMIN > EDITOR > USER
//
// 中间件组注册表（MiddlewareGroupRegistry）替代原 MiddlewareManager，
// 提供命名组（web/api/auth/admin/editor）与 apply 方法。

import veb
import photon.security
import photon.logger
import photon.web
import time
import sync

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

// handle 生成 UUID v4 风格 request_id，注入 logger MDC，写回 Context 并设置响应头
// 统一由本中间件生成 request_id，移除 before_request() 中的重复生成逻辑（SubTask 9.5）
pub fn (m &RequestIdMiddleware) handle(mut ctx Context) {
	request_id := generate_request_id()

	// 写回 Context（供后续中间件与控制器使用）
	ctx.request_id = request_id

	// 注入到 logger MDC（Mapped Diagnostic Context）
	mut log := m.log
	log.put('request_id', request_id)

	// 设置响应头，方便客户端追踪
	ctx.set_custom_header('X-Request-Id', request_id) or {}
}

// generate_request_id 已迁移至 helpers.v

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
// CsrfMiddleware — CSRF 跨站请求伪造防护
// ═══════════════════════════════════════════════════════════
//
// 基于 Double-Submit Cookie 模式（由 security.CsrfManager 实现）：
//   1. 客户端首次 GET 请求时，服务端通过 Set-Cookie 下发 XSRF-TOKEN
//   2. 客户端后续状态变更请求（POST/PUT/PATCH/DELETE）需在 X-CSRF-TOKEN
//      头或 _csrf 表单字段中回传同一 token
//   3. 本中间件对比 cookie 中的 token 与请求头/表单中的 token
//
// 仅对 'web' 中间件组启用（Web 表单路由）；
// 'api' 组使用 JWT Bearer 令牌，天然免疫 CSRF，无需此中间件。
//
// Laravel 等价：VerifyCsrfToken 中间件（$except 配置忽略路径）

pub struct CsrfMiddleware {
pub:
	mgr &security.CsrfManager
}

pub fn new_csrf_middleware(mgr &security.CsrfManager) &CsrfMiddleware {
	return &CsrfMiddleware{
		mgr: mgr
	}
}

// handle 校验 CSRF token
// 对 GET/HEAD/OPTIONS/TRACE 等安全方法直接放行（由 CsrfConfig.ignored_methods 配置）
// 对状态变更方法（POST/PUT/PATCH/DELETE）校验 X-CSRF-TOKEN 头或 _csrf 表单字段
// 校验失败时抛出错误，由调用方（apply_web_group）转换为 403 响应
pub fn (m &CsrfMiddleware) handle(mut ctx veb.Context) ! {
	method := ctx.req.method.str()

	// 安全方法直接放行
	if !m.mgr.is_csrf_required(method) {
		return
	}

	// 提取请求头中的 token（X-CSRF-TOKEN）与表单字段（_csrf）
	actual_header := ctx.get_custom_header(m.mgr.config.header_name) or { '' }
	actual_form := ctx.get_custom_header(m.mgr.config.form_field_name) or { '' }
	actual := m.mgr.get_actual_token(actual_header, actual_form)

	// 从 cookie 存储中读取期望 token
	mut mgr := m.mgr
	expected := mgr.get_expected_token()

	// 若期望 token 为空（首次请求或 cookie 失效），跳过校验
	// 由后续 GET 请求重新下发 cookie，避免首次 POST 即被拒绝
	if expected.len == 0 {
		return
	}

	m.mgr.validate(actual, expected)!
}

// ═══════════════════════════════════════════════════════════
// 中间件组编排
// ═══════════════════════════════════════════════════════════
//
// MiddlewareManager 已移除（SubTask 9.4），改由 MiddlewareGroupRegistry 统一编排。
// 见 app/Http/Middleware/registry.v：
//   - apply_web_group()  — CORS + RequestId + RequestLog + CSRF
//   - apply_api_group()  — web + RateLimit（CSRF 由 api 组跳过，因 API 使用 JWT）
//   - authenticate()     — JWT 认证（写回 Context）
//   - authorize()        — 角色校验
//   - apply_group(name)  — 按命名组应用（auth/admin/editor）
//
// 关于 security.SecurityFilterChain：
//   框架 SecurityFilterChain 基于 &veb.Context（与 veb 中间件签名一致），
//   但其内置 CSRF/JWT/角色校验逻辑与 Demo 的 MiddlewareGroupRegistry 职责重叠。
//   为保持单一中间件编排入口与类型安全的 Demo Context 访问（ctx.request_id 等），
//   Demo 选择复用自研 MiddlewareGroupRegistry，仅在 CsrfMiddleware 内部复用
//   security.CsrfManager 的 token 生成与校验能力（避免重复造轮子）。

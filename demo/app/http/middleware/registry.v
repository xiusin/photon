module middleware

import veb
import sync
import time
import photon.logger
import photon.security
import photon.web
import util
import appconfig
import services

// ═══════════════════════════════════════════════════════════
// MiddlewareGroupRegistry — 中间件组注册表
// ═══════════════════════════════════════════════════════════

@[heap]
pub struct MiddlewareGroupRegistry {
pub:
	cors        &CorsMiddleware
	request_id  &RequestIdMiddleware
	request_log &RequestLogMiddleware
pub mut:
	rate_limit  &RateLimitMiddleware
	jwt_auth    &JwtAuthMiddleware
	role_auth   &RoleAuthMiddleware
	csrf        &CsrfMiddleware
	logger      &logger.Logger
	groups map[string][]string // group_name -> middleware spec list
}

// new_middleware_group_registry 创建中间件组注册表
pub fn new_middleware_group_registry(
	cfg appconfig.WebConfig,
	auth_svc &services.AuthService,
	rh &security.RoleHierarchy,
	csrf_mgr &security.CsrfManager,
	log &logger.Logger,
) &MiddlewareGroupRegistry {
	// CORS 配置从 config/web.v 读取
	cors := &CorsMiddleware{
		allowed_origins: parse_cors_origins(cfg.cors_allowed_origins)
		allowed_methods: cfg.cors_allowed_methods
		allowed_headers: cfg.cors_allowed_headers
	}

	// RateLimit 配置从 config/web.v 读取
	rate_limit := &RateLimitMiddleware{
		max_requests: cfg.rate_limit_max_requests
		window_secs:  cfg.rate_limit_window_secs
	}

	// CSRF 中间件
	csrf := if isnil(csrf_mgr) {
		new_csrf_middleware(security.new_csrf_manager(security.CsrfConfig{
			enabled: false
		}))
	} else {
		new_csrf_middleware(csrf_mgr)
	}

	return &MiddlewareGroupRegistry{
		cors:        cors
		request_id:  new_request_id_middleware(log)
		request_log: new_request_log_middleware(log)
		rate_limit:  rate_limit
		jwt_auth:    new_jwt_auth_middleware(auth_svc)
		role_auth:   new_role_auth_middleware(rh)
		csrf:        csrf
		logger:      log
		groups: {
			'web':    ['cors', 'request_id', 'request_log', 'csrf']
			'api':    ['cors', 'request_id', 'request_log', 'rate_limit']
			'auth':   ['jwt_auth']
			'admin':  ['jwt_auth', 'role:ADMIN']
			'editor': ['jwt_auth', 'role:EDITOR,ADMIN']
		}
	}
}

fn parse_cors_origins(s string) []string {
	if s.len == 0 || s == '*' {
		return ['*']
	}
	mut origins := []string{}
	for part in s.split(',') {
		trimmed := part.trim_space()
		if trimmed.len > 0 {
			origins << trimmed
		}
	}
	if origins.len == 0 {
		return ['*']
	}
	return origins
}

fn parse_role_spec(spec string) []string {
	parts := spec.split(':')
	if parts.len < 2 {
		return []
	}
	mut roles := []string{}
	for r in parts[1].split(',') {
		trimmed := r.trim_space()
		if trimmed.len > 0 {
			roles << trimmed
		}
	}
	return roles
}

// ═══════════════════════════════════════════════════════════
// 组应用方法
// ═══════════════════════════════════════════════════════════

// apply_web_group 应用 web 组中间件，返回 request_id
pub fn (reg &MiddlewareGroupRegistry) apply_web_group(mut ctx veb.Context) !string {
	reg.cors.handle(mut ctx)
	request_id := reg.request_id.handle(mut ctx)
	reg.request_log.handle(mut ctx)
	reg.csrf.handle(mut ctx)!
	return request_id
}

// apply_api_group 应用 api 组中间件，返回 request_id
pub fn (mut reg MiddlewareGroupRegistry) apply_api_group(mut ctx veb.Context) !string {
	reg.cors.handle(mut ctx)
	request_id := reg.request_id.handle(mut ctx)
	reg.request_log.handle(mut ctx)

	ip := web.client_ip(&ctx)
	reg.rate_limit.handle(ip)!

	return request_id
}

// authenticate 应用 JWT 认证，返回 (username, roles)
pub fn (mut reg MiddlewareGroupRegistry) authenticate(mut ctx veb.Context) !(string, []string) {
	return reg.jwt_auth.authenticate(mut ctx)!
}

// authorize 应用角色校验
pub fn (reg &MiddlewareGroupRegistry) authorize(required_roles []string, user_roles []string) ! {
	return reg.role_auth.authorize(required_roles, user_roles)
}

// apply_group 应用指定组的中间件链，返回 (username, roles)
pub fn (mut reg MiddlewareGroupRegistry) apply_group(mut ctx veb.Context, group string) !(string, []string) {
	middlewares := reg.groups[group] or {
		return error('middleware group not found: ${group}')
	}

	mut username := ''
	mut roles := []string{}

	for mw in middlewares {
		if mw == 'jwt_auth' {
			username, roles = reg.jwt_auth.authenticate(mut ctx)!
		} else if mw.starts_with('role:') {
			required := parse_role_spec(mw)
			reg.role_auth.authorize(required, roles)!
		}
	}

	return username, roles
}

// has_group 检查组是否已注册
pub fn (reg &MiddlewareGroupRegistry) has_group(name string) bool {
	return name in reg.groups
}

// group_names 返回所有已注册的组名
pub fn (reg &MiddlewareGroupRegistry) group_names() []string {
	mut names := []string{}
	for name, _ in reg.groups {
		names << name
	}
	return names
}

// middlewares_of 返回指定组的中间件规范列表
pub fn (reg &MiddlewareGroupRegistry) middlewares_of(name string) []string {
	return reg.groups[name] or { []string{} }
}

// ═══════════════════════════════════════════════════════════
// 中间件类型定义
// ═══════════════════════════════════════════════════════════

// RequestLogMiddleware — 请求日志 + 耗时统计
pub struct RequestLogMiddleware {
pub:
	log &logger.Logger
}

pub fn new_request_log_middleware(log &logger.Logger) &RequestLogMiddleware {
	return &RequestLogMiddleware{log: log}
}

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

// CorsMiddleware — CORS 跨域
pub struct CorsMiddleware {
pub mut:
	allowed_origins []string
	allowed_methods string = 'GET, POST, PUT, DELETE, PATCH, OPTIONS'
	allowed_headers string = 'Content-Type, Authorization, X-Requested-With, X-CSRF-TOKEN, X-Request-Id'
}

pub fn new_cors_middleware() &CorsMiddleware {
	return &CorsMiddleware{allowed_origins: ['*']}
}

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

	if ctx.req.method == .options {
		ctx.send_response_to_client('text/plain', '')
	}
}

// RequestIdMiddleware — 生成 UUID 风格 request_id
pub struct RequestIdMiddleware {
pub:
	log &logger.Logger
}

pub fn new_request_id_middleware(log &logger.Logger) &RequestIdMiddleware {
	return &RequestIdMiddleware{log: log}
}

// handle 生成 request_id，注入 logger MDC，设置响应头，返回 request_id
pub fn (m &RequestIdMiddleware) handle(mut ctx veb.Context) string {
	request_id := util.generate_request_id()

	mut log := m.log
	log.put('request_id', request_id)

	ctx.set_custom_header('X-Request-Id', request_id) or {}

	return request_id
}

// RateLimitMiddleware — 基于 IP 的滑动窗口限流
pub struct RateLimitMiddleware {
pub mut:
	max_requests int = 60
	window_secs  int = 60
mut:
	limits map[string][]i64
	mu     sync.Mutex
}

pub fn new_rate_limit_middleware() &RateLimitMiddleware {
	return &RateLimitMiddleware{max_requests: 60, window_secs: 60}
}

pub fn (mut m RateLimitMiddleware) handle(ip string) ! {
	m.mu.@lock()
	defer { m.mu.unlock() }

	now := time.now().unix()
	mut timestamps := m.limits[ip] or { []i64{} }

	mut valid := []i64{}
	for ts in timestamps {
		if now - ts < i64(m.window_secs) {
			valid << ts
		}
	}

	if valid.len >= m.max_requests {
		m.limits[ip] = valid
		return error('rate limit exceeded — try again in ${m.window_secs} seconds (limit: ${m.max_requests}/min)')
	}

	valid << now
	m.limits[ip] = valid
}

// JwtAuthMiddleware — JWT 认证
pub struct JwtAuthMiddleware {
pub:
	auth_svc &services.AuthService
}

pub fn new_jwt_auth_middleware(auth_svc &services.AuthService) &JwtAuthMiddleware {
	return unsafe { &JwtAuthMiddleware{auth_svc: auth_svc} }
}

pub fn (mut m JwtAuthMiddleware) authenticate(mut ctx veb.Context) !(string, []string) {
	auth_header := ctx.get_custom_header('Authorization') or {
		return error('Authorization header required / 缺少认证头')
	}

	if !auth_header.starts_with('Bearer ') {
		return error('Authorization must be Bearer <token> / 认证格式错误，需 Bearer 令牌')
	}

	token := auth_header[7..]

	mut auth_svc := unsafe { m.auth_svc }
	username := auth_svc.validate_token(token) or {
		return error('invalid or expired token / 令牌无效或已过期: ${err}')
	}

	claims := auth_svc.parse_token(token) or {
		return error('failed to parse token / 令牌解析失败: ${err}')
	}

	return username, claims.roles
}

// RoleAuthMiddleware — 基于 RoleHierarchy 的角色校验
pub struct RoleAuthMiddleware {
pub:
	role_hierarchy &security.RoleHierarchy
}

pub fn new_role_auth_middleware(rh &security.RoleHierarchy) &RoleAuthMiddleware {
	return unsafe { &RoleAuthMiddleware{role_hierarchy: rh} }
}

pub fn (m &RoleAuthMiddleware) authorize(required_roles []string, user_roles []string) ! {
	if required_roles.len == 0 {
		return
	}

	if m.role_hierarchy.has_any_role(user_roles, required_roles) {
		return
	}

	return error('permission denied — required roles: ${required_roles.join(', ')} / 权限不足，需要角色: ${required_roles.join(', ')}')
}

// CsrfMiddleware — CSRF 跨站请求伪造防护
pub struct CsrfMiddleware {
pub:
	mgr &security.CsrfManager
}

pub fn new_csrf_middleware(mgr &security.CsrfManager) &CsrfMiddleware {
	return &CsrfMiddleware{mgr: mgr}
}

pub fn (m &CsrfMiddleware) handle(mut ctx veb.Context) ! {
	method := ctx.req.method.str()

	if !m.mgr.is_csrf_required(method) {
		return
	}

	actual_header := ctx.get_custom_header(m.mgr.config.header_name) or { '' }
	actual_form := ctx.get_custom_header(m.mgr.config.form_field_name) or { '' }
	actual := m.mgr.get_actual_token(actual_header, actual_form)

	mut mgr := m.mgr
	expected := mgr.get_expected_token()

	if expected.len == 0 {
		return
	}

	m.mgr.validate(actual, expected)!
}

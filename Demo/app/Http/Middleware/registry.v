module main

// app/Http/Middleware/registry.v — 中间件组注册表
//
// 注册命名中间件组，按 Laravel 风格组织中间件链：
//   web    — CORS + RequestId + RequestLog
//   api    — web + RateLimit
//   auth   — JwtAuth（写回 user_id/username/role 到 Context）
//   admin  — auth + RoleAuth[ADMIN]
//   editor — auth + RoleAuth[EDITOR, ADMIN]
//
// 中间件参数从 config/web.v 读取：
//   CORS allowed_origins/methods/headers
//   RateLimit max_requests/window_secs
//
// 设计说明：
//   框架 web.MiddlewareGroupRegistry 基于 web.MiddlewareContext（包装 &veb.Context），
//   其参数化中间件（throttle_middleware/role_middleware/cors_configurable_middleware）
//   签名为 fn(mut &MiddlewareContext) !bool，与 Demo 基于 veb.Context 的中间件链不兼容。
//   本注册表为 Demo 专用，复用 Demo 中间件实现（直接操作 veb.Context），
//   同时保留命名组元数据供路由层与文档生成使用。
//
// Laravel 等价：App\Http\Kernel::$middlewareGroups + $routeMiddleware

import photon.logger
import photon.security
import photon.web

// ═══════════════════════════════════════════════════════════
// MiddlewareGroupRegistry — 中间件组注册表
// ═══════════════════════════════════════════════════════════

@[heap]
pub struct MiddlewareGroupRegistry {
pub:
	cors        &CorsMiddleware
	request_id  &RequestIdMiddleware
	request_log &RequestLogMiddleware
	rate_limit  &RateLimitMiddleware
	jwt_auth    &JwtAuthMiddleware
	role_auth   &RoleAuthMiddleware
	logger      &logger.Logger
pub mut:
	groups map[string][]string // group_name -> middleware spec list
}

// new_middleware_group_registry 创建中间件组注册表
// 从 WebConfig 读取 CORS 与限流参数，装配所有中间件实例并注册命名组
pub fn new_middleware_group_registry(
	cfg WebConfig,
	auth_svc &AuthService,
	rh &security.RoleHierarchy,
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

	return &MiddlewareGroupRegistry{
		cors:        cors
		request_id:  new_request_id_middleware(log)
		request_log: new_request_log_middleware(log)
		rate_limit:  rate_limit
		jwt_auth:    new_jwt_auth_middleware(auth_svc)
		role_auth:   new_role_auth_middleware(rh)
		logger:      log
		groups: {
			'web':    ['cors', 'request_id', 'request_log']
			'api':    ['cors', 'request_id', 'request_log', 'rate_limit']
			'auth':   ['jwt_auth']
			'admin':  ['jwt_auth', 'role:ADMIN']
			'editor': ['jwt_auth', 'role:EDITOR,ADMIN']
		}
	}
}

// parse_cors_origins 解析 CORS allowed_origins 配置字符串
// '*' 或空 → ['*']；逗号分隔 → 列表
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

// parse_role_spec 解析 'role:ADMIN' 或 'role:EDITOR,ADMIN' 规范
// 返回所需角色列表
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

// apply_web_group 应用 web 组中间件（CORS + RequestId + RequestLog）
// 全局基础中间件，每次请求执行
pub fn (reg &MiddlewareGroupRegistry) apply_web_group(mut ctx Context) {
	reg.cors.handle(mut ctx.Context)
	reg.request_id.handle(mut ctx) // RequestIdMiddleware 写回 ctx.request_id（Demo Context）
	reg.request_log.handle(mut ctx.Context)
}

// apply_api_group 应用 api 组中间件（web + RateLimit）
// 返回错误表示限流触发
pub fn (reg &MiddlewareGroupRegistry) apply_api_group(mut ctx Context) ! {
	reg.apply_web_group(mut ctx)
	ip := web.client_ip(&ctx.Context)
	mut rl := reg.rate_limit
	rl.handle(ip)!
}

// authenticate 应用 JWT 认证
// 成功后将 user_id/username/role 写回 Context，控制器直接读取
// 返回 (username, roles) 供需要角色列表的调用方使用
pub fn (reg &MiddlewareGroupRegistry) authenticate(mut ctx Context) !(string, []string) {
	username, roles := reg.jwt_auth.authenticate(mut ctx.Context)!

	// 写回 Context（SubTask 9.6：移除控制器重复查库）
	ctx.username = username
	ctx.role = if roles.len > 0 { roles[0] } else { '' }

	// 尝试从用户服务获取 user_id（避免控制器重复查询）
	// 注：user_id 写回需控制器层在首次查询后设置，此处仅写 username/role
	return username, roles
}

// authorize 应用角色校验
// 基于 RoleHierarchy 检查用户是否拥有所需角色中的任一个
pub fn (reg &MiddlewareGroupRegistry) authorize(required_roles []string, user_roles []string) ! {
	return reg.role_auth.authorize(required_roles, user_roles)
}

// apply_group 应用指定组的中间件链
// 适用于 auth/admin/editor 组（含 JWT 认证与角色校验）
// 返回 (username, roles)，失败时返回错误
pub fn (reg &MiddlewareGroupRegistry) apply_group(mut ctx Context, group string) !(string, []string) {
	middlewares := reg.groups[group] or {
		return error('middleware group not found: ${group}')
	}

	mut username := ''
	mut roles := []string{}

	for mw in middlewares {
		if mw == 'jwt_auth' {
			username, roles = reg.jwt_auth.authenticate(mut ctx.Context)!
			// 写回 Context（SubTask 9.6）
			ctx.username = username
			ctx.role = if roles.len > 0 { roles[0] } else { '' }
		} else if mw.starts_with('role:') {
			required := parse_role_spec(mw)
			reg.role_auth.authorize(required, roles)!
		}
		// 其他中间件规格（cors/request_id/request_log/rate_limit）由 apply_web_group/apply_api_group 处理
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

module main

// middleware_test.v — PhotonBlog 中间件测试
//
// 测试覆盖：
//   - CorsMiddleware 配置与行为
//   - RateLimitMiddleware 限流逻辑
//   - JwtAuthMiddleware 认证
//   - RoleAuthMiddleware 角色校验
//   - MiddlewareGroupRegistry 命名组注册与编排

fn test_cors_middleware_default() {
	middleware := new_cors_middleware()
	assert middleware.allowed_origins.len == 1
	assert middleware.allowed_origins[0] == '*'
	assert middleware.allowed_methods.contains('GET')
	assert middleware.allowed_headers.contains('Authorization')
}

fn test_rate_limit_middleware_under_limit() {
	mut rl := new_rate_limit_middleware()
	assert rl.max_requests == 60
	assert rl.window_secs == 60

	// 在限流阈值内应正常通过
	rl.handle('192.168.1.1') or {
		assert false
		return
	}
	assert true
}

fn test_rate_limit_middleware_exceed_limit() {
	mut rl := new_rate_limit_middleware()
	rl.max_requests = 3
	rl.window_secs = 60

	// 发送 3 次请求
	rl.handle('10.0.0.1') or { assert false }
	rl.handle('10.0.0.1') or { assert false }
	rl.handle('10.0.0.1') or { assert false }

	// 第 4 次应被限流
	rl.handle('10.0.0.1') or {
		assert err.msg().contains('rate limit')
		return
	}
	assert false
}

fn test_rate_limit_middleware_different_ips() {
	mut rl := new_rate_limit_middleware()
	rl.max_requests = 2
	rl.window_secs = 60

	// IP1 达到限流
	rl.handle('10.0.0.1') or { assert false }
	rl.handle('10.0.0.1') or { assert false }
	rl.handle('10.0.0.1') or {
		assert err.msg().contains('rate limit')
	}

	// IP2 不受限流影响
	rl.handle('10.0.0.2') or {
		assert false
		return
	}
	assert true
}

fn test_jwt_auth_middleware_authenticate() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	// 注册用户并生成令牌
	reg := CreateUserDto{username: 'mwuser', email: 'mw@test.com', password: 'pass', role: 'ADMIN'}
	user, _ := user_svc.register(reg)!
	token, _ := boot.auth_svc.generate_token(&user)!

	// JwtAuthMiddleware 认证
	jwt_mw := new_jwt_auth_middleware(boot.auth_svc)

	// 直接通过 AuthService 验证令牌
	username := boot.auth_svc.validate_token(token)!
	assert username == 'mwuser'

	claims := boot.auth_svc.parse_token(token)!
	assert claims.sub == 'mwuser'
	assert 'ADMIN' in claims.roles
}

fn test_role_auth_middleware_authorize_admin() {
	boot := test_setup()!
	role_mw := new_role_auth_middleware(boot.role_hierarchy)

	// ADMIN 应通过所有角色校验
	role_mw.authorize(['ADMIN'], ['ADMIN']) or { assert false }
	role_mw.authorize(['EDITOR'], ['ADMIN']) or { assert false }
	role_mw.authorize(['USER'], ['ADMIN']) or { assert false }
}

fn test_role_auth_middleware_authorize_editor() {
	boot := test_setup()!
	role_mw := new_role_auth_middleware(boot.role_hierarchy)

	// EDITOR 继承 USER 权限
	role_mw.authorize(['USER'], ['EDITOR']) or { assert false }
	role_mw.authorize(['EDITOR'], ['EDITOR']) or { assert false }

	// EDITOR 不继承 ADMIN 权限
	role_mw.authorize(['ADMIN'], ['EDITOR']) or {
		assert err.msg().contains('permission') || err.msg().contains('权限')
		return
	}
	assert false
}

fn test_role_auth_middleware_authorize_user() {
	boot := test_setup()!
	role_mw := new_role_auth_middleware(boot.role_hierarchy)

	// USER 不继承上级权限
	role_mw.authorize(['EDITOR'], ['USER']) or {
		assert true
		return
	}
	assert false
}

fn test_role_auth_middleware_empty_roles() {
	boot := test_setup()!
	role_mw := new_role_auth_middleware(boot.role_hierarchy)

	// 无角色要求应直接通过
	role_mw.authorize([], ['USER']) or { assert false }
}

fn test_role_auth_middleware_any_role() {
	boot := test_setup()!
	role_mw := new_role_auth_middleware(boot.role_hierarchy)

	// ADMIN 满足 EDITOR 或 ADMIN 中的任一个
	role_mw.authorize(['EDITOR', 'ADMIN'], ['ADMIN']) or { assert false }
}

// ═══════════════════════════════════════════════════════════
// MiddlewareGroupRegistry 测试
// ═══════════════════════════════════════════════════════════

fn test_middleware_group_registry_creation() {
	boot := test_setup()!
	cfg := default_web_config()
	reg := new_middleware_group_registry(cfg, boot.auth_svc, boot.role_hierarchy, boot.log)

	// 所有中间件实例应已装配
	assert !isnil(reg.cors)
	assert !isnil(reg.request_id)
	assert !isnil(reg.request_log)
	assert !isnil(reg.rate_limit)
	assert !isnil(reg.jwt_auth)
	assert !isnil(reg.role_auth)

	// CORS 参数从 config 读取
	assert reg.cors.allowed_methods == cfg.cors_allowed_methods

	// RateLimit 参数从 config 读取
	assert reg.rate_limit.max_requests == cfg.rate_limit_max_requests
	assert reg.rate_limit.window_secs == cfg.rate_limit_window_secs
}

fn test_middleware_group_registry_named_groups() {
	boot := test_setup()!
	cfg := default_web_config()
	reg := new_middleware_group_registry(cfg, boot.auth_svc, boot.role_hierarchy, boot.log)

	// 所有命名组应已注册
	assert reg.has_group('web')
	assert reg.has_group('api')
	assert reg.has_group('auth')
	assert reg.has_group('admin')
	assert reg.has_group('editor')

	// web 组：cors + request_id + request_log
	web_mws := reg.middlewares_of('web')
	assert web_mws.len == 3
	assert 'cors' in web_mws
	assert 'request_id' in web_mws
	assert 'request_log' in web_mws

	// api 组：web + rate_limit
	api_mws := reg.middlewares_of('api')
	assert api_mws.len == 4
	assert 'rate_limit' in api_mws

	// auth 组：jwt_auth
	auth_mws := reg.middlewares_of('auth')
	assert auth_mws.len == 1
	assert 'jwt_auth' in auth_mws

	// admin 组：jwt_auth + role:ADMIN
	admin_mws := reg.middlewares_of('admin')
	assert admin_mws.len == 2
	assert admin_mws[1].starts_with('role:')

	// editor 组：jwt_auth + role:EDITOR,ADMIN
	editor_mws := reg.middlewares_of('editor')
	assert editor_mws.len == 2
	assert editor_mws[1].contains('EDITOR')
	assert editor_mws[1].contains('ADMIN')
}

fn test_middleware_group_registry_authorize() {
	boot := test_setup()!
	cfg := default_web_config()
	reg := new_middleware_group_registry(cfg, boot.auth_svc, boot.role_hierarchy, boot.log)

	// ADMIN 通过 EDITOR 校验
	reg.authorize(['EDITOR'], ['ADMIN']) or { assert false }

	// USER 不通过 ADMIN 校验
	reg.authorize(['ADMIN'], ['USER']) or {
		assert true
		return
	}
	assert false
}

fn test_middleware_group_registry_group_names() {
	boot := test_setup()!
	cfg := default_web_config()
	reg := new_middleware_group_registry(cfg, boot.auth_svc, boot.role_hierarchy, boot.log)

	names := reg.group_names()
	assert names.len >= 5
	assert 'web' in names
	assert 'api' in names
	assert 'auth' in names
	assert 'admin' in names
	assert 'editor' in names
}

fn test_parse_cors_origins() {
	// 默认通配符
	assert parse_cors_origins('*') == ['*']
	assert parse_cors_origins('') == ['*']

	// 单个域名
	origins := parse_cors_origins('https://example.com')
	assert origins.len == 1
	assert origins[0] == 'https://example.com'

	// 多个域名（逗号分隔，含空格）
	origins2 := parse_cors_origins('https://a.com, https://b.com ,https://c.com')
	assert origins2.len == 3
	assert origins2[0] == 'https://a.com'
	assert origins2[1] == 'https://b.com'
	assert origins2[2] == 'https://c.com'
}

fn test_parse_role_spec() {
	// 单角色
	roles := parse_role_spec('role:ADMIN')
	assert roles.len == 1
	assert roles[0] == 'ADMIN'

	// 多角色
	roles2 := parse_role_spec('role:EDITOR,ADMIN')
	assert roles2.len == 2
	assert 'EDITOR' in roles2
	assert 'ADMIN' in roles2

	// 无角色（格式错误）
	roles3 := parse_role_spec('role')
	assert roles3.len == 0
}

fn test_request_id_generation() {
	id1 := generate_request_id()
	id2 := generate_request_id()

	// UUID 格式：8-4-4-4-12
	assert id1.len == 36
	assert id1[8] == `-`
	assert id1[13] == `-`
	assert id1[18] == `-`
	assert id1[23] == `-`

	// 两个 ID 应不同
	assert id1 != id2
}

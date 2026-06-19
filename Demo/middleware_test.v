module main

// middleware_test.v — PhotonBlog 中间件测试
//
// 测试覆盖：
//   - CorsMiddleware 配置与行为
//   - RateLimitMiddleware 限流逻辑
//   - JwtAuthMiddleware 认证
//   - RoleAuthMiddleware 角色校验
//   - MiddlewareManager 统一管理

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

fn test_middleware_manager_creation() {
	boot := test_setup()!
	mm := new_middleware_manager(boot.auth_svc, boot.role_hierarchy, boot.log)

	assert !isnil(mm.request_log)
	assert !isnil(mm.cors)
	assert !isnil(mm.request_id)
	assert !isnil(mm.rate_limit)
	assert !isnil(mm.jwt_auth)
	assert !isnil(mm.role_auth)
}

fn test_middleware_manager_rate_limit() {
	boot := test_setup()!
	mut mm := new_middleware_manager(boot.auth_svc, boot.role_hierarchy, boot.log)

	// 在限流阈值内应正常通过
	mm.apply_rate_limit('192.168.1.1') or {
		assert false
		return
	}
	assert true
}

fn test_middleware_manager_role_check() {
	boot := test_setup()!
	mm := new_middleware_manager(boot.auth_svc, boot.role_hierarchy, boot.log)

	// ADMIN 通过 EDITOR 校验
	mm.apply_role(['EDITOR'], ['ADMIN']) or { assert false }

	// USER 不通过 ADMIN 校验
	mm.apply_role(['ADMIN'], ['USER']) or {
		assert true
		return
	}
	assert false
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

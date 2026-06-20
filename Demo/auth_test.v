module main

// auth_test.v — PhotonBlog 认证授权测试套件
//
// 测试覆盖：
//   - 用户注册（成功 / 重复用户名 / 重复邮箱）
//   - 用户登录（成功 / 密码错误 / 账户禁用）
//   - JWT 令牌生成与验证
//   - JWT 令牌刷新
//   - 角色权限校验
//
// 使用 TestCase 基类提供测试基础设施：
//   - 每个测试获得独立的 :memory: 数据库
//   - acting_as_role() / acting_as_admin() 等辅助方法
//   - user_factory() 等工厂访问器

// ═══════════════════════════════════════════════════════════
// test_setup 已移至 test_helpers.v（非测试文件），所有测试文件共享
// ═══════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════
// 用户注册测试
// ═══════════════════════════════════════════════════════════

fn test_user_registration() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	dto := CreateUserDto{
		username: 'testuser'
		email:    'test@example.com'
		password: 'password123'
		nickname: 'Test User'
	}
	user, _ := user_svc.register(dto)!

	assert user.username == 'testuser'
	assert user.email == 'test@example.com'
	assert user.password != 'password123' // 密码已哈希
	assert user.id > 0
	assert user.role == 'USER'
	assert user.status == 1
	assert user.nickname == 'Test User'
}

fn test_duplicate_username_registration() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	dto1 := CreateUserDto{
		username: 'duplicate'
		email:    'first@example.com'
		password: 'password123'
	}
	user_svc.register(dto1)!

	dto2 := CreateUserDto{
		username: 'duplicate'
		email:    'second@example.com'
		password: 'password123'
	}

	user_svc.register(dto2) or {
		assert true
		return
	}
	assert false // 不应该到达这里
}

fn test_duplicate_email_registration() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	dto1 := CreateUserDto{
		username: 'user1'
		email:    'same@example.com'
		password: 'password123'
	}
	user_svc.register(dto1)!

	dto2 := CreateUserDto{
		username: 'user2'
		email:    'same@example.com'
		password: 'password123'
	}

	user_svc.register(dto2) or {
		assert true
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// 用户登录测试
// ═══════════════════════════════════════════════════════════

fn test_user_login_success() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg_dto := CreateUserDto{
		username: 'loginuser'
		email:    'login@example.com'
		password: 'password123'
	}
	user_svc.register(reg_dto)!

	login_dto := LoginDto{
		username: 'loginuser'
		password: 'password123'
	}
	user := user_svc.login(login_dto)!

	assert user.username == 'loginuser'
	assert user.id > 0
}

fn test_user_login_wrong_password() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg_dto := CreateUserDto{
		username: 'loginuser'
		email:    'login@example.com'
		password: 'password123'
	}
	user_svc.register(reg_dto)!

	login_dto := LoginDto{
		username: 'loginuser'
		password: 'wrongpassword'
	}

	user_svc.login(login_dto) or {
		assert true
		return
	}
	assert false
}

fn test_user_login_nonexistent_user() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	login_dto := LoginDto{
		username: 'ghost'
		password: 'password123'
	}

	user_svc.login(login_dto) or {
		assert true
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// JWT 令牌测试
// ═══════════════════════════════════════════════════════════

fn test_jwt_token_generation_and_validation() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	// 注册用户
	reg_dto := CreateUserDto{
		username: 'jwtuser'
		email:    'jwt@example.com'
		password: 'password123'
		role:     'ADMIN'
	}
	user, _ := user_svc.register(reg_dto)!

	// 生成令牌
	access_token, refresh_token := boot.auth_svc.generate_token(&user)!

	assert access_token.len > 0
	assert refresh_token.len > 0
	assert access_token != refresh_token

	// 验证访问令牌
	username := boot.auth_svc.validate_token(access_token)!
	assert username == 'jwtuser'

	// 解析令牌获取 claims
	claims := boot.auth_svc.parse_token(access_token)!
	assert claims.sub == 'jwtuser'
	assert claims.roles.len == 1
	assert claims.roles[0] == 'ADMIN'
}

fn test_jwt_token_refresh() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg_dto := CreateUserDto{
		username: 'refreshuser'
		email:    'refresh@example.com'
		password: 'password123'
	}
	user, _ := user_svc.register(reg_dto)!

	_, refresh_token := boot.auth_svc.generate_token(&user)!

	mut auth_svc := boot.auth_svc
	new_access, new_refresh := auth_svc.refresh_token(refresh_token)!

	assert new_access.len > 0
	assert new_refresh.len > 0

	// 新访问令牌应可验证
	username := boot.auth_svc.validate_token(new_access)!
	assert username == 'refreshuser'
}

fn test_jwt_token_validation_invalid() {
	boot := test_setup()!

	// 无效 token 应抛错
	boot.auth_svc.validate_token('invalid.token.here') or {
		assert true
		return
	}
	assert false
}

fn test_jwt_token_validation_empty() {
	boot := test_setup()!

	boot.auth_svc.validate_token('') or {
		assert true
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// 角色权限测试
// ═══════════════════════════════════════════════════════════

fn test_role_check_admin() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg_dto := CreateUserDto{
		username: 'admin'
		email:    'admin@example.com'
		password: 'password123'
		role:     'ADMIN'
	}
	user, _ := user_svc.register(reg_dto)!
	token, _ := boot.auth_svc.generate_token(&user)!

	// ADMIN 角色检查
	assert boot.auth_svc.has_role(token, 'ADMIN')
}

fn test_role_check_user_not_admin() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg_dto := CreateUserDto{
		username: 'regular'
		email:    'regular@example.com'
		password: 'password123'
		role:     'USER'
	}
	user, _ := user_svc.register(reg_dto)!
	token, _ := boot.auth_svc.generate_token(&user)!

	// USER 不应有 ADMIN 角色
	assert !boot.auth_svc.has_role(token, 'ADMIN')
	assert boot.auth_svc.has_role(token, 'USER')
}

fn test_role_hierarchy_permission() {
	boot := test_setup()!

	// ADMIN 继承 EDITOR 和 USER 的权限
	assert boot.auth_svc.check_permission(['ADMIN'], 'EDITOR')
	assert boot.auth_svc.check_permission(['ADMIN'], 'USER')
	assert boot.auth_svc.check_permission(['ADMIN'], 'ADMIN')

	// EDITOR 继承 USER 的权限
	assert boot.auth_svc.check_permission(['EDITOR'], 'USER')
	assert !boot.auth_svc.check_permission(['EDITOR'], 'ADMIN')

	// USER 不继承上级权限
	assert !boot.auth_svc.check_permission(['USER'], 'EDITOR')
	assert !boot.auth_svc.check_permission(['USER'], 'ADMIN')
}

fn test_build_login_response() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg_dto := CreateUserDto{
		username: 'loginresp'
		email:    'loginresp@example.com'
		password: 'password123'
	}
	user, _ := user_svc.register(reg_dto)!

	mut auth_svc := boot.auth_svc
	resp := auth_svc.build_login_response(&user)!

	assert resp.access_token.len > 0
	assert resp.refresh_token.len > 0
	assert resp.token_type == 'Bearer'
	assert resp.expires_in == 3600
	assert resp.user.username == 'loginresp'
	assert resp.user.email == 'loginresp@example.com'
}

// ═══════════════════════════════════════════════════════════
// TestCase 集成测试（演示新版测试基类用法）
// ═══════════════════════════════════════════════════════════

fn test_testcase_register_admin() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 通过 acting_as_role 创建并认证 ADMIN
	admin := t.acting_as_role('ADMIN')!
	assert admin.role == 'ADMIN'
	assert t.is_authenticated()

	// ADMIN 角色可被令牌识别
	mut auth_svc := t.auth_svc()
	assert auth_svc.has_role(t.token(), 'ADMIN')
}

fn test_testcase_login_with_factory_user() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 用 Factory 创建用户
	user := t.user_factory().with_username('testcase_user').with_password('secret').create()!

	// 用 Service 登录
	logged_in := t.user_svc().login(LoginDto{
		username: 'testcase_user'
		password: 'secret'
	})!
	assert logged_in.id == user.id
}

fn test_testcase_refresh_database_resets_state() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 创建用户
	_ := t.user_factory().create()!
	assert t.bootstrap().user_repo.count()! == 1

	// 刷新数据库
	t.refresh_database()!
	assert t.bootstrap().user_repo.count()! == 0
}

fn test_testcase_acting_as_user_role_check() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.acting_as_user()
	_ = user

	// USER 角色不应有 ADMIN 权限
	mut auth_svc := t.auth_svc()
	assert !auth_svc.has_role(t.token(), 'ADMIN')
	assert auth_svc.has_role(t.token(), 'USER')
}

fn test_testcase_complete_auth_flow() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 完整流程：注册 → 登录 → 令牌 → 校验
	dto := CreateUserDto{
		username: 'flowuser'
		email:    'flow@test.com'
		password: 'pass123'
		role:     'EDITOR'
	}
	user, _ := t.user_svc().register(dto)!

	logged_in := t.user_svc().login(LoginDto{
		username: 'flowuser'
		password: 'pass123'
	})!
	assert logged_in.id == user.id

	access, refresh := t.auth_svc().generate_token(&user)!
	assert access.len > 0
	assert refresh.len > 0

	username := t.auth_svc().validate_token(access)!
	assert username == 'flowuser'

	// 刷新令牌
	new_access, new_refresh := t.auth_svc().refresh_token(refresh)!
	assert new_access.len > 0
	assert t.auth_svc().validate_token(new_access)! == 'flowuser'
}

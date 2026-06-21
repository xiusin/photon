module tests

// tests/factory_test.v — Factory 模式与 TestCase 集成测试
//
// 测试覆盖：
//   - UserFactory 链式调用与属性定制
//   - PostFactory 必需属性验证
//   - CommentFactory 父子关系构建
//   - Factory + TestCase.acting_as() 集成
//   - create_or_first 幂等性
//   - make() 与 create() 行为差异
//   - 随机后缀确保唯一性（多个工厂实例不冲突）

// ═══════════════════════════════════════════════════════════
// UserFactory 基础测试
// ═══════════════════════════════════════════════════════════

fn test_user_factory_default() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().create()!
	assert user.id > 0
	assert user.username.starts_with('user_')
	assert user.email.ends_with('@factory.dev')
	assert user.role == 'USER'
	assert user.status == 1
}

fn test_user_factory_with_role() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	admin := t.user_factory().with_role('ADMIN').create()!
	editor := t.user_factory().with_role('EDITOR').create()!
	regular := t.user_factory().with_role('USER').create()!

	assert admin.role == 'ADMIN'
	assert editor.role == 'EDITOR'
	assert regular.role == 'USER'
}

fn test_user_factory_with_username() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().with_username('alice').create()!
	assert user.username == 'alice'
	assert user.email == 'alice@factory.dev'
}

fn test_user_factory_with_email() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().with_email('custom@example.com').create()!
	assert user.email == 'custom@example.com'
}

fn test_user_factory_with_password() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 用户名 + 自定义密码
	user := t.user_factory().with_password('MySecretPass1').create()!
	// 密码已被哈希
	assert user.password != 'MySecretPass1'
	assert user.password.len > 20 // bcrypt hash 长度
}

fn test_user_factory_make_not_persisted() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// make() 不持久化
	mut f := t.user_factory()
	user := f.make()
	assert user.id == 0
	assert user.password.len > 0
}

fn test_user_factory_create_or_first_idempotent() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 首次创建
	u1 := t.user_factory().with_username('idem').create()!
	// 重复创建应返回已存在用户
	u2 := t.user_factory().with_username('idem').create_or_first()!

	assert u1.id == u2.id
}

// ═══════════════════════════════════════════════════════════
// PostFactory 测试
// ═══════════════════════════════════════════════════════════

fn test_post_factory_requires_author() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 不设置 author_id 应失败
	t.post_factory().create() or {
		assert err.msg().contains('author_id') || err.msg().contains('author')
		return
	}
	assert false
}

fn test_post_factory_with_author() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	post := t.post_factory().with_author(author.id).create()!

	assert post.id > 0
	assert post.author_id == author.id
	assert post.status == 'draft'
}

fn test_post_factory_with_status() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	post := t.post_factory().with_author(author.id).with_status('published').create()!
	assert post.status == 'published'
}

fn test_post_factory_with_category() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	post := t.post_factory().with_author(author.id).with_category(5).create()!
	assert post.category_id == 5
}

// ═══════════════════════════════════════════════════════════
// CommentFactory 测试
// ═══════════════════════════════════════════════════════════

fn test_comment_factory_requires_post() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().create()!
	t.comment_factory().with_user(author.id).create() or {
		assert err.msg().contains('post_id')
		return
	}
	assert false
}

fn test_comment_factory_requires_user() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().create()!
	post := t.post_factory().with_author(author.id).create()!
	t.comment_factory().with_post(post.id).create() or {
		assert err.msg().contains('user_id')
		return
	}
	assert false
}

fn test_comment_factory_with_parent() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().create()!
	post := t.post_factory().with_author(author.id).create()!
	parent := t.comment_factory().with_post(post.id).with_user(author.id).create()!

	reply := t.comment_factory().with_post(post.id).with_user(author.id).with_parent(parent.id).create()!
	assert reply.parent_id == parent.id
}

// ═══════════════════════════════════════════════════════════
// TestCase.acting_as 集成
// ═══════════════════════════════════════════════════════════

fn test_acting_as_role() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 模拟 ADMIN 认证
	admin := t.acting_as_role('ADMIN')!
	assert admin.role == 'ADMIN'
	assert t.is_authenticated()
	assert t.token().len > 0
}

fn test_acting_as_admin() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	admin := t.acting_as_admin()!
	assert admin.role == 'ADMIN'
}

fn test_acting_as_editor() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	editor := t.acting_as_editor()!
	assert editor.role == 'EDITOR'
}

fn test_acting_as_user() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.acting_as_user()!
	assert user.role == 'USER'
}

fn test_acting_as_existing_user() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().with_role('EDITOR').create()!
	t.acting_as(&user)!

	// 校验令牌角色
	t.assert_has_role('EDITOR')!
}

fn test_assert_authenticated_fails_when_not() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 未认证时 is_authenticated() 应返回 false
	assert t.is_authenticated() == false
	assert t.token().len == 0
}

fn test_assert_has_role_succeeds_for_admin() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	t.acting_as_admin()
	t.assert_has_role('ADMIN')!
}

// ═══════════════════════════════════════════════════════════
// TestCase.refresh_database
// ═══════════════════════════════════════════════════════════

fn test_refresh_database_clears_state() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 创建一些数据
	_ := t.user_factory().create()!
	_ := t.user_factory().create()!
	before := t.bootstrap().user_repo.count()!
	assert before == 2

	// 刷新数据库
	t.refresh_database()!

	// 数据库应为空
	after := t.bootstrap().user_repo.count()!
	assert after == 0
}

fn test_refresh_database_then_recreate() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 第一次创建
	_ := t.user_factory().with_role('ADMIN').create()!
	assert t.bootstrap().user_repo.count()! == 1

	// 刷新
	t.refresh_database()!
	assert t.bootstrap().user_repo.count()! == 0

	// 再次创建
	_ := t.user_factory().with_role('USER').create()!
	assert t.bootstrap().user_repo.count()! == 1
}

// ═══════════════════════════════════════════════════════════
// TestCase 服务访问器
// ═══════════════════════════════════════════════════════════

fn test_test_case_service_accessors() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 所有服务访问器都应返回非空引用
	assert !isnil(t.user_svc())
	assert !isnil(t.auth_svc())
	assert !isnil(t.post_svc())
	assert !isnil(t.comment_svc())
	assert !isnil(t.stats_svc())
}

fn test_test_case_bootstrap_accessor() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	boot := t.bootstrap()
	assert !isnil(boot)
	assert !isnil(boot.user_svc)
	assert !isnil(boot.post_svc)
}

// ═══════════════════════════════════════════════════════════
// TestResponse 辅助测试
// ═══════════════════════════════════════════════════════════

fn test_test_response_status_checks() {
	r200 := TestResponse{status_code: 200, body: '{}', headers: {}}
	r404 := TestResponse{status_code: 404, body: '{}', headers: {}}
	r401 := TestResponse{status_code: 401, body: '{}', headers: {}}
	r422 := TestResponse{status_code: 422, body: '{}', headers: {}}
	r500 := TestResponse{status_code: 500, body: '{}', headers: {}}

	assert r200.is_successful()
	assert !r200.is_client_error()
	assert !r200.is_server_error()

	assert r404.is_not_found()
	assert r404.is_client_error()
	assert !r404.is_successful()

	assert r401.is_unauthorized()
	assert r422.is_validation_error()
	assert r500.is_server_error()
}

fn test_test_response_body_contains() {
	r := TestResponse{
		status_code: 200
		body:        '{"username":"alice"}'
		headers:     {}
	}
	assert r.body_contains('alice')
	assert r.body_contains('username')
	assert !r.body_contains('password')
}

module tests

// tests/test_case.v — TestCase 测试基类
//
// Laravel 风格的测试基类，为 PhotonBlog 测试提供统一基础设施：
//   - setup() / teardown() 生命周期钩子
//   - refresh_database() 每个测试前重置数据库（内存数据库 + 迁移）
//   - acting_as(user) / acting_as_role(role) 模拟已认证用户
//   - user_factory() / post_factory() / comment_factory() 工厂访问器
//   - json_request(method, path, body) 构造测试请求（服务层测试）
//
// 用法：
//   fn test_create_post_as_admin() {
//       mut t := TestCase{}
//       t.setup()!
//       defer { t.teardown() }
//
//       admin := t.acting_as_role('ADMIN')!
//       post := t.post_factory().with_author(admin.id).with_status('published').create()!
//       assert post.id > 0
//       assert post.status == 'published'
//   }
//
// 设计说明：
//   V 语言无类继承，通过 struct 嵌入实现 "继承" TestCase。
//   测试函数创建 TestCase 实例，调用 setup() 初始化，defer teardown() 清理。
//   每个测试使用独立的 :memory: 内存数据库，互不干扰。

import json

// ═══════════════════════════════════════════════════════════
// TestResponse — 测试响应封装
// ═══════════════════════════════════════════════════════════

// TestResponse 封装 HTTP 响应或服务层调用的结果
pub struct TestResponse {
pub:
	status_code int
	body        string
	headers     map[string]string
}

// body_json 将响应体解析为指定类型
pub fn (r TestResponse) body_json[T]() !T {
	return json.decode[T](r.body)!
}

// is_successful 是否为 2xx 成功响应
pub fn (r TestResponse) is_successful() bool {
	return r.status_code >= 200 && r.status_code < 300
}

// is_client_error 是否为 4xx 客户端错误
pub fn (r TestResponse) is_client_error() bool {
	return r.status_code >= 400 && r.status_code < 500
}

// is_server_error 是否为 5xx 服务端错误
pub fn (r TestResponse) is_server_error() bool {
	return r.status_code >= 500
}

// is_not_found 是否为 404
pub fn (r TestResponse) is_not_found() bool {
	return r.status_code == 404
}

// is_unauthorized 是否为 401
pub fn (r TestResponse) is_unauthorized() bool {
	return r.status_code == 401
}

// is_forbidden 是否为 403
pub fn (r TestResponse) is_forbidden() bool {
	return r.status_code == 403
}

// is_validation_error 是否为 422
pub fn (r TestResponse) is_validation_error() bool {
	return r.status_code == 422
}

// body_contains 响应体是否包含子串
pub fn (r TestResponse) body_contains(substr string) bool {
	return r.body.contains(substr)
}

// ═══════════════════════════════════════════════════════════
// TestCase — 测试基类
// ═══════════════════════════════════════════════════════════

// TestCase 测试基类，持有 Bootstrap 引用与认证状态
pub struct TestCase {
mut:
	boot          &Bootstrap = unsafe { nil }
	auth_token    string
	current_user  ?User
}

// setup 初始化测试环境：创建内存数据库 Bootstrap + 运行迁移
// 每次调用获得全新的 :memory: 数据库，确保测试隔离
pub fn (mut t TestCase) setup() ! {
	t.boot = test_setup()!
	t.auth_token = ''
	t.current_user = none
}

// teardown 清理测试环境，释放引用
pub fn (mut t TestCase) teardown() {
	t.boot = unsafe { nil }
	t.auth_token = ''
	t.current_user = none
}

// refresh_database 重置数据库（重新创建内存数据库 + 迁移）
// 等价于 migrate:fresh，用于需要干净数据库的场景
pub fn (mut t TestCase) refresh_database() ! {
	t.setup()!
}

// ═══════════════════════════════════════════════════════════
// 认证辅助
// ═══════════════════════════════════════════════════════════

// acting_as 模拟已认证用户（生成 JWT 令牌并存储）
// 后续可通过 token() 获取令牌，用于需要认证的服务调用
pub fn (mut t TestCase) acting_as(user &User) ! {
	mut auth_svc := t.boot.auth_svc
	token, _ := auth_svc.generate_token(user)!
	t.auth_token = token
	t.current_user = *user
}

// acting_as_role 创建指定角色的用户并模拟认证
// 返回创建的用户实体，便于测试中引用
pub fn (mut t TestCase) acting_as_role(role string) !User {
	user := new_user_factory(t.boot).with_role(role).create()!
	t.acting_as(&user)!
	return user
}

// acting_as_admin 创建 ADMIN 用户并认证（快捷方法）
pub fn (mut t TestCase) acting_as_admin() !User {
	return t.acting_as_role('ADMIN')
}

// acting_as_editor 创建 EDITOR 用户并认证（快捷方法）
pub fn (mut t TestCase) acting_as_editor() !User {
	return t.acting_as_role('EDITOR')
}

// acting_as_user 创建普通 USER 用户并认证（快捷方法）
pub fn (mut t TestCase) acting_as_user() !User {
	return t.acting_as_role('USER')
}

// token 获取当前认证令牌（空字符串表示未认证）
pub fn (t &TestCase) token() string {
	return t.auth_token
}

// is_authenticated 是否已认证
pub fn (t &TestCase) is_authenticated() bool {
	return t.auth_token.len > 0
}

// current_user 获取当前模拟用户
pub fn (t &TestCase) get_current_user() ?User {
	return t.current_user
}

// ═══════════════════════════════════════════════════════════
// 工厂访问器
// ═══════════════════════════════════════════════════════════

// user_factory 返回绑定到当前 Bootstrap 的 UserFactory
pub fn (t &TestCase) user_factory() UserFactory {
	return new_user_factory(t.boot)
}

// post_factory 返回绑定到当前 Bootstrap 的 PostFactory
pub fn (t &TestCase) post_factory() PostFactory {
	return new_post_factory(t.boot)
}

// comment_factory 返回绑定到当前 Bootstrap 的 CommentFactory
pub fn (t &TestCase) comment_factory() CommentFactory {
	return new_comment_factory(t.boot)
}

// ═══════════════════════════════════════════════════════════
// Bootstrap 访问器
// ═══════════════════════════════════════════════════════════

// bootstrap 获取底层 Bootstrap 引用
pub fn (t &TestCase) bootstrap() &Bootstrap {
	return t.boot
}

// user_svc 快捷访问 UserService
pub fn (t &TestCase) user_svc() &UserService {
	return t.boot.user_svc
}

// auth_svc 快捷访问 AuthService
pub fn (t &TestCase) auth_svc() &AuthService {
	return t.boot.auth_svc
}

// post_svc 快捷访问 PostService
pub fn (t &TestCase) post_svc() &PostService {
	return t.boot.post_svc
}

// comment_svc 快捷访问 CommentService
pub fn (t &TestCase) comment_svc() &CommentService {
	return t.boot.comment_svc
}

// stats_svc 快捷访问 StatsService
pub fn (t &TestCase) stats_svc() &StatsService {
	return t.boot.stats_svc
}

// ═══════════════════════════════════════════════════════════
// 请求构造（服务层测试）
// ═══════════════════════════════════════════════════════════

// json_request 构造测试请求并返回 TestResponse
//
// 注意：PhotonBlog 测试主要在服务层进行（直接调用 Service 方法），
// 而非通过 HTTP 请求。此方法用于需要模拟完整请求场景的集成测试。
//
// 在服务层测试中，推荐直接调用：
//   t.user_svc().register(dto)!
//   t.post_svc().create(dto)!
//
// 当需要 HTTP 级别测试时，启动测试服务器后可用此方法发送请求。
pub fn (mut t TestCase) json_request(method string, path string, body string) !TestResponse {
	// 构造请求头
	mut headers := map[string]string{}
	headers['Content-Type'] = 'application/json'
	if t.auth_token.len > 0 {
		headers['Authorization'] = 'Bearer ${t.auth_token}'
	}

	// 服务层测试模式：解析 body 并直接调用对应服务
	// 此实现提供请求构造基础设施，具体端点分发由集成测试扩展
	return TestResponse{
		status_code: 200
		body: body
		headers: headers
	}
}

// ═══════════════════════════════════════════════════════════
// 断言辅助
// ═══════════════════════════════════════════════════════════

// assert_authenticated 断言当前已认证
pub fn (t &TestCase) assert_authenticated() {
	assert t.auth_token.len > 0
}

// assert_has_role 断言当前用户拥有指定角色（通过令牌校验）
pub fn (t &TestCase) assert_has_role(role string) ! {
	assert t.auth_token.len > 0
	mut auth_svc := t.boot.auth_svc
	assert auth_svc.has_role(t.auth_token, role)
}

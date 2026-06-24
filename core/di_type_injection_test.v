module core

// di_type_injection_test.v - 验证 DI 字段注入按类型解析（Task B1）
//
// 测试 @[autowired] 字段按字段类型名解析依赖（Spring @Autowired 语义），
// 而非按字段名解析。例如字段 `repo &UserRepository` 应按 'UserRepository'
// 解析，而非按 'repo' 解析。
//
// 覆盖：
//   - scan_component_info 返回的 Dependency.type_name 为类型名（非字段名）
//   - scan_and_register 注册的 BeanDefinition 中 Dependency.type_name 正确
//   - autowire_bean 按类型名解析并注入字段
//   - create_and_wire 端到端按类型注入
//   - qualifier 优先于类型名解析
//   - 字段名回退（向后兼容）

// ═══════════════════════════════════════════════════════════
// 测试用结构体
// ═══════════════════════════════════════════════════════════

// TypeTestRepo — 仓库层 Bean
@[repository]
pub struct TypeTestRepo {
pub mut:
	data map[string]string
}

// TypeTestService — 服务层 Bean，字段名 'repo' 与类型名 'TypeTestRepo' 不同
@[service]
pub struct TypeTestService {
mut:
	repo &TypeTestRepo = unsafe { nil } @[autowired]
}

// TypeTestConsumer — 消费层 Bean，验证链式注入
@[component]
pub struct TypeTestConsumer {
mut:
	svc &TypeTestService = unsafe { nil } @[autowired]
}

// TypeTestWithQualifier — 验证 qualifier 优先于类型名解析
@[service]
pub struct TypeTestWithQualifier {
mut:
	repo &TypeTestRepo = unsafe { nil } @[autowired; qualifier: 'primary_repo']
}

// TypeTestFallback — 验证字段名回退（向后兼容）
// 字段名 'type_test_repo' 与类型名 'TypeTestRepo' 不同，
// 但容器中按字段名注册了 bean 时应能回退解析
@[component]
pub struct TypeTestFallback {
mut:
	type_test_repo &TypeTestRepo = unsafe { nil } @[autowired]
}

// TypeTestMultiDeps — 多依赖服务
@[service]
pub struct TypeTestMultiDeps {
mut:
	repo &TypeTestRepo = unsafe { nil } @[autowired]
	svc &TypeTestService = unsafe { nil } @[autowired]
}

// ═══════════════════════════════════════════════════════════
// scan_component_info 测试 — 验证 Dependency.type_name 为类型名
// ═══════════════════════════════════════════════════════════

fn test_scan_component_info_type_name_is_field_type() {
	info := scan_component_info[TypeTestService]()

	// 应有 1 个 @[autowired] 依赖
	assert info.dependencies.len == 1

	dep := info.dependencies[0]
	// type_name 应为 'core.TypeTestRepo'（字段类型名），而非 'repo'（字段名）
	// typeof(field.typ) 返回完全限定名，与 T.name 一致
	assert dep.type_name == 'core.TypeTestRepo'
	// field_name 应为 'repo'（字段名）
	assert dep.field_name == 'repo'
}

fn test_scan_component_info_type_name_not_field_name() {
	info := scan_component_info[TypeTestService]()

	dep := info.dependencies[0]
	// 关键断言：type_name 不等于字段名 'repo'
	assert dep.type_name != 'repo'
	assert dep.type_name == 'core.TypeTestRepo'
}

fn test_scan_component_info_consumer_dependency() {
	info := scan_component_info[TypeTestConsumer]()

	assert info.dependencies.len == 1
	dep := info.dependencies[0]
	// 字段名 'svc'，类型名 'core.TypeTestService'
	assert dep.field_name == 'svc'
	assert dep.type_name == 'core.TypeTestService'
}

fn test_scan_component_info_qualifier_preserved() {
	info := scan_component_info[TypeTestWithQualifier]()

	assert info.dependencies.len == 1
	dep := info.dependencies[0]
	assert dep.field_name == 'repo'
	assert dep.type_name == 'core.TypeTestRepo'
	// qualifier 应被保留
	assert dep.qualifier == 'primary_repo'
}

// ═══════════════════════════════════════════════════════════
// scan_and_register 测试 — 验证注册的 BeanDefinition 中依赖类型名正确
// ═══════════════════════════════════════════════════════════

fn test_scan_and_register_dependency_type_name() {
	mut ctx := new_application_context()
	scan_and_register[TypeTestService](mut ctx) or { assert false; return }

	// scan_and_register 按 T.name（完全限定名 'core.TypeTestService'）注册
	def := ctx.get_definition('core.TypeTestService') or {
		assert false
		return
	}
	assert def.dependencies.len == 1
	dep := def.dependencies[0]
	// 关键：type_name 为类型名，非字段名
	assert dep.type_name == 'core.TypeTestRepo'
	assert dep.field_name == 'repo'
}

// ═══════════════════════════════════════════════════════════
// autowire_bean 测试 — 验证按类型名解析并注入
// ═══════════════════════════════════════════════════════════

fn test_autowire_bean_resolves_by_type_name() {
	mut ctx := new_application_context()

	// 注册 TypeTestRepo 单例（按类型名注册）
	repo := &TypeTestRepo{ data: {'key': 'value'} }
	ctx.register_instance('TypeTestRepo', repo) or { assert false; return }

	// 创建服务实例并自动注入
	mut svc := TypeTestService{}
	ctx.autowire_bean[TypeTestService](mut svc) or { assert false; return }

	// 验证 repo 字段被注入（按类型名 'TypeTestRepo' 解析，而非字段名 'repo'）
	assert !isnil(svc.repo)
	assert svc.repo.data['key'] == 'value'
}

fn test_autowire_bean_resolves_by_type_not_field_name() {
	mut ctx := new_application_context()

	// 仅按类型名 'TypeTestRepo' 注册，不按字段名 'repo' 注册
	repo := &TypeTestRepo{ data: {'id': '42'} }
	ctx.register_instance('TypeTestRepo', repo) or { assert false; return }

	mut svc := TypeTestService{}
	ctx.autowire_bean[TypeTestService](mut svc) or { assert false; return }

	// 若按字段名 'repo' 解析，会失败（容器中无 'repo' bean）
	// 按类型名 'TypeTestRepo' 解析，应成功
	assert !isnil(svc.repo)
	assert svc.repo.data['id'] == '42'
}

// ═══════════════════════════════════════════════════════════
// create_and_wire 端到端测试
// ═══════════════════════════════════════════════════════════

fn test_create_and_wire_injects_by_type() {
	mut ctx := new_application_context()

	// 注册依赖
	repo := &TypeTestRepo{ data: {'name': 'photon'} }
	ctx.register_instance('TypeTestRepo', repo) or { assert false; return }

	// 创建并注入
	svc := ctx.create_and_wire[TypeTestService]() or { assert false; return }

	// 验证按类型注入
	assert !isnil(svc.repo)
	assert svc.repo.data['name'] == 'photon'
}

// ═══════════════════════════════════════════════════════════
// qualifier 优先级测试
// ═══════════════════════════════════════════════════════════

fn test_autowire_bean_qualifier_takes_priority_over_type() {
	mut ctx := new_application_context()

	// 注册两个 TypeTestRepo 实例：一个按类型名，一个按 qualifier
	default_repo := &TypeTestRepo{ data: {'source': 'default'} }
	ctx.register_instance('TypeTestRepo', default_repo) or { assert false; return }

	primary_repo := &TypeTestRepo{ data: {'source': 'primary'} }
	ctx.register_instance('primary_repo', primary_repo) or { assert false; return }

	// TypeTestWithQualifier 的 repo 字段标注了 @[qualifier('primary_repo')]
	mut svc := TypeTestWithQualifier{}
	ctx.autowire_bean[TypeTestWithQualifier](mut svc) or { assert false; return }

	// qualifier 应优先于类型名解析
	assert !isnil(svc.repo)
	assert svc.repo.data['source'] == 'primary'
}

// ═══════════════════════════════════════════════════════════
// 字段名回退测试（向后兼容）
// ═══════════════════════════════════════════════════════════

fn test_autowire_bean_falls_back_to_field_name() {
	mut ctx := new_application_context()

	// 仅按字段名 'type_test_repo' 注册（不按类型名 'TypeTestRepo' 注册）
	// 验证当类型名解析失败时，回退到字段名解析
	repo := &TypeTestRepo{ data: {'fallback': 'true'} }
	ctx.register_instance('type_test_repo', repo) or { assert false; return }

	mut consumer := TypeTestFallback{}
	ctx.autowire_bean[TypeTestFallback](mut consumer) or { assert false; return }

	assert !isnil(consumer.type_test_repo)
	assert consumer.type_test_repo.data['fallback'] == 'true'
}

// ═══════════════════════════════════════════════════════════
// 多依赖注入测试
// ═══════════════════════════════════════════════════════════

fn test_autowire_bean_multiple_dependencies_by_type() {
	mut ctx := new_application_context()

	repo := &TypeTestRepo{ data: {'multi': 'dep'} }
	ctx.register_instance('TypeTestRepo', repo) or { assert false; return }

	inner_svc := &TypeTestService{ repo: repo }
	ctx.register_instance('TypeTestService', inner_svc) or { assert false; return }

	mut svc := TypeTestMultiDeps{}
	ctx.autowire_bean[TypeTestMultiDeps](mut svc) or { assert false; return }

	// 两个依赖都应按类型名注入
	assert !isnil(svc.repo)
	assert svc.repo.data['multi'] == 'dep'
	assert !isnil(svc.svc)
	assert !isnil(svc.svc.repo)
}

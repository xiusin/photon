module core

// di_constructor_injection_test.v - 验证构造器注入（Task B2）
//
// 测试 @[autowired] init 方法作为构造器注入标记：
//   - extract_constructor 扫描 @[autowired] init 方法参数（元数据）
//   - has_autowired_init / autowired_init_param_count comptime 检测
//   - scan_and_register 将 constructor_params 存入 BeanDefinition
//   - create_and_wire 调用 @[autowired] init() 零参构造后回调
//   - create_and_wire_with_constructor[T, D] 真构造器注入（1 参）
//   - create_and_wire_with_constructor2[T, D, E] 真构造器注入（2 参）
//
// V comptime 限制：
//   - typeof(method.args[i].typ) 返回 'int'（类型索引），无法获取参数类型名
//   - 因此 constructor_params 仅记录参数名，type_name 留空
//   - 实际依赖注入由字段级 @[autowired] 完成（Task B1）
//   - @[autowired] init() 零参方法作为构造后回调（等价 @PostConstruct）

// ═══════════════════════════════════════════════════════════
// 测试用结构体
// ═══════════════════════════════════════════════════════════

// CtorRepo — 仓库层 Bean
@[repository]
@[heap]
pub struct CtorRepo {
pub mut:
	id int
}

// CtorCache — 缓存层 Bean（用于双依赖构造器注入测试）
@[component]
@[heap]
pub struct CtorCache {
pub mut:
	hit_count int
}

// CtorCallbackService — 零参 @[autowired] init 作为构造后回调
// 字段注入负责实际依赖装配，init() 仅作为生命周期回调
@[service]
@[heap]
pub struct CtorCallbackService {
mut:
	repo &CtorRepo = unsafe { nil } @[autowired]
pub mut:
	initialized bool
}

// @[autowired] 零参 init — 构造后回调（等价 @PostConstruct）
@[autowired]
pub fn (mut s CtorCallbackService) init() {
	s.initialized = true
}

// CtorOneDepService — 单参 @[autowired] init 真构造器注入
@[service]
@[heap]
pub struct CtorOneDepService {
mut:
	repo &CtorRepo = unsafe { nil }
pub mut:
	constructed bool
}

// @[autowired] 单参 init — 真构造器注入
@[autowired]
pub fn (mut s CtorOneDepService) init(repo &CtorRepo) {
	s.repo = unsafe { repo }
	s.constructed = true
}

// CtorTwoDepService — 双参 @[autowired] init 真构造器注入
@[service]
@[heap]
pub struct CtorTwoDepService {
mut:
	repo  &CtorRepo  = unsafe { nil }
	cache &CtorCache = unsafe { nil }
pub mut:
	constructed bool
}

// @[autowired] 双参 init — 真构造器注入
@[autowired]
pub fn (mut s CtorTwoDepService) init(repo &CtorRepo, cache &CtorCache) {
	s.repo = unsafe { repo }
	s.cache = unsafe { cache }
	s.constructed = true
}

// CtorNoInitService — 无 @[autowired] init 的服务（对照组）
@[service]
@[heap]
pub struct CtorNoInitService {
mut:
	repo &CtorRepo = unsafe { nil } @[autowired]
}

// ═══════════════════════════════════════════════════════════
// extract_constructor 测试 — 验证元数据扫描
// ═══════════════════════════════════════════════════════════

fn test_extract_constructor_zero_arg_init() {
	// CtorCallbackService 的 @[autowired] init() 零参
	params := extract_constructor[CtorCallbackService]()
	// 零参 init → constructor_params 为空
	assert params.len == 0
}

fn test_extract_constructor_one_param_init() {
	// CtorOneDepService 的 @[autowired] init(repo) 单参
	params := extract_constructor[CtorOneDepService]()
	assert params.len == 1
	// 参数名应为 'repo'
	assert params[0].field_name == 'repo'
	// V 限制：type_name 为空（无法获取方法参数类型名）
	assert params[0].type_name == ''
	assert params[0].is_required == true
}

fn test_extract_constructor_two_param_init() {
	// CtorTwoDepService 的 @[autowired] init(repo, cache) 双参
	params := extract_constructor[CtorTwoDepService]()
	assert params.len == 2
	assert params[0].field_name == 'repo'
	assert params[1].field_name == 'cache'
	// V 限制：type_name 均为空
	assert params[0].type_name == ''
	assert params[1].type_name == ''
}

fn test_extract_constructor_no_autowired_init() {
	// CtorNoInitService 无 @[autowired] init → constructor_params 为空
	params := extract_constructor[CtorNoInitService]()
	assert params.len == 0
}

// ═══════════════════════════════════════════════════════════
// has_autowired_init / autowired_init_param_count 测试
// ═══════════════════════════════════════════════════════════

fn test_has_autowired_init_true_for_callback_service() {
	assert has_autowired_init[CtorCallbackService]() == true
}

fn test_has_autowired_init_true_for_one_dep_service() {
	assert has_autowired_init[CtorOneDepService]() == true
}

fn test_has_autowired_init_false_for_no_init_service() {
	assert has_autowired_init[CtorNoInitService]() == false
}

fn test_autowired_init_param_count_zero() {
	assert autowired_init_param_count[CtorCallbackService]() == 0
}

fn test_autowired_init_param_count_one() {
	assert autowired_init_param_count[CtorOneDepService]() == 1
}

fn test_autowired_init_param_count_two() {
	assert autowired_init_param_count[CtorTwoDepService]() == 2
}

fn test_autowired_init_param_count_none() {
	assert autowired_init_param_count[CtorNoInitService]() == 0
}

// ═══════════════════════════════════════════════════════════
// scan_and_register 测试 — 验证 constructor_params 存入 BeanDefinition
// ═══════════════════════════════════════════════════════════

fn test_scan_and_register_stores_constructor_params_one_dep() {
	mut ctx := new_application_context()
	scan_and_register[CtorOneDepService](mut ctx) or { assert false; return }

	def := ctx.get_definition('core.CtorOneDepService') or {
		assert false
		return
	}
	// constructor_params 应记录 1 个参数
	assert def.constructor_params.len == 1
	assert def.constructor_params[0].field_name == 'repo'
}

fn test_scan_and_register_stores_constructor_params_two_dep() {
	mut ctx := new_application_context()
	scan_and_register[CtorTwoDepService](mut ctx) or { assert false; return }

	def := ctx.get_definition('core.CtorTwoDepService') or {
		assert false
		return
	}
	assert def.constructor_params.len == 2
	assert def.constructor_params[0].field_name == 'repo'
	assert def.constructor_params[1].field_name == 'cache'
}

fn test_scan_and_register_constructor_params_empty_for_no_init() {
	mut ctx := new_application_context()
	scan_and_register[CtorNoInitService](mut ctx) or { assert false; return }

	def := ctx.get_definition('core.CtorNoInitService') or {
		assert false
		return
	}
	assert def.constructor_params.len == 0
	assert def.has_constructor_params() == false
}

fn test_scan_and_register_has_constructor_params_true() {
	mut ctx := new_application_context()
	scan_and_register[CtorOneDepService](mut ctx) or { assert false; return }

	def := ctx.get_definition('core.CtorOneDepService') or {
		assert false
		return
	}
	assert def.has_constructor_params() == true
}

// ═══════════════════════════════════════════════════════════
// scan_component_info 测试 — 验证 ScannedBean.constructor_params
// ═══════════════════════════════════════════════════════════

fn test_scan_component_info_constructor_params() {
	info := scan_component_info[CtorOneDepService]()
	assert info.constructor_params.len == 1
	assert info.constructor_params[0].field_name == 'repo'
}

// ═══════════════════════════════════════════════════════════
// create_and_wire 测试 — 验证 @[autowired] init() 零参回调
// ═══════════════════════════════════════════════════════════

fn test_create_and_wire_calls_autowired_init_callback() {
	mut ctx := new_application_context()

	// 注册依赖
	repo := &CtorRepo{ id: 42 }
	ctx.register_instance('CtorRepo', repo) or { assert false; return }

	// create_and_wire 应：1) 字段注入 repo  2) 调用 @[autowired] init()
	svc := ctx.create_and_wire[CtorCallbackService]() or { assert false; return }

	// 字段注入成功
	assert !isnil(svc.repo)
	assert svc.repo.id == 42
	// @[autowired] init() 回调被调用
	assert svc.initialized == true
}

fn test_create_and_wire_no_init_does_not_crash() {
	mut ctx := new_application_context()

	repo := &CtorRepo{ id: 7 }
	ctx.register_instance('CtorRepo', repo) or { assert false; return }

	// CtorNoInitService 无 @[autowired] init，create_and_wire 应正常工作
	svc := ctx.create_and_wire[CtorNoInitService]() or { assert false; return }

	assert !isnil(svc.repo)
	assert svc.repo.id == 7
}

// ═══════════════════════════════════════════════════════════
// create_and_wire_with_constructor 测试 — 真构造器注入（1 参）
// ═══════════════════════════════════════════════════════════

fn test_create_and_wire_with_constructor_one_dep() {
	mut ctx := new_application_context()

	repo := &CtorRepo{ id: 99 }
	ctx.register_instance('CtorRepo', repo) or { assert false; return }

	// 真构造器注入：init(repo) 被调用，repo 通过参数注入
	svc := ctx.create_and_wire_with_constructor[CtorOneDepService, CtorRepo]() or {
		assert false
		return
	}

	// 构造器注入成功
	assert svc.constructed == true
	assert !isnil(svc.repo)
	assert svc.repo.id == 99
}

fn test_create_and_wire_with_constructor_fails_when_dep_missing() {
	mut ctx := new_application_context()
	// 不注册 CtorRepo → 应返回错误

	_ := ctx.create_and_wire_with_constructor[CtorOneDepService, CtorRepo]() or {
		// 预期失败
		assert err.msg().contains('not found') || err.msg().contains('未找到')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// create_and_wire_with_constructor2 测试 — 真构造器注入（2 参）
// ═══════════════════════════════════════════════════════════

fn test_create_and_wire_with_constructor2_two_deps() {
	mut ctx := new_application_context()

	repo := &CtorRepo{ id: 100 }
	ctx.register_instance('CtorRepo', repo) or { assert false; return }

	cache := &CtorCache{ hit_count: 5 }
	ctx.register_instance('CtorCache', cache) or { assert false; return }

	// 真构造器注入：init(repo, cache) 被调用
	svc := ctx.create_and_wire_with_constructor2[CtorTwoDepService, CtorRepo, CtorCache]() or {
		assert false
		return
	}

	// 双参构造器注入成功
	assert svc.constructed == true
	assert !isnil(svc.repo)
	assert svc.repo.id == 100
	assert !isnil(svc.cache)
	assert svc.cache.hit_count == 5
}

fn test_create_and_wire_with_constructor2_fails_when_dep_missing() {
	mut ctx := new_application_context()
	// 仅注册 CtorRepo，不注册 CtorCache
	repo := &CtorRepo{ id: 1 }
	ctx.register_instance('CtorRepo', repo) or { assert false; return }

	_ := ctx.create_and_wire_with_constructor2[CtorTwoDepService, CtorRepo, CtorCache]() or {
		assert err.msg().contains('not found') || err.msg().contains('未找到')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// BeanDefinitionBuilder 测试 — 验证 add_constructor_param
// ═══════════════════════════════════════════════════════════

fn test_bean_definition_builder_add_constructor_param() {
	mut builder := new_bean_definition_builder('TestBean')
	builder.add_constructor_param(Dependency{ field_name: 'repo', type_name: 'Repo' })
	def := builder.build()

	assert def.constructor_params.len == 1
	assert def.constructor_params[0].field_name == 'repo'
	assert def.constructor_params[0].type_name == 'Repo'
	assert def.has_constructor_params() == true
}

fn test_new_bean_definition_initializes_constructor_params() {
	def := new_bean_definition('TestBean')
	// constructor_params 应被初始化为空切片
	assert def.constructor_params.len == 0
	assert def.has_constructor_params() == false
}

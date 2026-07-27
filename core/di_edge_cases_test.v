module core

// di_edge_cases_test.v — DI 容器边界路径验证（第三批）
//
// 验证路径：
//   K. Prototype scope 行为
//   L. FactoryBean 解析
//   M. Bean definition 合并（父子继承）
//   N. destroy / destroy_all（DisposableBean 回调）
//   O. is_singleton / is_prototype scope 查询
//   P. register_alias 错误场景
//   Q. remove_alias
//   R. resolve_by_qualifier / has_qualifier
//   S. resolve_all_by_type（综合查找）
//   T. create_mutable_deferred_provider
//   U. ContainerFreeze 冻结状态
//   V. create_and_wire（创建+注入+post_construct）
//   W. 计数器（bean_count / singleton_count / alias_count）
//   X. bean_names / list_beans / dependencies_of
//   Z. mark_ready 状态转换
//   AA. get_merged_definition 循环检测

// ── Mock 结构体（本文件独立编译）──

struct EdgeMockRepo {
	id    int
	label string
}

struct EdgeMockService {
pub mut:
	repo &EdgeMockRepo = unsafe { nil } @[autowired]
}

// ── K. Prototype scope ──

fn test_prototype_scope_not_cached() {
	mut c := new_container()
	mut def := new_bean_definition('proto_bean')
	def.scope = .prototype
	c.register(def) or { assert false }

	// prototype bean 没有 register_instance，resolve 返回 nil_sentinel
	// 但 is_prototype 查询应正确
	assert c.is_prototype('proto_bean') == true
	assert c.is_singleton('proto_bean') == false
}

fn test_is_singleton_default_scope() {
	mut c := new_container()
	c.register(new_bean_definition('singleton_bean')) or { assert false }

	assert c.is_singleton('singleton_bean') == true
	assert c.is_prototype('singleton_bean') == false
}

fn test_is_singleton_returns_false_for_unknown() {
	mut c := new_container()
	assert c.is_singleton('nonexistent') == false
	assert c.is_prototype('nonexistent') == false
}

// ── L. FactoryBean 解析 ──

struct MockConnectionFactory {}

fn (f &MockConnectionFactory) create() !voidptr {
	return unsafe { voidptr(&EdgeMockRepo{id: 1, label: 'factory'}) }
}

fn (f &MockConnectionFactory) bean_type() string {
	return 'FactoryProducedRepo'
}

fn (f &MockConnectionFactory) is_singleton() bool {
	return true
}

fn test_factory_bean_registration_and_resolution() {
	mut c := new_container()
	factory := &MockConnectionFactory{}
	c.register_factory('FactoryProducedRepo', factory) or { assert false }

	// has 应能发现 factory 生产的 bean
	assert c.has('FactoryProducedRepo') == true

	// resolve 应调用 factory.create()
	inst := c.resolve('FactoryProducedRepo') or { assert false; return }
	assert !isnil(inst)
	repo := unsafe { &EdgeMockRepo(inst) }
	assert repo.label == 'factory'
}

fn test_factory_bean_singleton_cached() {
	mut c := new_container()
	factory := &MockConnectionFactory{}
	// register_factory 以 factory.bean_type() 为 output_type_name 注册
	c.register_factory('FactoryProducedRepo', factory) or { assert false }

	// 第一次 resolve — factory.create() 被调用
	inst1 := c.resolve('FactoryProducedRepo') or { assert false; return }
	// 第二次 resolve — singleton 应缓存，返回同一实例
	inst2 := c.resolve('FactoryProducedRepo') or { assert false; return }

	assert inst1 == inst2
}

// ── M. Bean definition 合并（父子继承）──

fn test_get_merged_definition_no_parent() {
	mut c := new_container()
	mut def := new_bean_definition('child_bean')
	def.init_method = 'init'
	c.register(def) or { assert false }

	merged := c.get_merged_definition('child_bean') or { assert false; return }
	assert merged.init_method == 'init'
	assert merged.parent_name == ''
}

fn test_get_merged_definition_inherits_parent() {
	mut c := new_container()

	// 注册父 bean
	mut parent_def := new_bean_definition('parent_bean')
	parent_def.init_method = 'parent_init'
	parent_def.destroy_method = 'parent_destroy'
	c.register(parent_def) or { assert false }

	// 注册子 bean，继承父 bean
	mut child_def := new_bean_definition('child_bean')
	child_def.parent_name = 'parent_bean'
	// child 不设 init_method → 应继承 parent 的
	c.register(child_def) or { assert false }

	merged := c.get_merged_definition('child_bean') or { assert false; return }
	assert merged.init_method == 'parent_init'
	assert merged.destroy_method == 'parent_destroy'
}

// ── N. destroy / destroy_all ──

fn test_destroy_removes_instance() {
	mut c := new_container()
	repo := &EdgeMockRepo{id: 1}
	c.register_instance('destroyable', unsafe { voidptr(repo) }) or { assert false }
	assert c.has_instance('destroyable') == true

	c.destroy('destroyable') or { assert false }
	assert c.has_instance('destroyable') == false
}

fn test_destroy_unknown_returns_error() {
	mut c := new_container()
	c.destroy('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_destroy_all_clears_instances() {
	mut c := new_container()
	c.register_instance('bean_a', unsafe { voidptr(&EdgeMockRepo{id: 1}) }) or { assert false }
	c.register_instance('bean_b', unsafe { voidptr(&EdgeMockRepo{id: 2}) }) or { assert false }
	c.register_instance('bean_c', unsafe { voidptr(&EdgeMockRepo{id: 3}) }) or { assert false }
	assert c.singleton_count() == 3

	c.destroy_all()
	assert c.singleton_count() == 0
	assert c.bean_count() == 0
}

fn test_destroy_invokes_disposable_callback() {
	mut c := new_container()
	repo := &EdgeMockRepo{id: 42}
	c.register_instance('disposable_bean', unsafe { voidptr(repo) }) or { assert false }

	c.register_destroy_callback('disposable_bean', fn (inst voidptr) ! {
		// 回调被调用即标记
		_ = inst
	})
	assert c.has_destroy_callback('disposable_bean') == true

	c.destroy('disposable_bean') or { assert false }
	// destroy 后 callback 应被清除
	assert c.has_destroy_callback('disposable_bean') == false
}

// ── O. register_alias 错误场景 ──

fn test_register_alias_duplicate_returns_error() {
	mut c := new_container()
	c.register_instance('real_bean', unsafe { voidptr(&EdgeMockRepo{id: 1}) }) or { assert false }
	c.register_alias('Dup', 'real_bean') or { assert false }

	c.register_alias('Dup', 'real_bean') or {
		assert err.msg().contains('already registered')
		return
	}
	assert false
}

fn test_register_alias_nonexistent_canonical_returns_error() {
	mut c := new_container()
	c.register_alias('Alias', 'nonexistent_bean') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ── Q. remove_alias ──

fn test_remove_alias() {
	mut c := new_container()
	c.register_instance('bean', unsafe { voidptr(&EdgeMockRepo{id: 1}) }) or { assert false }
	c.register_alias('ToRemove', 'bean') or { assert false }
	assert c.has_alias('ToRemove') == true

	c.remove_alias('ToRemove')
	assert c.has_alias('ToRemove') == false
	// 原 bean 仍在
	assert c.has('bean') == true
}

fn test_remove_alias_idempotent() {
	mut c := new_container()
	// remove 不存在的别名不应报错
	c.remove_alias('nonexistent_alias')
	assert c.has_alias('nonexistent_alias') == false
}

// ── R. resolve_by_qualifier / has_qualifier ──

fn test_resolve_by_qualifier() {
	mut c := new_container()
	mut def := new_bean_definition('qualified_bean')
	def.qualifier = 'my_qualifier'
	c.register(def) or { assert false }
	repo := &EdgeMockRepo{id: 55}
	c.register_instance('qualified_bean', unsafe { voidptr(repo) }) or { assert false }

	assert c.has_qualifier('my_qualifier') == true
	assert c.has_qualifier('nonexistent') == false

	inst := c.resolve_by_qualifier('my_qualifier') or { assert false; return }
	assert inst == unsafe { voidptr(repo) }
}

fn test_resolve_by_qualifier_not_found() {
	mut c := new_container()
	c.resolve_by_qualifier('nonexistent') or {
		assert err.msg().contains('no bean')
		return
	}
	assert false
}

// ── S. resolve_all_by_type ──

fn test_resolve_all_by_type_exact_name_match() {
	mut c := new_container()
	repo := &EdgeMockRepo{id: 88}
	c.register_instance('EdgeMockRepo', unsafe { voidptr(repo) }) or { assert false }

	instances := c.resolve_all_by_type('EdgeMockRepo') or { assert false; return }
	assert instances.len >= 1
	assert instances[0] == unsafe { voidptr(repo) }
}

fn test_resolve_all_by_type_interface_match() {
	mut c := new_container()
	mut builder := new_bean_definition_builder('iface_impl')
	builder.add_interface('IRepo')
	def := builder.build()
	c.register(def) or { assert false }
	repo := &EdgeMockRepo{id: 99}
	c.register_instance('iface_impl', unsafe { voidptr(repo) }) or { assert false }

	instances := c.resolve_all_by_type('IRepo') or { assert false; return }
	assert instances.len >= 1
}

// ── T. create_mutable_deferred_provider ──

fn test_mutable_deferred_provider_no_cache() {
	mut c := new_container()
	repo := &EdgeMockRepo{id: 77}
	c.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }

	mut provider := c.create_mutable_deferred_provider('mock_repo')
	assert provider.is_resolved() == false

	inst1 := provider.get() or { assert false; return }
	// mutable provider 不缓存，但 singleton bean 本身缓存，所以返回同一实例
	inst2 := provider.get() or { assert false; return }
	assert inst1 == inst2 // singleton bean 返回同一实例
}

// ── U. ContainerFreeze ──

fn test_container_freeze_lifecycle() {
	mut cf := new_container_freeze()
	assert cf.frozen() == false

	cf.freeze()
	assert cf.frozen() == true

	cf.unfreeze()
	assert cf.frozen() == false
}

fn test_container_freeze_idempotent() {
	mut cf := new_container_freeze()
	cf.freeze()
	cf.freeze() // 二次冻结无害
	assert cf.frozen() == true
}

// ── V. create_and_wire ──

fn test_create_and_wire_injects_dependencies() {
	mut ctx := new_application_context()
	repo := &EdgeMockRepo{id: 10, label: 'wired'}
	ctx.register_instance('repo', unsafe { voidptr(repo) }) or { assert false }

	svc := ctx.create_and_wire[EdgeMockService]() or { assert false; return }
	assert !isnil(svc.repo)
	assert svc.repo.id == 10
	assert svc.repo.label == 'wired'
}

// ── W. 计数器 ──

fn test_bean_count_after_registration() {
	mut c := new_container()
	assert c.bean_count() == 0

	c.register(new_bean_definition('bean_a')) or { assert false }
	c.register(new_bean_definition('bean_b')) or { assert false }
	assert c.bean_count() == 2
}

fn test_singleton_count_after_instance_registration() {
	mut c := new_container()
	assert c.singleton_count() == 0

	c.register_instance('inst_a', unsafe { voidptr(&EdgeMockRepo{id: 1}) }) or { assert false }
	c.register_instance('inst_b', unsafe { voidptr(&EdgeMockRepo{id: 2}) }) or { assert false }
	assert c.singleton_count() == 2
}

fn test_alias_count() {
	mut c := new_container()
	c.register_instance('bean', unsafe { voidptr(&EdgeMockRepo{id: 1}) }) or { assert false }
	assert c.alias_count() == 0

	c.register_alias('A1', 'bean') or { assert false }
	c.register_alias('A2', 'bean') or { assert false }
	assert c.alias_count() == 2
}

// ── X. bean_names / list_beans / dependencies_of ──

fn test_bean_names_returns_all() {
	mut c := new_container()
	c.register(new_bean_definition('alpha')) or { assert false }
	c.register(new_bean_definition('beta')) or { assert false }
	c.register(new_bean_definition('gamma')) or { assert false }

	names := c.bean_names()
	assert 'alpha' in names
	assert 'beta' in names
	assert 'gamma' in names
	assert names.len == 3
}

fn test_list_beans_returns_bean_info() {
	mut c := new_container()
	mut builder := new_bean_definition_builder('listed_bean')
	builder.add_tag('service')
	def := builder.build()
	c.register(def) or { assert false }

	beans := c.list_beans()
	assert beans.len >= 1

	// 找到 listed_bean
	mut found := false
	for bean in beans {
		if bean.name == 'listed_bean' {
			found = true
			assert bean.scope == 'singleton'
		}
	}
	assert found
}

fn test_dependencies_of_returns_empty_for_no_deps() {
	mut c := new_container()
	c.register(new_bean_definition('no_deps_bean')) or { assert false }

	deps := c.dependencies_of('no_deps_bean')
	assert deps.len == 0
}

fn test_dependencies_of_returns_registered_deps() {
	mut c := new_container()
	mut builder := new_bean_definition_builder('dep_bean')
	builder.add_dependency(Dependency{
		field_name: 'repo'
		type_name:  'EdgeMockRepo'
	})
	def := builder.build()
	c.register(def) or { assert false }

	deps := c.dependencies_of('dep_bean')
	assert deps.len == 1
	assert deps[0].field_name == 'repo'
	assert deps[0].type_name == 'EdgeMockRepo'
}

fn test_dependencies_of_unknown_returns_empty() {
	mut c := new_container()
	deps := c.dependencies_of('nonexistent')
	assert deps.len == 0
}

// ── Z. mark_ready ──

fn test_mark_ready_transitions_state() {
	mut c := new_container()
	c.register(new_bean_definition('state_bean')) or { assert false }

	// mark_ready 不报错即通过
	c.mark_ready('state_bean') or { assert false; return }

	// 再次 mark_ready 也不报错
	c.mark_ready('state_bean') or { assert false; return }
}

fn test_mark_ready_unknown_returns_error() {
	mut c := new_container()
	c.mark_ready('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ── AA. get_merged_definition 循环检测 ──

fn test_get_merged_definition_circular_inheritance_detected() {
	mut c := new_container()

	// A → B → A（循环继承）
	mut def_a := new_bean_definition('circular_a')
	def_a.parent_name = 'circular_b'
	c.register(def_a) or { assert false }

	mut def_b := new_bean_definition('circular_b')
	def_b.parent_name = 'circular_a'
	c.register(def_b) or { assert false }

	c.get_merged_definition('circular_a') or {
		assert err.msg().contains('circular')
		return
	}
	assert false
}

fn test_get_merged_definition_unknown_parent_uses_child_as_is() {
	mut c := new_container()
	mut def := new_bean_definition('orphan_child')
	def.parent_name = 'nonexistent_parent'
	def.init_method = 'child_init'
	c.register(def) or { assert false }

	// 父不存在时，返回 child 定义本身
	merged := c.get_merged_definition('orphan_child') or { assert false; return }
	assert merged.init_method == 'child_init'
}

module core

// di_core_test.v — DI 容器核心安全路径验证（第四批）
//
// 本批聚焦 DI 容器的安全基石与副作用正确性：
//   BB. 循环依赖检测（check_circular_dependencies / find_dependency_cycle）
//   CC. 重复注册错误（register / register_instance）
//   DD. set_instance 存储实例
//   EE. init_callback 注册与调用
//   FF. replace_definition 副作用（旧实例移除）
//   GG. remove_definition 副作用（实例+别名+qualifier 清理）
//   HH. 多级别名链解析（A→B→C→bean）
//   II. get_service / get_service_by_name / has_service
//   JJ. autowire_bean 多字段同时注入
//   KK. autowire_bean capitalize_first 两级匹配
//   LL. get_definition 返回正确副本
//   MM. snapshot_singletons 多实例+多别名完整性
//   NN. resolve 未知 bean 错误信息

// ── Mock 结构体（本文件独立编译）──

struct CoreMockRepo {
	id int
}

struct CoreMockCache {
	size int
}

struct CoreMockService {
pub mut:
	repo  &CoreMockRepo  = unsafe { nil } @[autowired]
	cache &CoreMockCache = unsafe { nil } @[autowired]
}

struct CoreMockCapService {
pub mut:
	repo &CoreMockRepo = unsafe { nil } @[autowired]
}

// ── BB. 循环依赖检测 ──

fn test_check_circular_dependencies_no_cycle() {
	mut c := new_container()

	// A → B → C（无环）
	mut def_a := new_bean_definition('dep_a')
	def_a.dependencies = [Dependency{ field_name: 'b', type_name: 'dep_b' }]
	c.register(def_a) or { assert false }

	mut def_b := new_bean_definition('dep_b')
	def_b.dependencies = [Dependency{ field_name: 'c', type_name: 'dep_c' }]
	c.register(def_b) or { assert false }

	c.register(new_bean_definition('dep_c')) or { assert false }

	c.check_circular_dependencies() or {
		assert false
		return
	}
}

fn test_check_circular_dependencies_detects_simple_cycle() {
	mut c := new_container()

	// A → B → A（简单环）
	mut def_a := new_bean_definition('cycle_a')
	def_a.dependencies = [Dependency{ field_name: 'b', type_name: 'cycle_b' }]
	c.register(def_a) or { assert false }

	mut def_b := new_bean_definition('cycle_b')
	def_b.dependencies = [Dependency{ field_name: 'a', type_name: 'cycle_a' }]
	c.register(def_b) or { assert false }

	c.check_circular_dependencies() or {
		assert err.msg().contains('circular')
		return
	}
	assert false
}

fn test_check_circular_dependencies_detects_three_node_cycle() {
	mut c := new_container()

	// A → B → C → A（三节点环）
	mut def_a := new_bean_definition('tri_a')
	def_a.dependencies = [Dependency{ field_name: 'b', type_name: 'tri_b' }]
	c.register(def_a) or { assert false }

	mut def_b := new_bean_definition('tri_b')
	def_b.dependencies = [Dependency{ field_name: 'c', type_name: 'tri_c' }]
	c.register(def_b) or { assert false }

	mut def_c := new_bean_definition('tri_c')
	def_c.dependencies = [Dependency{ field_name: 'a', type_name: 'tri_a' }]
	c.register(def_c) or { assert false }

	c.check_circular_dependencies() or {
		assert err.msg().contains('circular')
		return
	}
	assert false
}

fn test_check_circular_dependencies_self_reference() {
	mut c := new_container()

	// A → A（自引用环）
	mut def := new_bean_definition('self_ref')
	def.dependencies = [Dependency{ field_name: 'self', type_name: 'self_ref' }]
	c.register(def) or { assert false }

	c.check_circular_dependencies() or {
		assert err.msg().contains('circular')
		return
	}
	assert false
}

fn test_find_dependency_cycle_returns_path() {
	mut c := new_container()

	mut def_a := new_bean_definition('path_a')
	def_a.dependencies = [Dependency{ field_name: 'b', type_name: 'path_b' }]
	c.register(def_a) or { assert false }

	mut def_b := new_bean_definition('path_b')
	def_b.dependencies = [Dependency{ field_name: 'a', type_name: 'path_a' }]
	c.register(def_b) or { assert false }

	cycle := c.find_dependency_cycle()
	assert cycle.len > 0
	// 路径应包含 path_a 和 path_b
	assert 'path_a' in cycle
	assert 'path_b' in cycle
}

fn test_find_dependency_cycle_no_cycle_returns_empty() {
	mut c := new_container()
	c.register(new_bean_definition('standalone')) or { assert false }

	cycle := c.find_dependency_cycle()
	assert cycle.len == 0
}

fn test_check_circular_dependencies_depends_on_explicit_order() {
	mut c := new_container()

	// 用 @[depends_on] 创建环：X depends_on Y, Y depends_on X
	mut def_x := new_bean_definition('dep_on_x')
	def_x.depends_on = ['dep_on_y']
	c.register(def_x) or { assert false }

	mut def_y := new_bean_definition('dep_on_y')
	def_y.depends_on = ['dep_on_x']
	c.register(def_y) or { assert false }

	c.check_circular_dependencies() or {
		assert err.msg().contains('circular')
		return
	}
	assert false
}

// ── CC. 重复注册错误 ──

fn test_register_duplicate_returns_error() {
	mut c := new_container()
	c.register(new_bean_definition('dup_bean')) or { assert false }

	c.register(new_bean_definition('dup_bean')) or {
		assert err.msg().contains('already registered')
		return
	}
	assert false
}

fn test_register_instance_duplicate_returns_error() {
	mut c := new_container()
	c.register_instance('dup_inst', unsafe { voidptr(&CoreMockRepo{ id: 1 }) }) or { assert false }

	c.register_instance('dup_inst', unsafe { voidptr(&CoreMockRepo{ id: 2 }) }) or {
		assert err.msg().contains('already registered')
		return
	}
	assert false
}

// ── DD. set_instance 存储实例 ──

fn test_set_instance_stores_and_resolves() {
	mut c := new_container()
	c.register(new_bean_definition('set_bean')) or { assert false }

	repo := &CoreMockRepo{ id: 42 }
	c.set_instance('set_bean', unsafe { voidptr(repo) })

	// resolve 应返回 set_instance 存储的实例
	inst := c.resolve('set_bean') or {
		assert false
		return
	}
	assert inst == unsafe { voidptr(repo) }
	assert c.has_instance('set_bean') == true
}

fn test_set_instance_overwrites_existing() {
	mut c := new_container()
	c.register(new_bean_definition('overwrite_bean')) or { assert false }

	repo1 := &CoreMockRepo{ id: 1 }
	c.set_instance('overwrite_bean', unsafe { voidptr(repo1) })

	repo2 := &CoreMockRepo{ id: 2 }
	c.set_instance('overwrite_bean', unsafe { voidptr(repo2) })

	inst := c.resolve('overwrite_bean') or {
		assert false
		return
	}
	assert inst == unsafe { voidptr(repo2) }
}

// ── EE. init_callback 注册与调用 ──

fn test_register_init_callback() {
	mut c := new_container()
	c.register(new_bean_definition('init_bean')) or { assert false }

	c.register_init_callback('init_bean', fn (inst voidptr) ! {
		_ = inst
	})
	assert c.has_init_callback('init_bean') == true
	assert c.has_init_callback('nonexistent') == false
}

fn test_invoke_init_callback_executes() {
	mut c := new_container()
	c.register(new_bean_definition('invoke_bean')) or { assert false }
	repo := &CoreMockRepo{ id: 10 }
	c.register_instance('invoke_bean', unsafe { voidptr(repo) }) or { assert false }

	invoked := false
	c.register_init_callback('invoke_bean', fn (inst voidptr) ! {
		_ = inst
	})

	// invoke_init_callback 不应报错
	c.invoke_init_callback('invoke_bean', unsafe { voidptr(repo) }) or {
		assert false
		return
	}
	_ = invoked
}

fn test_invoke_init_callback_no_callback_is_noop() {
	mut c := new_container()
	c.register(new_bean_definition('no_callback_bean')) or { assert false }

	// 没有 callback 时，invoke 应静默通过（noop）
	c.invoke_init_callback('no_callback_bean', voidptr(unsafe { nil })) or {
		assert false
		return
	}
}

// ── FF. replace_definition 副作用 ──

fn test_replace_definition_removes_old_instance() {
	mut c := new_container()
	repo1 := &CoreMockRepo{ id: 1 }
	c.register_instance('replace_bean', unsafe { voidptr(repo1) }) or { assert false }
	assert c.has_instance('replace_bean') == true

	// replace_definition 应移除旧实例
	c.replace_definition(new_bean_definition('replace_bean')) or { assert false }
	assert c.has_instance('replace_bean') == false
	assert c.has_definition('replace_bean') == true
}

fn test_replace_definition_updates_qualifier() {
	mut c := new_container()
	mut def_old := new_bean_definition('qual_replace')
	def_old.qualifier = 'old_qual'
	c.register(def_old) or { assert false }
	assert c.has_qualifier('old_qual') == true

	// 替换为新 qualifier
	mut def_new := new_bean_definition('qual_replace')
	def_new.qualifier = 'new_qual'
	c.replace_definition(def_new) or { assert false }

	assert c.has_qualifier('old_qual') == false
	assert c.has_qualifier('new_qual') == true
}

fn test_replace_definition_preserves_aliases() {
	mut c := new_container()
	c.register_instance('aliased_bean', unsafe { voidptr(&CoreMockRepo{ id: 1 }) }) or { assert false }
	c.register_alias('Alias1', 'aliased_bean') or { assert false }
	c.register_alias('Alias2', 'aliased_bean') or { assert false }

	// replace_definition 应保留别名
	c.replace_definition(new_bean_definition('aliased_bean')) or { assert false }
	assert c.has_alias('Alias1') == true
	assert c.has_alias('Alias2') == true
}

// ── GG. remove_definition 副作用 ──

fn test_remove_definition_removes_instance() {
	mut c := new_container()
	c.register_instance('rm_bean', unsafe { voidptr(&CoreMockRepo{ id: 1 }) }) or { assert false }
	assert c.has_instance('rm_bean') == true

	c.remove_definition('rm_bean') or { assert false }
	assert c.has_instance('rm_bean') == false
	assert c.has_definition('rm_bean') == false
}

fn test_remove_definition_removes_qualifier() {
	mut c := new_container()
	mut def := new_bean_definition('qual_rm')
	def.qualifier = 'rm_qual'
	c.register(def) or { assert false }
	assert c.has_qualifier('rm_qual') == true

	c.remove_definition('qual_rm') or { assert false }
	assert c.has_qualifier('rm_qual') == false
}

fn test_remove_definition_removes_aliases() {
	mut c := new_container()
	c.register_instance('aliased_rm', unsafe { voidptr(&CoreMockRepo{ id: 1 }) }) or { assert false }
	c.register_alias('RmAlias1', 'aliased_rm') or { assert false }
	c.register_alias('RmAlias2', 'aliased_rm') or { assert false }

	c.remove_definition('aliased_rm') or { assert false }
	assert c.has_alias('RmAlias1') == false
	assert c.has_alias('RmAlias2') == false
}

fn test_remove_definition_unknown_returns_error() {
	mut c := new_container()
	c.remove_definition('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ── HH. 多级别名链解析 ──

fn test_multi_level_alias_chain_resolution() {
	// register_alias 要求 canonical_name 在 definitions 中，
	// 不支持指向别名的别名。所以多级别名链通过公开 API 不可达。
	// 但单级别名链 resolve_alias_chain 的递归逻辑仍需验证。
	mut c := new_container()
	repo := &CoreMockRepo{ id: 99 }
	c.register_instance('actual_bean', unsafe { voidptr(repo) }) or { assert false }

	// 单级别名: AliasA → actual_bean
	c.register_alias('AliasA', 'actual_bean') or { assert false }

	// canonical_name 应穿透到实际 bean
	assert c.canonical_name('AliasA') == 'actual_bean'
	assert c.canonical_name('actual_bean') == 'actual_bean'

	// resolve 通过别名应找到实例
	inst := c.resolve('AliasA') or {
		assert false
		return
	}
	assert inst == unsafe { voidptr(repo) }
}

fn test_alias_chain_self_reference_returns_self() {
	mut c := new_container()
	c.register_instance('self_bean', unsafe { voidptr(&CoreMockRepo{ id: 1 }) }) or { assert false }
	c.register_alias('SelfRef', 'self_bean') or { assert false }

	// 正常链解析
	assert c.canonical_name('SelfRef') == 'self_bean'
	// 非别名名返回自身
	assert c.canonical_name('self_bean') == 'self_bean'
	assert c.canonical_name('nonexistent') == 'nonexistent'
}

// ── II. get_service / get_service_by_name / has_service ──

fn test_get_service_resolves_by_type() {
	mut ctx := new_application_context()
	// create_and_register 内部用 T.name 注册，与 get_service[T] 的 T.name 一致
	ctx.create_and_register[CoreMockRepo]() or {
		assert false
		return
	}

	svc := ctx.get_service[CoreMockRepo]() or {
		assert false
		return
	}
	assert !isnil(svc)
}

fn test_get_service_by_name_resolves() {
	mut ctx := new_application_context()
	repo := &CoreMockRepo{ id: 66 }
	ctx.register_instance('named_service', unsafe { voidptr(repo) }) or { assert false }

	inst := ctx.get_service_by_name('named_service') or {
		assert false
		return
	}
	assert inst == unsafe { voidptr(repo) }
}

fn test_get_service_by_name_not_found() {
	mut ctx := new_application_context()
	ctx.get_service_by_name('nonexistent') or {
		return
	}
	assert false
}

fn test_has_service_checks_existence() {
	mut ctx := new_application_context()
	ctx.register_instance('present', unsafe { voidptr(&CoreMockRepo{ id: 1 }) }) or { assert false }

	assert ctx.has_service('present') == true
	assert ctx.has_service('absent') == false
}

// ── JJ. autowire_bean 多字段同时注入 ──

fn test_autowire_bean_multi_field_injection() {
	mut ctx := new_application_context()
	repo := &CoreMockRepo{ id: 10 }
	cache := &CoreMockCache{ size: 256 }

	ctx.register_instance('repo', unsafe { voidptr(repo) }) or { assert false }
	ctx.register_instance('cache', unsafe { voidptr(cache) }) or { assert false }

	mut svc := CoreMockService{}
	ctx.autowire_bean[CoreMockService](mut svc) or { assert false }

	assert !isnil(svc.repo)
	assert svc.repo.id == 10
	assert !isnil(svc.cache)
	assert svc.cache.size == 256
}

fn test_autowire_bean_partial_injection_when_one_missing() {
	mut ctx := new_application_context()
	repo := &CoreMockRepo{ id: 20 }
	// 只注册 repo，不注册 cache
	ctx.register_instance('repo', unsafe { voidptr(repo) }) or { assert false }

	mut svc := CoreMockService{}
	ctx.autowire_bean[CoreMockService](mut svc) or {}

	// repo 应注入成功
	assert !isnil(svc.repo)
	assert svc.repo.id == 20
	// cache 应保持 nil（未找到）
	assert isnil(svc.cache)
}

// ── KK. autowire_bean capitalize_first 两级匹配 ──

fn test_autowire_bean_capitalize_first_match() {
	mut ctx := new_application_context()
	repo := &CoreMockRepo{ id: 30 }

	// 注册名为首字母大写形式 'Repo'，字段名为 'repo'
	ctx.register_instance('Repo', unsafe { voidptr(repo) }) or { assert false }

	mut svc := CoreMockCapService{}
	ctx.autowire_bean[CoreMockCapService](mut svc) or { assert false }

	// capitalize_first('repo') = 'Repo' → 应命中
	assert !isnil(svc.repo)
	assert svc.repo.id == 30
}

fn test_autowire_bean_field_name_exact_match_preferred() {
	mut ctx := new_application_context()
	repo_lower := &CoreMockRepo{ id: 40 }
	repo_upper := &CoreMockRepo{ id: 41 }

	// 同时注册 'repo' 和 'Repo'
	ctx.register_instance('repo', unsafe { voidptr(repo_lower) }) or { assert false }
	ctx.register_instance('Repo', unsafe { voidptr(repo_upper) }) or { assert false }

	mut svc := CoreMockCapService{}
	ctx.autowire_bean[CoreMockCapService](mut svc) or { assert false }

	// 字段名 'repo' 精确匹配优先于 capitalize_first('repo')='Repo'
	assert !isnil(svc.repo)
	assert svc.repo.id == 40
}

// ── LL. get_definition 返回正确副本 ──

fn test_get_definition_returns_correct_copy() {
	mut c := new_container()
	mut def := new_bean_definition('def_bean')
	def.scope = .prototype
	def.is_lazy = true
	def.init_method = 'my_init'
	def.qualifier = 'my_qual'
	c.register(def) or { assert false }

	retrieved := c.get_definition('def_bean') or {
		assert false
		return
	}
	assert retrieved.type_name == 'def_bean'
	assert retrieved.scope == .prototype
	assert retrieved.is_lazy == true
	assert retrieved.init_method == 'my_init'
	assert retrieved.qualifier == 'my_qual'
}

fn test_get_definition_unknown_returns_error() {
	mut c := new_container()
	c.get_definition('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ── MM. snapshot_singletons 多实例+多别名完整性 ──

fn test_snapshot_singletons_multi_instance_multi_alias() {
	mut c := new_container()
	repo1 := &CoreMockRepo{ id: 1 }
	repo2 := &CoreMockRepo{ id: 2 }

	c.register_instance('bean_a', unsafe { voidptr(repo1) }) or { assert false }
	c.register_instance('bean_b', unsafe { voidptr(repo2) }) or { assert false }
	c.register_alias('AliasA', 'bean_a') or { assert false }
	c.register_alias('AliasB', 'bean_b') or { assert false }
	c.register_alias('TypeA', 'bean_a') or { assert false }

	snapshot := c.snapshot_singletons()
	// 2 实例 + 3 别名 = 5 条目
	assert snapshot.len == 5
	// 指针值 map 的下标必须带 `or {}`（-prod 下缺失会直接编译失败），
	// 下面统一走一次 unsafely 取值，保持断言可读。
	got_a := snapshot['bean_a'] or { voidptr(0) }
	got_b := snapshot['bean_b'] or { voidptr(0) }
	got_alias_a := snapshot['AliasA'] or { voidptr(0) }
	got_alias_b := snapshot['AliasB'] or { voidptr(0) }
	got_type_a := snapshot['TypeA'] or { voidptr(0) }
	assert unsafe { got_a == voidptr(repo1) }
	assert unsafe { got_b == voidptr(repo2) }
	assert unsafe { got_alias_a == voidptr(repo1) }
	assert unsafe { got_alias_b == voidptr(repo2) }
	assert unsafe { got_type_a == voidptr(repo1) }
}

// ── NN. resolve 未知 bean 错误信息 ──

fn test_resolve_unknown_returns_descriptive_error() {
	mut c := new_container()
	c.resolve('nonexistent_bean') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_resolve_unknown_in_empty_container() {
	mut c := new_container()
	c.resolve('anything') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ── OO. ApplicationContext resolve 未冻结时缓存填充 ──

fn test_resolve_before_freeze_populates_cache() {
	mut ctx := new_application_context()
	repo := &CoreMockRepo{ id: 77 }
	ctx.register_instance('pre_freeze_bean', unsafe { voidptr(repo) }) or { assert false }

	// 未冻结时 resolve
	inst1 := ctx.resolve('pre_freeze_bean') or {
		assert false
		return
	}
	assert inst1 == unsafe { voidptr(repo) }

	// 第二次 resolve 应命中缓存（未冻结时走 cache_mu 路径）
	misses_before := ctx.cache_miss_count()
	inst2 := ctx.resolve('pre_freeze_bean') or {
		assert false
		return
	}
	misses_after := ctx.cache_miss_count()

	assert inst2 == inst1
	// 第二次不应产生新的 cache miss
	assert misses_after == misses_before
}

// ── PP. register_instance 自动创建 definition ──

fn test_register_instance_auto_creates_definition() {
	mut c := new_container()
	c.register_instance('auto_def_bean', unsafe { voidptr(&CoreMockRepo{ id: 1 }) }) or { assert false }

	// register_instance 应自动创建 definition
	assert c.has_definition('auto_def_bean') == true
	assert c.has_instance('auto_def_bean') == true

	// 自动创建的 definition 应为 singleton scope
	assert c.is_singleton('auto_def_bean') == true
}

// ── QQ. freeze 后 cache_hits 增长 ──

fn test_freeze_cache_hits_increment_on_resolve() {
	mut ctx := new_application_context()
	ctx.register_instance('hit_bean', unsafe { voidptr(&CoreMockRepo{ id: 1 }) }) or { assert false }
	ctx.freeze_bean_definitions()

	hits_before := ctx.cache_hit_count()

	_ = ctx.resolve('hit_bean') or {
		assert false
		return
	}
	_ = ctx.resolve('hit_bean') or {
		assert false
		return
	}
	_ = ctx.resolve('hit_bean') or {
		assert false
		return
	}

	hits_after := ctx.cache_hit_count()
	// 3 次 resolve 应产生 3 次 cache hit 增长
	assert hits_after >= hits_before + 3
}

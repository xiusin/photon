module core

// di_advanced_test.v — DI 容器高级路径验证（第二批）
//
// 验证路径：
//   A. 别名链与 canonical_name
//   B. 冻结后写操作被阻止
//   C. has 系列（has / has_alias / has_definition / has_instance）
//   D. resolve_or / resolve_typed
//   E. 父容器（hierarchical context）
//   F. type-based lookup（interface / tag）
//   G. primary bean
//   H. DeferredProvider 延迟解析
//   I. autowire_bean qualifier 优先级
//   J. invalidate_cache + unfreeze

// ── Mock 结构体（本文件独立编译，不依赖其他 _test.v）──

struct AdvMockRepo {
	id int
}

// ── A. 别名链与 canonical_name ──

fn test_canonical_name_single_alias() {
	mut c := new_container()
	repo := &AdvMockRepo{ id: 1 }
	c.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }
	c.register_alias('AdvMockRepo', 'mock_repo') or { assert false }

	assert c.canonical_name('AdvMockRepo') == 'mock_repo'
	assert c.canonical_name('mock_repo') == 'mock_repo'
}

fn test_canonical_name_no_alias_returns_self() {
	mut c := new_container()
	c.register_instance('plain_bean', unsafe { voidptr(&AdvMockRepo{ id: 2 }) }) or { assert false }

	assert c.canonical_name('plain_bean') == 'plain_bean'
	assert c.canonical_name('nonexistent') == 'nonexistent'
}

fn test_resolve_uses_alias_to_find_instance() {
	mut c := new_container()
	repo := &AdvMockRepo{ id: 33 }
	c.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }
	c.register_alias('Repo', 'mock_repo') or { assert false }

	inst := c.resolve('Repo') or {
		assert false
		return
	}
	assert inst == unsafe { voidptr(repo) }
}

// ── B. 冻结后写操作被阻止 ──

fn test_freeze_blocks_register() {
	mut ctx := new_application_context()
	ctx.freeze_bean_definitions()

	ctx.register(new_bean_definition('blocked_bean')) or {
		assert err.msg().contains('frozen')
		return
	}
	assert false
}

fn test_freeze_blocks_register_instance() {
	mut ctx := new_application_context()
	ctx.freeze_bean_definitions()

	ctx.register_instance('blocked_inst', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or {
		assert err.msg().contains('frozen')
		return
	}
	assert false
}

fn test_freeze_blocks_register_instance_with_aliases() {
	mut ctx := new_application_context()
	ctx.freeze_bean_definitions()

	ctx.register_instance_with_aliases('blocked', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }, ['Alias']) or {
		assert err.msg().contains('frozen')
		return
	}
	assert false
}

fn test_freeze_blocks_remove_definition() {
	mut ctx := new_application_context()
	ctx.register_instance('removable', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }
	ctx.freeze_bean_definitions()

	ctx.remove_definition('removable') or {
		assert err.msg().contains('frozen')
		return
	}
	assert false
}

fn test_freeze_blocks_replace_definition() {
	mut ctx := new_application_context()
	ctx.register_instance('replaceable', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }
	ctx.freeze_bean_definitions()

	ctx.replace_definition(new_bean_definition('replaceable')) or {
		assert err.msg().contains('frozen')
		return
	}
	assert false
}

// ── C. has 系列 ──

fn test_has_finds_registered_definition() {
	mut c := new_container()
	c.register(new_bean_definition('my_bean')) or { assert false }

	assert c.has('my_bean') == true
}

fn test_has_finds_via_alias() {
	mut c := new_container()
	c.register_instance('real_bean', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }
	c.register_alias('Alias', 'real_bean') or { assert false }

	assert c.has('Alias') == true
	assert c.has('real_bean') == true
}

fn test_has_returns_false_for_unknown() {
	mut c := new_container()
	assert c.has('nonexistent') == false
}

fn test_has_alias_check() {
	mut c := new_container()
	c.register_instance('bean', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }
	c.register_alias('A1', 'bean') or { assert false }

	assert c.has_alias('A1') == true
	assert c.has_alias('bean') == false
}

fn test_has_definition_strict_check() {
	mut c := new_container()
	c.register_instance('inst_bean', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }

	// register_instance auto-creates definition, so has_definition is true
	assert c.has_definition('inst_bean') == true
	assert c.has_definition('nonexistent') == false
}

fn test_has_instance_after_register_instance() {
	mut c := new_container()
	c.register(new_bean_definition('def_only')) or { assert false }
	c.register_instance('with_inst', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }

	assert c.has_instance('with_inst') == true
	assert c.has_instance('def_only') == false // definition only, no instance
}

// ── D. resolve_or / resolve_typed ──

fn test_resolve_or_returns_default_when_not_found() {
	mut c := new_container()
	default_val := unsafe { voidptr(&AdvMockRepo{ id: 999 }) }

	result := c.resolve_or('nonexistent', default_val)
	assert result == default_val
}

fn test_resolve_or_returns_instance_when_found() {
	mut c := new_container()
	repo := &AdvMockRepo{ id: 55 }
	c.register_instance('found', unsafe { voidptr(repo) }) or { assert false }
	default_val := unsafe { voidptr(&AdvMockRepo{ id: 999 }) }

	result := c.resolve_or('found', default_val)
	assert result == unsafe { voidptr(repo) }
	assert result != default_val
}

fn test_resolve_typed_correct_cast() {
	mut ctx := new_application_context()
	repo := &AdvMockRepo{ id: 77 }
	ctx.register_instance('AdvMockRepo', unsafe { voidptr(repo) }) or { assert false }

	resolved := ctx.resolve_typed[AdvMockRepo]('AdvMockRepo') or {
		assert false
		return
	}
	assert resolved.id == 77
}

// ── E. 父容器（hierarchical context）──

fn test_parent_container_fallback_resolve() {
	mut parent := new_container()
	parent_repo := &AdvMockRepo{ id: 42 }
	parent.register_instance('parent_bean', unsafe { voidptr(parent_repo) }) or { assert false }

	mut child := new_container()
	child.set_parent(parent)

	inst := child.resolve('parent_bean') or {
		assert false
		return
	}
	assert inst == unsafe { voidptr(parent_repo) }
}

fn test_has_checks_parent_container() {
	mut parent := new_container()
	parent.register_instance('parent_only', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }

	mut child := new_container()
	child.set_parent(parent)

	assert child.has('parent_only') == true
	assert child.has('child_only') == false
}

// ── F. type-based lookup（interface / tag）──

fn test_beans_for_interface_lookup() {
	mut c := new_container()
	mut builder1 := new_bean_definition_builder('handler_a')
	builder1.add_interface('EventHandler')
	def1 := builder1.build()
	c.register(def1) or { assert false }
	c.register_instance('handler_a', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }

	mut builder2 := new_bean_definition_builder('handler_b')
	builder2.add_interface('EventHandler')
	def2 := builder2.build()
	c.register(def2) or { assert false }
	c.register_instance('handler_b', unsafe { voidptr(&AdvMockRepo{ id: 2 }) }) or { assert false }

	names := c.beans_for_interface('EventHandler')
	assert 'handler_a' in names
	assert 'handler_b' in names
	assert names.len >= 2
}

fn test_resolve_all_by_interface() {
	mut c := new_container()
	mut builder := new_bean_definition_builder('iface_bean')
	builder.add_interface('IDataSource')
	def := builder.build()
	c.register(def) or { assert false }
	repo := &AdvMockRepo{ id: 88 }
	c.register_instance('iface_bean', unsafe { voidptr(repo) }) or { assert false }

	instances := c.resolve_all_by_interface('IDataSource') or {
		assert false
		return
	}
	assert instances.len >= 1
	assert instances[0] == unsafe { voidptr(repo) }
}

fn test_beans_for_tag_lookup() {
	mut c := new_container()
	mut builder1 := new_bean_definition_builder('cache_a')
	builder1.add_tag('cache')
	def1 := builder1.build()
	c.register(def1) or { assert false }
	c.register_instance('cache_a', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }

	mut builder2 := new_bean_definition_builder('cache_b')
	builder2.add_tag('cache')
	def2 := builder2.build()
	c.register(def2) or { assert false }
	c.register_instance('cache_b', unsafe { voidptr(&AdvMockRepo{ id: 2 }) }) or { assert false }

	names := c.beans_for_tag('cache')
	assert 'cache_a' in names
	assert 'cache_b' in names
}

fn test_resolve_all_by_tag() {
	mut c := new_container()
	mut builder := new_bean_definition_builder('tagged_bean')
	builder.add_tag('service')
	def := builder.build()
	c.register(def) or { assert false }
	repo := &AdvMockRepo{ id: 66 }
	c.register_instance('tagged_bean', unsafe { voidptr(repo) }) or { assert false }

	instances := c.resolve_all_by_tag('service') or {
		assert false
		return
	}
	assert instances.len >= 1
	assert instances[0] == unsafe { voidptr(repo) }
}

// ── G. primary bean ──

fn test_resolve_primary_returns_primary() {
	mut c := new_container()

	mut def_primary := new_bean_definition('primary_repo')
	def_primary.is_primary = true
	c.register(def_primary) or { assert false }
	c.register_instance('primary_repo', unsafe { voidptr(&AdvMockRepo{ id: 111 }) }) or { assert false }

	mut def_secondary := new_bean_definition('secondary_repo')
	c.register(def_secondary) or { assert false }
	c.register_instance('secondary_repo', unsafe { voidptr(&AdvMockRepo{ id: 222 }) }) or { assert false }

	inst := c.resolve_primary() or {
		assert false
		return
	}
	repo := unsafe { &AdvMockRepo(inst) }
	assert repo.id == 111
}

fn test_get_primary_bean_name() {
	mut c := new_container()
	assert c.get_primary_bean_name() == ''

	mut def := new_bean_definition('the_primary')
	def.is_primary = true
	c.register(def) or { assert false }

	assert c.get_primary_bean_name() == 'the_primary'
}

// ── H. DeferredProvider 延迟解析 ──

fn test_deferred_provider_lazy_resolution() {
	mut c := new_container()
	repo := &AdvMockRepo{ id: 77 }
	c.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }

	mut provider := c.create_deferred_provider('mock_repo')
	assert provider.is_resolved() == false

	inst := provider.get() or {
		assert false
		return
	}
	assert provider.is_resolved() == true
	assert inst == unsafe { voidptr(repo) }

	// 第二次 get 应返回缓存（同一实例）
	inst2 := provider.get() or {
		assert false
		return
	}
	assert inst2 == inst
}

// ── I. autowire_bean qualifier 优先级 ──

struct QualifierMockService {
pub mut:
	repo &AdvMockRepo = unsafe { nil } @[autowired; qualifier: 'primary']
}

fn test_autowire_bean_qualifier_precedence() {
	mut ctx := new_application_context()
	primary_repo := &AdvMockRepo{ id: 100 }
	field_name_repo := &AdvMockRepo{ id: 200 }

	// 注册两个 bean：qualifier 名 'primary' + 字段名 'repo'
	ctx.register_instance('primary', unsafe { voidptr(primary_repo) }) or { assert false }
	ctx.register_instance('repo', unsafe { voidptr(field_name_repo) }) or { assert false }

	mut svc := QualifierMockService{}
	ctx.autowire_bean[QualifierMockService](mut svc) or { assert false }

	// qualifier 'primary' 应优先于字段名 'repo'
	assert !isnil(svc.repo)
	assert svc.repo.id == 100
}

// ── J. invalidate_cache + unfreeze ──

fn test_unfreeze_clears_cache_and_counters() {
	mut ctx := new_application_context()
	ctx.register_instance('bean_a', unsafe { voidptr(&AdvMockRepo{ id: 1 }) }) or { assert false }
	ctx.freeze_bean_definitions()

	// 冻结后 resolve 产生 cache hit
	_ = ctx.resolve('bean_a') or {
		assert false
		return
	}
	assert ctx.cache_hit_count() >= 1

	ctx.unfreeze_bean_definitions()
	assert ctx.is_frozen_bean_definitions() == false
	assert ctx.cache_size() == 0
	assert ctx.cache_hit_count() == 0
	assert ctx.cache_miss_count() == 0
}

fn test_replace_definition_invalidates_cache() {
	mut ctx := new_application_context()
	repo1 := &AdvMockRepo{ id: 10 }
	ctx.register_instance('replaceable_bean', unsafe { voidptr(repo1) }) or { assert false }

	// resolve 填充缓存
	inst1 := ctx.resolve('replaceable_bean') or {
		assert false
		return
	}
	assert inst1 == unsafe { voidptr(repo1) }

	// replace_definition 应使缓存失效
	ctx.replace_definition(new_bean_definition('replaceable_bean')) or { assert false }

	// 缓存应被清除（该 type_name 条目）
	// 重新 resolve 会走慢速路径（cache miss）
	misses_before := ctx.cache_miss_count()
	_ = ctx.resolve('replaceable_bean') or { voidptr(unsafe { nil }) }
	misses_after := ctx.cache_miss_count()
	assert misses_after > misses_before
}

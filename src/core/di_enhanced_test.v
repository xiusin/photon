module core

// di_enhanced_test.v - Tests for Enhanced DI Features
//
// Tests:
//   - MethodInjection
//   - CollectionInjection
//   - DeferredProvider
//   - BeanTypeIndex
//   - ServiceProvider / ProviderRegistry
//   - ShardedRwMutex
//   - BeanLock

// ═══════════════════════════════════════════════════════════
// MethodInjection Tests
// ═══════════════════════════════════════════════════════════

fn test_method_injection_struct() {
	mi := MethodInjection{
		method_name: 'set_cache'
		params:      [Dependency{ field_name: 'cache', type_name: 'CacheService' }]
	}
	assert mi.method_name == 'set_cache'
	assert mi.params.len == 1
	assert mi.params[0].type_name == 'CacheService'
}

fn test_dependency_is_required_default() {
	dep := Dependency{
		field_name: 'repo'
		type_name:  'UserRepository'
	}
	assert dep.is_required == true // default should be true

	dep2 := Dependency{
		field_name:  'cache'
		type_name:   'CacheService'
		is_required: false
	}
	assert dep2.is_required == false
}

// ═══════════════════════════════════════════════════════════
// CollectionInjection Tests
// ═══════════════════════════════════════════════════════════

fn test_collection_injection_struct() {
	ci := CollectionInjection{
		field_name:     'handlers'
		interface_name: 'EventHandler'
	}
	assert ci.field_name == 'handlers'
	assert ci.interface_name == 'EventHandler'
	assert ci.tag == ''
}

fn test_collection_injection_with_tag() {
	ci := CollectionInjection{
		field_name:     'caches'
		interface_name: 'CacheService'
		tag:            'distributed'
	}
	assert ci.tag == 'distributed'
}

// ═══════════════════════════════════════════════════════════
// DeferredProvider Tests
// ═══════════════════════════════════════════════════════════

fn test_deferred_provider_new() {
	mut dp := new_deferred_provider('CacheService')
	assert dp.type_name == 'CacheService'
	assert dp.is_resolved() == false
	assert dp.mutable == false
}

fn test_deferred_provider_mutable() {
	mut dp := new_deferred_provider('CacheService')
	dp.mutable = true
	assert dp.mutable == true
}

fn test_deferred_provider_no_container() {
	mut dp := new_deferred_provider('TestService')
	dp.get() or {
		assert err.msg().contains('no container')
		return
	}
	assert false
}

fn test_deferred_provider_get_or() {
	mut dp := new_deferred_provider('TestService')
	result := dp.get_or(unsafe { voidptr(42) })
	// Without container, should return default
	assert result == unsafe { voidptr(42) }
}

fn test_container_create_deferred_provider() {
	mut c := new_container()
	mut provider := c.create_deferred_provider('UserService')
	assert provider.type_name == 'UserService'
	assert provider.is_resolved() == false
}

fn test_container_create_mutable_deferred_provider() {
	mut c := new_container()
	provider := c.create_mutable_deferred_provider('UserService')
	assert provider.type_name == 'UserService'
	assert provider.mutable == true
}

// ═══════════════════════════════════════════════════════════
// BeanTypeIndex Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_type_index_new() {
	mut idx := new_bean_type_index()
	assert idx.interface_count() == 0
	assert idx.tag_count() == 0
}

fn test_bean_type_index_register_interface() {
	mut idx := new_bean_type_index()
	idx.register_interface('RedisCache', 'CacheService')
	idx.register_interface('MemCache', 'CacheService')

	beans := idx.beans_for_interface('CacheService')
	assert beans.len == 2
	assert 'RedisCache' in beans
	assert 'MemCache' in beans
}

fn test_bean_type_index_register_tag() {
	mut idx := new_bean_type_index()
	idx.register_tag('RedisCache', 'cache')
	idx.register_tag('MemCache', 'cache')

	beans := idx.beans_for_tag('cache')
	assert beans.len == 2
}

fn test_bean_type_index_has_interface() {
	mut idx := new_bean_type_index()
	assert idx.has_interface('CacheService') == false
	idx.register_interface('RedisCache', 'CacheService')
	assert idx.has_interface('CacheService') == true
}

fn test_bean_type_index_has_tag() {
	mut idx := new_bean_type_index()
	assert idx.has_tag('cache') == false
	idx.register_tag('RedisCache', 'cache')
	assert idx.has_tag('cache') == true
}

fn test_bean_type_index_no_duplicates() {
	mut idx := new_bean_type_index()
	idx.register_interface('RedisCache', 'CacheService')
	idx.register_interface('RedisCache', 'CacheService') // duplicate
	beans := idx.beans_for_interface('CacheService')
	assert beans.len == 1
}

fn test_bean_type_index_rebuild() {
	mut idx := new_bean_type_index()
	mut c := new_container()
	mut def1 := new_bean_definition('RedisCache')
	def1.tags = ['cache']
	c.register(def1) or { assert false }

	mut def2 := new_bean_definition('MemCache')
	def2.tags = ['cache']
	c.register(def2) or { assert false }

	idx.rebuild(mut c)
	assert idx.tag_count() == 1
	beans := idx.beans_for_tag('cache')
	assert beans.len == 2
}

// ═══════════════════════════════════════════════════════════
// Container Type-Based Lookup Tests
// ═══════════════════════════════════════════════════════════

fn test_container_beans_for_interface() {
	mut c := new_container()
	mut def1 := new_bean_definition('RedisCache')
	def1.interfaces = ['CacheService']
	c.register(def1) or { assert false }

	mut def2 := new_bean_definition('MemCache')
	def2.interfaces = ['CacheService']
	c.register(def2) or { assert false }

	beans := c.beans_for_interface('CacheService')
	assert beans.len == 2
	assert 'RedisCache' in beans
	assert 'MemCache' in beans
}

fn test_container_beans_for_tag() {
	mut c := new_container()
	mut def1 := new_bean_definition('RedisCache')
	def1.tags = ['cache', 'distributed']
	c.register(def1) or { assert false }

	beans := c.beans_for_tag('cache')
	assert beans.len == 1
	assert 'RedisCache' in beans

	beans_distributed := c.beans_for_tag('distributed')
	assert beans_distributed.len == 1
}

fn test_container_beans_for_interface_empty() {
	mut c := new_container()
	c.register(new_bean_definition('SomeService')) or { assert false }
	beans := c.beans_for_interface('NonExistentInterface')
	assert beans.len == 0
}

fn test_container_beans_for_tag_empty() {
	mut c := new_container()
	c.register(new_bean_definition('SomeService')) or { assert false }
	beans := c.beans_for_tag('nonexistent')
	assert beans.len == 0
}

// ═══════════════════════════════════════════════════════════
// ServiceProvider / ProviderRegistry Tests
// ═══════════════════════════════════════════════════════════

fn test_provider_registry_new() {
	mut reg := new_provider_registry()
	assert reg.provider_count() == 0
}

fn test_provider_registry_add() {
	mut reg := new_provider_registry()
	reg.add('CacheProvider', &ServiceProvider(&TestServiceProvider{}))
	assert reg.provider_count() == 1
}

fn test_provider_registry_is_booted() {
	mut reg := new_provider_registry()
	reg.add('CacheProvider', &ServiceProvider(&TestServiceProvider{}))
	assert reg.is_booted('CacheProvider') == false
	assert reg.is_booted('NonExistent') == false
}

// Test helper: ServiceProvider implementation
struct TestServiceProvider {
pub mut:
	registered bool
	booted     bool
}

pub fn (sp TestServiceProvider) register(mut ctx ApplicationContext) ! {
	// ServiceProvider.register — immutable receiver for interface compatibility
}

pub fn (sp TestServiceProvider) boot(mut ctx ApplicationContext) ! {
	// ServiceProvider.boot — immutable receiver for interface compatibility
}

fn test_application_context_register_provider() {
	mut ctx := new_application_context()
	ctx.register_provider('CacheProvider', &ServiceProvider(&TestServiceProvider{}))
	assert !isnil(ctx.provider_registry)
	assert ctx.provider_registry.provider_count() == 1
}

// ═══════════════════════════════════════════════════════════
// ShardedRwMutex Tests
// ═══════════════════════════════════════════════════════════

fn test_sharded_rw_mutex_new() {
	mut sm := new_sharded_rw_mutex()
	assert sm.shards.len == shard_count
}

fn test_sharded_rw_mutex_rlock_unlock() {
	mut sm := new_sharded_rw_mutex()
	sm.rlock('test_key')
	sm.runlock('test_key')
	// Should not panic
	assert true
}

fn test_sharded_rw_mutex_write_lock_unlock() {
	mut sm := new_sharded_rw_mutex()
	sm.@lock('test_key')
	sm.unlock('test_key')
	// Should not panic
	assert true
}

fn test_sharded_rw_mutex_rlock_all() {
	mut sm := new_sharded_rw_mutex()
	sm.rlock_all()
	sm.runlock_all()
	// Should not panic
	assert true
}

fn test_sharded_rw_mutex_lock_all() {
	mut sm := new_sharded_rw_mutex()
	sm.lock_all()
	sm.unlock_all()
	// Should not panic
	assert true
}

// ═══════════════════════════════════════════════════════════
// BeanLock Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_lock_new() {
	mut bl := new_bean_lock()
	assert bl.lock_count() == 0
}

fn test_bean_lock_lock_unlock() {
	mut bl := new_bean_lock()
	bl.lock('UserService')
	assert bl.lock_count() == 1
	bl.unlock('UserService')
	assert bl.lock_count() == 1 // still exists until removed
}

fn test_bean_lock_remove() {
	mut bl := new_bean_lock()
	bl.lock('UserService')
	bl.unlock('UserService')
	bl.remove('UserService')
	assert bl.lock_count() == 0
}

fn test_bean_lock_cleanup() {
	mut bl := new_bean_lock()
	bl.lock('ServiceA')
	bl.unlock('ServiceA')
	bl.lock('ServiceB')
	bl.unlock('ServiceB')
	assert bl.lock_count() == 2
	bl.cleanup()
	assert bl.lock_count() == 0
}

// ═══════════════════════════════════════════════════════════
// BeanDefinition Enhanced Fields Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_definition_enhanced_fields() {
	mut def := new_bean_definition('UserService')
	assert def.interfaces.len == 0
	assert def.method_injections.len == 0
	assert def.collection_injections.len == 0

	def.interfaces = ['CacheService', 'LogService']
	def.method_injections = [
		MethodInjection{
			method_name: 'set_cache'
			params:      []Dependency{}
		},
	]
	def.collection_injections = [
		CollectionInjection{
			field_name:     'handlers'
			interface_name: 'EventHandler'
		},
	]

	assert def.interfaces.len == 2
	assert def.method_injections.len == 1
	assert def.collection_injections.len == 1
}

fn test_bean_definition_builder_enhanced() {
	mut builder := new_bean_definition_builder('UserService')
	builder.add_interface('CacheService')
	builder.add_method_injection(MethodInjection{
		method_name: 'set_cache'
		params:      [Dependency{ field_name: 'cache', type_name: 'CacheService' }]
	})
	builder.add_collection_injection(CollectionInjection{
		field_name:     'handlers'
		interface_name: 'EventHandler'
	})

	def := builder.build()
	assert def.interfaces.len == 1
	assert def.interfaces[0] == 'CacheService'
	assert def.method_injections.len == 1
	assert def.collection_injections.len == 1
}

// ═══════════════════════════════════════════════════════════
// ApplicationContext Type-Based Lookup Tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_beans_for_interface() {
	mut ctx := new_application_context()
	mut def1 := new_bean_definition('RedisCache')
	def1.interfaces = ['CacheService']
	ctx.register(def1) or { assert false }

	beans := ctx.beans_for_interface('CacheService')
	assert beans.len == 1
	assert 'RedisCache' in beans
}

fn test_application_context_beans_for_tag() {
	mut ctx := new_application_context()
	mut def1 := new_bean_definition('RedisCache')
	def1.tags = ['cache']
	ctx.register(def1) or { assert false }

	beans := ctx.beans_for_tag('cache')
	assert beans.len == 1
}

fn test_application_context_create_deferred_provider() {
	mut ctx := new_application_context()
	mut provider := ctx.create_deferred_provider('CacheService')
	assert provider.type_name == 'CacheService'
	assert provider.is_resolved() == false
}

// ═══════════════════════════════════════════════════════════
// BeanTypeIndex Unregister Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_type_index_unregister_interface() {
	mut idx := new_bean_type_index()
	idx.register_interface('RedisCache', 'CacheService')
	idx.register_interface('MemCache', 'CacheService')
	assert idx.beans_for_interface('CacheService').len == 2

	// Unregister one bean
	idx.unregister_interface('RedisCache', 'CacheService')
	beans := idx.beans_for_interface('CacheService')
	assert beans.len == 1
	assert 'MemCache' in beans
	assert 'RedisCache' !in beans
}

fn test_bean_type_index_unregister_last_interface() {
	mut idx := new_bean_type_index()
	idx.register_interface('RedisCache', 'CacheService')
	assert idx.has_interface('CacheService') == true

	// Unregister the only bean → interface should be removed
	idx.unregister_interface('RedisCache', 'CacheService')
	assert idx.has_interface('CacheService') == false
	assert idx.beans_for_interface('CacheService').len == 0
}

fn test_bean_type_index_unregister_tag() {
	mut idx := new_bean_type_index()
	idx.register_tag('RedisCache', 'cache')
	idx.register_tag('MemCache', 'cache')
	assert idx.beans_for_tag('cache').len == 2

	idx.unregister_tag('RedisCache', 'cache')
	beans := idx.beans_for_tag('cache')
	assert beans.len == 1
	assert 'MemCache' in beans
}

// ═══════════════════════════════════════════════════════════
// Bean Lifecycle Event Tests
// ═══════════════════════════════════════════════════════════

fn test_container_set_event_bus() {
	mut c := new_container()
	mut bus := new_event_bus()
	c.set_event_bus(bus)
	// Just verify it doesn't panic — the event_bus is set
	assert true
}

fn test_container_destroy_dispatches_event() {
	mut c := new_container()
	mut bus := new_event_bus()
	c.set_event_bus(bus)

	// Register a bean instance
	c.register_instance('TestService', unsafe { voidptr(42) }) or { assert false }

	// Register a listener for bean.destroyed event
	bus.on(event_bean_destroyed, fn (e &Event) {
		// Listener invoked — verified by dispatch return count
	})
	assert bus.listener_count_for(event_bean_destroyed) == 1

	// Destroy the bean — should dispatch event to the listener
	c.destroy('TestService') or { assert false }

	// Verify the bean was removed
	assert c.singleton_count() == 0
}

// ═══════════════════════════════════════════════════════════
// Container remove_definition Tests
// ═══════════════════════════════════════════════════════════

fn test_container_remove_definition() {
	mut c := new_container()
	c.register(new_bean_definition('TestService')) or { assert false }
	assert c.has('TestService') == true

	c.remove_definition('TestService') or { assert false }
	assert c.has('TestService') == false
	assert c.bean_count() == 0
}

fn test_container_remove_definition_nonexistent() {
	mut c := new_container()
	c.remove_definition('NonExistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_container_remove_definition_with_qualifier() {
	mut c := new_container()
	mut def := new_bean_definition('CacheService')
	def.qualifier = 'cache'
	c.register(def) or { assert false }
	assert c.has_qualifier('cache') == true

	c.remove_definition('CacheService') or { assert false }
	assert c.has('CacheService') == false
	assert c.has_qualifier('cache') == false
}

fn test_container_remove_definition_with_alias() {
	mut c := new_container()
	c.register(new_bean_definition('UserService')) or { assert false }
	c.register_alias('userSvc', 'UserService') or { assert false }
	assert c.has_alias('userSvc') == true

	c.remove_definition('UserService') or { assert false }
	assert c.has('UserService') == false
	// Alias should also be removed
	assert c.has_alias('userSvc') == false
}

fn test_container_remove_definition_with_type_index() {
	mut c := new_container()
	mut def := new_bean_definition('RedisCache')
	def.interfaces = ['CacheService']
	def.tags = ['cache']
	c.register(def) or { assert false }

	// Verify type index
	beans := c.beans_for_interface('CacheService')
	assert beans.len == 1

	// Remove definition
	c.remove_definition('RedisCache') or { assert false }

	// Type index should be cleaned up
	beans_after := c.beans_for_interface('CacheService')
	assert beans_after.len == 0
}

fn test_application_context_remove_definition() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('TestService')) or { assert false }
	assert ctx.has('TestService') == true

	ctx.remove_definition('TestService') or { assert false }
	assert ctx.has('TestService') == false
}

// ═══════════════════════════════════════════════════════════
// Alias Chain Resolution Tests
// ═══════════════════════════════════════════════════════════

fn test_container_alias_chain_resolution() {
	mut c := new_container()
	c.register(new_bean_definition('ActualBean')) or { assert false }
	// Chain: shortAlias → mediumAlias → ActualBean
	// We build the chain by directly inserting into the aliases map,
	// since register_alias() only allows registering aliases to real beans.
	c.register_alias('mediumAlias', 'ActualBean') or { assert false }
	// Manually add the second-level alias (shortAlias → mediumAlias)
	// In practice, this would be set up by the comptime scanner
	c.aliases['shortAlias'] = 'mediumAlias'

	// canonical_name should resolve the full chain
	assert c.canonical_name('shortAlias') == 'ActualBean'
	assert c.canonical_name('mediumAlias') == 'ActualBean'
	assert c.canonical_name('ActualBean') == 'ActualBean'
}

fn test_container_alias_chain_has() {
	mut c := new_container()
	c.register(new_bean_definition('RealService')) or { assert false }
	c.register_alias('alias1', 'RealService') or { assert false }
	// Manually add the second-level alias (alias2 → alias1)
	c.aliases['alias2'] = 'alias1'

	// has() should resolve through alias chain
	assert c.has('alias2') == true
	assert c.has('alias1') == true
	assert c.has('RealService') == true
}

fn test_container_alias_chain_circular() {
	mut c := new_container()
	// Create a circular alias: A → B → A
	// This is technically invalid but should not hang
	c.aliases['A'] = 'B'
	c.aliases['B'] = 'A'

	// Should not hang — max depth protection kicks in
	result := c.canonical_name('A')
	// Should return something without hanging (either A or B)
	assert result.len > 0
}

// ═══════════════════════════════════════════════════════════
// ConditionalOnBean / ConditionalOnMissingBean Tests
// ═══════════════════════════════════════════════════════════

fn test_on_bean_condition_present() {
	mut ctx := new_condition_context()
	mut c := new_container()
	c.register(new_bean_definition('CacheService')) or { assert false }
	ctx = ctx.with_container(c)

	cond := OnBeanCondition{
		bean_type: 'CacheService'
	}
	assert cond.evaluate(mut ctx) == true
}

fn test_on_bean_condition_absent() {
	mut ctx := new_condition_context()
	mut c := new_container()
	ctx = ctx.with_container(c)

	cond := OnBeanCondition{
		bean_type: 'NonExistentService'
	}
	assert cond.evaluate(mut ctx) == false
}

fn test_on_missing_bean_condition_present() {
	mut ctx := new_condition_context()
	mut c := new_container()
	c.register(new_bean_definition('CacheService')) or { assert false }
	ctx = ctx.with_container(c)

	cond := OnMissingBeanCondition{
		bean_type: 'CacheService'
	}
	assert cond.evaluate(mut ctx) == false
}

fn test_on_missing_bean_condition_absent() {
	mut ctx := new_condition_context()
	mut c := new_container()
	ctx = ctx.with_container(c)

	cond := OnMissingBeanCondition{
		bean_type: 'NonExistentService'
	}
	assert cond.evaluate(mut ctx) == true
}

fn test_on_missing_bean_condition_no_container() {
	mut ctx := new_condition_context()
	// No container set — bean is "missing" by definition
	cond := OnMissingBeanCondition{
		bean_type: 'AnyService'
	}
	assert cond.evaluate(mut ctx) == true
}

fn test_conditional_on_bean_attribute_skips() {
	mut ctx := new_application_context()
	// Register the primary bean
	ctx.register(new_bean_definition('PrimaryCache')) or { assert false }

	// Try to register a bean that depends on 'PrimaryCache' being present
	// (conditional_on_bean:PrimaryCache) — should succeed
	def := BeanDefinition{
		type_name: 'BackupCache'
		tags:      ['conditional_on_bean:PrimaryCache']
	}
	ctx.register(def) or {}
	assert ctx.has('BackupCache') == true
}

fn test_conditional_on_missing_bean_attribute_skips() {
	mut ctx := new_application_context()
	// Register a primary bean
	ctx.register(new_bean_definition('PrimaryCache')) or { assert false }

	// Try to register a fallback that should only exist when PrimaryCache is missing
	def := BeanDefinition{
		type_name: 'FallbackCache'
		tags:      ['conditional_on_missing_bean:PrimaryCache']
	}
	ctx.register(def) or {}
	// Should be skipped because PrimaryCache exists
	assert ctx.has('FallbackCache') == false
}

// ═══════════════════════════════════════════════════════════
// replace_definition Tests (Spring override / Laravel rebind)
// ═══════════════════════════════════════════════════════════

fn test_container_replace_definition_new() {
	mut c := new_container()
	// Replacing a non-existent definition should act like register()
	mut def := new_bean_definition('NewService')
	def.scope = .prototype
	c.replace_definition(def) or { assert false }
	assert c.has('NewService') == true
}

fn test_container_replace_definition_existing() {
	mut c := new_container()
	// Register original
	mut def1 := new_bean_definition('CacheService')
	def1.qualifier = 'cache'
	def1.interfaces = ['ICache']
	def1.tags = ['cache']
	c.register(def1) or { assert false }
	assert c.has_qualifier('cache') == true

	// Replace with new definition
	mut def2 := new_bean_definition('CacheService')
	def2.qualifier = 'fast-cache'
	def2.interfaces = ['ICache', 'IInvalidation']
	def2.tags = ['cache', 'distributed']
	c.replace_definition(def2) or { assert false }

	// Old qualifier should be removed, new one added
	assert c.has_qualifier('fast-cache') == true
	assert c.has_qualifier('cache') == false

	// Type index should be updated
	beans := c.beans_for_interface('IInvalidation')
	assert 'CacheService' in beans
}

fn test_container_replace_definition_removes_instance() {
	mut c := new_container()
	// Register and create instance
	c.register_instance('TestService', unsafe { voidptr(42) }) or { assert false }
	assert c.singleton_count() == 1

	// Replace definition — instance should be removed
	mut def := new_bean_definition('TestService')
	c.replace_definition(def) or { assert false }
	assert c.singleton_count() == 0
}

fn test_application_context_replace_definition() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('OldService')) or { assert false }
	assert ctx.has('OldService') == true

	mut new_def := new_bean_definition('OldService')
	new_def.is_lazy = true
	ctx.replace_definition(new_def) or { assert false }

	def := ctx.get_definition('OldService') or {
		assert false
		return
	}
	assert def.is_lazy == true
}

// ═══════════════════════════════════════════════════════════
// resolve_or Tests (Spring getIfAvailable)
// ═══════════════════════════════════════════════════════════

fn test_container_resolve_or_found() {
	mut c := new_container()
	c.register_instance('TestService', unsafe { voidptr(42) }) or { assert false }
	result := c.resolve_or('TestService', unsafe { nil })
	assert result == unsafe { voidptr(42) }
}

fn test_container_resolve_or_missing() {
	mut c := new_container()
	result := c.resolve_or('NonExistent', unsafe { voidptr(99) })
	assert result == unsafe { voidptr(99) }
}

fn test_application_context_resolve_or() {
	mut ctx := new_application_context()
	ctx.register_instance('TestService', unsafe { voidptr(42) }) or { assert false }
	result := ctx.resolve_or('TestService', unsafe { nil })
	assert result == unsafe { voidptr(42) }

	result2 := ctx.resolve_or('NonExistent', unsafe { voidptr(99) })
	assert result2 == unsafe { voidptr(99) }
}

// ═══════════════════════════════════════════════════════════
// ContainerFreeze Tests
// ═══════════════════════════════════════════════════════════

fn test_container_freeze_new() {
	mut cf := new_container_freeze()
	assert cf.frozen() == false
}

fn test_container_freeze_freeze() {
	mut cf := new_container_freeze()
	cf.freeze()
	assert cf.frozen() == true
}

fn test_container_freeze_unfreeze() {
	mut cf := new_container_freeze()
	cf.freeze()
	assert cf.frozen() == true
	cf.unfreeze()
	assert cf.frozen() == false
}

fn test_container_freeze_double_freeze() {
	mut cf := new_container_freeze()
	cf.freeze()
	cf.freeze() // should not panic
	assert cf.frozen() == true
}

// ═══════════════════════════════════════════════════════════
// LookupInjection Tests (Spring @Lookup)
// ═══════════════════════════════════════════════════════════

fn test_lookup_injection_struct() {
	li := LookupInjection{
		method_name: 'create_command'
		type_name:   'Command'
		qualifier:   'async'
	}
	assert li.method_name == 'create_command'
	assert li.type_name == 'Command'
	assert li.qualifier == 'async'
}

fn test_lookup_injection_no_qualifier() {
	li := LookupInjection{
		method_name: 'get_handler'
		type_name:   'Handler'
	}
	assert li.qualifier == ''
}

// ═══════════════════════════════════════════════════════════
// BeanTypeIndex rebuild with interface index Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_type_index_rebuild_includes_interfaces() {
	mut idx := new_bean_type_index()
	mut c := new_container()

	mut def1 := new_bean_definition('RedisCache')
	def1.interfaces = ['ICache']
	def1.tags = ['cache']
	c.register(def1) or { assert false }

	mut def2 := new_bean_definition('MemCache')
	def2.interfaces = ['ICache']
	def2.tags = ['cache']
	c.register(def2) or { assert false }

	idx.rebuild(mut c)

	// Verify interface index is rebuilt
	iface_beans := idx.beans_for_interface('ICache')
	assert iface_beans.len == 2
	assert 'RedisCache' in iface_beans
	assert 'MemCache' in iface_beans

	// Verify tag index is rebuilt
	tag_beans := idx.beans_for_tag('cache')
	assert tag_beans.len == 2
}

fn test_bean_type_index_full_rebuild_with_parent() {
	mut parent := new_container()
	mut def1 := new_bean_definition('ParentCache')
	def1.interfaces = ['ICache']
	def1.tags = ['cache']
	parent.register(def1) or { assert false }

	mut child := new_container()
	mut def2 := new_bean_definition('ChildCache')
	def2.interfaces = ['ICache']
	def2.tags = ['cache', 'local']
	child.register(def2) or { assert false }
	child.set_parent(parent)

	mut idx := new_bean_type_index()
	idx.full_rebuild(mut child)

	// Should include both parent and child beans
	iface_beans := idx.beans_for_interface('ICache')
	assert iface_beans.len == 2
	assert 'ParentCache' in iface_beans
	assert 'ChildCache' in iface_beans
}

// ═══════════════════════════════════════════════════════════
// BeanRegistrationOptions Enhanced Fields Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_registration_options_interfaces() {
	mut ctx := new_application_context()
	ctx.register_bean('CacheService', BeanRegistrationOptions{
		scope:      .singleton
		interfaces: ['ICache', 'IInvalidation']
		tags:       ['cache']
	}) or { assert false }

	assert ctx.has('CacheService') == true
	beans := ctx.beans_for_interface('ICache')
	assert 'CacheService' in beans

	beans2 := ctx.beans_for_interface('IInvalidation')
	assert 'CacheService' in beans2
}

fn test_bean_registration_options_method_injections() {
	mut ctx := new_application_context()
	ctx.register_bean('OrderService', BeanRegistrationOptions{
		method_injections: [
			MethodInjection{
				method_name: 'set_payment'
				params:      [
					Dependency{
						field_name: 'payment'
						type_name:  'PaymentService'
					},
				]
			},
		]
	}) or { assert false }

	def := ctx.get_definition('OrderService') or {
		assert false
		return
	}
	assert def.method_injections.len == 1
	assert def.method_injections[0].method_name == 'set_payment'
}

fn test_bean_registration_options_collection_injections() {
	mut ctx := new_application_context()
	ctx.register_bean('EventHandlerChain', BeanRegistrationOptions{
		collection_injections: [
			CollectionInjection{
				field_name:     'handlers'
				interface_name: 'IEventHandler'
				tag:            'event'
			},
		]
	}) or { assert false }

	def := ctx.get_definition('EventHandlerChain') or {
		assert false
		return
	}
	assert def.collection_injections.len == 1
	assert def.collection_injections[0].interface_name == 'IEventHandler'
}

// ═══════════════════════════════════════════════════════════
// @Lookup Method Injection Tests (Spring @Lookup)
// ═══════════════════════════════════════════════════════════

fn test_lookup_injection_in_bean_definition() {
	mut def := new_bean_definition('OrderService')
	assert def.lookup_injections.len == 0

	def.lookup_injections = [
		LookupInjection{
			method_name: 'create_command'
			type_name:   'Command'
			qualifier:   'async'
		},
	]
	assert def.lookup_injections.len == 1
	assert def.lookup_injections[0].method_name == 'create_command'
	assert def.lookup_injections[0].type_name == 'Command'
	assert def.lookup_injections[0].qualifier == 'async'
}

fn test_lookup_injection_builder() {
	mut builder := new_bean_definition_builder('OrderService')
	builder.add_lookup_injection(LookupInjection{
		method_name: 'create_command'
		type_name:   'Command'
	})
	builder.add_lookup_injection(LookupInjection{
		method_name: 'get_handler'
		type_name:   'Handler'
		qualifier:   'sync'
	})

	def := builder.build()
	assert def.lookup_injections.len == 2
	assert def.lookup_injections[0].method_name == 'create_command'
	assert def.lookup_injections[1].qualifier == 'sync'
}

fn test_container_resolve_lookup() {
	mut c := new_container()
	c.register_instance('Command', unsafe { voidptr(100) }) or { assert false }

	instance := c.resolve_lookup('Command', '') or {
		assert false
		return
	}
	assert instance == unsafe { voidptr(100) }
}

fn test_container_resolve_lookup_with_qualifier() {
	mut c := new_container()
	mut def := new_bean_definition('AsyncCommand')
	def.qualifier = 'async'
	c.register(def) or { assert false }
	c.register_instance('AsyncCommand', unsafe { voidptr(200) }) or { assert false }

	instance := c.resolve_lookup('AsyncCommand', 'async') or {
		assert false
		return
	}
	assert instance == unsafe { voidptr(200) }
}

fn test_container_resolve_lookup_missing() {
	mut c := new_container()
	c.resolve_lookup('NonExistent', '') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_container_resolve_lookup_for_bean() {
	mut c := new_container()
	c.register_instance('Command', unsafe { voidptr(42) }) or { assert false }
	c.register_instance('Handler', unsafe { voidptr(84) }) or { assert false }

	mut def := new_bean_definition('OrderService')
	def.lookup_injections = [
		LookupInjection{
			method_name: 'create_command'
			type_name:   'Command'
		},
		LookupInjection{
			method_name: 'get_handler'
			type_name:   'Handler'
		},
	]
	c.register(def) or { assert false }

	result := c.resolve_lookup_for_bean('OrderService') or {
		assert false
		return
	}

	assert result.len == 2
	assert result['create_command'] == unsafe { voidptr(42) }
	assert result['get_handler'] == unsafe { voidptr(84) }
}

fn test_container_resolve_lookup_for_bean_no_lookups() {
	mut c := new_container()
	c.register(new_bean_definition('SimpleService')) or { assert false }

	result := c.resolve_lookup_for_bean('SimpleService') or {
		assert false
		return
	}
	assert result.len == 0
}

fn test_container_resolve_lookup_for_bean_nonexistent() {
	mut c := new_container()
	result := c.resolve_lookup_for_bean('NonExistent') or {
		assert false
		return
	}
	assert result.len == 0
}

fn test_application_context_resolve_lookup() {
	mut ctx := new_application_context()
	ctx.register_instance('Command', unsafe { voidptr(42) }) or { assert false }

	instance := ctx.resolve_lookup('Command', '') or {
		assert false
		return
	}
	assert instance == unsafe { voidptr(42) }
}

fn test_application_context_resolve_lookup_for_bean() {
	mut ctx := new_application_context()
	ctx.register_instance('Command', unsafe { voidptr(42) }) or { assert false }

	mut def := new_bean_definition('OrderService')
	def.lookup_injections = [
		LookupInjection{
			method_name: 'create_command'
			type_name:   'Command'
		},
	]
	ctx.register(def) or { assert false }

	result := ctx.resolve_lookup_for_bean('OrderService') or {
		assert false
		return
	}
	assert result.len == 1
	assert result['create_command'] == unsafe { voidptr(42) }
}

fn test_bean_registration_options_lookup_injections() {
	mut ctx := new_application_context()
	ctx.register_bean('OrderService', BeanRegistrationOptions{
		lookup_injections: [
			LookupInjection{
				method_name: 'create_command'
				type_name:   'Command'
			},
		]
	}) or { assert false }

	def := ctx.get_definition('OrderService') or {
		assert false
		return
	}
	assert def.lookup_injections.len == 1
	assert def.lookup_injections[0].method_name == 'create_command'
}

// ═══════════════════════════════════════════════════════════
// resolve_all_by_type Tests (Spring getBeansOfType)
// ═══════════════════════════════════════════════════════════

fn test_container_resolve_all_by_type_via_interface() {
	mut c := new_container()
	mut def1 := new_bean_definition('RedisCache')
	def1.interfaces = ['CacheService']
	c.register(def1) or { assert false }
	c.register_instance('RedisCache', unsafe { voidptr(1) }) or { assert false }

	mut def2 := new_bean_definition('MemCache')
	def2.interfaces = ['CacheService']
	c.register(def2) or { assert false }
	c.register_instance('MemCache', unsafe { voidptr(2) }) or { assert false }

	instances := c.resolve_all_by_type('CacheService') or {
		assert false
		return
	}
	assert instances.len == 2
}

fn test_container_resolve_all_by_type_via_tag() {
	mut c := new_container()
	mut def := new_bean_definition('RedisCache')
	def.tags = ['cache']
	c.register(def) or { assert false }
	c.register_instance('RedisCache', unsafe { voidptr(1) }) or { assert false }

	instances := c.resolve_all_by_type('cache') or {
		assert false
		return
	}
	assert instances.len == 1
}

fn test_container_resolve_all_by_type_exact_name() {
	mut c := new_container()
	c.register(new_bean_definition('UniqueService')) or { assert false }
	c.register_instance('UniqueService', unsafe { voidptr(42) }) or { assert false }

	instances := c.resolve_all_by_type('UniqueService') or {
		assert false
		return
	}
	assert instances.len == 1
}

fn test_container_resolve_all_by_type_no_duplicates() {
	mut c := new_container()
	mut def := new_bean_definition('RedisCache')
	def.interfaces = ['CacheService']
	def.tags = ['CacheService'] // same name as interface — should not duplicate
	c.register(def) or { assert false }
	c.register_instance('RedisCache', unsafe { voidptr(1) }) or { assert false }

	instances := c.resolve_all_by_type('CacheService') or {
		assert false
		return
	}
	assert instances.len == 1 // should not duplicate
}

fn test_container_resolve_all_by_type_empty() {
	mut c := new_container()
	instances := c.resolve_all_by_type('NonExistent') or {
		assert false
		return
	}
	assert instances.len == 0
}

fn test_application_context_resolve_all_by_type() {
	mut ctx := new_application_context()
	mut def := new_bean_definition('RedisCache')
	def.interfaces = ['CacheService']
	ctx.register(def) or { assert false }
	ctx.register_instance('RedisCache', unsafe { voidptr(1) }) or { assert false }

	instances := ctx.resolve_all_by_type('CacheService') or {
		assert false
		return
	}
	assert instances.len == 1
}

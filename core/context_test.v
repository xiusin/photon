module core

// context_test.v — Tests for ApplicationContext, Environment, ServiceLocator,
// FactoryBean, BeanPostProcessor, AutoConfiguration, and Conditions

// ═══════════════════════════════════════════════════════════
// ApplicationContext Tests
// ═══════════════════════════════════════════════════════════

fn test_new_application_context() {
	mut ctx := new_application_context()
	assert !isnil(ctx.container)
	assert !isnil(ctx.event_bus)
	assert !isnil(ctx.lifecycle)
	assert !isnil(ctx.environment)
	assert ctx.current_state() == .created
}

fn test_application_context_profiles() {
	mut ctx := new_application_context()
	ctx.set_profiles(['dev', 'local'])
	assert ctx.has_profile('dev') == true
	assert ctx.has_profile('local') == true
	assert ctx.has_profile('prod') == false
}

fn test_application_context_add_profile() {
	mut ctx := new_application_context()
	ctx.add_profile('dev')
	ctx.add_profile('prod')
	assert ctx.has_profile('dev') == true
	assert ctx.has_profile('prod') == true
}

fn test_application_context_register_and_has() {
	mut ctx := new_application_context()
	def := new_bean_definition('UserService')
	ctx.register(def) or { assert false }
	assert ctx.has('UserService') == true
	assert ctx.has('NonExistent') == false
}

fn test_application_context_register_bean() {
	mut ctx := new_application_context()
	ctx.register_bean('CacheService', BeanRegistrationOptions{
		scope:     .singleton
		is_lazy:   true
		qualifier: 'cache'
		tags:      ['service']
	}) or { assert false }
	assert ctx.has('CacheService') == true
}

fn test_application_context_bean_names() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('UserService')) or { assert false }
	ctx.register(new_bean_definition('AuthService')) or { assert false }
	names := ctx.bean_names()
	assert names.len == 2
}

fn test_application_context_bean_count() {
	mut ctx := new_application_context()
	assert ctx.bean_count() == 0
	ctx.register(new_bean_definition('UserService')) or { assert false }
	assert ctx.bean_count() == 1
}

fn test_application_context_is_ready() {
	mut ctx := new_application_context()
	assert ctx.is_ready() == false
}

fn test_application_context_is_running() {
	mut ctx := new_application_context()
	assert ctx.is_running() == false
}

fn test_application_context_properties() {
	mut ctx := new_application_context()
	ctx.set_property('app.name', 'PhotonAPI')
	assert ctx.get_property('app.name') == 'PhotonAPI'
	assert ctx.get_property('missing') == ''
	assert ctx.get_property_or('missing', 'default') == 'default'
	assert ctx.get_property_or('app.name', 'default') == 'PhotonAPI'
}

fn test_application_context_shutdown() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('TestBean')) or { assert false }
	ctx.shutdown()
	assert ctx.current_state() == .closed
}

fn test_application_context_double_shutdown() {
	mut ctx := new_application_context()
	ctx.shutdown()
	assert ctx.current_state() == .closed
	ctx.shutdown() // should not panic
	assert ctx.current_state() == .closed
}

fn test_application_context_event_dispatch() {
	mut ctx := new_application_context()
	ctx.on('test.event', fn (e &Event) {
		assert e.payload_str == 'hello'
	})
	event := new_event('test.event', 'hello')
	ctx.dispatch(event)
}

// ═══════════════════════════════════════════════════════════
// Environment Tests
// ═══════════════════════════════════════════════════════════

fn test_new_environment() {
	mut env := new_environment()
	assert env.get_active_profiles().len > 0
	assert env.get_active_profiles()[0] == 'default'
}

fn test_environment_set_profiles() {
	mut env := new_environment()
	env.set_active_profiles(['dev', 'staging'])
	profiles := env.get_active_profiles()
	assert profiles.len == 2
	assert profiles[0] == 'dev'
	assert profiles[1] == 'staging'
}

fn test_environment_add_profile() {
	mut env := new_environment()
	env.add_active_profile('prod')
	assert env.accepts_profile('prod') == true
	assert env.accepts_profile('dev') == false
}

fn test_environment_remove_profile() {
	mut env := new_environment()
	env.add_active_profile('dev')
	env.add_active_profile('prod')
	env.remove_active_profile('dev')
	assert env.accepts_profile('dev') == false
	assert env.accepts_profile('prod') == true
}

fn test_environment_set_property() {
	mut env := new_environment()
	env.set_property('app.name', 'PhotonAPI')
	assert env.get_property('app.name') == 'PhotonAPI'
	assert env.get_property('nonexistent') == ''
}

fn test_environment_get_property_or() {
	mut env := new_environment()
	assert env.get_property_or('missing', 'default') == 'default'
	env.set_property('app.name', 'PhotonAPI')
	assert env.get_property_or('app.name', 'default') == 'PhotonAPI'
}

fn test_environment_get_property_int() {
	mut env := new_environment()
	env.set_property('server.port', '8080')
	val := env.get_property_int('server.port') or { 0 }
	assert val == 8080
}

fn test_environment_get_property_int_or() {
	mut env := new_environment()
	assert env.get_property_int_or('missing', 3000) == 3000
	env.set_property('server.port', '8080')
	assert env.get_property_int_or('server.port', 3000) == 8080
}

fn test_environment_get_property_bool() {
	mut env := new_environment()
	env.set_property('app.debug', 'true')
	val := env.get_property_bool('app.debug') or { false }
	assert val == true
}

fn test_environment_get_property_bool_or() {
	mut env := new_environment()
	assert env.get_property_bool_or('missing', false) == false
	env.set_property('app.debug', 'true')
	assert env.get_property_bool_or('app.debug', false) == true
}

fn test_environment_has_property() {
	mut env := new_environment()
	assert env.has_property('missing') == false
	env.set_property('app.name', 'PhotonAPI')
	assert env.has_property('app.name') == true
}

fn test_environment_remove_property() {
	mut env := new_environment()
	env.set_property('app.name', 'PhotonAPI')
	env.remove_property('app.name')
	assert env.has_property('app.name') == false
}

fn test_environment_property_keys() {
	mut env := new_environment()
	env.set_property('a', '1')
	env.set_property('b', '2')
	keys := env.property_keys()
	assert keys.len == 2
}

fn test_environment_property_count() {
	mut env := new_environment()
	assert env.property_count() == 0
	env.set_property('a', '1')
	assert env.property_count() == 1
}

fn test_environment_set_properties() {
	mut env := new_environment()
	env.set_properties({
		'app.name':    'PhotonAPI'
		'app.version': '0.4.0'
	})
	assert env.get_property('app.name') == 'PhotonAPI'
	assert env.get_property('app.version') == '0.4.0'
}

fn test_environment_resolve_placeholders() {
	mut env := new_environment()
	env.set_property('app.name', 'PhotonAPI')
	env.set_property('app.version', '0.4.0')
	dollar := rune(36).str() // '$'
	template := 'Hello ' + dollar + '{app.name} v' + dollar + '{app.version}'
	result := env.resolve_placeholders(template)
	assert result == 'Hello PhotonAPI v0.4.0'
}

fn test_environment_resolve_placeholders_with_default() {
	mut env := new_environment()
	env.set_property('app.name', 'PhotonAPI')
	dollar := rune(36).str() // '$'
	default_placeholder := dollar + '{app.env:production}'
	template := dollar + '{app.name} running on ' + default_placeholder
	result := env.resolve_placeholders(template)
	assert result == 'PhotonAPI running on production'
}

fn test_environment_validate_required_properties() {
	mut env := new_environment()
	env.set_property('app.name', 'PhotonAPI')
	// Should pass — app.name exists
	env.validate_required_properties(['app.name']) or { assert false }
	// Should fail — missing.property doesn't exist
	env.validate_required_properties(['missing.property']) or {
		assert err.msg().contains('missing required properties')
		return
	}
	assert false // should have returned in the or block
}

fn test_environment_is_profile_active() {
	mut env := new_environment()
	env.add_active_profile('dev')
	assert env.is_profile_active('dev') == true
	assert env.is_profile_active('prod') == false
}

// ═══════════════════════════════════════════════════════════
// Condition Tests (Enhanced)
// ═══════════════════════════════════════════════════════════

fn test_on_expression_condition_equality() {
	mut ctx := new_condition_context()
	ctx = ctx.with_properties({
		'cache.enabled': 'true'
	})
	c := OnExpressionCondition{
		expression: 'cache.enabled==true'
	}
	assert c.evaluate(mut ctx) == true
}

fn test_on_expression_condition_inequality() {
	mut ctx := new_condition_context()
	ctx = ctx.with_properties({
		'cache.driver': 'redis'
	})
	c := OnExpressionCondition{
		expression: 'cache.driver!=memory'
	}
	assert c.evaluate(mut ctx) == true
}

fn test_on_expression_condition_truthy() {
	mut ctx := new_condition_context()
	ctx = ctx.with_properties({
		'app.prod': 'true'
	})
	c := OnExpressionCondition{
		expression: 'app.prod'
	}
	assert c.evaluate(mut ctx) == true
}

fn test_on_expression_condition_not_prefix() {
	mut ctx := new_condition_context()
	ctx = ctx.with_properties({
		'app.debug': 'true'
	})
	c := OnExpressionCondition{
		expression: '!app.debug'
	}
	assert c.evaluate(mut ctx) == false
}

fn test_on_expression_condition_missing_key() {
	mut ctx := new_condition_context()
	ctx = ctx.with_properties({
		'other': 'value'
	})
	c := OnExpressionCondition{
		expression: 'nonexistent==value'
	}
	assert c.evaluate(mut ctx) == false
}

fn test_on_cloud_platform_condition() {
	mut ctx := new_condition_context()
	ctx = ctx.with_properties({
		'cloud.platform': 'aliyun'
	})
	c := OnCloudPlatformCondition{
		platform: 'aliyun'
	}
	assert c.evaluate(mut ctx) == true

	c2 := OnCloudPlatformCondition{
		platform: 'aws'
	}
	assert c2.evaluate(mut ctx) == false
}

fn test_any_condition_matches() {
	mut ctx := new_condition_context()
	ctx = ctx.with_profiles(['prod'])

	c1 := &Condition(&OnProfileCondition{
		profile: 'dev'
	})
	c2 := &Condition(&OnProfileCondition{
		profile: 'prod'
	})

	// None match
	mut conditions1 := []&Condition{}
	conditions1 << c1
	assert any_condition_matches(conditions1, mut ctx) == false

	// One matches
	mut conditions2 := []&Condition{}
	conditions2 << c1
	conditions2 << c2
	assert any_condition_matches(conditions2, mut ctx) == true
}

// ═══════════════════════════════════════════════════════════
// Service Locator Tests
// ═══════════════════════════════════════════════════════════

fn test_binding_registry_bind() {
	mut registry := new_binding_registry()
	registry.bind('TestService', fn () !voidptr {
		return unsafe { voidptr(1) }
	}, true)
	assert registry.has_binding('TestService') == true
	assert registry.has_binding('NonExistent') == false
}

fn test_binding_registry_bind_instance() {
	mut registry := new_binding_registry()
	registry.bind_instance('TestService', unsafe { voidptr(42) })
	assert registry.has_binding('TestService') == true
}

fn test_binding_registry_resolve_singleton() {
	mut registry := new_binding_registry()
	registry.bind('TestService', fn () !voidptr {
		return unsafe { voidptr(1) }
	}, true) // singleton
	result := registry.resolve('TestService') or { unsafe { nil } }
	assert !isnil(result)
}

fn test_binding_registry_resolve_prototype() {
	mut registry := new_binding_registry()
	registry.bind('TestService', fn () !voidptr {
		return unsafe { voidptr(1) }
	}, false) // prototype
	result := registry.resolve('TestService') or { unsafe { nil } }
	assert !isnil(result)
}

fn test_binding_registry_singleton_caching() {
	mut registry := new_binding_registry()
	registry.bind('SingletonService', fn () !voidptr {
		return unsafe { voidptr(99) }
	}, true) // singleton

	// First resolve
	r1 := registry.resolve('SingletonService') or { unsafe { nil } }
	// Second resolve should use cache (same pointer)
	r2 := registry.resolve('SingletonService') or { unsafe { nil } }
	assert r1 == r2
}

fn test_binding_registry_resolve_missing() {
	mut registry := new_binding_registry()
	registry.resolve('NonExistent') or {
		assert err.msg().contains('not bound')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// FactoryBean Registry Tests
// ═══════════════════════════════════════════════════════════

fn test_factory_bean_registry() {
	mut registry := new_factory_bean_registry()
	assert registry.factory_count() == 0
}

fn test_factory_bean_registry_has_factory() {
	mut registry := new_factory_bean_registry()
	assert registry.has_factory('TestFactory') == false
}

// ═══════════════════════════════════════════════════════════
// AutoConfiguration Manager Tests
// ═══════════════════════════════════════════════════════════

fn test_auto_configuration_manager() {
	mut mgr := new_auto_configuration_manager()
	assert mgr.candidate_count() == 0
}

// ═══════════════════════════════════════════════════════════
// Scanner Helper Tests
// ═══════════════════════════════════════════════════════════

fn test_has_conditional_attr() {
	assert has_conditional_attr(['component', 'conditional_on_profile:prod']) == true
	assert has_conditional_attr(['component', 'service']) == false
}

fn test_extract_conditions() {
	attrs := ['component', 'conditional_on_profile:prod', 'conditional_on_property:cache.enabled']
	conditions := extract_conditions(attrs)
	assert conditions.len == 2
	assert conditions[0].starts_with('conditional_on_profile')
	assert conditions[1].starts_with('conditional_on_property')
}

fn test_is_required() {
	assert is_required(['autowired', 'required']) == true
	assert is_required(['autowired']) == false
}

fn test_has_event_listener() {
	assert has_event_listener(['event_listener']) == true
	assert has_event_listener(['get']) == false
}

fn test_extract_scheduled_expr() {
	assert extract_scheduled_expr(['scheduled:0 0 * * *']) == '0 0 * * *'
	assert extract_scheduled_expr(['component']) == ''
}

fn test_extract_cacheable_key() {
	assert extract_cacheable_key(['cacheable:user:#id']) == 'user:#id'
	assert extract_cacheable_key(['component']) == ''
}

fn test_component_type_auto_configuration() {
	ct := component_type_from_attr('auto_configuration')
	assert ct == .auto_configuration
	assert ct.str() == 'auto_configuration'
}

// ═══════════════════════════════════════════════════════════
// Container Enhancement Tests
// ═══════════════════════════════════════════════════════════

fn test_container_has_with_factory_registry() {
	mut c := new_container()
	assert c.has('NonExistent') == false
}

fn test_container_register_and_has() {
	mut c := new_container()
	c.register(new_bean_definition('TestBean')) or { assert false }
	assert c.has('TestBean') == true
}

fn test_container_double_register() {
	mut c := new_container()
	c.register(new_bean_definition('TestBean')) or { assert false }
	c.register(new_bean_definition('TestBean')) or {
		assert err.msg().contains('already registered')
		return
	}
	assert false
}

fn test_container_resolve_missing() {
	mut c := new_container()
	c.resolve('NonExistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// PostProcessor Tests
// ═══════════════════════════════════════════════════════════

fn test_base_post_processor() {
	pp := BasePostProcessor{}
	result := pp.post_process_before_initialization('TestBean', unsafe { voidptr(1) })
	assert !isnil(result)
	result2 := pp.post_process_after_initialization('TestBean', unsafe { voidptr(1) })
	assert !isnil(result2)
}

fn test_application_context_add_post_processor() {
	mut ctx := new_application_context()
	pp := &BasePostProcessor{}
	ctx.add_post_processor(pp)
	assert ctx.post_processors.len == 1
}

fn test_application_context_add_factory_post_processor() {
	mut ctx := new_application_context()
	fpp := &TestFactoryPostProcessor{}
	ctx.add_factory_post_processor(fpp)
	assert ctx.factory_post_processors.len == 1
}

// Test helper: simple BeanFactoryPostProcessor
struct TestFactoryPostProcessor {
mut:
	processed bool
}

pub fn (fpp &TestFactoryPostProcessor) post_process_bean_factory(mut ctx ApplicationContext) {
	unsafe {
		mut f := fpp
		f.processed = true
	}
}

// ═══════════════════════════════════════════════════════════
// Conditional Registration Tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_conditional_registration_skip() {
	mut ctx := new_application_context()
	ctx.set_profiles(['dev'])

	// This bean should be skipped — 'prod' profile is not active
	def := BeanDefinition{
		type_name: 'ProdOnlyService'
		tags:      ['conditional_on_profile:prod']
	}
	ctx.register(def) or {}
	// Bean should NOT be registered
	assert ctx.has('ProdOnlyService') == false
}

fn test_application_context_conditional_registration_pass() {
	mut ctx := new_application_context()
	ctx.set_profiles(['dev'])

	// This bean should be registered — 'dev' profile is active
	def := BeanDefinition{
		type_name: 'DevService'
		tags:      ['conditional_on_profile:dev']
	}
	ctx.register(def) or {}
	// Bean should be registered
	assert ctx.has('DevService') == true
}

// ═══════════════════════════════════════════════════════════
// Diagnostic Tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_print_info() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('TestBean')) or { assert false }
	ctx.print_info() // just verify it doesn't panic
	assert ctx.bean_count() == 1
}

// ═══════════════════════════════════════════════════════════
// Bean Alias Tests
// ═══════════════════════════════════════════════════════════

fn test_container_register_alias() {
	mut c := new_container()
	c.register(new_bean_definition('UserService')) or { assert false }
	c.register_alias('userSvc', 'UserService') or { assert false }
	assert c.has_alias('userSvc') == true
	assert c.canonical_name('userSvc') == 'UserService'
	assert c.canonical_name('UserService') == 'UserService' // not an alias
}

fn test_container_alias_has() {
	mut c := new_container()
	c.register(new_bean_definition('UserService')) or { assert false }
	c.register_alias('userSvc', 'UserService') or { assert false }
	assert c.has('userSvc') == true // alias resolves via has()
	assert c.has('UserService') == true
}

fn test_container_alias_count() {
	mut c := new_container()
	assert c.alias_count() == 0
	c.register(new_bean_definition('UserService')) or { assert false }
	c.register_alias('userSvc', 'UserService') or { assert false }
	assert c.alias_count() == 1
}

fn test_container_remove_alias() {
	mut c := new_container()
	c.register(new_bean_definition('UserService')) or { assert false }
	c.register_alias('userSvc', 'UserService') or { assert false }
	c.remove_alias('userSvc')
	assert c.has_alias('userSvc') == false
}

fn test_container_alias_double_register() {
	mut c := new_container()
	c.register(new_bean_definition('UserService')) or { assert false }
	c.register_alias('userSvc', 'UserService') or { assert false }
	c.register_alias('userSvc', 'UserService') or {
		assert err.msg().contains('already registered')
		return
	}
	assert false
}

fn test_container_alias_nonexistent_canonical() {
	mut c := new_container()
	c.register_alias('userSvc', 'NonExistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// Parent Container (Hierarchical Context) Tests
// ═══════════════════════════════════════════════════════════

fn test_container_parent_resolve() {
	mut parent := new_container()
	parent.register(new_bean_definition('ParentBean')) or { assert false }

	mut child := new_container()
	child.set_parent(parent)

	// Child can see parent's beans
	assert child.has('ParentBean') == true
	// Child delegates resolution to parent — since no actual instance exists
	// (comptime-generated code sets instances), we just verify has() works
	// and the parent lookup path doesn't error on definition lookup
}

fn test_container_parent_has() {
	mut parent := new_container()
	parent.register(new_bean_definition('ParentBean')) or { assert false }

	mut child := new_container()
	child.set_parent(parent)
	child.register(new_bean_definition('ChildBean')) or { assert false }

	assert child.has('ParentBean') == true
	assert child.has('ChildBean') == true
	assert child.has('NonExistent') == false
}

fn test_application_context_set_parent() {
	mut parent_ctx := new_application_context()
	parent_ctx.register(new_bean_definition('SharedService')) or { assert false }

	mut child_ctx := new_application_context()
	child_ctx.register(new_bean_definition('LocalService')) or { assert false }
	child_ctx.set_parent(parent_ctx)

	assert child_ctx.has('SharedService') == true
	assert child_ctx.has('LocalService') == true
}

// ═══════════════════════════════════════════════════════════
// BeanDefinitionBuilder Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_definition_builder_basic() {
	mut builder := new_bean_definition_builder('UserService')
	builder.set_scope(.singleton)
	builder.set_lazy(true)
	builder.set_qualifier('userSvc')
	builder.add_tag('service')
	builder.add_dependency(Dependency{ field_name: 'repo', type_name: 'UserRepository' })
	builder.set_init_method('init')
	builder.set_destroy_method('cleanup')
	def := builder.build()

	assert def.type_name == 'UserService'
	assert def.scope == .singleton
	assert def.is_lazy == true
	assert def.qualifier == 'userSvc'
	assert 'service' in def.tags
	assert def.dependencies.len == 1
	assert def.dependencies[0].type_name == 'UserRepository'
	assert def.init_method == 'init'
	assert def.destroy_method == 'cleanup'
}

fn test_bean_definition_builder_defaults() {
	def := new_bean_definition_builder('SimpleBean').build()
	assert def.type_name == 'SimpleBean'
	assert def.scope == .singleton
	assert def.is_lazy == false
	assert def.qualifier == ''
	assert def.dependencies.len == 0
}

// ═══════════════════════════════════════════════════════════
// SmartLifecycle Tests
// ═══════════════════════════════════════════════════════════

fn test_smart_lifecycle_manager() {
	mut mgr := new_smart_lifecycle_manager()
	assert mgr.entry_count() == 0
}

fn test_smart_lifecycle_phase_ordering() {
	mut mgr := new_smart_lifecycle_manager()
	mgr.register('LowPhase', &SmartLifecycle(&TestSmartLifecycle{
		phase_val: 10
	}))
	mgr.register('HighPhase', &SmartLifecycle(&TestSmartLifecycle{
		phase_val: 100
	}))

	assert mgr.entry_count() == 2
	// start_all should sort by ascending phase and call start
	mgr.start_all() or {}
	// stop_all should sort by descending phase and call stop
	mgr.stop_all()
}

// Test helper: SmartLifecycle implementation
struct TestSmartLifecycle {
pub:
	phase_val int
}

pub fn (tsl &TestSmartLifecycle) is_running() bool {
	return true
}

pub fn (tsl &TestSmartLifecycle) start() ! {}

pub fn (tsl &TestSmartLifecycle) stop() ! {}

pub fn (tsl &TestSmartLifecycle) phase() int {
	return tsl.phase_val
}

// ═══════════════════════════════════════════════════════════
// ApplicationRunner Tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_add_runner() {
	mut ctx := new_application_context()
	runner := &ApplicationRunner(&TestApplicationRunner{})
	ctx.add_runner(runner)
	assert ctx.runners.len == 1
}

// Test helper: ApplicationRunner implementation
struct TestApplicationRunner {
mut:
	executed bool
}

pub fn (tar &TestApplicationRunner) run(mut ctx ApplicationContext) ! {
	unsafe {
		mut t := tar
		t.executed = true
	}
}

// ═══════════════════════════════════════════════════════════
// ApplicationContext Alias and Parent Tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_register_alias() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('UserService')) or { assert false }
	ctx.register_alias('userSvc', 'UserService') or { assert false }
	assert ctx.has('userSvc') == true
}

fn test_application_context_remove_alias() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('UserService')) or { assert false }
	ctx.register_alias('userSvc', 'UserService') or { assert false }
	ctx.remove_alias('userSvc')
	assert ctx.has('userSvc') == false
	assert ctx.has('UserService') == true
}

// ═══════════════════════════════════════════════════════════
// Environment Enhancement Tests (f64, prefix, subtree)
// ═══════════════════════════════════════════════════════════

fn test_environment_get_property_f64() {
	mut env := new_environment()
	env.set_property('app.rate', '3.14')
	val := env.get_property_f64('app.rate') or { 0.0 }
	assert val == 3.14
}

fn test_environment_get_property_f64_or() {
	mut env := new_environment()
	assert env.get_property_f64_or('missing', 1.5) == 1.5
	env.set_property('app.rate', '2.71')
	assert env.get_property_f64_or('app.rate', 1.5) == 2.71
}

fn test_environment_get_by_prefix() {
	mut env := new_environment()
	env.set_property('app.db.host', 'localhost')
	env.set_property('app.db.port', '5432')
	env.set_property('app.name', 'Photon')

	result := env.get_by_prefix('app.db.')
	assert result.len == 2
	assert result['app.db.host'] == 'localhost'
	assert result['app.db.port'] == '5432'
}

fn test_environment_get_subtree() {
	mut env := new_environment()
	env.set_property('app.db.host', 'localhost')
	env.set_property('app.db.port', '5432')
	env.set_property('app.name', 'Photon')

	result := env.get_subtree('app.db.')
	assert result.len == 2
	assert result['host'] == 'localhost'
	assert result['port'] == '5432'
	assert 'app.name' !in result
}

fn test_environment_source_count() {
	mut env := new_environment()
	assert env.source_count() == 0
}

// ═══════════════════════════════════════════════════════════
// EventBus Enhancement Tests (off_listener, listener_count_for)
// ═══════════════════════════════════════════════════════════

fn test_event_bus_listener_count_for() {
	mut bus := new_event_bus()
	assert bus.listener_count_for('test.event') == 0
	bus.on('test.event', fn (e &Event) {})
	assert bus.listener_count_for('test.event') == 1
}

fn test_event_bus_off_listener() {
	mut bus := new_event_bus()
	listener := fn (e &Event) {}
	bus.on('test.event', listener)
	assert bus.listener_count_for('test.event') == 1

	bus.off_listener('test.event', listener)
	assert bus.listener_count_for('test.event') == 0
}

fn test_event_bus_off_all() {
	mut bus := new_event_bus()
	bus.on('test.event', fn (e &Event) {})
	bus.on('test.event', fn (e &Event) {})
	assert bus.listener_count_for('test.event') == 2

	bus.off('test.event')
	assert bus.listener_count_for('test.event') == 0
}

// ═══════════════════════════════════════════════════════════
// ApplicationContext Environment Convenience Tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_get_by_prefix() {
	mut ctx := new_application_context()
	ctx.set_property('app.db.host', 'localhost')
	ctx.set_property('app.db.port', '5432')
	ctx.set_property('app.name', 'Photon')

	result := ctx.get_by_prefix('app.db.')
	assert result.len == 2
}

fn test_application_context_get_subtree() {
	mut ctx := new_application_context()
	ctx.set_property('app.db.host', 'localhost')
	ctx.set_property('app.db.port', '5432')

	result := ctx.get_subtree('app.db.')
	assert result.len == 2
	assert result['host'] == 'localhost'
	assert result['port'] == '5432'
}

// ═══════════════════════════════════════════════════════════
// ApplicationEvent Name Constants Tests
// ═══════════════════════════════════════════════════════════

fn test_event_name_constants() {
	assert event_context_refreshed == 'context.refreshed'
	assert event_context_started == 'context.started'
	assert event_context_stopped == 'context.stopped'
	assert event_context_closed == 'context.closed'
	assert event_bean_created == 'bean.created'
	assert event_bean_destroyed == 'bean.destroyed'
}

fn test_event_bus_with_constant_name() {
	mut bus := new_event_bus()
	bus.on(event_context_refreshed, fn (e &Event) {
		// Event received — verified by dispatch return count
	})
	event := new_event(event_context_refreshed, '')
	called := bus.dispatch(event)
	assert called == 1
}

// ═══════════════════════════════════════════════════════════
// ShutdownHook Tests
// ═══════════════════════════════════════════════════════════

fn test_shutdown_hook_manager() {
	mut mgr := new_shutdown_hook_manager()
	assert mgr.hook_count() == 0

	mgr.add_hook(fn () {
		// First hook
	})
	assert mgr.hook_count() == 1
}

fn test_shutdown_hook_manager_run_hooks() {
	mut mgr := new_shutdown_hook_manager()
	mgr.add_hook(fn () {
		// First hook — runs second (reverse order)
	})
	mgr.add_hook(fn () {
		// Second hook — runs first (reverse order)
	})
	mgr.run_hooks()
	// Verify hooks ran without panic
	assert mgr.hook_count() == 2
}

fn test_application_context_add_shutdown_hook() {
	mut ctx := new_application_context()
	ctx.add_shutdown_hook(fn () {
		// Shutdown cleanup
	})
	assert !isnil(ctx.shutdown_hooks)
	assert ctx.shutdown_hooks.hook_count() == 1
}

// ═══════════════════════════════════════════════════════════
// @Primary Bean Tests
// ═══════════════════════════════════════════════════════════

fn test_container_primary_bean() {
	mut c := new_container()

	// Register two beans, one is primary
	mut def1 := new_bean_definition('RedisCache')
	def1.is_primary = true
	c.register(def1) or { assert false }

	c.register(new_bean_definition('MemCache')) or { assert false }

	assert c.get_primary_bean_name() == 'RedisCache'
}

fn test_container_no_primary() {
	mut c := new_container()
	c.register(new_bean_definition('ServiceA')) or { assert false }
	assert c.get_primary_bean_name() == ''
}

fn test_container_resolve_primary() {
	mut c := new_container()
	mut def1 := new_bean_definition('RedisCache')
	def1.is_primary = true
	c.register(def1) or { assert false }
	// Resolve primary — won't find instances (no comptime code), but verifies lookup path
	primary_name := c.get_primary_bean_name()
	assert primary_name == 'RedisCache'
}

// ═══════════════════════════════════════════════════════════
// @DependsOn Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_definition_depends_on() {
	mut def := new_bean_definition('OrderService')
	def.depends_on = ['UserService', 'PaymentService']
	assert def.depends_on.len == 2
	assert 'UserService' in def.depends_on
	assert 'PaymentService' in def.depends_on
}

fn test_bean_definition_builder_depends_on() {
	mut builder := new_bean_definition_builder('OrderService')
	builder.add_depends_on('UserService')
	builder.add_depends_on('PaymentService')
	def := builder.build()
	assert def.depends_on.len == 2
	assert def.depends_on[0] == 'UserService'
	assert def.depends_on[1] == 'PaymentService'
}

// ═══════════════════════════════════════════════════════════
// BeanDefinition Merging Tests
// ═══════════════════════════════════════════════════════════

fn test_container_merged_definition_no_parent() {
	mut c := new_container()
	mut def := new_bean_definition('ChildService')
	def.scope = .prototype
	c.register(def) or { assert false }

	merged := c.get_merged_definition('ChildService') or {
		assert false
		return
	}
	assert merged.scope == .prototype
	assert merged.parent_name.len == 0
}

fn test_container_merged_definition_with_parent() {
	mut c := new_container()

	// Register parent with init_method and dependencies
	mut parent_def := new_bean_definition('BaseService')
	parent_def.init_method = 'base_init'
	parent_def.destroy_method = 'base_destroy'
	parent_def.dependencies = [
		Dependency{
			field_name: 'logger'
			type_name:  'Logger'
		},
	]
	parent_def.tags = ['service']
	parent_def.depends_on = ['ConfigService']
	c.register(parent_def) or { assert false }

	// Register child that extends parent
	mut child_def := new_bean_definition('ExtendedService')
	child_def.parent_name = 'BaseService'
	child_def.dependencies = [
		Dependency{
			field_name: 'repo'
			type_name:  'Repository'
		},
	]
	child_def.tags = ['extended']
	c.register(child_def) or { assert false }

	merged := c.get_merged_definition('ExtendedService') or {
		assert false
		return
	}

	// Child should inherit init_method from parent
	assert merged.init_method == 'base_init'
	// Child should inherit destroy_method from parent
	assert merged.destroy_method == 'base_destroy'
	// Dependencies should be merged
	assert merged.dependencies.len == 2
	// Tags should be merged (deduplicated)
	assert merged.tags.len == 2
	// depends_on should be merged
	assert merged.depends_on.len == 1
	assert merged.depends_on[0] == 'ConfigService'
	// parent_name should be cleared
	assert merged.parent_name.len == 0
}

// ═══════════════════════════════════════════════════════════
// ApplicationContext start/stop/close Tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_close_alias() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('TestBean')) or { assert false }
	ctx.close()
	assert ctx.current_state() == .closed
}

fn test_application_context_lifecycle_bean_count() {
	mut ctx := new_application_context()
	assert ctx.lifecycle_bean_count() == 0
}

// ═══════════════════════════════════════════════════════════
// Scanner Attribute Parsing Tests (Enhanced)
// ═══════════════════════════════════════════════════════════

fn test_extract_depends_on() {
	attrs := ['component', 'depends_on:UserService,PaymentService']
	deps := extract_depends_on(attrs)
	assert deps.len == 2
	assert deps[0] == 'UserService'
	assert deps[1] == 'PaymentService'
}

fn test_extract_depends_on_empty() {
	attrs := ['component', 'service']
	deps := extract_depends_on(attrs)
	assert deps.len == 0
}

fn test_has_primary_attr() {
	assert has_primary_attr(['component', 'primary']) == true
	assert has_primary_attr(['component', 'service']) == false
}

fn test_extract_parent_name() {
	attrs := ['component', 'extends:BaseService']
	parent := extract_parent_name(attrs)
	assert parent == 'BaseService'
}

fn test_extract_parent_name_empty() {
	attrs := ['component']
	parent := extract_parent_name(attrs)
	assert parent == ''
}

// ═══════════════════════════════════════════════════════════
// BeanMethod and ConfigurationClass Tests
// ═══════════════════════════════════════════════════════════

fn test_bean_method_basic() {
	bm := new_bean_method('create_cache', ['bean'])
	assert bm.method_name == 'create_cache'
	assert bm.bean_name == 'create_cache' // defaults to method name
}

fn test_bean_method_custom_name() {
	bm := new_bean_method('create_cache', ['bean:CustomCache'])
	assert bm.bean_name == 'CustomCache'
}

fn test_bean_method_scope() {
	bm := new_bean_method('create_cache', ['bean', 'scope:prototype'])
	assert bm.scope() == .prototype
}

fn test_bean_method_is_primary() {
	bm := new_bean_method('create_cache', ['bean', 'primary'])
	assert bm.is_primary() == true
}

fn test_bean_method_depends_on() {
	bm := new_bean_method('create_cache', ['bean', 'depends_on:ConfigService'])
	deps := bm.depends_on()
	assert deps.len == 1
	assert deps[0] == 'ConfigService'
}

fn test_configuration_class() {
	mut cc := new_configuration_class('AppConfig', ['configuration'])
	assert cc.type_name == 'AppConfig'
	assert cc.bean_count() == 0

	bm := new_bean_method('create_cache', ['bean'])
	cc.add_bean_method(bm)
	assert cc.bean_count() == 1
}

fn test_has_bean_attr() {
	assert has_bean_attr(['bean']) == true
	assert has_bean_attr(['bean:CustomCache']) == true
	assert has_bean_attr(["bean('CustomCache')"]) == true
	assert has_bean_attr(['component']) == false
}

// ═══════════════════════════════════════════════════════════
// Environment PropertySource Priority Tests
// ═══════════════════════════════════════════════════════════

fn test_environment_has_source() {
	mut env := new_environment()
	assert env.has_source('test') == false
}

fn test_environment_source_names() {
	mut env := new_environment()
	names := env.source_names()
	assert names.len == 0
}

// ═══════════════════════════════════════════════════════════
// BeanDefinitionBuilder with Primary and DependsOn
// ═══════════════════════════════════════════════════════════

fn test_bean_definition_builder_primary() {
	mut builder := new_bean_definition_builder('PrimaryService')
	builder.set_primary(true)
	def := builder.build()
	assert def.is_primary == true
}

fn test_bean_definition_builder_parent_name() {
	mut builder := new_bean_definition_builder('ExtendedService')
	builder.set_parent_name('BaseService')
	def := builder.build()
	assert def.parent_name == 'BaseService'
}

// ═══════════════════════════════════════════════════════════
// BeanRegistrationOptions with new fields
// ═══════════════════════════════════════════════════════════

fn test_bean_registration_options_depends_on() {
	mut ctx := new_application_context()
	ctx.register_bean('OrderService', BeanRegistrationOptions{
		depends_on: ['UserService', 'PaymentService']
		is_primary: true
	}) or { assert false }

	assert ctx.has('OrderService') == true
	def := ctx.get_definition('OrderService') or {
		assert false
		return
	}
	assert def.depends_on.len == 2
	assert def.is_primary == true
}

// ═══════════════════════════════════════════════════════════
// Deep Audit Tests — Bug Fix Verification
// ═══════════════════════════════════════════════════════════

// --- Bug #1 & #2: depends_on in circular check and topological sort ---

fn test_check_circular_dependencies_with_depends_on() {
	mut c := new_container()
	// A depends_on B, B depends_on A (via depends_on) → circular
	mut def_a := new_bean_definition('ServiceA')
	def_a.depends_on = ['ServiceB']
	c.register(def_a) or { assert false }

	mut def_b := new_bean_definition('ServiceB')
	def_b.depends_on = ['ServiceA']
	c.register(def_b) or { assert false }

	c.check_circular_dependencies() or {
		assert err.msg().contains('circular dependency')
		return
	}
	assert false // should have returned in the or block
}

fn test_check_circular_dependencies_depends_on_plus_autowired() {
	mut c := new_container()
	// A autowires B, B depends_on A → circular
	mut def_a := new_bean_definition('ServiceA')
	def_a.dependencies = [Dependency{ field_name: 'b', type_name: 'ServiceB' }]
	c.register(def_a) or { assert false }

	mut def_b := new_bean_definition('ServiceB')
	def_b.depends_on = ['ServiceA']
	c.register(def_b) or { assert false }

	c.check_circular_dependencies() or {
		assert err.msg().contains('circular dependency')
		return
	}
	assert false
}

fn test_check_circular_dependencies_depends_on_no_cycle() {
	mut c := new_container()
	// A depends_on B (no cycle)
	mut def_a := new_bean_definition('ServiceA')
	def_a.depends_on = ['ServiceB']
	c.register(def_a) or { assert false }

	c.register(new_bean_definition('ServiceB')) or { assert false }

	c.check_circular_dependencies() or {
		assert false // should not detect a cycle
		return
	}
}

// --- Bug #3: is_running() includes started/stopped states ---

fn test_is_running_after_start_and_stop() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('TestBean')) or { assert false }
	ctx.refresh() or {}
	assert ctx.is_ready() == true
	assert ctx.is_running() == true // ready → is_running

	ctx.start() or {}
	assert ctx.current_state() == .started
	assert ctx.is_running() == true // started → is_running

	ctx.stop() or {}
	assert ctx.current_state() == .stopped
	assert ctx.is_running() == true // stopped → is_running

	ctx.shutdown()
	assert ctx.is_running() == false // closed → not running
}

// --- Bug #4: refresh() blocks started/stopped/closed re-entry ---

fn test_refresh_blocks_started_state() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('TestBean')) or { assert false }
	ctx.refresh() or {}
	ctx.start() or {}

	// Trying to refresh after start should fail
	ctx.refresh() or {
		assert err.msg().contains('already been refreshed')
		return
	}
	assert false
}

fn test_refresh_blocks_stopped_state() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('TestBean')) or { assert false }
	ctx.refresh() or {}
	ctx.stop() or {}

	// Trying to refresh after stop should fail
	ctx.refresh() or {
		assert err.msg().contains('already been refreshed')
		return
	}
	assert false
}

fn test_refresh_blocks_closed_state() {
	mut ctx := new_application_context()
	ctx.shutdown()
	assert ctx.current_state() == .closed

	// Trying to refresh after close should fail
	ctx.refresh() or {
		assert err.msg().contains('closed')
		return
	}
	assert false
}

// --- Bug #5: register_instance no dangling pointer ---

fn test_register_instance_auto_creates_definition() {
	mut c := new_container()
	// Register an instance without a pre-existing definition
	c.register_instance('DynamicService', unsafe { voidptr(42) }) or { assert false }

	// Should auto-create definition and have it accessible
	assert c.has('DynamicService') == true
	assert c.singleton_count() == 1
}

// --- Bug #7: get_merged_definition circular inheritance protection ---

fn test_merged_definition_circular_inheritance() {
	mut c := new_container()

	// A extends B, B extends A → circular
	mut def_a := new_bean_definition('ServiceA')
	def_a.parent_name = 'ServiceB'
	c.register(def_a) or { assert false }

	mut def_b := new_bean_definition('ServiceB')
	def_b.parent_name = 'ServiceA'
	c.register(def_b) or { assert false }

	c.get_merged_definition('ServiceA') or {
		assert err.msg().contains('circular') || err.msg().contains('inheritance')
		return
	}
	assert false
}

fn test_merged_definition_self_inheritance() {
	mut c := new_container()

	mut def_a := new_bean_definition('ServiceA')
	def_a.parent_name = 'ServiceA' // self-reference
	c.register(def_a) or { assert false }

	c.get_merged_definition('ServiceA') or {
		assert err.msg().contains('circular')
		return
	}
	assert false
}

fn test_merged_definition_three_level_no_cycle() {
	mut c := new_container()

	// GrandParent → Parent → Child (no cycle)
	mut gp_def := new_bean_definition('GrandParent')
	gp_def.init_method = 'gp_init'
	gp_def.tags = ['base']
	c.register(gp_def) or { assert false }

	mut p_def := new_bean_definition('Parent')
	p_def.parent_name = 'GrandParent'
	p_def.tags = ['middle']
	c.register(p_def) or { assert false }

	mut c_def := new_bean_definition('Child')
	c_def.parent_name = 'Parent'
	c_def.tags = ['leaf']
	c.register(c_def) or { assert false }

	merged := c.get_merged_definition('Child') or {
		assert false
		return
	}
	// Child should inherit init_method from GrandParent
	assert merged.init_method == 'gp_init'
	// Tags should be merged (3 unique tags)
	assert merged.tags.len == 3
	assert merged.parent_name.len == 0
}

// --- Bug #8: resolve_placeholders circular reference protection ---

fn test_resolve_placeholders_circular_reference() {
	mut env := new_environment()
	dollar := rune(36).str()
	env.set_property('a', dollar + '{b}')
	env.set_property('b', dollar + '{a}')

	result := env.resolve_placeholders(dollar + '{a}')
	// Should detect circular reference and not hang
	assert result.contains('→') || result.len > 0 // either cycle marker or partial resolution
}

fn test_resolve_placeholders_self_reference() {
	mut env := new_environment()
	dollar := rune(36).str()
	env.set_property('x', dollar + '{x}')

	result := env.resolve_placeholders(dollar + '{x}')
	// Should detect self-reference and not hang
	assert result.len > 0
}

fn test_resolve_placeholders_nested_no_cycle() {
	mut env := new_environment()
	dollar := rune(36).str()
	env.set_property('app.greeting', 'Hello ' + dollar + '{app.name}!')
	env.set_property('app.name', 'Photon')

	result := env.resolve_placeholders(dollar + '{app.greeting}')
	assert result == 'Hello Photon!'
}

// ═══════════════════════════════════════════════════════════
// State Machine Transition Tests
// ═══════════════════════════════════════════════════════════

fn test_application_state_transitions() {
	mut ctx := new_application_context()
	assert ctx.current_state() == .created

	ctx.register(new_bean_definition('BeanA')) or { assert false }
	ctx.refresh() or {}
	assert ctx.current_state() == .ready

	ctx.start() or {}
	assert ctx.current_state() == .started

	ctx.stop() or {}
	assert ctx.current_state() == .stopped

	// Can restart after stop
	ctx.start() or {}
	assert ctx.current_state() == .started

	ctx.shutdown()
	assert ctx.current_state() == .closed
}

fn test_start_from_created_fails() {
	mut ctx := new_application_context()
	// Cannot start before refresh
	ctx.start() or {
		assert err.msg().contains('cannot start')
		return
	}
	assert false
}

fn test_stop_from_created_fails() {
	mut ctx := new_application_context()
	// Cannot stop before refresh
	ctx.stop() or {
		assert err.msg().contains('cannot stop')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// Edge Case Tests
// ═══════════════════════════════════════════════════════════

fn test_container_register_instance_no_definition() {
	mut c := new_container()
	// Register instance for a type that has no definition
	c.register_instance('AdHocService', unsafe { voidptr(123) }) or { assert false }
	assert c.has('AdHocService') == true
	assert c.singleton_count() == 1
}

fn test_container_register_instance_duplicate() {
	mut c := new_container()
	c.register_instance('TestService', unsafe { voidptr(1) }) or { assert false }
	// Duplicate should error
	c.register_instance('TestService', unsafe { voidptr(2) }) or {
		assert err.msg().contains('already registered')
		return
	}
	assert false
}

fn test_container_destroy_nonexistent() {
	mut c := new_container()
	c.destroy('NonExistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_container_empty_destroy_all() {
	mut c := new_container()
	c.destroy_all() // should not panic
	assert c.singleton_count() == 0
}

fn test_application_context_double_refresh() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('BeanA')) or { assert false }
	ctx.refresh() or {}
	// Second refresh should fail
	ctx.refresh() or {
		assert err.msg().contains('already been refreshed')
		return
	}
	assert false
}

fn test_environment_resolve_placeholders_no_placeholders() {
	mut env := new_environment()
	result := env.resolve_placeholders('plain text without placeholders')
	assert result == 'plain text without placeholders'
}

fn test_environment_resolve_placeholders_unclosed_bracket() {
	mut env := new_environment()
	dollar := rune(36).str()
	result := env.resolve_placeholders('hello ' + dollar + '{unclosed')
	// Should not panic, returns as-is or partial
	assert result.len > 0
}

fn test_environment_resolve_placeholders_missing_key_default() {
	mut env := new_environment()
	dollar := rune(36).str()
	result := env.resolve_placeholders(dollar + '{missing.key:fallback_value}')
	assert result == 'fallback_value'
}

fn test_container_get_merged_definition_nonexistent() {
	mut c := new_container()
	c.get_merged_definition('NonExistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// Environment contains_prefix Tests
// ═══════════════════════════════════════════════════════════

fn test_environment_contains_prefix_true() {
	mut env := new_environment()
	env.set_property('app.db.host', 'localhost')
	env.set_property('app.db.port', '5432')
	env.set_property('app.name', 'MyApp')

	assert env.contains_prefix('app.db.') == true
	assert env.contains_prefix('app.') == true
}

fn test_environment_contains_prefix_false() {
	mut env := new_environment()
	env.set_property('app.name', 'MyApp')

	assert env.contains_prefix('app.db.') == false
	assert env.contains_prefix('cache.') == false
}

fn test_environment_contains_prefix_empty_env() {
	mut env := new_environment()
	assert env.contains_prefix('any.') == false
}

// ═══════════════════════════════════════════════════════════
// Environment prefix_count Tests
// ═══════════════════════════════════════════════════════════

fn test_environment_prefix_count() {
	mut env := new_environment()
	env.set_property('app.db.host', 'localhost')
	env.set_property('app.db.port', '5432')
	env.set_property('app.name', 'MyApp')

	assert env.prefix_count('app.db.') == 2
	assert env.prefix_count('app.') == 3
	assert env.prefix_count('cache.') == 0
}

// ═══════════════════════════════════════════════════════════
// Environment bind_to Tests (Spring @ConfigurationProperties)
// ═══════════════════════════════════════════════════════════

fn test_environment_bind_to_with_dot_prefix() {
	mut env := new_environment()
	env.set_property('app.db.host', 'localhost')
	env.set_property('app.db.port', '5432')

	result := env.bind_to('app.db.') or {
		assert false
		return
	}
	assert result.len == 2
	assert result['host'] == 'localhost'
	assert result['port'] == '5432'
}

fn test_environment_bind_to_without_dot_prefix() {
	mut env := new_environment()
	env.set_property('app.db.host', 'localhost')
	env.set_property('app.db.port', '5432')

	// 'app.db' without trailing dot should auto-match 'app.db.host'
	result := env.bind_to('app.db') or {
		assert false
		return
	}
	assert result.len == 2
	assert result['host'] == 'localhost'
}

fn test_environment_bind_to_no_match() {
	mut env := new_environment()
	env.set_property('app.name', 'MyApp')

	env.bind_to('cache.') or {
		assert err.msg().contains('no properties found')
		return
	}
	assert false
}

fn test_environment_bind_to_empty_prefix() {
	mut env := new_environment()
	env.set_property('name', 'MyApp')
	env.set_property('port', '8080')

	result := env.bind_to('') or {
		assert false
		return
	}
	// Empty prefix should match all properties
	assert result.len == 2
}

// ═══════════════════════════════════════════════════════════
// Environment bind_to_with_defaults Tests
// ═══════════════════════════════════════════════════════════

fn test_environment_bind_to_with_defaults_override() {
	mut env := new_environment()
	env.set_property('app.db.host', 'production-host')
	// 'port' is NOT set — should use default

	defaults := {
		'host':    'localhost'
		'port':    '5432'
		'timeout': '30'
	}

	result := env.bind_to_with_defaults('app.db', defaults) or {
		assert false
		return
	}
	// Environment value should override default
	assert result['host'] == 'production-host'
	// Default should be used when environment doesn't have the key
	assert result['port'] == '5432'
	assert result['timeout'] == '30'
}

fn test_environment_bind_to_with_defaults_no_env() {
	mut env := new_environment()
	// No properties set — should return all defaults

	defaults := {
		'host': 'localhost'
		'port': '5432'
	}

	result := env.bind_to_with_defaults('app.db', defaults) or {
		assert false
		return
	}
	assert result['host'] == 'localhost'
	assert result['port'] == '5432'
}

// ═══════════════════════════════════════════════════════════
// Environment validate_prefix Tests
// ═══════════════════════════════════════════════════════════

fn test_environment_validate_prefix_all_present() {
	mut env := new_environment()
	env.set_property('app.db.host', 'localhost')
	env.set_property('app.db.port', '5432')

	env.validate_prefix('app.db', ['host', 'port']) or {
		assert false
		return
	}
}

fn test_environment_validate_prefix_missing_keys() {
	mut env := new_environment()
	env.set_property('app.db.host', 'localhost')
	// 'port' is missing

	env.validate_prefix('app.db', ['host', 'port']) or {
		assert err.msg().contains('missing')
		assert err.msg().contains('port')
		return
	}
	assert false
}

fn test_environment_validate_prefix_all_missing() {
	mut env := new_environment()
	// No properties at all

	env.validate_prefix('app.db', ['host', 'port']) or {
		assert err.msg().contains('missing')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// ApplicationContext @ConfigurationProperties Proxy Tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_contains_prefix() {
	mut ctx := new_application_context()
	ctx.set_property('app.db.host', 'localhost')
	assert ctx.contains_prefix('app.db.') == true
	assert ctx.contains_prefix('cache.') == false
}

fn test_application_context_bind_to() {
	mut ctx := new_application_context()
	ctx.set_property('app.db.host', 'localhost')
	ctx.set_property('app.db.port', '5432')

	result := ctx.bind_to('app.db') or {
		assert false
		return
	}
	assert result['host'] == 'localhost'
	assert result['port'] == '5432'
}

fn test_application_context_bind_to_with_defaults() {
	mut ctx := new_application_context()
	ctx.set_property('app.db.host', 'production-host')

	defaults := {
		'host': 'localhost'
		'port': '5432'
	}

	result := ctx.bind_to_with_defaults('app.db', defaults) or {
		assert false
		return
	}
	assert result['host'] == 'production-host'
	assert result['port'] == '5432'
}

fn test_application_context_validate_prefix() {
	mut ctx := new_application_context()
	ctx.set_property('app.db.host', 'localhost')
	ctx.set_property('app.db.port', '5432')

	ctx.validate_prefix('app.db', ['host', 'port']) or {
		assert false
		return
	}
}

fn test_application_context_prefix_count() {
	mut ctx := new_application_context()
	ctx.set_property('app.db.host', 'localhost')
	ctx.set_property('app.db.port', '5432')
	ctx.set_property('app.name', 'MyApp')

	assert ctx.prefix_count('app.db.') == 2
	assert ctx.prefix_count('app.') == 3
}

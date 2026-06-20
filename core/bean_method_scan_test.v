module core

// bean_method_scan_test.v - Tests for @[configuration] + @[bean] method scanning
// (Task A3: SubTasks A3.1–A3.3)
//
// Verifies that:
//   - extract_bean_methods[T]() discovers @[bean] methods in @[configuration] classes
//   - BeanMethod records carry correct method name, bean name, arg count, config class
//   - register_configuration[T]() registers BeanDefinitions for each @[bean] method
//   - register_bean_method_factory[T, R]() instantiates 0-arg @[bean] methods
//   - register_bean_method_with_dep[T, R, D]() instantiates 1-arg @[bean] methods
//     with the dependency auto-injected from the container
//   - Non-@[configuration] types are refused (contract enforcement)
//   - Methods without @[bean] are not scanned
//   - Multiple configuration classes register independently
//
// V comptime can only inspect types in the current compilation unit, so all
// test structs are defined in this file. The "auto" guarantee is that the
// comptime check refuses types lacking @[configuration] — no manual type_name
// strings, no runtime reflection.

// ═══════════════════════════════════════════════════════════
// Test Fixtures — bean types produced by @[bean] methods
// ═══════════════════════════════════════════════════════════

// TestDataSource is a 0-arg bean — produced by TestConfig.datasource().
struct TestDataSource {
	url string
}

// TestUserService is a 1-arg bean — produced by TestConfig.user_service(ds).
// It depends on TestDataSource, which is auto-injected by the container.
struct TestUserService {
	ds TestDataSource
	name string
}

// TestCache is a 0-arg bean from a second configuration class — used to
// verify multiple configurations register independently.
struct TestCache {
	ttl int
}

// ═══════════════════════════════════════════════════════════
// Test Fixtures — @[configuration] classes
// ═══════════════════════════════════════════════════════════

// TestConfig is the primary @[configuration] class for these tests.
// It has two @[bean] methods:
//   - datasource() → TestDataSource           (0 args)
//   - user_service(ds TestDataSource) → TestUserService  (1 arg, dependency)
@[configuration]
struct TestConfig {
	config_name string
}

@[bean]
fn (c TestConfig) datasource() TestDataSource {
	return TestDataSource{url: 'localhost:5432'}
}

@[bean]
fn (c TestConfig) user_service(ds TestDataSource) TestUserService {
	return TestUserService{ds: ds, name: 'primary'}
}

// helper_method is NOT annotated with @[bean] — must be skipped by the scanner.
fn (c TestConfig) helper_method() int {
	return 42
}

// AnotherConfig is a second @[configuration] class — used to verify that
// multiple configuration classes register independently.
@[configuration]
struct AnotherConfig {
	tag string
}

@[bean]
fn (c AnotherConfig) cache() TestCache {
	return TestCache{ttl: 300}
}

// PlainConfigNoAttr is NOT annotated with @[configuration] — used to verify
// that the comptime check refuses non-annotated types.
struct PlainConfigNoAttr {
	x int
}

@[bean]
fn (c PlainConfigNoAttr) should_not_register() TestDataSource {
	return TestDataSource{url: 'unreachable'}
}

// ═══════════════════════════════════════════════════════════
// SubTask A3.1 — extract_bean_methods[T]() comptime scanning
// ═══════════════════════════════════════════════════════════

fn test_extract_bean_methods_returns_correct_count() {
	// TestConfig has exactly two @[bean] methods: datasource, user_service.
	// helper_method is NOT annotated and must be excluded.
	methods := extract_bean_methods[TestConfig]()
	assert methods.len == 2
}

fn test_extract_bean_methods_returns_correct_method_names() {
	methods := extract_bean_methods[TestConfig]()

	mut names := []string{}
	for m in methods {
		names << m.method_name
	}
	assert 'datasource' in names
	assert 'user_service' in names
}

fn test_extract_bean_methods_returns_correct_bean_names() {
	// By default, bean_name == method_name (no @[bean('CustomName')] used).
	methods := extract_bean_methods[TestConfig]()

	mut bean_names := []string{}
	for m in methods {
		bean_names << m.bean_name
	}
	assert 'datasource' in bean_names
	assert 'user_service' in bean_names
}

fn test_extract_bean_methods_records_arg_count() {
	// datasource() has 0 args; user_service(ds) has 1 arg.
	methods := extract_bean_methods[TestConfig]()

	for m in methods {
		match m.method_name {
			'datasource' { assert m.arg_count == 0 }
			'user_service' { assert m.arg_count == 1 }
			else { assert false } // unexpected method
		}
	}
}

fn test_extract_bean_methods_records_config_class() {
	// The config_class field should carry the fully-qualified type name.
	methods := extract_bean_methods[TestConfig]()
	assert methods.len > 0
	for m in methods {
		assert m.config_class == 'core.TestConfig'
	}
}

fn test_extract_bean_methods_skips_non_bean_methods() {
	// helper_method() is NOT annotated with @[bean] — must not appear.
	methods := extract_bean_methods[TestConfig]()
	for m in methods {
		assert m.method_name != 'helper_method'
	}
}

fn test_extract_configuration_detects_annotated_struct() {
	assert extract_configuration[TestConfig]() == true
	assert extract_configuration[AnotherConfig]() == true
}

fn test_extract_configuration_rejects_plain_struct() {
	// PlainConfigNoAttr has no @[configuration] attribute.
	assert extract_configuration[PlainConfigNoAttr]() == false
}

fn test_configuration_type_name_returns_fully_qualified_name() {
	assert configuration_type_name[TestConfig]() == 'core.TestConfig'
}

// ═══════════════════════════════════════════════════════════
// SubTask A3.2 — register_bean_methods / register_configuration
// ═══════════════════════════════════════════════════════════

fn test_register_configuration_registers_bean_definitions() {
	mut ctx := new_application_context()

	methods := ctx.register_configuration[TestConfig]()!

	// Should return the two @[bean] methods discovered.
	assert methods.len == 2

	// Both bean definitions should be registered in the container.
	assert ctx.has('datasource') == true
	assert ctx.has('user_service') == true
}

fn test_register_configuration_refuses_non_annotated_type() {
	mut ctx := new_application_context()

	// PlainConfigNoAttr lacks @[configuration] → must return an error.
	ctx.register_configuration[PlainConfigNoAttr]() or {
		assert err.msg().contains('configuration') == true
		assert err.msg().contains('PlainConfigNoAttr') == true
		return
	}
	assert false
}

fn test_register_bean_methods_returns_method_descriptors() {
	mut ctx := new_application_context()

	methods := ctx.auto_config_manager.register_bean_methods[TestConfig](mut ctx)!

	assert methods.len == 2
	mut has_datasource := false
	mut has_user_service := false
	for m in methods {
		if m.method_name == 'datasource' {
			has_datasource = true
		}
		if m.method_name == 'user_service' {
			has_user_service = true
		}
	}
	assert has_datasource == true
	assert has_user_service == true
}

// ═══════════════════════════════════════════════════════════
// SubTask A3.3 — Bean method instantiation + dependency injection
// ═══════════════════════════════════════════════════════════

fn test_register_bean_method_factory_instantiates_zero_arg_bean() {
	mut ctx := new_application_context()

	// Register the definition first (metadata), then instantiate.
	ctx.register_configuration[TestConfig]()!
	ctx.register_bean_method_factory[TestConfig, TestDataSource]()!

	// The bean should be resolvable by bean name.
	assert ctx.has('datasource') == true

	// Resolve and verify the instance is a TestDataSource with the expected URL.
	ds := ctx.resolve_typed[TestDataSource]('datasource')!
	assert ds.url == 'localhost:5432'
}

fn test_register_bean_method_with_dep_injects_dependency() {
	mut ctx := new_application_context()

	// Step 1: register definitions for all @[bean] methods.
	ctx.register_configuration[TestConfig]()!

	// Step 2: instantiate the 0-arg bean (datasource) first.
	// This registers an instance under 'datasource' and an alias from
	// 'core.TestDataSource' to 'datasource'.
	ctx.register_bean_method_factory[TestConfig, TestDataSource]()!

	// Step 3: instantiate the 1-arg bean (user_service), which depends on
	// TestDataSource. The container resolves the dependency by type name
	// (D.name = 'core.TestDataSource') via the alias registered in step 2.
	ctx.register_bean_method_with_dep[TestConfig, TestUserService, TestDataSource]()!

	// The user_service bean should be resolvable.
	assert ctx.has('user_service') == true

	// Resolve and verify the datasource was injected.
	us := ctx.resolve_typed[TestUserService]('user_service')!
	assert us.name == 'primary'
	assert us.ds.url == 'localhost:5432'
}

fn test_register_bean_method_with_dep_fails_when_dependency_missing() {
	mut ctx := new_application_context()

	ctx.register_configuration[TestConfig]()!

	// Attempt to instantiate user_service WITHOUT first registering datasource.
	// The dependency resolution must fail with a clear bilingual error.
	ctx.register_bean_method_with_dep[TestConfig, TestUserService, TestDataSource]() or {
		assert err.msg().contains('TestDataSource') == true
		return
	}
	assert false
}

fn test_bean_resolvable_by_type_name_via_alias() {
	mut ctx := new_application_context()

	ctx.register_configuration[TestConfig]()!
	ctx.register_bean_method_factory[TestConfig, TestDataSource]()!

	// The alias from R.name ('core.TestDataSource') to bean name ('datasource')
	// allows resolution by fully-qualified type name as well.
	ds := ctx.resolve_typed[TestDataSource]('core.TestDataSource')!
	assert ds.url == 'localhost:5432'
}

// ═══════════════════════════════════════════════════════════
// Multiple Configuration Classes — independent registration
// ═══════════════════════════════════════════════════════════

fn test_multiple_config_classes_register_independently() {
	mut ctx := new_application_context()

	// Register and instantiate beans from TestConfig.
	ctx.register_configuration[TestConfig]()!
	ctx.register_bean_method_factory[TestConfig, TestDataSource]()!
	ctx.register_bean_method_with_dep[TestConfig, TestUserService, TestDataSource]()!

	// Register and instantiate beans from AnotherConfig.
	ctx.register_configuration[AnotherConfig]()!
	ctx.register_bean_method_factory[AnotherConfig, TestCache]()!

	// All beans from both configurations should be present.
	assert ctx.has('datasource') == true
	assert ctx.has('user_service') == true
	assert ctx.has('cache') == true

	// Verify the cache bean from AnotherConfig.
	cache := ctx.resolve_typed[TestCache]('cache')!
	assert cache.ttl == 300

	// Verify the datasource bean from TestConfig is unaffected.
	ds := ctx.resolve_typed[TestDataSource]('datasource')!
	assert ds.url == 'localhost:5432'
}

fn test_extract_bean_methods_on_second_config_class() {
	// AnotherConfig has exactly one @[bean] method: cache.
	methods := extract_bean_methods[AnotherConfig]()
	assert methods.len == 1
	assert methods[0].method_name == 'cache'
	assert methods[0].arg_count == 0
	assert methods[0].config_class == 'core.AnotherConfig'
}

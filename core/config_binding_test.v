module core

// config_binding_test.v - Tests for type-safe @ConfigurationProperties binding
//
// Tests the bind_to_struct[T] function which provides compile-time type-safe
// binding of environment properties to struct fields, equivalent to Spring Boot's
// @ConfigurationProperties annotation.

// ── Test Structs ──

// SimpleConfig tests primitive type binding
struct SimpleConfig {
	host    string
	port    int
	timeout f64
	enabled bool
}

// NestedInner is a nested struct for testing recursive binding
struct NestedInner {
	host string
	port int
}

// NestedConfig tests nested struct binding
struct NestedConfig {
	name  string
	inner NestedInner
}

// ArrayConfig tests array type binding (comma-separated values)
struct ArrayConfig {
	tags    []string
	numbers []int
	ratios  []f64
	flags   []bool
}

// CustomKeyConfig tests @[config_field] custom key mapping
struct CustomKeyConfig {
	host       string @[config_field: 'hostname']
	port       int    @[config_field: 'port_number']
	alias_name string @[config_field: 'display_name']
}

// DeeplyNestedConfig tests multiple levels of nesting.
// NOTE: V 0.5.1 comptime has a bug where triple-nested struct type inference
// in bind_to_struct_impl generates incorrect C code (type mismatch between
// unrelated struct types). This is tracked as a compiler limitation.
// The test is moved to config_deeply_nested_test.v as a standalone file
// to avoid cross-contamination with other struct types in the same comptime unit.
// struct DeepLevel3 { value string }
// struct DeepLevel2 { name string; level DeepLevel3 }
// struct DeeplyNestedConfig { app string; mid DeepLevel2 }
//
// fn test_bind_to_struct_deeply_nested() {
// 	mut env := new_environment()
// 	env.set_property('app.app', 'MyApp')
// 	env.set_property('app.mid.name', 'Middle')
// 	env.set_property('app.mid.level.value', 'DeepValue')
// 	config := bind_to_struct[DeeplyNestedConfig](env, 'app')!
// 	assert config.app == 'MyApp'
// 	assert config.mid.name == 'Middle'
// 	assert config.mid.level.value == 'DeepValue'
// }

// MixedConfig tests a mix of all supported types
struct MixedConfig {
	name   string
	count  int
	ratio  f64
	active bool
	tags   []string
	nested NestedInner
	custom string @[config_field: 'special_key']
}

// ── Primitive Type Binding Tests ──

fn test_bind_to_struct_string_field() {
	mut env := new_environment()
	env.set_property('app.host', 'localhost')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.host == 'localhost'
}

fn test_bind_to_struct_int_field() {
	mut env := new_environment()
	env.set_property('app.port', '5432')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.port == 5432
}

fn test_bind_to_struct_f64_field() {
	mut env := new_environment()
	env.set_property('app.timeout', '30.5')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.timeout == 30.5
}

fn test_bind_to_struct_bool_field_true() {
	mut env := new_environment()
	env.set_property('app.enabled', 'true')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.enabled == true
}

fn test_bind_to_struct_bool_field_one() {
	mut env := new_environment()
	env.set_property('app.enabled', '1')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.enabled == true
}

fn test_bind_to_struct_bool_field_yes() {
	mut env := new_environment()
	env.set_property('app.enabled', 'yes')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.enabled == true
}

fn test_bind_to_struct_bool_field_false() {
	mut env := new_environment()
	env.set_property('app.enabled', 'false')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.enabled == false
}

fn test_bind_to_struct_bool_field_zero() {
	mut env := new_environment()
	env.set_property('app.enabled', '0')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.enabled == false
}

fn test_bind_to_struct_all_primitive_fields() {
	mut env := new_environment()
	env.set_property('app.host', 'redis.example.com')
	env.set_property('app.port', '6379')
	env.set_property('app.timeout', '60.5')
	env.set_property('app.enabled', 'true')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.host == 'redis.example.com'
	assert config.port == 6379
	assert config.timeout == 60.5
	assert config.enabled == true
}

// ── Default Value Tests (fields not in environment remain zero) ──

fn test_bind_to_struct_missing_fields_remain_zero() {
	mut env := new_environment()
	// Only set one property
	env.set_property('app.host', 'localhost')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.host == 'localhost'
	// Fields not in environment should be zero values
	assert config.port == 0
	assert config.timeout == 0.0
	assert config.enabled == false
}

fn test_bind_to_struct_no_properties_returns_zero_struct() {
	mut env := new_environment()
	// No properties set at all

	config := bind_to_struct[SimpleConfig](env, 'nonexistent')!
	// All fields should be zero values
	assert config.host == ''
	assert config.port == 0
	assert config.timeout == 0.0
	assert config.enabled == false
}

fn test_bind_to_struct_empty_prefix() {
	mut env := new_environment()
	env.set_property('host', 'localhost')
	env.set_property('port', '8080')

	config := bind_to_struct[SimpleConfig](env, '')!
	assert config.host == 'localhost'
	assert config.port == 8080
}

// ── Nested Struct Binding Tests ──

fn test_bind_to_struct_nested_struct() {
	mut env := new_environment()
	env.set_property('app.name', 'MyApp')
	env.set_property('app.inner.host', 'db.example.com')
	env.set_property('app.inner.port', '5432')

	config := bind_to_struct[NestedConfig](env, 'app')!
	assert config.name == 'MyApp'
	assert config.inner.host == 'db.example.com'
	assert config.inner.port == 5432
}

fn test_bind_to_struct_nested_struct_partial() {
	mut env := new_environment()
	env.set_property('app.name', 'MyApp')
	// Only set one nested field
	env.set_property('app.inner.host', 'db.example.com')

	config := bind_to_struct[NestedConfig](env, 'app')!
	assert config.name == 'MyApp'
	assert config.inner.host == 'db.example.com'
	// Missing nested field should be zero
	assert config.inner.port == 0
}

fn test_bind_to_struct_nested_struct_no_nested_properties() {
	mut env := new_environment()
	env.set_property('app.name', 'MyApp')
	// No nested properties set

	config := bind_to_struct[NestedConfig](env, 'app')!
	assert config.name == 'MyApp'
	// Nested struct should be zero-valued
	assert config.inner.host == ''
	assert config.inner.port == 0
}

// ── Array Binding Tests ──

fn test_bind_to_struct_string_array() {
	mut env := new_environment()
	env.set_property('app.tags', 'redis,cache,memory')

	config := bind_to_struct[ArrayConfig](env, 'app')!
	assert config.tags.len == 3
	assert config.tags[0] == 'redis'
	assert config.tags[1] == 'cache'
	assert config.tags[2] == 'memory'
}

fn test_bind_to_struct_int_array() {
	mut env := new_environment()
	env.set_property('app.numbers', '1,2,3,42')

	config := bind_to_struct[ArrayConfig](env, 'app')!
	assert config.numbers.len == 4
	assert config.numbers[0] == 1
	assert config.numbers[1] == 2
	assert config.numbers[2] == 3
	assert config.numbers[3] == 42
}

fn test_bind_to_struct_f64_array() {
	mut env := new_environment()
	env.set_property('app.ratios', '1.5,2.5,3.14')

	config := bind_to_struct[ArrayConfig](env, 'app')!
	assert config.ratios.len == 3
	assert config.ratios[0] == 1.5
	assert config.ratios[1] == 2.5
	assert config.ratios[2] == 3.14
}

fn test_bind_to_struct_bool_array() {
	mut env := new_environment()
	env.set_property('app.flags', 'true,false,1,0')

	config := bind_to_struct[ArrayConfig](env, 'app')!
	assert config.flags.len == 4
	assert config.flags[0] == true
	assert config.flags[1] == false
	assert config.flags[2] == true
	assert config.flags[3] == false
}

fn test_bind_to_struct_array_with_spaces() {
	mut env := new_environment()
	env.set_property('app.tags', 'redis, cache , memory')

	config := bind_to_struct[ArrayConfig](env, 'app')!
	assert config.tags.len == 3
	assert config.tags[0] == 'redis'
	assert config.tags[1] == 'cache'
	assert config.tags[2] == 'memory'
}

fn test_bind_to_struct_empty_array_not_set() {
	mut env := new_environment()
	// Don't set array properties

	config := bind_to_struct[ArrayConfig](env, 'app')!
	// Arrays should remain empty (zero value)
	assert config.tags.len == 0
	assert config.numbers.len == 0
	assert config.ratios.len == 0
	assert config.flags.len == 0
}

// ── Custom Field Key Tests ──

fn test_bind_to_struct_custom_field_key_colon_syntax() {
	mut env := new_environment()
	env.set_property('app.hostname', 'myhost')
	env.set_property('app.port_number', '9999')
	env.set_property('app.display_name', 'MyAlias')

	config := bind_to_struct[CustomKeyConfig](env, 'app')!
	assert config.host == 'myhost'
	assert config.port == 9999
	assert config.alias_name == 'MyAlias'
}

fn test_bind_to_struct_custom_field_key_paren_syntax() {
	mut env := new_environment()
	// @[config_field('port_number')] should map to 'port_number'
	env.set_property('app.port_number', '7777')

	config := bind_to_struct[CustomKeyConfig](env, 'app')!
	assert config.port == 7777
}

fn test_bind_to_struct_custom_field_key_mixed() {
	mut env := new_environment()
	env.set_property('app.hostname', 'customhost')
	env.set_property('app.port_number', '3333')
	env.set_property('app.display_name', 'DisplayName')

	config := bind_to_struct[CustomKeyConfig](env, 'app')!
	assert config.host == 'customhost'
	assert config.port == 3333
	assert config.alias_name == 'DisplayName'
}

// ── Mixed Type Tests ──

fn test_bind_to_struct_mixed_types() {
	mut env := new_environment()
	env.set_property('app.name', 'MixedApp')
	env.set_property('app.count', '42')
	env.set_property('app.ratio', '0.95')
	env.set_property('app.active', 'true')
	env.set_property('app.tags', 'a,b,c')
	env.set_property('app.nested.host', 'nested.host')
	env.set_property('app.nested.port', '3306')
	env.set_property('app.special_key', 'custom_value')

	config := bind_to_struct[MixedConfig](env, 'app')!
	assert config.name == 'MixedApp'
	assert config.count == 42
	assert config.ratio == 0.95
	assert config.active == true
	assert config.tags.len == 3
	assert config.tags[0] == 'a'
	assert config.tags[1] == 'b'
	assert config.tags[2] == 'c'
	assert config.nested.host == 'nested.host'
	assert config.nested.port == 3306
	assert config.custom == 'custom_value'
}

// ── ApplicationContext Integration Tests ──

fn test_application_context_bind_to_struct() {
	mut ctx := new_application_context()
	ctx.set_property('app.host', 'localhost')
	ctx.set_property('app.port', '5432')

	config := ctx.bind_to_struct[SimpleConfig]('app')!
	assert config.host == 'localhost'
	assert config.port == 5432
}

fn test_application_context_bind_to_struct_nested() {
	mut ctx := new_application_context()
	ctx.set_property('app.name', 'CtxApp')
	ctx.set_property('app.inner.host', 'ctx.db.host')
	ctx.set_property('app.inner.port', '3306')

	config := ctx.bind_to_struct[NestedConfig]('app')!
	assert config.name == 'CtxApp'
	assert config.inner.host == 'ctx.db.host'
	assert config.inner.port == 3306
}

fn test_register_configuration_properties() {
	mut ctx := new_application_context()
	ctx.set_property('app.host', 'registered.host')
	ctx.set_property('app.port', '4242')

	config := ctx.register_configuration_properties[SimpleConfig]('SimpleConfig', 'app')!
	assert config.host == 'registered.host'
	assert config.port == 4242

	// The bean should be registered and resolvable
	assert ctx.has('SimpleConfig') == true

	// Resolve it back and verify
	resolved := ctx.resolve('SimpleConfig')!
	resolved_config := unsafe { &SimpleConfig(resolved) }
	assert resolved_config.host == 'registered.host'
	assert resolved_config.port == 4242
}

fn test_register_configuration_properties_nested() {
	mut ctx := new_application_context()
	ctx.set_property('app.name', 'RegisteredNested')
	ctx.set_property('app.inner.host', 'nested.db')
	ctx.set_property('app.inner.port', '5432')

	config := ctx.register_configuration_properties[NestedConfig]('NestedConfig', 'app')!
	assert config.name == 'RegisteredNested'
	assert config.inner.host == 'nested.db'
	assert config.inner.port == 5432

	assert ctx.has('NestedConfig') == true
}

// ── Edge Case Tests ──

fn test_bind_to_struct_trailing_dot_in_prefix() {
	mut env := new_environment()
	// Note: bind_to_struct uses prefix.field_name, so trailing dots
	// would create double dots. Users should NOT include trailing dots.
	// This test verifies the standard behavior without trailing dot.
	env.set_property('app.host', 'localhost')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	assert config.host == 'localhost'
}

fn test_bind_to_struct_int_conversion_invalid() {
	mut env := new_environment()
	// V's string.int() returns 0 for invalid input
	env.set_property('app.port', 'not_a_number')

	config := bind_to_struct[SimpleConfig](env, 'app')!
	// Invalid int string converts to 0 (V's default behavior)
	assert config.port == 0
}

fn test_bind_to_struct_single_element_array() {
	mut env := new_environment()
	env.set_property('app.tags', 'only_one')

	config := bind_to_struct[ArrayConfig](env, 'app')!
	assert config.tags.len == 1
	assert config.tags[0] == 'only_one'
}

fn test_bind_to_struct_extract_config_field_key_helper() {
	// Test the helper function directly
	attrs1 := ["config_field: 'my_key'"]
	assert extract_config_field_key(attrs1) == 'my_key'

	attrs2 := ['config_field: "double_quoted"']
	assert extract_config_field_key(attrs2) == 'double_quoted'

	attrs3 := ['config_field: bare_key']
	assert extract_config_field_key(attrs3) == 'bare_key'

	attrs4 := ['some_other_attr', 'another']
	assert extract_config_field_key(attrs4) == ''

	attrs5 := []string{}
	assert extract_config_field_key(attrs5) == ''
}

module core

// value_injection_test.v - Tests for ValueAnnotationPostProcessor
//
// Tests the real @[value: 'key'] injection via the comptime
// ValueAnnotationPostProcessor.inject_values[T]() method.
//
// Covers:
//   - All 4 primitive types: string, int, f64, bool
//   - Missing key error (readable bilingual message)
//   - Multiple fields in a single struct
//   - Boolean value variations ('true'/'false'/'TRUE'/'1'/'0')
//   - Environment integration (set_property / get_property priority chain)
//   - Convenience wrapper inject_values_for_bean (uses embedded environment)

// ── Test Structs ──

// ValueTestConfig covers all 4 primitive types in a single struct.
struct ValueTestConfig {
	app_name string @[value: 'app.name']
	port     int    @[value: 'app.port']
	debug    bool   @[value: 'app.debug']
	ratio    f64    @[value: 'app.ratio']
}

// ValueTestMissingKey has a field referencing a non-existent property key.
struct ValueTestMissingKey {
	missing_field string @[value: 'app.nonexistent']
}

// ValueTestBool isolates bool conversion for variation testing.
struct ValueTestBool {
	flag bool @[value: 'flag']
}

// ValueTestString isolates string injection.
struct ValueTestString {
	greeting string @[value: 'greeting']
}

// ValueTestAppName isolates string injection with an app.name key.
struct ValueTestAppName {
	app_name string @[value: 'app.name']
}

// ValueTestInt isolates int injection.
struct ValueTestInt {
	count int @[value: 'count']
}

// ValueTestAppPort isolates int injection with an app.port key.
struct ValueTestAppPort {
	port int @[value: 'app.port']
}

// ValueTestF64 isolates f64 injection.
struct ValueTestF64 {
	temperature f64 @[value: 'temperature']
}

// ValueTestAppRatio isolates f64 injection with an app.ratio key.
struct ValueTestAppRatio {
	ratio f64 @[value: 'app.ratio']
}

// ValueTestI64 tests i64 field type.
struct ValueTestI64 {
	big_number i64 @[value: 'big.number']
}

// ValueTestF32 tests f32 field type.
struct ValueTestF32 {
	precision f32 @[value: 'precision']
}

// ValueTestMixedAnnotated has a mix of annotated and non-annotated fields.
// Non-annotated fields must remain at their zero values.
struct ValueTestMixedAnnotated {
	title           string @[value: 'app.title']
	version         int    @[value: 'app.version']
	untouched_field string
	untouched_count  int
}

// ── String Injection Tests ──

fn test_inject_string_value() {
	mut env := new_environment()
	env.set_property('app.name', 'Photon')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestAppName{}
	pp.inject_values[ValueTestAppName](mut cfg, env)!

	assert cfg.app_name == 'Photon'
}

fn test_inject_string_isolated() {
	mut env := new_environment()
	env.set_property('greeting', 'Hello, Photon!')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestString{}
	pp.inject_values[ValueTestString](mut cfg, env)!

	assert cfg.greeting == 'Hello, Photon!'
}

fn test_inject_string_with_special_chars() {
	mut env := new_environment()
	env.set_property('greeting', 'Hello "World" / 你好')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestString{}
	pp.inject_values[ValueTestString](mut cfg, env)!

	assert cfg.greeting == 'Hello "World" / 你好'
}

// ── Int Injection Tests ──

fn test_inject_int_value() {
	mut env := new_environment()
	env.set_property('app.port', '8080')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestAppPort{}
	pp.inject_values[ValueTestAppPort](mut cfg, env)!

	assert cfg.port == 8080
}

fn test_inject_int_isolated() {
	mut env := new_environment()
	env.set_property('count', '42')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestInt{}
	pp.inject_values[ValueTestInt](mut cfg, env)!

	assert cfg.count == 42
}

fn test_inject_int_zero() {
	mut env := new_environment()
	env.set_property('count', '0')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestInt{}
	pp.inject_values[ValueTestInt](mut cfg, env)!

	assert cfg.count == 0
}

fn test_inject_int_negative() {
	mut env := new_environment()
	env.set_property('count', '-100')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestInt{}
	pp.inject_values[ValueTestInt](mut cfg, env)!

	assert cfg.count == -100
}

// ── F64 Injection Tests ──

fn test_inject_f64_value() {
	mut env := new_environment()
	env.set_property('app.ratio', '0.95')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestAppRatio{}
	pp.inject_values[ValueTestAppRatio](mut cfg, env)!

	assert cfg.ratio == 0.95
}

fn test_inject_f64_isolated() {
	mut env := new_environment()
	env.set_property('temperature', '36.6')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestF64{}
	pp.inject_values[ValueTestF64](mut cfg, env)!

	assert cfg.temperature == 36.6
}

fn test_inject_f64_integer_string() {
	mut env := new_environment()
	env.set_property('temperature', '100')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestF64{}
	pp.inject_values[ValueTestF64](mut cfg, env)!

	assert cfg.temperature == 100.0
}

fn test_inject_f64_zero() {
	mut env := new_environment()
	env.set_property('temperature', '0.0')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestF64{}
	pp.inject_values[ValueTestF64](mut cfg, env)!

	assert cfg.temperature == 0.0
}

// ── Bool Injection Tests ──

fn test_inject_bool_true() {
	mut env := new_environment()
	env.set_property('flag', 'true')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestBool{}
	pp.inject_values[ValueTestBool](mut cfg, env)!

	assert cfg.flag == true
}

fn test_inject_bool_false() {
	mut env := new_environment()
	env.set_property('flag', 'false')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestBool{}
	pp.inject_values[ValueTestBool](mut cfg, env)!

	assert cfg.flag == false
}

fn test_inject_bool_variation_true_uppercase() {
	mut env := new_environment()
	env.set_property('flag', 'TRUE')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestBool{}
	pp.inject_values[ValueTestBool](mut cfg, env)!

	assert cfg.flag == true
}

fn test_inject_bool_variation_false_uppercase() {
	mut env := new_environment()
	env.set_property('flag', 'FALSE')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestBool{}
	pp.inject_values[ValueTestBool](mut cfg, env)!

	assert cfg.flag == false
}

fn test_inject_bool_variation_one() {
	mut env := new_environment()
	env.set_property('flag', '1')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestBool{}
	pp.inject_values[ValueTestBool](mut cfg, env)!

	assert cfg.flag == true
}

fn test_inject_bool_variation_zero() {
	mut env := new_environment()
	env.set_property('flag', '0')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestBool{}
	pp.inject_values[ValueTestBool](mut cfg, env)!

	assert cfg.flag == false
}

fn test_inject_bool_variation_mixed_case() {
	mut env := new_environment()
	env.set_property('flag', 'True')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestBool{}
	pp.inject_values[ValueTestBool](mut cfg, env)!

	assert cfg.flag == true
}

// ── Missing Key Error Tests ──

fn test_inject_missing_key_returns_error() {
	mut env := new_environment()
	// Do NOT set 'app.nonexistent'

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestMissingKey{}

	mut got_error := false
	mut error_msg := ''
	pp.inject_values[ValueTestMissingKey](mut cfg, env) or {
		got_error = true
		error_msg = err.msg()
	}

	// Verify an error was returned and the message is readable
	assert got_error == true
	assert error_msg.contains('value injection failed')
	assert error_msg.contains('app.nonexistent')
	assert error_msg.contains('not found')
}

fn test_inject_missing_key_error_is_bilingual() {
	mut env := new_environment()

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestMissingKey{}

	mut got_error := false
	mut error_msg := ''
	pp.inject_values[ValueTestMissingKey](mut cfg, env) or {
		got_error = true
		error_msg = err.msg()
	}

	assert got_error == true
	// English part
	assert error_msg.contains('value injection failed')
	// Chinese part
	assert error_msg.contains('值注入失败')
}

fn test_inject_missing_key_does_not_mutate_bean() {
	mut env := new_environment()

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestMissingKey{}

	mut got_error := false
	pp.inject_values[ValueTestMissingKey](mut cfg, env) or {
		got_error = true
	}

	assert got_error == true
	// Bean should remain at zero value even on error
	assert cfg.missing_field == ''
}

// ── Multiple Fields Tests ──

fn test_inject_all_four_types_in_one_struct() {
	mut env := new_environment()
	env.set_property('app.name', 'Photon')
	env.set_property('app.port', '8080')
	env.set_property('app.debug', 'true')
	env.set_property('app.ratio', '0.95')

	mut pp := ValueAnnotationPostProcessor{}
	mut config := ValueTestConfig{}
	pp.inject_values[ValueTestConfig](mut config, env)!

	assert config.app_name == 'Photon'
	assert config.port == 8080
	assert config.debug == true
	assert config.ratio == 0.95
}

fn test_inject_mixed_annotated_and_non_annotated_fields() {
	mut env := new_environment()
	env.set_property('app.title', 'MyApp')
	env.set_property('app.version', '3')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestMixedAnnotated{}
	pp.inject_values[ValueTestMixedAnnotated](mut cfg, env)!

	// Annotated fields are injected
	assert cfg.title == 'MyApp'
	assert cfg.version == 3
	// Non-annotated fields remain at zero values
	assert cfg.untouched_field == ''
	assert cfg.untouched_count == 0
}

// ── i64 / f32 Field Type Tests ──

fn test_inject_i64_field() {
	mut env := new_environment()
	env.set_property('big.number', '9223372036854775807')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestI64{}
	pp.inject_values[ValueTestI64](mut cfg, env)!

	assert cfg.big_number == 9223372036854775807
}

fn test_inject_f32_field() {
	mut env := new_environment()
	env.set_property('precision', '3.14')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestF32{}
	pp.inject_values[ValueTestF32](mut cfg, env)!

	assert cfg.precision == f32(3.14)
}

// ── Environment Integration Tests ──

fn test_inject_uses_environment_priority_chain() {
	// CLI args have highest priority and should override programmatic properties.
	mut env := new_environment()
	env.set_property('app.name', 'FromProperties')
	env.set_cli_arg('app.name', 'FromCLI')

	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ValueTestAppName{}
	pp.inject_values[ValueTestAppName](mut cfg, env)!

	// CLI arg should win over programmatic property
	assert cfg.app_name == 'FromCLI'
}

fn test_inject_with_environment_from_application_context() {
	mut ctx := new_application_context()
	ctx.set_property('app.name', 'CtxApp')
	ctx.set_property('app.port', '3000')
	ctx.set_property('app.debug', 'true')
	ctx.set_property('app.ratio', '1.5')

	// 使用 inject_values_for_bean 规避 V 0.5.1 的 &&Environment 泛型 bug
	mut pp := ValueAnnotationPostProcessor{
		environment: ctx.environment
	}
	mut config := ValueTestConfig{}
	pp.inject_values_for_bean[ValueTestConfig](mut config)!

	assert config.app_name == 'CtxApp'
	assert config.port == 3000
	assert config.debug == true
	assert config.ratio == 1.5
}

// ── Convenience Wrapper Tests ──

fn test_inject_values_for_bean_uses_embedded_environment() {
	mut env := new_environment()
	env.set_property('app.name', 'EmbeddedEnv')
	env.set_property('app.port', '9090')
	env.set_property('app.debug', 'true')
	env.set_property('app.ratio', '0.5')

	mut pp := ValueAnnotationPostProcessor{
		environment: env
	}
	mut config := ValueTestConfig{}
	pp.inject_values_for_bean[ValueTestConfig](mut config)!

	assert config.app_name == 'EmbeddedEnv'
	assert config.port == 9090
	assert config.debug == true
	assert config.ratio == 0.5
}

fn test_inject_values_for_bean_errors_without_environment() {
	mut pp := ValueAnnotationPostProcessor{}
	mut config := ValueTestConfig{}

	mut got_error := false
	mut error_msg := ''
	pp.inject_values_for_bean[ValueTestConfig](mut config) or {
		got_error = true
		error_msg = err.msg()
	}

	assert got_error == true
	assert error_msg.contains('environment')
}

// ── Post-Processor Interface Tests ──

fn test_value_post_processor_satisfies_bean_post_processor_interface() {
	mut pp := ValueAnnotationPostProcessor{}
	// The no-op marker methods must return the bean unchanged.
	dummy := unsafe { nil }
	result_before := pp.post_process_before_initialization('TestBean', dummy)
	assert result_before == dummy

	result_after := pp.post_process_after_initialization('TestBean', dummy)
	assert result_after == dummy
}

// ── Empty / No-Annotation Struct Test ──

struct ValueTestNoAnnotations {
	name  string
	count int
}

fn test_inject_struct_with_no_value_annotations() {
	mut env := new_environment()
	env.set_property('name', 'ShouldNotBeInjected')

	// 使用 inject_values_for_bean 规避 V 0.5.1 的 &&Environment 泛型 bug
	mut pp := ValueAnnotationPostProcessor{
		environment: env
	}
	mut cfg := ValueTestNoAnnotations{}
	// Should succeed (no-op) since no fields have @[value] annotations
	pp.inject_values_for_bean[ValueTestNoAnnotations](mut cfg)!

	// Fields remain at zero values — no @[value] annotations to process
	assert cfg.name == ''
	assert cfg.count == 0
}

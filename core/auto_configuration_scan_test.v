module core

// auto_configuration_scan_test.v - Tests for @[auto_configuration] comptime scanning
// (Task A1: SubTasks A1.1–A1.4)
//
// Verifies that:
//   - extract_auto_configuration[T]() detects the @[auto_configuration] attribute
//   - AutoConfigurationManager.register_from_comptime[T]() registers annotated types
//   - Non-annotated types are refused with an error (contract enforcement)
//   - ApplicationContext.register_auto_configuration[T]() wires through to the manager
//   - @[conditional_on_*] attributes are parsed into Condition objects
//   - Conditions are evaluated during apply_all() (Spring Boot two-phase model)
//
// V comptime can only inspect types in the current compilation unit, so all
// test structs are defined in this file. The "auto" guarantee is that the
// comptime check refuses types lacking @[auto_configuration] — no manual
// type_name strings, no runtime reflection.

// ═══════════════════════════════════════════════════════════
// Test Fixtures — auto-configuration candidate structs
// ═══════════════════════════════════════════════════════════

// RedisAutoConfig is a plain auto-configuration class — no conditions.
@[auto_configuration]
struct RedisAutoConfig {
	host string
	port int
}

// WebMvcAutoConfig carries a profile condition — only active under 'prod'.
@[conditional_on_profile: 'prod']
@[auto_configuration]
struct WebMvcAutoConfig {
	port int
}

// DevOnlyAutoConfig carries a profile condition for 'dev'.
@[conditional_on_profile: 'dev']
@[auto_configuration]
struct DevOnlyAutoConfig {
	debug bool
}

// CacheAutoConfig carries a property condition — active only if
// cache.enabled == true.
@[conditional_on_property: 'cache.enabled,true']
@[auto_configuration]
struct CacheAutoConfig {
	driver string
}

// PlainService is NOT an auto-configuration — used to verify refusal.
struct PlainService {
	name string
}

// ═══════════════════════════════════════════════════════════
// SubTask A1.1 — extract_auto_configuration[T]() comptime detection
// ═══════════════════════════════════════════════════════════

fn test_extract_auto_configuration_detects_annotated_struct() {
	// Comptime scan should find @[auto_configuration] on RedisAutoConfig.
	assert extract_auto_configuration[RedisAutoConfig]() == true
}

fn test_extract_auto_configuration_rejects_plain_struct() {
	// PlainService has no @[auto_configuration] attribute.
	assert extract_auto_configuration[PlainService]() == false
}

fn test_extract_auto_configuration_detects_multiple_annotated_structs() {
	assert extract_auto_configuration[RedisAutoConfig]() == true
	assert extract_auto_configuration[WebMvcAutoConfig]() == true
	assert extract_auto_configuration[DevOnlyAutoConfig]() == true
	assert extract_auto_configuration[CacheAutoConfig]() == true
}

fn test_extract_auto_configuration_attrs_returns_attribute_names() {
	// The attrs helper should include 'auto_configuration' for an annotated type.
	attrs := extract_auto_configuration_attrs[RedisAutoConfig]()
	assert 'auto_configuration' in attrs
}

fn test_extract_auto_configuration_attrs_includes_conditional() {
	// WebMvcAutoConfig has both @[auto_configuration] and @[conditional_on_profile].
	attrs := extract_auto_configuration_attrs[WebMvcAutoConfig]()
	assert 'auto_configuration' in attrs
	// The conditional attribute should appear (with its arg normalized to name:arg).
	mut has_conditional := false
	for attr in attrs {
		if attr.starts_with('conditional_on_profile') {
			has_conditional = true
		}
	}
	assert has_conditional == true
}

fn test_auto_configuration_type_name_returns_fully_qualified_name() {
	// T.name returns the module-qualified type name.
	name := auto_configuration_type_name[RedisAutoConfig]()
	assert name == 'core.RedisAutoConfig'
}

// ═══════════════════════════════════════════════════════════
// SubTask A1.2 — AutoConfigurationManager.register_from_comptime[T]()
// ═══════════════════════════════════════════════════════════

fn test_register_from_comptime_registers_annotated_type() {
	mut mgr := new_auto_configuration_manager()
	assert mgr.candidate_count() == 0

	mgr.register_from_comptime[RedisAutoConfig]()!

	assert mgr.candidate_count() == 1
	assert mgr.has_candidate('core.RedisAutoConfig') == true
}

fn test_register_from_comptime_refuses_non_annotated_type() {
	mut mgr := new_auto_configuration_manager()

	// PlainService lacks @[auto_configuration] → must return an error.
	mgr.register_from_comptime[PlainService]() or {
		// Expected: verify the error message mentions the type and the annotation.
		assert err.msg().contains('auto_configuration') == true
		assert err.msg().contains('PlainService') == true
		return
	}
	// If we reach here, the refusal failed — the test must fail.
	assert false
}

fn test_register_from_comptime_multiple_types() {
	mut mgr := new_auto_configuration_manager()

	mgr.register_from_comptime[RedisAutoConfig]()!
	mgr.register_from_comptime[WebMvcAutoConfig]()!
	mgr.register_from_comptime[DevOnlyAutoConfig]()!

	assert mgr.candidate_count() == 3
	assert mgr.has_candidate('core.RedisAutoConfig') == true
	assert mgr.has_candidate('core.WebMvcAutoConfig') == true
	assert mgr.has_candidate('core.DevOnlyAutoConfig') == true
}

fn test_register_from_comptime_parses_profile_condition() {
	mut mgr := new_auto_configuration_manager()

	mgr.register_from_comptime[WebMvcAutoConfig]()!

	candidates := mgr.list()
	assert candidates.len == 1
	// The @[conditional_on_profile: 'prod'] should be parsed into a Condition.
	assert candidates[0].conditions.len == 1

	// Condition matches when 'prod' profile is active.
	mut ctx_prod := new_condition_context()
	ctx_prod = ctx_prod.with_profiles(['prod'])
	assert candidates[0].conditions[0].evaluate(mut ctx_prod) == true

	// Condition does NOT match when 'dev' profile is active.
	mut ctx_dev := new_condition_context()
	ctx_dev = ctx_dev.with_profiles(['dev'])
	assert candidates[0].conditions[0].evaluate(mut ctx_dev) == false
}

fn test_register_from_comptime_parses_property_condition() {
	mut mgr := new_auto_configuration_manager()

	mgr.register_from_comptime[CacheAutoConfig]()!

	candidates := mgr.list()
	assert candidates.len == 1
	assert candidates[0].conditions.len == 1

	// Condition matches when cache.enabled == true.
	mut ctx_match := new_condition_context()
	ctx_match = ctx_match.with_properties({
		'cache.enabled': 'true'
	})
	assert candidates[0].conditions[0].evaluate(mut ctx_match) == true

	// Condition does NOT match when cache.enabled == false.
	mut ctx_miss := new_condition_context()
	ctx_miss = ctx_miss.with_properties({
		'cache.enabled': 'false'
	})
	assert candidates[0].conditions[0].evaluate(mut ctx_miss) == false
}

fn test_register_from_comptime_no_conditions_for_plain_auto_config() {
	mut mgr := new_auto_configuration_manager()

	mgr.register_from_comptime[RedisAutoConfig]()!

	candidates := mgr.list()
	assert candidates.len == 1
	// RedisAutoConfig has no @[conditional_on_*] → zero conditions.
	assert candidates[0].conditions.len == 0
}

fn test_list_returns_snapshot_copy() {
	mut mgr := new_auto_configuration_manager()
	mgr.register_from_comptime[RedisAutoConfig]()!

	mut snapshot := mgr.list()
	assert snapshot.len == 1

	// Mutating the snapshot must NOT affect the manager's internal state.
	snapshot.clear()
	assert mgr.candidate_count() == 1
}

// ═══════════════════════════════════════════════════════════
// SubTask A1.3 — ApplicationContext.register_auto_configuration[T]()
// ═══════════════════════════════════════════════════════════

fn test_application_context_register_auto_configuration() {
	mut ctx := new_application_context()

	ctx.register_auto_configuration[RedisAutoConfig]()!

	assert ctx.auto_config_manager.candidate_count() == 1
	assert ctx.auto_config_manager.has_candidate('core.RedisAutoConfig') == true
}

fn test_application_context_register_auto_configuration_refuses_non_annotated() {
	mut ctx := new_application_context()

	ctx.register_auto_configuration[PlainService]() or {
		assert err.msg().contains('auto_configuration') == true
		return
	}
	assert false
}

fn test_application_context_register_multiple_auto_configurations() {
	mut ctx := new_application_context()

	ctx.register_auto_configuration[RedisAutoConfig]()!
	ctx.register_auto_configuration[WebMvcAutoConfig]()!
	ctx.register_auto_configuration[DevOnlyAutoConfig]()!

	assert ctx.auto_config_manager.candidate_count() == 3
}

// ═══════════════════════════════════════════════════════════
// Conditional Activation — apply_all() evaluates conditions during refresh
// ═══════════════════════════════════════════════════════════

fn test_apply_all_skips_candidates_with_unmet_conditions() {
	mut ctx := new_application_context()

	// WebMvcAutoConfig requires profile 'prod'. Activate 'dev' instead.
	ctx.set_profiles(['dev'])
	ctx.register_auto_configuration[WebMvcAutoConfig]()!

	// apply_all should NOT error — it silently skips candidates whose
	// conditions are not met. (config is nil for A1, so even matching
	// candidates are a no-op; the point is that apply_all runs cleanly.)
	ctx.auto_config_manager.apply_all(mut ctx) or {
		assert false // apply_all should not return an error for nil-config candidates
	}
}

fn test_apply_all_runs_cleanly_with_met_conditions() {
	mut ctx := new_application_context()

	// Activate the 'prod' profile so WebMvcAutoConfig's condition passes.
	ctx.set_profiles(['prod'])
	ctx.register_auto_configuration[WebMvcAutoConfig]()!
	ctx.register_auto_configuration[RedisAutoConfig]()! // no conditions

	ctx.auto_config_manager.apply_all(mut ctx) or { assert false }
}

fn test_apply_all_mixed_conditions() {
	mut ctx := new_application_context()
	ctx.set_profiles(['prod'])

	// RedisAutoConfig: no conditions → always considered
	// WebMvcAutoConfig: requires 'prod' → matches
	// DevOnlyAutoConfig: requires 'dev' → does NOT match
	ctx.register_auto_configuration[RedisAutoConfig]()!
	ctx.register_auto_configuration[WebMvcAutoConfig]()!
	ctx.register_auto_configuration[DevOnlyAutoConfig]()!

	assert ctx.auto_config_manager.candidate_count() == 3

	// apply_all evaluates all conditions; non-matching candidates are skipped
	// silently. No error should be returned.
	ctx.auto_config_manager.apply_all(mut ctx) or { assert false }
}

// ═══════════════════════════════════════════════════════════
// Thread-Safety — register_from_comptime under the manager lock
// ═══════════════════════════════════════════════════════════

fn test_register_from_comptime_thread_safety() {
	mut mgr := new_auto_configuration_manager()

	// Spawn goroutines that concurrently register different auto-configuration
	// types. The manager's RwMutex must keep the candidates slice consistent.
	done := chan bool{cap: 30}

	for i in 0 .. 30 {
		spawn fn (m &AutoConfigurationManager, idx int, d chan bool) {
			// Alternate between the two annotated types.
			if idx % 2 == 0 {
				unsafe {
					m.register_from_comptime[RedisAutoConfig]() or { assert false }
				}
			} else {
				unsafe {
					m.register_from_comptime[DevOnlyAutoConfig]() or { assert false }
				}
			}
			d <- true
		}(unsafe { mgr }, i, done)
	}

	mut completed := 0
	for _ in 0 .. 30 {
		_ = <-done
		completed++
	}
	assert completed == 30

	// All 30 registrations must be present (no lost updates).
	assert mgr.candidate_count() == 30
}

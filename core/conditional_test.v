module core

// conditional_test.v - Tests for @Conditional real condition evaluation
// (Task 10, P0 4.3)
//
// Verifies that:
//   - OnBeanCondition skips registration when the dependency is absent
//   - OnPropertyCondition skips registration when the property doesn't match
//   - OnClassCondition performs a REAL container check (P0 4.3 fix — no longer
//     always returns true)
//   - OnMissingClassCondition is the correct negation of OnClassCondition
//   - Multiple conditions use AND semantics (all must pass)
//   - BeanDefinitionBuilder.set_conditions() propagates conditions to build()
//   - Condition evaluation during register() is thread-safe under concurrency

// ═══════════════════════════════════════════════════════════
// OnBeanCondition Tests
// ═══════════════════════════════════════════════════════════

fn test_on_bean_condition_registers_when_dependency_exists() {
	mut container := new_container()

	// Register the dependency first
	container.register(new_bean_definition('DependencyBean'))!

	// Register a conditional bean that depends on DependencyBean
	mut def := new_bean_definition('ServiceBean')
	def.conditions = [&Condition(&OnBeanCondition{
		bean_type: 'DependencyBean'
	})]
	container.register(def)!

	assert container.has('ServiceBean') == true
	assert container.has_definition('ServiceBean') == true
}

fn test_on_bean_condition_skipped_when_dependency_absent() {
	mut container := new_container()

	// Do NOT register 'MissingBean'
	mut def := new_bean_definition('ServiceBean')
	def.conditions = [&Condition(&OnBeanCondition{
		bean_type: 'MissingBean'
	})]
	container.register(def)! // silently skipped — no error

	assert container.has('ServiceBean') == false
	assert container.has_definition('ServiceBean') == false
	assert container.bean_count() == 0
}

// ═══════════════════════════════════════════════════════════
// OnPropertyCondition Tests
// ═══════════════════════════════════════════════════════════

fn test_on_property_condition_registers_when_value_matches() {
	mut container := new_container()
	mut env := new_environment()
	env.set_property('cache.enabled', 'true')
	container.set_environment(env)

	mut def := new_bean_definition('CacheBean')
	def.conditions = [
		&Condition(&OnPropertyCondition{
			key:          'cache.enabled'
			having_value: 'true'
		}),
	]
	container.register(def)!

	assert container.has('CacheBean') == true
}

fn test_on_property_condition_skipped_when_value_mismatches() {
	mut container := new_container()
	mut env := new_environment()
	env.set_property('cache.enabled', 'false')
	container.set_environment(env)

	mut def := new_bean_definition('CacheBean')
	def.conditions = [
		&Condition(&OnPropertyCondition{
			key:          'cache.enabled'
			having_value: 'true'
		}),
	]
	container.register(def)! // skipped — value is 'false', not 'true'

	assert container.has('CacheBean') == false
}

fn test_on_property_condition_skipped_when_property_absent() {
	mut container := new_container()
	mut env := new_environment()
	container.set_environment(env)

	mut def := new_bean_definition('CacheBean')
	def.conditions = [
		&Condition(&OnPropertyCondition{
			key:          'cache.enabled'
			having_value: 'true'
		}),
	]
	container.register(def)! // skipped — property not set

	assert container.has('CacheBean') == false
}

// ═══════════════════════════════════════════════════════════
// OnClassCondition Tests (P0 4.3 — real evaluation, not always-true)
// ═══════════════════════════════════════════════════════════

fn test_on_class_condition_registers_when_class_exists() {
	mut container := new_container()

	// Register a bean representing the "class" being checked
	container.register(new_bean_definition('CacheManager'))!

	mut def := new_bean_definition('CacheService')
	def.conditions = [&Condition(&OnClassCondition{
		class_name: 'CacheManager'
	})]
	container.register(def)!

	assert container.has('CacheService') == true
}

fn test_on_class_condition_skipped_when_class_absent() {
	mut container := new_container()

	mut def := new_bean_definition('CacheService')
	def.conditions = [&Condition(&OnClassCondition{
		class_name: 'RedisCache'
	})]
	container.register(def)! // RedisCache not registered → skip

	// This is the core P0 4.3 assertion: previously OnClassCondition always
	// returned true, so CacheService WOULD have been registered.
	assert container.has('CacheService') == false
	assert container.bean_count() == 0
}

fn test_on_class_condition_direct_evaluate_with_container() {
	mut container := new_container()
	container.register(new_bean_definition('PresentClass'))!

	mut ctx := new_condition_context()
	ctx = ctx.with_container(unsafe { container })

	c_match := OnClassCondition{
		class_name: 'PresentClass'
	}
	assert c_match.evaluate(mut ctx) == true

	c_miss := OnClassCondition{
		class_name: 'AbsentClass'
	}
	assert c_miss.evaluate(mut ctx) == false
}

// ═══════════════════════════════════════════════════════════
// OnMissingClassCondition Tests
// ═══════════════════════════════════════════════════════════

fn test_on_missing_class_condition_registers_when_class_absent() {
	mut container := new_container()

	mut def := new_bean_definition('FallbackService')
	def.conditions = [
		&Condition(&OnMissingClassCondition{
			class_name: 'RedisCache'
		}),
	]
	container.register(def)!

	assert container.has('FallbackService') == true
}

fn test_on_missing_class_condition_skipped_when_class_exists() {
	mut container := new_container()
	container.register(new_bean_definition('RedisCache'))!

	mut def := new_bean_definition('FallbackService')
	def.conditions = [
		&Condition(&OnMissingClassCondition{
			class_name: 'RedisCache'
		}),
	]
	container.register(def)! // RedisCache exists → skip

	assert container.has('FallbackService') == false
}

// ═══════════════════════════════════════════════════════════
// Multiple Conditions (AND semantics)
// ═══════════════════════════════════════════════════════════

fn test_multiple_conditions_all_must_pass() {
	mut container := new_container()
	mut env := new_environment()
	env.set_property('feature.x', 'enabled')
	container.set_environment(env)

	container.register(new_bean_definition('DepBean'))!

	mut def := new_bean_definition('CompositeBean')
	def.conditions = [
		&Condition(&OnBeanCondition{
			bean_type: 'DepBean'
		}),
		&Condition(&OnPropertyCondition{
			key:          'feature.x'
			having_value: 'enabled'
		}),
	]
	container.register(def)!

	assert container.has('CompositeBean') == true
}

fn test_multiple_conditions_one_fails_skips_registration() {
	mut container := new_container()
	mut env := new_environment()
	env.set_property('feature.x', 'disabled')
	container.set_environment(env)

	container.register(new_bean_definition('DepBean'))!

	mut def := new_bean_definition('CompositeBean')
	def.conditions = [
		&Condition(&OnBeanCondition{
			bean_type: 'DepBean'
		}),
		&Condition(&OnPropertyCondition{
			key:          'feature.x'
			having_value: 'enabled'
		}),
	]
	container.register(def)! // property doesn't match → skip

	assert container.has('CompositeBean') == false
}

// ═══════════════════════════════════════════════════════════
// BeanDefinitionBuilder.set_conditions()
// ═══════════════════════════════════════════════════════════

fn test_bean_definition_builder_set_conditions() {
	mut container := new_container()
	container.register(new_bean_definition('BaseBean'))!

	mut builder := new_bean_definition_builder('BuiltBean')
	builder.set_conditions([&Condition(&OnBeanCondition{
		bean_type: 'BaseBean'
	})])
	def := builder.build()

	container.register(def)!
	assert container.has('BuiltBean') == true

	// Builder with a failing condition
	mut builder2 := new_bean_definition_builder('SkippedBean')
	builder2.set_conditions([
		&Condition(&OnBeanCondition{
			bean_type: 'AbsentBean'
		}),
	])
	def2 := builder2.build()

	container.register(def2)!
	assert container.has('SkippedBean') == false
}

// ═══════════════════════════════════════════════════════════
// No Conditions — register() behaves as before
// ═══════════════════════════════════════════════════════════

fn test_register_without_conditions_still_works() {
	mut container := new_container()

	container.register(new_bean_definition('PlainBean'))!
	assert container.has('PlainBean') == true
	assert container.bean_count() == 1
}

// ═══════════════════════════════════════════════════════════
// Thread-Safety Test
// ═══════════════════════════════════════════════════════════

// test_condition_evaluation_thread_safety spawns 50 goroutines that
// concurrently register beans with conditions. Half the conditions pass
// (depend on a pre-registered 'BaseBean') and half fail (depend on a
// non-existent bean). All goroutines must complete without crashing, and
// the final bean count must be exactly BaseBean + 25 passing beans.
fn test_condition_evaluation_thread_safety() {
	mut container := new_container()
	mut env := new_environment()
	env.set_property('feature.enabled', 'true')
	container.set_environment(env)

	// Register a base bean that the passing conditions will check
	container.register(new_bean_definition('BaseBean'))!

	done := chan bool{cap: 50}

	// 25 goroutines register beans whose conditions PASS
	for i in 0 .. 25 {
		spawn fn (c &Container, idx int, d chan bool) {
			mut def := new_bean_definition('PassBean_${idx}')
			def.conditions = [
				&Condition(&OnBeanCondition{
					bean_type: 'BaseBean'
				}),
			]
			unsafe {
				c.register(def) or { assert false }
			}
			d <- true
		}(unsafe { container }, i, done)
	}

	// 25 goroutines register beans whose conditions FAIL
	for i in 0 .. 25 {
		spawn fn (c &Container, idx int, d chan bool) {
			mut def := new_bean_definition('SkipBean_${idx}')
			def.conditions = [
				&Condition(&OnBeanCondition{
					bean_type: 'NonExistent'
				}),
			]
			unsafe {
				c.register(def) or { assert false }
			}
			d <- true
		}(unsafe { container }, i, done)
	}

	mut completed := 0
	for _ in 0 .. 50 {
		_ = <-done
		completed++
	}
	assert completed == 50

	// BaseBean + 25 PassBeans = 26. The 25 SkipBeans must NOT be registered.
	assert container.bean_count() == 26
}

module cache

// condition_unless_test.v - Tests for condition/unless expression evaluation (Task C5)
//
// Covers:
//   - evaluate_condition unit tests (#result, #param, ==, !=, null, and, or, literals)
//   - CacheableInterceptor.get_or_compute integration (condition false / unless true → not cached)
//   - CacheableInterceptor.put integration (unless true → not cached)
//   - Backward compatibility (empty condition/unless = existing behavior)

// Shared counter for compute-call tracking (module-level to avoid closure capture issues)
__global (
	cu_compute_count int
)

// ============================================================
// evaluate_condition Unit Tests
// ============================================================

// Test 1: condition true (empty) — empty condition = always true
fn test_evaluate_condition_empty_is_true() {
	ctx := ExpressionContext{
		result: 'hello'
	}
	assert evaluate_condition('', ctx) == true
}

// Test 2: condition true (#result != null) — non-null result
fn test_evaluate_condition_result_not_null_true() {
	ctx := ExpressionContext{
		result:         'hello'
		is_null_result: false
	}
	assert evaluate_condition('#result != null', ctx) == true
}

// Test 3: condition false (#result != null) — null result → FALSE → NOT cached
// Semantics: condition FALSE = don't cache. #result != null is FALSE when result is null.
fn test_evaluate_condition_result_is_null_false() {
	ctx := ExpressionContext{
		result:         ''
		is_null_result: true
	}
	assert evaluate_condition('#result != null', ctx) == false
}

// Test 4: condition false (#result != 'skip') — result is 'skip' → FALSE → NOT cached
// Semantics: condition FALSE = don't cache. #result != 'skip' is FALSE when result is 'skip'.
fn test_evaluate_condition_result_equals_skip_false() {
	ctx := ExpressionContext{
		result: 'skip'
	}
	assert evaluate_condition("#result != 'skip'", ctx) == false
}

// Test 5: unless true (#result == null) — null result
fn test_unless_result_is_null_true() {
	ctx := ExpressionContext{
		result:         ''
		is_null_result: true
	}
	assert evaluate_condition('#result == null', ctx) == true
}

// Test 6: unless false (#result == null) — non-null result → FALSE → cached
// Semantics: unless FALSE = cache. #result == null is FALSE when result is non-null.
fn test_unless_result_not_null_false() {
	ctx := ExpressionContext{
		result: 'hello'
	}
	assert evaluate_condition('#result == null', ctx) == false
}

// Test 7: unless true (#result == 'nocache')
fn test_unless_result_equals_nocache_true() {
	ctx := ExpressionContext{
		result: 'nocache'
	}
	assert evaluate_condition("#result == 'nocache'", ctx) == true
}

// Test 8: condition + unless both pass → cache allowed
fn test_condition_and_unless_both_pass() {
	ctx := ExpressionContext{
		result: 'hello'
	}
	cond := evaluate_condition('#result != null', ctx)
	unl := evaluate_condition("#result == 'nocache'", ctx)
	assert cond == true
	assert unl == false
}

// Test 9: condition true but unless true → unless blocks caching
fn test_condition_true_but_unless_blocks() {
	ctx := ExpressionContext{
		result: 'nocache'
	}
	cond := evaluate_condition('#result != null', ctx)
	unl := evaluate_condition("#result == 'nocache'", ctx)
	assert cond == true
	assert unl == true
}

// Test 10: condition false → blocks regardless of unless
fn test_condition_false_blocks() {
	ctx := ExpressionContext{
		result:         ''
		is_null_result: true
	}
	cond := evaluate_condition('#result != null', ctx)
	assert cond == false
}

// Test 11: #param evaluation
fn test_evaluate_condition_param_evaluation() {
	mut params := map[string]string{}
	params['force'] = 'true'
	ctx := ExpressionContext{
		result: 'hello'
		params: params
	}
	assert evaluate_condition("#param.force == 'true'", ctx) == true
	assert evaluate_condition("#param.force == 'false'", ctx) == false
}

// Test 12: and expression
fn test_evaluate_condition_and_expression() {
	mut params := map[string]string{}
	params['x'] = 'y'
	ctx := ExpressionContext{
		result: 'hello'
		params: params
	}
	// both sides true → true
	assert evaluate_condition("#result != null and #param.x == 'y'", ctx) == true

	// one side false → false
	params['x'] = 'z'
	ctx2 := ExpressionContext{
		result: 'hello'
		params: params
	}
	assert evaluate_condition("#result != null and #param.x == 'y'", ctx2) == false
}

// Test 13: or expression
fn test_evaluate_condition_or_expression() {
	mut params := map[string]string{}
	params['x'] = 'y'
	// #result == null (true) or #param.x == 'y' (true) → true
	ctx := ExpressionContext{
		result:         ''
		is_null_result: true
		params:         params
	}
	assert evaluate_condition("#result == null or #param.x == 'y'", ctx) == true

	// #result == null (false) or #param.x == 'y' (true) → true
	ctx2 := ExpressionContext{
		result: 'hello'
		params: params
	}
	assert evaluate_condition("#result == null or #param.x == 'y'", ctx2) == true

	// both false → false
	params['x'] = 'z'
	ctx3 := ExpressionContext{
		result: 'hello'
		params: params
	}
	assert evaluate_condition("#result == null or #param.x == 'y'", ctx3) == false
}

// Test 17: string literal with quotes (single and double)
fn test_evaluate_condition_string_literal_quotes() {
	ctx := ExpressionContext{
		result: 'value'
	}
	assert evaluate_condition("#result == 'value'", ctx) == true
	assert evaluate_condition('#result == "value"', ctx) == true
	assert evaluate_condition("#result == 'other'", ctx) == false
}

// Test 18: empty condition treated as always true (even for null result)
fn test_evaluate_condition_empty_always_true() {
	ctx := ExpressionContext{
		result:         ''
		is_null_result: true
	}
	assert evaluate_condition('', ctx) == true
}

// ============================================================
// get_or_compute Integration Tests
// ============================================================

// Test 14: get_or_compute with condition false → compute called, result returned but NOT cached
fn test_get_or_compute_condition_false_not_cached() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	attr := CacheableAttribute{
		cache_name:  'default'
		ttl_seconds: 60
		condition:   '#result == null' // false for non-null result → don't cache
	}

	cu_compute_count = 0
	result := ci.get_or_compute(attr, 'cond_false_method', [], fn () !string {
		cu_compute_count++
		return 'computed'
	})!

	assert result == 'computed'
	assert cu_compute_count == 1

	// Should NOT be cached → second call computes again
	result2 := ci.get_or_compute(attr, 'cond_false_method', [], fn () !string {
		cu_compute_count++
		return 'computed'
	})!

	assert result2 == 'computed'
	assert cu_compute_count == 2 // loader called again (not cached)
}

// Test 15: get_or_compute with unless true → compute called, result returned but NOT cached
fn test_get_or_compute_unless_true_not_cached() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	attr := CacheableAttribute{
		cache_name:  'default'
		ttl_seconds: 60
		unless:      "#result == 'nocache'"
	}

	cu_compute_count = 0
	result := ci.get_or_compute(attr, 'unless_true_method', [], fn () !string {
		cu_compute_count++
		return 'nocache'
	})!

	assert result == 'nocache'
	assert cu_compute_count == 1

	// Should NOT be cached → second call computes again
	result2 := ci.get_or_compute(attr, 'unless_true_method', [], fn () !string {
		cu_compute_count++
		return 'nocache'
	})!

	assert result2 == 'nocache'
	assert cu_compute_count == 2 // loader called again (not cached)
}

// Test 16: subsequent get returns none after condition/unless blocks caching
fn test_get_returns_none_after_blocked() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	attr := CacheableAttribute{
		cache_name:  'default'
		ttl_seconds: 60
		condition:   '#result == null' // blocks non-null result
	}

	ci.get_or_compute(attr, 'blocked_method', [], fn () !string {
		return 'computed'
	})!

	// Direct get should return miss (empty string from or block)
	cached := ci.cache_manager.get('default::blocked_method') or { '' }
	assert cached == ''
}

// Backward compat: get_or_compute with condition true → cached
fn test_get_or_compute_condition_true_cached() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	attr := CacheableAttribute{
		cache_name:  'default'
		ttl_seconds: 60
		condition:   '#result != null'
	}

	cu_compute_count = 0
	result := ci.get_or_compute(attr, 'cond_true_method', [], fn () !string {
		cu_compute_count++
		return 'computed'
	})!

	assert result == 'computed'
	assert cu_compute_count == 1

	// Should be cached → second call does NOT compute
	result2 := ci.get_or_compute(attr, 'cond_true_method', [], fn () !string {
		cu_compute_count++
		return 'should_not_reach'
	})!

	assert result2 == 'computed'
	assert cu_compute_count == 1 // loader NOT called again (cached)
}

// Backward compat: get_or_compute with no condition/unless → cached (existing behavior)
fn test_get_or_compute_no_condition_cached() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	attr := CacheableAttribute{
		cache_name:  'default'
		ttl_seconds: 60
	}

	cu_compute_count = 0
	result := ci.get_or_compute(attr, 'no_cond_method', [], fn () !string {
		cu_compute_count++
		return 'computed'
	})!

	assert result == 'computed'
	assert cu_compute_count == 1

	result2 := ci.get_or_compute(attr, 'no_cond_method', [], fn () !string {
		cu_compute_count++
		return 'should_not_reach'
	})!

	assert result2 == 'computed'
	assert cu_compute_count == 1
}

// ============================================================
// put Integration Tests
// ============================================================

// put with unless true → NOT cached
fn test_put_unless_true_not_cached() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	put_attr := CachePutAttribute{
		cache_name:  'default'
		ttl_seconds: 60
		unless:      "#result == 'nocache'"
	}

	ci.put(put_attr, 'put_unless_method', [], 'nocache')!

	cached := ci.cache_manager.get('default::put_unless_method') or { '' }
	assert cached == ''
}

// put with unless false → cached
fn test_put_unless_false_cached() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	put_attr := CachePutAttribute{
		cache_name:  'default'
		ttl_seconds: 60
		unless:      "#result == 'nocache'"
	}

	ci.put(put_attr, 'put_unless_method', [], 'normal_value')!

	cached := ci.cache_manager.get('default::put_unless_method') or { '' }
	assert cached == 'normal_value'
}

// put with no unless → cached (backward compat)
fn test_put_no_unless_cached() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	put_attr := CachePutAttribute{
		cache_name:  'default'
		ttl_seconds: 60
	}

	ci.put(put_attr, 'put_normal_method', [], 'value')!

	cached := ci.cache_manager.get('default::put_normal_method') or { '' }
	assert cached == 'value'
}

// put with unless on null result → NOT cached
fn test_put_unless_null_result_not_cached() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	put_attr := CachePutAttribute{
		cache_name:  'default'
		ttl_seconds: 60
		unless:      '#result == null'
	}

	ci.put(put_attr, 'put_null_method', [], '')!

	cached := ci.cache_manager.get('default::put_null_method') or { '' }
	assert cached == ''
}

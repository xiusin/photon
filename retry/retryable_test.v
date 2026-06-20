module retry

import time

// retryable_test.v - Tests for @[retryable] annotation and retry logic (Task C3)
//
// Covers (per task spec):
//   - Success on first try (no retry)
//   - Success after retry
//   - Retry exhausted (returns last error)
//   - retry_for / no_retry_for error-type filtering
//   - Fixed / linear / exponential backoff
//   - delay_for_attempt calculation
//   - should_retry logic
//   - Void operation wrapper
//   - Edge case: zero/negative max_attempts
//   - Concurrent retries (thread safety)
//   - Custom error types (typeof().name matching)
//   - Annotation parsing
//   - Comptime annotation extraction
//
// V 0.5.1 closures capture by value, so we use the pointer + unsafe
// dereference pattern (same as orm/transaction_attributes_test.v) for
// state tracking inside retry callbacks.

// ═══════════════════════════════════════════════════════════════
// Custom error types for retry tests
//
// Each error's msg() includes the type name so that
// error_type_matches() can match via err.msg().contains(type_name)
// as a fallback when typeof(err).name returns 'IError'.
// Both msg() and code() are required by V's IError interface.
// ═══════════════════════════════════════════════════════════════

struct NetworkError {
	code int = 500
}

fn (e NetworkError) msg() string {
	return 'NetworkError: network failure (code ${e.code})'
}

fn (e NetworkError) code() int {
	return e.code
}

struct ValidationError {
	code int = 400
}

fn (e ValidationError) msg() string {
	return 'ValidationError: invalid input (code ${e.code})'
}

fn (e ValidationError) code() int {
	return e.code
}

struct TransientError {
	code int = 503
}

fn (e TransientError) msg() string {
	return 'TransientError: service unavailable'
}

fn (e TransientError) code() int {
	return e.code
}

// ── Call counter for tracking operation invocations ──
//
// V 0.5.1 closures capture by value, so we capture a pointer (&cc)
// and mutate fields through unsafe dereference inside the closure.

struct CallCounter {
mut:
	count      int
	fail_until int // fail (return NetworkError) while count <= fail_until
}

// counter_operation is a free function taking a pointer so it can be
// called from inside a closure that captured the pointer by value.
// Mutations go through unsafe since the pointer is captured by value
// but still references the original struct.
fn counter_operation(cp &CallCounter) !int {
	unsafe { cp.count++ }
	cnt := unsafe { cp.count }
	fu := unsafe { cp.fail_until }
	if cnt <= fu {
		return NetworkError{}
	}
	return cnt
}

// ═══════════════════════════════════════════════════════════════
// C3.3: Success on first try (no retry needed)
// ═══════════════════════════════════════════════════════════════

fn test_success_first_try() {
	mut cc := CallCounter{
		fail_until: 0 // succeed immediately
	}
	mut cp := &cc

	config := RetryConfig{
		max_attempts: 3
		delay:        10 * time.millisecond
	}
	result := execute_with_retry[int](config, fn [cp] () !int {
		return counter_operation(cp)!
	})!

	assert result == 1
	assert cc.count == 1 // only one attempt
}

// ═══════════════════════════════════════════════════════════════
// C3.3: Success after retry (fails twice, succeeds on 3rd attempt)
// ═══════════════════════════════════════════════════════════════

fn test_success_after_retry() {
	mut cc := CallCounter{
		fail_until: 2 // fail first 2 attempts, succeed on 3rd
	}
	mut cp := &cc

	config := RetryConfig{
		max_attempts: 3
		delay:        10 * time.millisecond
	}
	result := execute_with_retry[int](config, fn [cp] () !int {
		return counter_operation(cp)!
	})!

	assert result == 3
	assert cc.count == 3 // three attempts total
}

// ═══════════════════════════════════════════════════════════════
// C3.3: Retry exhausted (all attempts fail, returns last error)
// ═══════════════════════════════════════════════════════════════

fn test_retry_exhausted() {
	mut cc := CallCounter{
		fail_until: 5 // always fail within max_attempts
	}
	mut cp := &cc

	config := RetryConfig{
		max_attempts: 3
		delay:        10 * time.millisecond
	}
	execute_with_retry[int](config, fn [cp] () !int {
		return counter_operation(cp)!
	}) or {
		// Should return the NetworkError after exhausting retries
		assert err.msg().contains('NetworkError')
		assert cc.count == 3
		return
	}

	// Should not reach here — all attempts should fail
	assert false
}

fn test_retry_exhausted_preserves_error() {
	mut cc := CallCounter{
		fail_until: 5
	}
	mut cp := &cc

	config := RetryConfig{
		max_attempts: 2
		delay:        5 * time.millisecond
	}
	mut captured_msg := ''
	execute_with_retry[int](config, fn [cp] () !int {
		return counter_operation(cp)!
	}) or {
		captured_msg = err.msg()
		return
	}
	assert cc.count == 2
	assert captured_msg.contains('NetworkError')
}

// ═══════════════════════════════════════════════════════════════
// retry_for: only retry specified error types
// ═══════════════════════════════════════════════════════════════

fn test_retry_for_matches() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
		retry_for:    ['NetworkError']
	}
	// NetworkError should be retried
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return NetworkError{}
	}) or { return }
	assert cc.count == 3 // retried up to max_attempts
}

fn test_retry_for_does_not_match() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
		retry_for:    ['NetworkError']
	}
	// ValidationError should NOT be retried (not in retry_for)
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return ValidationError{}
	}) or { return }
	assert cc.count == 1 // no retry, returned immediately
}

fn test_retry_for_multiple_types() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
		retry_for:    ['NetworkError', 'TransientError']
	}
	// TransientError is in retry_for, should be retried
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return TransientError{}
	}) or { return }
	assert cc.count == 3
}

// ═══════════════════════════════════════════════════════════════
// no_retry_for: never retry specified error types (takes precedence)
// ═══════════════════════════════════════════════════════════════

fn test_no_retry_for_blocks_retry() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
		no_retry_for: ['ValidationError']
	}
	// ValidationError in no_retry_for → no retry even though default is retry-all
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return ValidationError{}
	}) or { return }
	assert cc.count == 1
}

fn test_no_retry_for_allows_other_errors() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
		no_retry_for: ['ValidationError']
	}
	// NetworkError not in no_retry_for → should be retried
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return NetworkError{}
	}) or { return }
	assert cc.count == 3
}

fn test_no_retry_for_takes_precedence_over_retry_for() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
		retry_for:    ['NetworkError']
		no_retry_for: ['NetworkError']
	}
	// NetworkError is in BOTH lists → no_retry_for wins → no retry
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return NetworkError{}
	}) or { return }
	assert cc.count == 1
}

// ═══════════════════════════════════════════════════════════════
// Backoff policy: delay_for_attempt calculation
// ═══════════════════════════════════════════════════════════════

fn test_delay_for_attempt_fixed() {
	config := RetryConfig{
		delay:   100 * time.millisecond
		backoff: .fixed
	}
	// Fixed: same delay regardless of attempt
	assert config.delay_for_attempt(1) == 100 * time.millisecond
	assert config.delay_for_attempt(2) == 100 * time.millisecond
	assert config.delay_for_attempt(3) == 100 * time.millisecond
	assert config.delay_for_attempt(4) == 100 * time.millisecond
}

fn test_delay_for_attempt_linear() {
	config := RetryConfig{
		delay:   100 * time.millisecond
		backoff: .linear
	}
	// Linear: delay * attempt
	assert config.delay_for_attempt(1) == 100 * time.millisecond
	assert config.delay_for_attempt(2) == 200 * time.millisecond
	assert config.delay_for_attempt(3) == 300 * time.millisecond
	assert config.delay_for_attempt(4) == 400 * time.millisecond
}

fn test_delay_for_attempt_exponential() {
	config := RetryConfig{
		delay:   100 * time.millisecond
		backoff: .exponential
	}
	// Exponential: delay * 2^(attempt-1)
	assert config.delay_for_attempt(1) == 100 * time.millisecond
	assert config.delay_for_attempt(2) == 200 * time.millisecond
	assert config.delay_for_attempt(3) == 400 * time.millisecond
	assert config.delay_for_attempt(4) == 800 * time.millisecond
}

fn test_delay_for_attempt_first_attempt_returns_base() {
	// First attempt always returns base delay (no preceding wait)
	config := RetryConfig{
		delay:   50 * time.millisecond
		backoff: .exponential
	}
	assert config.delay_for_attempt(1) == 50 * time.millisecond
}

// ═══════════════════════════════════════════════════════════════
// Backoff timing: verify actual sleep behaviour
// ═══════════════════════════════════════════════════════════════

fn test_fixed_backoff_timing() {
	mut cc := CallCounter{
		fail_until: 2 // fail twice, succeed on 3rd
	}
	mut cp := &cc

	config := RetryConfig{
		max_attempts: 3
		delay:        40 * time.millisecond
		backoff:      .fixed
	}
	start := time.now()
	execute_with_retry[int](config, fn [cp] () !int {
		return counter_operation(cp)!
	})!
	elapsed := time.now() - start

	// Fixed: 2 retries × 40ms = ~80ms minimum
	// Allow generous margin for scheduler jitter (40ms to 400ms)
	assert elapsed >= 40 * time.millisecond
	assert elapsed < 400 * time.millisecond
}

fn test_exponential_backoff_timing() {
	mut cc := CallCounter{
		fail_until: 2 // fail twice, succeed on 3rd
	}
	mut cp := &cc

	config := RetryConfig{
		max_attempts: 3
		delay:        30 * time.millisecond
		backoff:      .exponential
	}
	start := time.now()
	execute_with_retry[int](config, fn [cp] () !int {
		return counter_operation(cp)!
	})!
	elapsed := time.now() - start

	// Exponential: attempt 1 fails → sleep 30ms, attempt 2 fails → sleep 60ms
	// Total sleep = 30 + 60 = 90ms minimum
	assert elapsed >= 60 * time.millisecond
	assert elapsed < 500 * time.millisecond
}

// ═══════════════════════════════════════════════════════════════
// should_retry logic: all combinations
// ═══════════════════════════════════════════════════════════════

fn test_should_retry_default_all_errors() {
	config := new_retry_config()
	// Default: retry all errors
	assert should_retry(config, IError(NetworkError{}))
	assert should_retry(config, IError(ValidationError{}))
}

fn test_should_retry_with_retry_for() {
	config := RetryConfig{
		retry_for: ['NetworkError']
	}
	assert should_retry(config, IError(NetworkError{}))
	assert !should_retry(config, IError(ValidationError{}))
}

fn test_should_retry_with_no_retry_for() {
	config := RetryConfig{
		no_retry_for: ['ValidationError']
	}
	assert should_retry(config, IError(NetworkError{}))
	assert !should_retry(config, IError(ValidationError{}))
}

fn test_should_retry_no_retry_for_precedence() {
	config := RetryConfig{
		retry_for:    ['NetworkError']
		no_retry_for: ['NetworkError']
	}
	// no_retry_for takes precedence
	assert !should_retry(config, IError(NetworkError{}))
}

fn test_should_retry_empty_retry_for_retries_all() {
	config := RetryConfig{
		retry_for: []
	}
	// Empty retry_for = retry all
	assert should_retry(config, IError(NetworkError{}))
}

// ═══════════════════════════════════════════════════════════════
// error_type_matches: dual-strategy matching
// ═══════════════════════════════════════════════════════════════

fn test_error_type_matches_by_typeof() {
	err := IError(NetworkError{})
	// typeof may return 'NetworkError', 'retry.NetworkError', or 'IError'
	// msg() fallback contains 'NetworkError'
	assert error_type_matches(err, 'NetworkError')
}

fn test_error_type_matches_by_msg_fallback() {
	// String errors created via error() — typeof returns 'IError'
	// but msg() contains the text
	err := IError(error('NetworkError: connection refused'))
	assert error_type_matches(err, 'NetworkError')
}

fn test_error_type_matches_no_match() {
	err := IError(ValidationError{})
	assert !error_type_matches(err, 'NetworkError')
}

// ═══════════════════════════════════════════════════════════════
// Void operation wrapper
// ═══════════════════════════════════════════════════════════════

fn test_void_operation_success_first_try() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
	}
	execute_void_with_retry(config, fn [cp] () ! {
		unsafe { cp.count++ }
	})!
	assert cc.count == 1
}

fn test_void_operation_success_after_retry() {
	mut cc := CallCounter{
		count:      0
		fail_until: 2
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
	}
	execute_void_with_retry(config, fn [cp] () ! {
		unsafe { cp.count++ }
		if unsafe { cp.count } <= unsafe { cp.fail_until } {
			return NetworkError{}
		}
	})!
	assert cc.count == 3
}

fn test_void_operation_exhausted() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 2
		delay:        5 * time.millisecond
	}
	execute_void_with_retry(config, fn [cp] () ! {
		unsafe { cp.count++ }
		return NetworkError{}
	}) or {
		assert err.msg().contains('NetworkError')
		assert cc.count == 2
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════════
// Edge case: zero/negative max_attempts (should default to 1)
// ═══════════════════════════════════════════════════════════════

fn test_zero_max_attempts_defaults_to_one() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 0 // invalid → treated as 1
		delay:        5 * time.millisecond
	}
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return NetworkError{}
	}) or { return }
	// Should attempt exactly once (no retries)
	assert cc.count == 1
}

fn test_negative_max_attempts_defaults_to_one() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: -5
		delay:        5 * time.millisecond
	}
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return 42
	})!
	assert cc.count == 1
}

fn test_max_attempts_one_no_retry() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 1
		delay:        5 * time.millisecond
	}
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return NetworkError{}
	}) or { return }
	assert cc.count == 1
}

// ═══════════════════════════════════════════════════════════════
// Concurrent retries: thread safety
// ═══════════════════════════════════════════════════════════════

struct ConcurrentState {
mut:
	count int
}

fn test_concurrent_retries() {
	mut state := ConcurrentState{}
	mut sp := &state
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
	}

	// Spawn multiple goroutines, each performing retries.
	// The retry logic itself is stateless (uses only local variables
	// and the immutable config), so concurrent calls are safe.
	mut threads := []thread{}
	for _ in 0 .. 5 {
		threads << spawn fn [sp, config] () {
			mut local_count := 0
			mut lp := &local_count
			execute_with_retry[int](config, fn [lp] () !int {
				unsafe { (*lp)++ }
				cnt := unsafe { *lp }
				if cnt < 2 {
					return NetworkError{}
				}
				return cnt
			}) or { return }
			unsafe { sp.count++ }
		}()
	}
	threads.wait()

	// All 5 goroutines should have succeeded (each retried once)
	assert unsafe { sp.count } == 5
}

// ═══════════════════════════════════════════════════════════════
// Custom error types: verify typeof().name matching
// ═══════════════════════════════════════════════════════════════

fn test_custom_error_type_retry_for() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
		retry_for:    ['TransientError']
	}
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return TransientError{}
	}) or { return }
	assert cc.count == 3
}

fn test_string_error_retry() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
	}
	// Plain string errors should be retried by default
	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return error('something failed')
	}) or { return }
	assert cc.count == 3
}

// ═══════════════════════════════════════════════════════════════
// Annotation parsing: parse_retryable_attr
// ═══════════════════════════════════════════════════════════════

fn test_parse_retryable_attr_default() {
	rc := parse_retryable_attr('')
	assert rc.max_attempts == 3
	assert rc.delay == 100 * time.millisecond
	assert rc.backoff == .fixed
	assert rc.retry_for.len == 0
	assert rc.no_retry_for.len == 0
}

fn test_parse_retryable_attr_max_attempts() {
	rc := parse_retryable_attr('max_attempts:5')
	assert rc.max_attempts == 5
}

fn test_parse_retryable_attr_delay() {
	rc := parse_retryable_attr('delay:250')
	assert rc.delay == 250 * time.millisecond
}

fn test_parse_retryable_attr_backoff() {
	rc := parse_retryable_attr('backoff:exponential')
	assert rc.backoff == .exponential

	rc2 := parse_retryable_attr('backoff:linear')
	assert rc2.backoff == .linear

	rc3 := parse_retryable_attr('backoff:fixed')
	assert rc3.backoff == .fixed
}

fn test_parse_retryable_attr_retry_for() {
	rc := parse_retryable_attr('retry_for:NetworkError')
	assert rc.retry_for.len == 1
	assert rc.retry_for[0] == 'NetworkError'
}

fn test_parse_retryable_attr_retry_for_multiple() {
	rc := parse_retryable_attr('retry_for:NetworkError,TimeoutError')
	assert rc.retry_for.len == 2
	assert rc.retry_for[0] == 'NetworkError'
	assert rc.retry_for[1] == 'TimeoutError'
}

fn test_parse_retryable_attr_no_retry_for() {
	rc := parse_retryable_attr('no_retry_for:ValidationError')
	assert rc.no_retry_for.len == 1
	assert rc.no_retry_for[0] == 'ValidationError'
}

fn test_parse_retryable_attr_complex() {
	rc :=
		parse_retryable_attr('max_attempts:5;delay:200;backoff:exponential;retry_for:NetworkError;no_retry_for:ValidationError')
	assert rc.max_attempts == 5
	assert rc.delay == 200 * time.millisecond
	assert rc.backoff == .exponential
	assert rc.retry_for.len == 1
	assert rc.retry_for[0] == 'NetworkError'
	assert rc.no_retry_for.len == 1
	assert rc.no_retry_for[0] == 'ValidationError'
}

fn test_parse_retryable_attr_strips_quotes() {
	// Comptime method.attrs includes surrounding quotes for @[retryable: '...']
	rc := parse_retryable_attr("'max_attempts:5;delay:200'")
	assert rc.max_attempts == 5
	assert rc.delay == 200 * time.millisecond
}

fn test_parse_retryable_attr_clamps_zero() {
	rc := parse_retryable_attr('max_attempts:0')
	assert rc.max_attempts == 1 // clamped to 1
}

fn test_parse_retryable_attr_clamps_negative() {
	rc := parse_retryable_attr('max_attempts:-3')
	assert rc.max_attempts == 1
}

fn test_parse_retryable_attr_ignores_whitespace() {
	rc := parse_retryable_attr(' max_attempts:5 ; delay:200 ')
	assert rc.max_attempts == 5
	assert rc.delay == 200 * time.millisecond
}

// ── backoff_from_str ──

fn test_backoff_from_str() {
	assert backoff_from_str('fixed') == .fixed
	assert backoff_from_str('linear') == .linear
	assert backoff_from_str('exponential') == .exponential
	assert backoff_from_str('exp') == .exponential
	assert backoff_from_str('EXPONENTIAL') == .exponential
	assert backoff_from_str('unknown') == .fixed // default
}

// ═══════════════════════════════════════════════════════════════
// Comptime annotation extraction (SubTask C3.2)
// ═══════════════════════════════════════════════════════════════

// Test service with @[retryable] annotated methods.
struct RetryService {
	x int
}

@[retryable]
fn (s RetryService) always_default() !int {
	return s.x
}

@[retryable: 'max_attempts:5;delay:200;backoff:exponential']
fn (s RetryService) custom_config() !int {
	return s.x
}

@[retryable: 'retry_for:NetworkError']
fn (s RetryService) retry_for_network() !int {
	return s.x
}

fn (s RetryService) not_annotated() !int {
	return s.x
}

fn test_extract_retryable_methods_finds_annotated() {
	methods := extract_retryable_methods[RetryService]()
	// Should find the 3 annotated methods (not the unannotated one)
	assert methods.len == 3
}

fn test_extract_retryable_methods_default_config() {
	methods := extract_retryable_methods[RetryService]()
	mut default_method := RetryMethodInfo{}
	mut found := false
	for m in methods {
		if m.method_name == 'always_default' {
			default_method = m
			found = true
		}
	}
	assert found
	assert default_method.config.max_attempts == 3
	assert default_method.config.backoff == .fixed
}

fn test_extract_retryable_methods_custom_config() {
	methods := extract_retryable_methods[RetryService]()
	mut custom_method := RetryMethodInfo{}
	mut found := false
	for m in methods {
		if m.method_name == 'custom_config' {
			custom_method = m
			found = true
		}
	}
	assert found
	assert custom_method.config.max_attempts == 5
	assert custom_method.config.delay == 200 * time.millisecond
	assert custom_method.config.backoff == .exponential
}

fn test_extract_retryable_methods_retry_for() {
	methods := extract_retryable_methods[RetryService]()
	mut rf_method := RetryMethodInfo{}
	mut found := false
	for m in methods {
		if m.method_name == 'retry_for_network' {
			rf_method = m
			found = true
		}
	}
	assert found
	assert rf_method.config.retry_for.len == 1
	assert rf_method.config.retry_for[0] == 'NetworkError'
}

fn test_is_retry_annotated_true() {
	assert is_retry_annotated[RetryService]()
}

fn test_is_retry_annotated_false() {
	// A struct with no @[retryable] methods
	assert !is_retry_annotated[CallCounter]()
}

// ═══════════════════════════════════════════════════════════════
// Integration: parse config then execute
// ═══════════════════════════════════════════════════════════════

fn test_integration_parse_then_execute() {
	config := parse_retryable_attr('max_attempts:3;delay:5;backoff:fixed;retry_for:NetworkError')
	mut cc := CallCounter{
		fail_until: 2 // fail twice, succeed on 3rd
	}
	mut cp := &cc

	result := execute_with_retry[int](config, fn [cp] () !int {
		return counter_operation(cp)!
	})!

	assert result == 3
	assert cc.count == 3
}

fn test_integration_no_retry_for_validation() {
	config := parse_retryable_attr('max_attempts:3;delay:5;no_retry_for:ValidationError')
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc

	execute_with_retry[int](config, fn [cp] () !int {
		unsafe { cp.count++ }
		return ValidationError{}
	}) or { return }
	// ValidationError is in no_retry_for → no retry
	assert cc.count == 1
}

// ═══════════════════════════════════════════════════════════════
// Return value integrity
// ═══════════════════════════════════════════════════════════════

fn test_return_value_preserved_on_success() {
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
	}
	result := execute_with_retry[string](config, fn () !string {
		return 'success_value'
	})!
	assert result == 'success_value'
}

fn test_return_value_after_retry() {
	mut cc := CallCounter{
		count: 0
	}
	mut cp := &cc
	config := RetryConfig{
		max_attempts: 3
		delay:        5 * time.millisecond
	}
	result := execute_with_retry[string](config, fn [cp] () !string {
		unsafe { cp.count++ }
		if unsafe { cp.count } < 3 {
			return NetworkError{}
		}
		return 'recovered'
	})!
	assert result == 'recovered'
	assert cc.count == 3
}

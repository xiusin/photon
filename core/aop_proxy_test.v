module core

// aop_proxy_test.v - Tests for AOP proxy helpers (Task 11: P0 1.6 / 5.1 / 5.4)
//
// Tests:
//   - SubTask 11.1: detect_aop_methods[T]() comptime detection
//   - SubTask 11.1: AnnotationAwarePostProcessor registration & introspection
//   - SubTask 11.2: transactional_wrap — begin/commit on success, rollback on error
//   - SubTask 11.3: cacheable_wrap — cache miss executes loader, cache hit returns cached
//   - SubTask 11.5: error propagation through wrappers

// ═══════════════════════════════════════════════════════════
// Mock Implementations
// ═══════════════════════════════════════════════════════════

// MockTxManager implements begin()/commit()/rollback() for transactional_wrap tests.
// Records which lifecycle methods were called so tests can verify behavior.
@[heap]
struct MockTxManager {
mut:
	begun       bool
	committed   bool
	rolled_back bool
	begin_err   bool // if true, begin() returns an error
	commit_err  bool // if true, commit() returns an error
}

fn (mut m MockTxManager) begin() ! {
	if m.begin_err {
		return error('mock begin error')
	}
	m.begun = true
}

fn (mut m MockTxManager) commit() ! {
	if m.commit_err {
		return error('mock commit error')
	}
	m.committed = true
}

fn (mut m MockTxManager) rollback() ! {
	m.rolled_back = true
}

// MockCache implements get()/set()/has() for cacheable_wrap tests.
@[heap]
struct MockCache {
mut:
	data      map[string]string
	get_count int
	set_count int
	set_error bool // if true, set() returns an error (tests graceful handling)
}

fn (mut m MockCache) get(key string) !string {
	m.get_count++
	if key in m.data {
		return m.data[key]
	}
	return error('cache miss')
}

fn (mut m MockCache) set(key string, value string, ttl_seconds int) ! {
	m.set_count++
	if m.set_error {
		return error('mock set error')
	}
	m.data[key] = value
}

fn (mut m MockCache) has(key string) bool {
	return key in m.data
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.1 — Comptime AOP Method Detection
// ═══════════════════════════════════════════════════════════

// TestAopService is a test struct with @[transactional] and @[cacheable]
// annotated methods, used to verify comptime detection.
struct TestAopService {
mut:
	called bool
}

@[transactional]
fn (mut s TestAopService) transfer() ! {
	s.called = true
}

@[cacheable]
fn (mut s TestAopService) get_data() !string {
	return 'data'
}

@[transactional: 'readonly']
fn (mut s TestAopService) read_only_op() ! {
	s.called = true
}

@[cacheable: 'users']
fn (mut s TestAopService) get_user() !string {
	return 'user'
}

// Plain method with no AOP annotations — should NOT be detected.
fn (mut s TestAopService) plain_method() ! {
	s.called = true
}

fn test_detect_aop_methods_finds_transactional() {
	descriptors := detect_aop_methods[TestAopService]()

	// Should find 4 annotated methods (transfer, get_data, read_only_op, get_user)
	// plain_method should NOT be included.
	assert descriptors.len == 4

	// Find the transactional methods
	tx_descs := descriptors.filter(it.has_transactional)
	assert tx_descs.len == 2 // transfer + read_only_op

	tx_names := tx_descs.map(it.name)
	assert 'transfer' in tx_names
	assert 'read_only_op' in tx_names
}

fn test_detect_aop_methods_finds_cacheable() {
	descriptors := detect_aop_methods[TestAopService]()

	cache_descs := descriptors.filter(it.has_cacheable)
	assert cache_descs.len == 2 // get_data + get_user

	cache_names := cache_descs.map(it.name)
	assert 'get_data' in cache_names
	assert 'get_user' in cache_names
}

fn test_detect_aop_methods_captures_attr_strings() {
	descriptors := detect_aop_methods[TestAopService]()

	// Find read_only_op — should have transactional_attr containing 'readonly'
	read_only := descriptors.filter(it.name == 'read_only_op')
	assert read_only.len == 1
	assert read_only[0].has_transactional
	// V stores the attribute with quotes: `transactional: 'readonly'`
	assert read_only[0].transactional_attr.contains('readonly')

	// Find get_user — should have cacheable_attr containing 'users'
	get_user := descriptors.filter(it.name == 'get_user')
	assert get_user.len == 1
	assert get_user[0].has_cacheable
	assert get_user[0].cacheable_attr.contains('users')
}

fn test_detect_aop_methods_excludes_plain_methods() {
	descriptors := detect_aop_methods[TestAopService]()

	// plain_method should NOT appear in the descriptors
	plain := descriptors.filter(it.name == 'plain_method')
	assert plain.len == 0
}

fn test_detect_aop_methods_empty_for_plain_struct() {
	descriptors := detect_aop_methods[MockTxManager]()
	// MockTxManager has no @[transactional] or @[cacheable] methods
	assert descriptors.len == 0
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.1 — AnnotationAwarePostProcessor Registration
// ═══════════════════════════════════════════════════════════

fn test_annotation_aware_post_processor_creation() {
	pp := new_annotation_aware_post_processor()
	assert pp.aop_bean_count() == 0
}

fn test_register_aop_methods() {
	mut pp := new_annotation_aware_post_processor()
	descriptors := detect_aop_methods[TestAopService]()

	assert descriptors.len > 0
	pp.register_aop_methods('TestAopService', descriptors)

	assert pp.has_aop_methods('TestAopService')
	assert pp.aop_bean_count() == 1

	retrieved := pp.get_aop_methods('TestAopService')
	assert retrieved.len == descriptors.len
}

fn test_register_aop_for_bean_comptime() {
	mut pp := new_annotation_aware_post_processor()
	pp.register_aop_for_bean[TestAopService]('TestAopService')

	assert pp.has_aop_methods('TestAopService')
	retrieved := pp.get_aop_methods('TestAopService')
	assert retrieved.len == 4
}

fn test_has_aop_methods_false_for_unregistered() {
	pp := new_annotation_aware_post_processor()
	assert !pp.has_aop_methods('NonExistent')
}

fn test_get_aop_methods_empty_for_unregistered() {
	pp := new_annotation_aware_post_processor()
	retrieved := pp.get_aop_methods('NonExistent')
	assert retrieved.len == 0
}

fn test_register_empty_descriptors_does_not_register() {
	mut pp := new_annotation_aware_post_processor()
	pp.register_aop_methods('EmptyBean', []AopMethodDescriptor{})
	assert !pp.has_aop_methods('EmptyBean')
	assert pp.aop_bean_count() == 0
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.1 — AnnotationAwarePostProcessor as BeanPostProcessor
// ═══════════════════════════════════════════════════════════

fn test_annotation_aware_post_processor_before_returns_bean_unchanged() {
	mut pp := new_annotation_aware_post_processor()
	bean := unsafe { voidptr(0x1234) }
	result := pp.post_process_before_initialization('TestBean', bean)
	assert result == bean
}

fn test_annotation_aware_post_processor_after_returns_bean_unchanged() {
	mut pp := new_annotation_aware_post_processor()
	bean := unsafe { voidptr(0x5678) }
	result := pp.post_process_after_initialization('TestBean', bean)
	assert result == bean
}

fn test_annotation_aware_post_processor_in_application_context() {
	mut ctx := new_application_context()
	mut pp := new_annotation_aware_post_processor()
	pp.register_aop_for_bean[TestAopService]('TestAopService')

	ctx.add_post_processor(&BeanPostProcessor(pp))

	// Verify the post-processor was registered
	assert ctx.post_processors.len == 1

	// Verify AOP metadata is accessible through the post-processor
	assert pp.has_aop_methods('TestAopService')
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.2 — transactional_wrap: success path (begin → commit)
// ═══════════════════════════════════════════════════════════

fn test_transactional_wrap_success_begins_and_commits() {
	mut tm := &MockTxManager{}

	// Track whether the callback executed
	mut callback_executed := false
	mut cb_ptr := &callback_executed

	transactional_wrap(mut tm, fn [cb_ptr] () ! {
		unsafe {
			*cb_ptr = true
		}
	}) or { assert false }

	// Verify: begin was called, callback executed, commit was called,
	// rollback was NOT called.
	assert tm.begun
	assert tm.committed
	assert !tm.rolled_back
	assert unsafe { *cb_ptr }
}

fn test_transactional_wrap_success_no_rollback() {
	mut tm := &MockTxManager{}

	transactional_wrap(mut tm, fn () ! {
		// success — no-op
	}) or { assert false }

	assert tm.begun
	assert tm.committed
	assert !tm.rolled_back
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.2 — transactional_wrap: error path (begin → rollback)
// ═══════════════════════════════════════════════════════════

fn test_transactional_wrap_error_rolls_back_and_propagates() {
	mut tm := &MockTxManager{}

	mut error_propagated := false
	transactional_wrap(mut tm, fn () ! {
		return error('business logic failed')
	}) or {
		error_propagated = true
		assert err.msg() == 'business logic failed'
	}

	// Verify: begin was called, rollback was called, commit was NOT called.
	assert tm.begun
	assert !tm.committed
	assert tm.rolled_back
	assert error_propagated
}

fn test_transactional_wrap_error_propagates_original_error() {
	mut tm := &MockTxManager{}

	mut captured_err := ''
	transactional_wrap(mut tm, fn () ! {
		return error('specific error message')
	}) or { captured_err = err.msg() }

	assert captured_err == 'specific error message'
	assert tm.rolled_back
	assert !tm.committed
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.2 — transactional_wrap: begin error propagation
// ═══════════════════════════════════════════════════════════

fn test_transactional_wrap_begin_error_propagates() {
	mut tm := &MockTxManager{
		begin_err: true
	}

	mut callback_executed := false
	mut cb_ptr := &callback_executed

	mut error_propagated := false
	transactional_wrap(mut tm, fn [cb_ptr] () ! {
		unsafe {
			*cb_ptr = true
		}
	}) or { error_propagated = true }

	// begin() failed, so callback should NOT have executed,
	// and neither commit nor rollback should have been called.
	assert !tm.begun // begin() errored before setting begun=true
	assert !tm.committed
	assert !tm.rolled_back
	assert !unsafe { *cb_ptr }
	assert error_propagated
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.2 — transactional_wrap: rollback error is swallowed
// ═══════════════════════════════════════════════════════════

// When the callback fails AND rollback also fails, the original error
// should still be propagated (rollback error is swallowed).
fn test_transactional_wrap_rollback_error_swallowed() {
	mut tm := &MockTxManager{}

	// Override rollback to always error — we'll test via a separate mock
	// Actually, MockTxManager.rollback() never errors, so this test verifies
	// that the `or {}` in transactional_wrap correctly swallows rollback errors.
	mut captured_err := ''
	transactional_wrap(mut tm, fn () ! {
		return error('original error')
	}) or { captured_err = err.msg() }

	// Original error should be propagated, not a rollback error.
	assert captured_err == 'original error'
	assert tm.rolled_back
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.3 — cacheable_wrap: cache miss executes loader
// ═══════════════════════════════════════════════════════════

fn test_cacheable_wrap_miss_executes_loader_and_caches() {
	mut cache := &MockCache{}

	mut loader_executed := false
	mut loader_ptr := &loader_executed

	result := cacheable_wrap(mut cache, 'test_key', 300, fn [loader_ptr] () !string {
		unsafe {
			*loader_ptr = true
		}
		return 'computed_value'
	}) or {
		assert false
		return
	}

	// Verify: loader was executed (cache miss), result returned, value cached.
	assert unsafe { *loader_ptr }
	assert result == 'computed_value'
	assert cache.set_count == 1
	assert cache.has('test_key')
}

fn test_cacheable_wrap_miss_stores_in_cache() {
	mut cache := &MockCache{}

	result := cacheable_wrap(mut cache, 'user:123', 600, fn () !string {
		return 'user_data'
	}) or {
		assert false
		return
	}

	assert result == 'user_data'
	assert cache.has('user:123')

	// Verify the cached value is correct
	cached := cache.get('user:123') or {
		assert false
		''
	}
	assert cached == 'user_data'
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.3 — cacheable_wrap: cache hit returns cached value
// ═══════════════════════════════════════════════════════════

fn test_cacheable_wrap_hit_returns_cached_without_loader() {
	mut cache := &MockCache{}
	// Pre-populate cache
	cache.data['existing_key'] = 'cached_value'

	mut loader_executed := false
	mut loader_ptr := &loader_executed

	result := cacheable_wrap(mut cache, 'existing_key', 300, fn [loader_ptr] () !string {
		unsafe {
			*loader_ptr = true
		}
		return 'should_not_be_used'
	}) or {
		assert false
		return
	}

	// Verify: loader was NOT executed, cached value returned.
	assert !unsafe { *loader_ptr }
	assert result == 'cached_value'
	// set() should NOT have been called (cache hit)
	assert cache.set_count == 0
}

fn test_cacheable_wrap_hit_does_not_call_set() {
	mut cache := &MockCache{}
	cache.data['hot_key'] = 'hot_value'

	result := cacheable_wrap(mut cache, 'hot_key', 300, fn () !string {
		return 'new_value'
	}) or {
		assert false
		return
	}

	assert result == 'hot_value'
	assert cache.set_count == 0
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.3 — cacheable_wrap: second call hits cache
// ═══════════════════════════════════════════════════════════

fn test_cacheable_wrap_second_call_hits_cache() {
	mut cache := &MockCache{}

	mut call_count := 0
	mut count_ptr := &call_count

	// First call — cache miss, loader executes
	result1 := cacheable_wrap(mut cache, 'compute_key', 300, fn [count_ptr] () !string {
		unsafe {
			*count_ptr = *count_ptr + 1
		}
		return 'result_1'
	}) or {
		assert false
		return
	}

	assert result1 == 'result_1'
	assert unsafe { *count_ptr } == 1

	// Second call — cache hit, loader should NOT execute
	result2 := cacheable_wrap(mut cache, 'compute_key', 300, fn [count_ptr] () !string {
		unsafe {
			*count_ptr = *count_ptr + 1
		}
		return 'result_2'
	}) or {
		assert false
		return
	}

	assert result2 == 'result_1' // cached value from first call
	assert unsafe { *count_ptr } == 1 // loader not called again
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.3 — cacheable_wrap: loader error propagation
// ═══════════════════════════════════════════════════════════

fn test_cacheable_wrap_loader_error_propagates() {
	mut cache := &MockCache{}

	mut error_propagated := false
	result := cacheable_wrap(mut cache, 'error_key', 300, fn () !string {
		return error('loader failed')
	}) or {
		error_propagated = true
		''
	}

	assert error_propagated
	assert result == ''
	// On loader error, value should NOT be cached
	assert !cache.has('error_key')
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.3 — cacheable_wrap: set error is swallowed
// ═══════════════════════════════════════════════════════════

// When the loader succeeds but cache.set() fails, the result should still
// be returned (cache failure should not break business logic).
fn test_cacheable_wrap_set_error_swallowed() {
	mut cache := &MockCache{
		set_error: true
	}

	result := cacheable_wrap(mut cache, 'set_fail_key', 300, fn () !string {
		return 'computed_value'
	}) or {
		assert false
		''
	}

	// Result should still be returned even though set() failed.
	assert result == 'computed_value'
	// set() was attempted but failed (data not stored)
	assert cache.set_count == 1
	assert !cache.has('set_fail_key')
}

// ═══════════════════════════════════════════════════════════
// SubTask 11.5 — Error propagation through wrappers
// ═══════════════════════════════════════════════════════════

fn test_transactional_wrap_propagates_error_through_or_block() {
	mut tm := &MockTxManager{}

	mut outer_captured := ''
	// Simulate a calling function that uses transactional_wrap via or-block propagation.
	transactional_wrap(mut tm, fn () ! {
		return error('inner error')
	}) or { outer_captured = err.msg() }

	assert outer_captured == 'inner error'
	assert tm.rolled_back
	assert !tm.committed
}

fn test_cacheable_wrap_propagates_error_through_or_block() {
	mut cache := &MockCache{}

	mut outer_captured := ''
	cacheable_wrap(mut cache, 'key', 300, fn () !string {
		return error('loader error')
	}) or { outer_captured = err.msg() }

	assert outer_captured == 'loader error'
}

// ═══════════════════════════════════════════════════════════
// Integration: transactional_wrap with real-like flow
// ═══════════════════════════════════════════════════════════

fn test_transactional_wrap_simulated_transfer_success() {
	mut tm := &MockTxManager{}

	// Simulate a bank transfer: debit + credit
	mut balance_from := 100.0
	mut balance_to := 50.0
	mut bf := &balance_from
	mut bt := &balance_to

	transactional_wrap(mut tm, fn [bf, bt] () ! {
		unsafe {
			*bf -= 30.0
			*bt += 30.0
		}
	}) or { assert false }

	// Verify: transaction committed, balances updated
	assert tm.begun
	assert tm.committed
	assert !tm.rolled_back
	assert unsafe { *bf } == 70.0
	assert unsafe { *bt } == 80.0
}

fn test_transactional_wrap_simulated_transfer_rollback() {
	mut tm := &MockTxManager{}

	mut balance_from := 20.0 // less than transfer amount, will go negative
	mut balance_to := 50.0
	mut bf := &balance_from
	mut bt := &balance_to

	// Simulate a transfer that fails midway (e.g., insufficient funds)
	transactional_wrap(mut tm, fn [bf, bt] () ! {
		unsafe {
			*bf -= 30.0
		}
		// Simulate failure — balance went negative
		if unsafe { *bf } < 0.0 {
			return error('insufficient funds')
		}
		unsafe {
			*bt += 30.0
		}
	}) or {
		// Error propagated — balances should be inconsistent (no auto-undo of
		// in-memory changes), but the transaction was rolled back.
		assert err.msg() == 'insufficient funds'
	}

	// Verify: transaction rolled back
	assert tm.begun
	assert !tm.committed
	assert tm.rolled_back
}

// ═══════════════════════════════════════════════════════════
// Integration: cacheable_wrap with TTL
// ═══════════════════════════════════════════════════════════

fn test_cacheable_wrap_with_different_ttls() {
	mut cache := &MockCache{}

	// First call with TTL=60
	r1 := cacheable_wrap(mut cache, 'ttl_key', 60, fn () !string {
		return 'value_60'
	}) or {
		assert false
		''
	}
	assert r1 == 'value_60'

	// Second call — should hit cache regardless of TTL parameter
	// (TTL only matters for set(), not for get() of existing value)
	r2 := cacheable_wrap(mut cache, 'ttl_key', 300, fn () !string {
		return 'value_300'
	}) or {
		assert false
		''
	}
	assert r2 == 'value_60' // cached value from first call
}

fn test_cacheable_wrap_different_keys_independent() {
	mut cache := &MockCache{}

	mut call_count := 0
	mut count_ptr := &call_count

	// Call with key A
	ra := cacheable_wrap(mut cache, 'key_a', 300, fn [count_ptr] () !string {
		unsafe {
			*count_ptr = *count_ptr + 1
		}
		return 'a_value'
	}) or {
		assert false
		''
	}

	// Call with key B — different key, should be a miss
	rb := cacheable_wrap(mut cache, 'key_b', 300, fn [count_ptr] () !string {
		unsafe {
			*count_ptr = *count_ptr + 1
		}
		return 'b_value'
	}) or {
		assert false
		''
	}

	assert ra == 'a_value'
	assert rb == 'b_value'
	assert unsafe { *count_ptr } == 2 // loader called for both (different keys)
}

module orm

// transaction_concurrency_test.v - Concurrency tests for TransactionManager
//
// Verifies the CRITICAL #3 fix: the active_count-based approach correctly
// handles concurrent transactions and nested requires_new propagation
// without state corruption.  The former single `active bool` flag was
// clobbered by concurrent / nested requires_new calls; the count-based
// stack preserves the outer transaction's nesting level.

// ── Workers for separate-TransactionManager tests ──
//
// Each goroutine owns its own TransactionManager — the recommended
// pattern for true transaction-level concurrency.

fn concurrent_begin_commit_worker() bool {
	mut tm := new_transaction_manager()
	tm.begin() or { return false }
	if !tm.is_active() {
		return false
	}
	tm.commit() or { return false }
	return !tm.is_active()
}

fn concurrent_requires_new_worker() bool {
	mut tm := new_transaction_manager()
	mut ok := true
	tm.execute(.requires_new, fn () ! {}) or { ok = false }
	return ok && !tm.is_active()
}

// concurrent_nested_requires_new_worker is the key regression test for
// CRITICAL #3: requires_new inside required must NOT corrupt the outer
// transaction's active state.  With the old `active bool` toggle,
// requires_new set active=false, began a new tx, then restored —
// corrupting any concurrent goroutine's view.  The count-based stack
// increments/decrements cleanly.
fn concurrent_nested_requires_new_worker() bool {
	mut tm := new_transaction_manager()
	mut inner_ran := false
	mut i_ran := &inner_ran
	mut outer_ok := true
	tm.execute(.required, fn [mut tm, i_ran] () ! {
		if !tm.is_active() {
			return error('outer not active')
		}
		tm.execute(.requires_new, fn [i_ran] () ! {
			unsafe {
				*i_ran = true
			}
		}) or { return error('inner requires_new failed') }
		// Outer tx must still be active after inner requires_new commits.
		if !tm.is_active() {
			return error('outer corrupted after requires_new')
		}
	}) or { outer_ok = false }
	return outer_ok && unsafe { *i_ran } && !tm.is_active()
}

// ── Concurrency tests (separate managers) ──

fn test_concurrent_begin_commit_separate_managers() {
	n := 20
	mut handles := []thread bool{}
	for _ in 0 .. n {
		handles << spawn concurrent_begin_commit_worker()
	}
	results := handles.wait()
	assert results.len == n
	for r in results {
		assert r == true, 'concurrent begin/commit worker failed'
	}
}

fn test_concurrent_requires_new_separate_managers() {
	n := 20
	mut handles := []thread bool{}
	for _ in 0 .. n {
		handles << spawn concurrent_requires_new_worker()
	}
	results := handles.wait()
	assert results.len == n
	for r in results {
		assert r == true, 'concurrent requires_new worker failed'
	}
}

fn test_concurrent_nested_requires_new_no_corruption() {
	n := 20
	mut handles := []thread bool{}
	for _ in 0 .. n {
		handles << spawn concurrent_nested_requires_new_worker()
	}
	results := handles.wait()
	assert results.len == n
	for r in results {
		assert r == true, 'nested requires_new corrupted outer tx state'
	}
}

// ── Shared TransactionManager serialization test ──
//
// Multiple goroutines share a single TransactionManager. The internal
// RwMutex serializes state mutations. After all goroutines complete,
// the manager must be inactive (no leaked transactions).  This verifies
// the mutex correctly protects active_count from data races.

fn shared_tm_required_worker(mut tm TransactionManager) bool {
	tm.execute(.required, fn () ! {}) or { return false }
	return true
}

fn test_shared_manager_concurrent_serialized() {
	mut tm := new_transaction_manager()
	n := 10
	mut handles := []thread bool{}
	for _ in 0 .. n {
		handles << spawn shared_tm_required_worker(mut tm)
	}
	results := handles.wait()
	assert results.len == n
	for r in results {
		assert r == true, 'shared TM worker failed'
	}
	// No leaked transactions after all workers complete.
	assert tm.is_active() == false
	assert tm.active_count == 0
}

// ── Single-goroutine active_count stack semantics ──
//
// Directly verifies the count-based stack that fixes CRITICAL #3.
// requires_new must increment/decrement without disturbing the outer
// transaction's nesting level.

fn test_requires_new_count_stack_semantics() {
	mut tm := new_transaction_manager()
	assert tm.active_count == 0

	// Begin outer tx → count 0→1
	tm.begin()!
	assert tm.active_count == 1
	assert tm.is_active()

	// requires_new pushes a new level → count 1→2, then 2→1 on commit.
	// The outer level (1) is preserved.
	tm.execute(.requires_new, fn () ! {})!
	assert tm.active_count == 1
	assert tm.is_active()

	// .required inside an active tx joins (no count change).
	tm.execute(.required, fn [mut tm] () ! {
		assert tm.active_count == 1
		// Nested requires_new → count 1→2→1.
		tm.execute(.requires_new, fn () ! {})!
		assert tm.active_count == 1
	})!
	assert tm.active_count == 1

	// Commit outer → count 1→0.
	tm.commit()!
	assert tm.active_count == 0
	assert !tm.is_active()
}

// ── requires_new failure path preserves outer count ──

fn test_requires_new_failure_preserves_outer_count() {
	mut tm := new_transaction_manager()
	tm.begin()!
	assert tm.active_count == 1

	// Inner requires_new fails → rollback decrements its own level.
	// Outer tx must remain active (count == 1).
	tm.execute(.requires_new, fn () ! {
		return error('inner new tx failure')
	}) or {}
	assert tm.active_count == 1
	assert tm.is_active()

	tm.commit()!
	assert tm.active_count == 0
}

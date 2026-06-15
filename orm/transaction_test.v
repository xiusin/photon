module orm

// transaction_test.v - Tests for TransactionManager
//
// NOTE: V 0.5.1 closures cannot reliably capture and mutate outer variables.
// We use the pointer + unsafe dereference pattern from adapter_test.v.

fn test_transaction_manager_new() {
	tm := new_transaction_manager()
	assert tm.active == false
	assert tm.is_active() == false
}

fn test_transaction_begin_commit() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	assert tm.is_active()
	tm.commit() or { assert false }
	assert tm.is_active() == false
}

fn test_transaction_begin_rollback() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	tm.rollback() or { assert false }
	assert tm.is_active() == false
}

fn test_transaction_double_begin() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	mut failed := false
	tm.begin() or { failed = true }
	assert failed
}

fn test_transaction_required_creates_and_commits() {
	mut tm := new_transaction_manager()
	mut executed := false
	mut ex := &executed
	tm.execute(.required, fn [ex]() ! {
		unsafe { *ex = true }
	}) or { assert false }
	assert unsafe { *ex } == true
	// After execute completes, transaction should be committed (inactive)
	assert tm.is_active() == false
}

fn test_transaction_required_nested_joins_existing() {
	mut tm := new_transaction_manager()
	mut outer_ran := false
	mut inner_ran := false
	mut o_ran := &outer_ran
	mut i_ran := &inner_ran
	tm.execute(.required, fn [mut tm, o_ran, i_ran]() ! {
		unsafe { *o_ran = true }
		// Nested .required should join the existing transaction
		tm.execute(.required, fn [i_ran]() ! {
			unsafe { *i_ran = true }
		}) or { assert false }
	}) or { assert false }
	assert unsafe { *o_ran } == true
	assert unsafe { *i_ran } == true
	assert tm.is_active() == false
}

fn test_transaction_requires_new() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }

	mut executed := false
	mut ex := &executed
	tm.execute(.requires_new, fn [ex]() ! {
		unsafe { *ex = true }
	}) or { assert false }

	assert unsafe { *ex } == true
	assert tm.is_active() // original tx restored
}

fn test_transaction_mandatory_without_tx() {
	mut tm := new_transaction_manager()
	mut failed := false
	tm.execute(.mandatory, fn () ! {}) or { failed = true }
	assert failed
}

fn test_transaction_mandatory_with_tx() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	mut failed := false
	tm.execute(.mandatory, fn () ! {}) or { failed = true }
	assert !failed
}

fn test_transaction_never_with_tx() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	mut failed := false
	tm.execute(.never, fn () ! {}) or { failed = true }
	assert failed
}

fn test_transaction_never_without_tx() {
	mut tm := new_transaction_manager()
	mut failed := false
	tm.execute(.never, fn () ! {}) or { failed = true }
	assert !failed
}

fn test_transaction_supports() {
	mut tm := new_transaction_manager()
	mut failed := false
	tm.execute(.supports, fn () ! {}) or { failed = true }
	assert !failed
	tm.begin() or { assert false }
	tm.execute(.supports, fn () ! {}) or { failed = true }
	assert !failed
}

fn test_transaction_not_supported() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	tm.execute(.not_supported, fn () ! {}) or { assert false }
	assert tm.is_active() // original tx restored
}

fn test_transactional_convenience() {
	mut ran := false
	mut r := &ran
	transactional(fn [r]() ! {
		unsafe { *r = true }
	}) or { assert false }
	assert unsafe { *r }
}

fn test_transaction_rollback_on_failure() {
	mut tm := new_transaction_manager()
	mut failed := false
	tm.execute(.required, fn () ! {
		return error('business error')
	}) or { failed = true }
	assert failed
	assert tm.is_active() == false
}

// ── Edge cases ──

fn test_transaction_required_nested_inner_failure() {
	// Outer .required creates tx, inner .required fails.
	// Error propagates to outer → outer rolls back.
	mut tm := new_transaction_manager()
	mut outer_ran := false
	mut o_ran := &outer_ran
	mut failed := false
	tm.execute(.required, fn [mut tm, o_ran]() ! {
		unsafe { *o_ran = true }
		tm.execute(.required, fn () ! {
			return error('inner failure')
		})!
	}) or { failed = true }
	assert unsafe { *o_ran } == true
	assert failed
	assert tm.is_active() == false // outer rolled back
}

fn test_transaction_requires_new_inside_required() {
	// Outer .required creates tx, inner .requires_new suspends it,
	// creates/commits its own tx, then restores the outer tx.
	// A .mandatory call after verifies the outer tx is still active.
	mut tm := new_transaction_manager()
	mut outer_ran := false
	mut inner_ran := false
	mut o_ran := &outer_ran
	mut i_ran := &inner_ran
	tm.execute(.required, fn [mut tm, o_ran, i_ran]() ! {
		unsafe { *o_ran = true }
		// .requires_new suspends outer, creates independent tx
		tm.execute(.requires_new, fn [i_ran]() ! {
			unsafe { *i_ran = true }
		}) or { assert false }
		// Verify outer tx was restored (mandatory requires active tx)
		tm.execute(.mandatory, fn () ! {}) or { assert false }
	}) or { assert false }
	assert unsafe { *o_ran } == true
	assert unsafe { *i_ran } == true
	assert tm.is_active() == false // outer committed after f() returned ok
}

fn test_transaction_requires_new_inside_required_inner_failure() {
	// Outer .required creates tx, inner .requires_new fails.
	// Inner rolls back its own tx and restores outer tx.
	// Error propagates → outer rolls back too.
	mut tm := new_transaction_manager()
	mut outer_ran := false
	mut o_ran := &outer_ran
	mut failed := false
	tm.execute(.required, fn [mut tm, o_ran]() ! {
		unsafe { *o_ran = true }
		tm.execute(.requires_new, fn () ! {
			return error('inner new tx failure')
		})!
	}) or { failed = true }
	assert unsafe { *o_ran } == true
	assert failed
	assert tm.is_active() == false
}

fn test_transaction_nested_savepoint_rollback() {
	// Outer .required creates tx, inner .nested creates a savepoint.
	// Inner fails → savepoint rolls back, error propagates to outer
	// → outer rolls back too.
	mut tm := new_transaction_manager()
	mut outer_ran := false
	mut o_ran := &outer_ran
	mut failed := false
	tm.execute(.required, fn [mut tm, o_ran]() ! {
		unsafe { *o_ran = true }
		tm.execute(.nested, fn () ! {
			return error('savepoint failure')
		})!
	}) or { failed = true }
	assert unsafe { *o_ran } == true
	assert failed
	assert tm.is_active() == false // outer rolled back
	assert tm.savepoint_count == 0 // savepoint was decremented
}

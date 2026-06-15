module orm

// transaction_test.v - Tests for TransactionManager

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
	err := tm.begin() or { 'error' }
	assert err == 'error'
}

fn test_transaction_required() {
	mut tm := new_transaction_manager()
	mut executed := false
	tm.execute(.required, fn [mut executed]() ! {
		assert tm.is_active()
		executed = true
	}) or { assert false }
	assert executed == true
	assert tm.is_active() == false
}

fn test_transaction_requires_new() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }

	mut executed := false
	tm.execute(.requires_new, fn [mut executed]() ! {
		executed = true
	}) or { assert false }

	assert executed == true
	assert tm.is_active() // original tx restored
}

fn test_transaction_mandatory_without_tx() {
	mut tm := new_transaction_manager()
	err := tm.execute(.mandatory, fn () ! {}) or { 'error' }
	assert err == 'error'
}

fn test_transaction_mandatory_with_tx() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	err := tm.execute(.mandatory, fn () ! {}) or { 'should_not_error' }
	assert err == 'should_not_error'
}

fn test_transaction_never_with_tx() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	err := tm.execute(.never, fn () ! {}) or { 'error' }
	assert err == 'error'
}

fn test_transaction_never_without_tx() {
	mut tm := new_transaction_manager()
	tm.execute(.never, fn () ! {}) or { assert false }
}

fn test_transaction_supports() {
	mut tm := new_transaction_manager()
	tm.execute(.supports, fn () ! {}) or { assert false } // works without tx
	tm.begin() or { assert false }
	tm.execute(.supports, fn () ! {}) or { assert false } // works with tx
}

fn test_transaction_not_supported() {
	mut tm := new_transaction_manager()
	tm.begin() or { assert false }
	tm.execute(.not_supported, fn () ! {}) or { assert false }
	assert tm.is_active() // original tx restored
}

fn test_transactional_convenience() {
	mut ran := false
	transactional(fn [mut ran]() ! {
		ran = true
	}) or { assert false }
	assert ran
}

fn test_transaction_rollback_on_failure() {
	mut tm := new_transaction_manager()
	err := tm.execute(.required, fn () ! {
		return error('business error')
	}) or { 'rolled_back' }
	assert err == 'rolled_back'
	assert tm.is_active() == false
}

module orm

// transaction_attributes_test.v - Tests for transaction attribute execution (Task B3)
//
// Verifies that isolation (B3.1), readonly (B3.2), timeout (B3.3),
// and rollback_for/no_rollback_for (B3.4) attributes are actually
// executed, not just parsed and stored.
//
// Uses callback-based TransactionManager (no real DB connection needed).
// V 0.5.1 closures capture by value, so we use the pointer + unsafe
// dereference pattern from transaction_test.v for state tracking.

import time

// ── Custom error types for rollback_for/no_rollback_for tests ──
//
// Each error's msg() includes the type name so that
// error_type_matches() can match via err.msg().contains(type_name)
// as a fallback when typeof(err).name doesn't return the dynamic type.

struct NetworkError {
	msg string
}

fn (e NetworkError) msg() string {
	return e.msg
}

fn (e NetworkError) code() int {
	return 1001
}

struct ValueError {
	msg string
}

fn (e ValueError) msg() string {
	return e.msg
}

fn (e ValueError) code() int {
	return 1002
}

struct TransientError {
	msg string
}

fn (e TransientError) msg() string {
	return e.msg
}

fn (e TransientError) code() int {
	return 1003
}

// ── Tracker struct for callback invocations ──

struct AttrTracker {
mut:
	begin_called    bool
	commit_called   bool
	rollback_called bool
	exec_sqls       []string
}

// ═══════════════════════════════════════════════════════════════
// B3.1: Isolation level execution
// ═══════════════════════════════════════════════════════════════

fn test_isolation_read_uncommitted_sqlite() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	begin_fn := fn [t] (c voidptr) ! {
		unsafe { t.begin_called = true }
	}
	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, begin_fn, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn
	tm.driver = .sqlite

	tm.begin_with_options(TransactionOptions{
		isolation: .read_uncommitted
	})!

	assert unsafe { t.begin_called }
	// SQLite read_uncommitted → PRAGMA read_uncommitted = 1
	assert unsafe { t.exec_sqls.len } == 1
	assert unsafe { t.exec_sqls[0] } == 'PRAGMA read_uncommitted = 1'

	tm.commit()!
}

fn test_isolation_serializable_sqlite() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn
	tm.driver = .sqlite

	tm.begin_with_options(TransactionOptions{
		isolation: .serializable
	})!

	// SQLite serializable → PRAGMA read_uncommitted = 0
	assert unsafe { t.exec_sqls.len } == 1
	assert unsafe { t.exec_sqls[0] } == 'PRAGMA read_uncommitted = 0'

	tm.commit()!
}

fn test_isolation_read_committed_pg() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn
	tm.driver = .pg

	tm.begin_with_options(TransactionOptions{
		isolation: .read_committed
	})!

	// PostgreSQL → SET TRANSACTION ISOLATION LEVEL READ COMMITTED
	assert unsafe { t.exec_sqls.len } == 1
	assert unsafe { t.exec_sqls[0] } == 'SET TRANSACTION ISOLATION LEVEL READ COMMITTED'

	tm.commit()!
}

fn test_isolation_repeatable_read_mysql() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn
	tm.driver = .mysql

	tm.begin_with_options(TransactionOptions{
		isolation: .repeatable_read
	})!

	assert unsafe { t.exec_sqls.len } == 1
	assert unsafe { t.exec_sqls[0] } == 'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ'

	tm.commit()!
}

fn test_isolation_default_no_sql() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn
	tm.driver = .sqlite

	tm.begin_with_options(TransactionOptions{
		isolation: .default_
	})!

	// default_ isolation → no SQL executed
	assert unsafe { t.exec_sqls.len } == 0

	tm.commit()!
}

fn test_isolation_no_exec_fn_still_works() {
	// Without exec_fn, isolation is stored but not executed via SQL.
	mut tm := new_transaction_manager()
	// exec_fn is nil by default
	tm.begin_with_options(TransactionOptions{
		isolation: .read_uncommitted
	})!
	assert tm.isolation == .read_uncommitted
	tm.commit()!
}

// ═══════════════════════════════════════════════════════════════
// B3.2: Readonly enforcement
// ═══════════════════════════════════════════════════════════════

fn test_readonly_allows_select() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	// SELECT should succeed in a readonly transaction
	tm.exec_within('SELECT * FROM users', [])!

	assert unsafe { t.exec_sqls.len } == 1
	assert unsafe { t.exec_sqls[0] } == 'SELECT * FROM users'

	tm.commit()!
}

fn test_readonly_allows_lowercase_select() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	// Lowercase SELECT should also succeed (case-insensitive check)
	tm.exec_within('select * from users where id = 1', [])!

	assert unsafe { t.exec_sqls.len } == 1

	tm.commit()!
}

fn test_readonly_blocks_insert() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	mut failed := false
	mut err_msg := ''
	tm.exec_within('INSERT INTO users VALUES (1)', []) or {
		failed = true
		err_msg = err.msg()
	}
	assert failed
	assert err_msg.contains('readonly transaction cannot perform write operation')

	// No SQL should have been executed
	assert unsafe { t.exec_sqls.len } == 0

	tm.commit()!
}

fn test_readonly_blocks_update() {
	mut tm := new_transaction_manager()
	tm.exec_fn = fn (c voidptr, sql_stmt string) ! {}

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	mut failed := false
	mut err_msg := ''
	tm.exec_within('UPDATE users SET name = "bob"', []) or {
		failed = true
		err_msg = err.msg()
	}
	assert failed
	assert err_msg.contains('readonly transaction cannot perform write operation')

	tm.commit()!
}

fn test_readonly_blocks_delete() {
	mut tm := new_transaction_manager()
	tm.exec_fn = fn (c voidptr, sql_stmt string) ! {}

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	mut failed := false
	tm.exec_within('DELETE FROM users WHERE id = 1', []) or { failed = true }
	assert failed

	tm.commit()!
}

fn test_readonly_blocks_drop() {
	mut tm := new_transaction_manager()
	tm.exec_fn = fn (c voidptr, sql_stmt string) ! {}

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	mut failed := false
	tm.exec_within('DROP TABLE users', []) or { failed = true }
	assert failed

	tm.commit()!
}

fn test_readonly_blocks_create() {
	mut tm := new_transaction_manager()
	tm.exec_fn = fn (c voidptr, sql_stmt string) ! {}

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	mut failed := false
	tm.exec_within('CREATE TABLE temp (id INT)', []) or { failed = true }
	assert failed

	tm.commit()!
}

fn test_readonly_blocks_alter() {
	mut tm := new_transaction_manager()
	tm.exec_fn = fn (c voidptr, sql_stmt string) ! {}

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	mut failed := false
	tm.exec_within('ALTER TABLE users ADD COLUMN email TEXT', []) or { failed = true }
	assert failed

	tm.commit()!
}

fn test_readonly_blocks_truncate() {
	mut tm := new_transaction_manager()
	tm.exec_fn = fn (c voidptr, sql_stmt string) ! {}

	tm.begin_with_options(TransactionOptions{
		readonly: true
	})!

	mut failed := false
	tm.exec_within('TRUNCATE TABLE users', []) or { failed = true }
	assert failed

	tm.commit()!
}

fn test_readonly_disabled_allows_writes() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn

	// readonly: false (default) → writes allowed
	tm.begin_with_options(TransactionOptions{
		readonly: false
	})!

	tm.exec_within('INSERT INTO users VALUES (1)', [])!

	assert unsafe { t.exec_sqls.len } == 1

	tm.commit()!
}

// ═══════════════════════════════════════════════════════════════
// B3.3: Timeout
// ═══════════════════════════════════════════════════════════════

fn test_timeout_triggers_on_check() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)

	tm.begin_with_options(TransactionOptions{
		timeout_ms: 100
	})!

	// Sleep beyond the timeout
	time.sleep(200 * time.millisecond)

	mut failed := false
	mut err_msg := ''
	tm.check_timeout() or {
		failed = true
		err_msg = err.msg()
	}
	assert failed
	assert err_msg.contains('transaction timeout')
	// Auto-rollback should have been called
	assert unsafe { t.rollback_called }
	assert !tm.is_active()
}

fn test_timeout_not_triggered() {
	mut tm := new_transaction_manager()

	tm.begin_with_options(TransactionOptions{
		timeout_ms: 1000
	})!

	// Check immediately — should not timeout
	tm.check_timeout()!

	assert tm.is_active()

	tm.commit()!
}

fn test_timeout_triggers_on_exec() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)
	tm.exec_fn = fn (c voidptr, sql_stmt string) ! {}

	tm.begin_with_options(TransactionOptions{
		timeout_ms: 100
	})!

	time.sleep(200 * time.millisecond)

	mut failed := false
	mut err_msg := ''
	tm.exec_within('SELECT 1', []) or {
		failed = true
		err_msg = err.msg()
	}
	assert failed
	assert err_msg.contains('transaction timeout')
	assert unsafe { t.rollback_called }
	assert !tm.is_active()
}

fn test_timeout_zero_means_no_timeout() {
	mut tm := new_transaction_manager()
	tm.exec_fn = fn (c voidptr, sql_stmt string) ! {}

	// timeout_ms = 0 means no timeout
	tm.begin_with_options(TransactionOptions{
		timeout_ms: 0
	})!

	time.sleep(50 * time.millisecond)

	// Should not timeout
	tm.check_timeout()!
	tm.exec_within('SELECT 1', [])!

	assert tm.is_active()

	tm.commit()!
}

fn test_timeout_exec_within_within_limit() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn

	tm.begin_with_options(TransactionOptions{
		timeout_ms: 5000
	})!

	// Execute within the timeout — should succeed
	tm.exec_within('SELECT 1', [])!

	assert unsafe { t.exec_sqls.len } == 1
	assert tm.is_active()

	tm.commit()!
}

// ═══════════════════════════════════════════════════════════════
// B3.4: rollback_for / no_rollback_for
// ═══════════════════════════════════════════════════════════════

fn test_rollback_for_matching() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)
	tm.begin()!

	attr := TransactionAttribute{
		rollback_for: ['NetworkError']
	}
	err := IError(NetworkError{msg: 'NetworkError: connection refused'})

	tm.rollback_if_needed(err, attr)!

	assert unsafe { t.rollback_called }
	assert !tm.is_active()
}

fn test_rollback_for_mismatch_no_rollback() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)
	tm.begin()!

	attr := TransactionAttribute{
		rollback_for: ['NetworkError']
	}
	// ValueError does not match NetworkError → no rollback
	err := IError(ValueError{msg: 'ValueError: invalid input'})

	tm.rollback_if_needed(err, attr)!

	assert !unsafe { t.rollback_called }
	// Transaction should still be active
	assert tm.is_active()

	tm.commit()!
}

fn test_no_rollback_for_matching() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)
	tm.begin()!

	attr := TransactionAttribute{
		no_rollback_for: ['TransientError']
	}
	// TransientError matches no_rollback_for → no rollback
	err := IError(TransientError{msg: 'TransientError: temporary failure'})

	tm.rollback_if_needed(err, attr)!

	assert !unsafe { t.rollback_called }
	assert tm.is_active()

	tm.commit()!
}

fn test_no_rollback_for_mismatch_rollback() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)
	tm.begin()!

	attr := TransactionAttribute{
		no_rollback_for: ['TransientError']
	}
	// NetworkError does not match no_rollback_for → rollback (default)
	err := IError(NetworkError{msg: 'NetworkError: connection refused'})

	tm.rollback_if_needed(err, attr)!

	assert unsafe { t.rollback_called }
	assert !tm.is_active()
}

fn test_default_rollback_on_any_error() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)
	tm.begin()!

	// No rollback_for / no_rollback_for → rollback on any error
	attr := TransactionAttribute{}
	err := IError(ValueError{msg: 'ValueError: something went wrong'})

	tm.rollback_if_needed(err, attr)!

	assert unsafe { t.rollback_called }
	assert !tm.is_active()
}

fn test_rollback_for_with_string_error() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)
	tm.begin()!

	attr := TransactionAttribute{
		rollback_for: ['NetworkError']
	}
	// String error with type name in message
	err := error('NetworkError: connection refused')

	tm.rollback_if_needed(err, attr)!

	assert unsafe { t.rollback_called }
	assert !tm.is_active()
}

fn test_no_rollback_for_takes_precedence_over_rollback_for() {
	mut tracker := AttrTracker{}
	mut t := &tracker

	rollback_fn := fn [t] (c voidptr) ! {
		unsafe { t.rollback_called = true }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, rollback_fn)
	tm.begin()!

	// Both rollback_for and no_rollback_for contain the error type.
	// no_rollback_for is checked first → no rollback.
	attr := TransactionAttribute{
		rollback_for: ['NetworkError']
		no_rollback_for: ['NetworkError']
	}
	err := IError(NetworkError{msg: 'NetworkError: connection refused'})

	tm.rollback_if_needed(err, attr)!

	assert !unsafe { t.rollback_called }
	assert tm.is_active()

	tm.commit()!
}

fn test_rollback_if_needed_no_active_transaction() {
	mut tm := new_transaction_manager()
	// No active transaction — rollback_if_needed should be a no-op
	attr := TransactionAttribute{
		rollback_for: ['NetworkError']
	}
	err := IError(NetworkError{msg: 'NetworkError: fail'})

	tm.rollback_if_needed(err, attr) or {
		assert false, 'should not error when no active transaction'
	}
	assert !tm.is_active()
}

// ═══════════════════════════════════════════════════════════════
// TransactionAttribute.to_options() conversion
// ═══════════════════════════════════════════════════════════════

fn test_transaction_attribute_to_options() {
	attr := TransactionAttribute{
		propagation: .requires_new
		isolation: .read_committed
		readonly: true
		timeout_ms: 5000
		rollback_for: ['NetworkError']
		no_rollback_for: ['TransientError']
	}
	opts := attr.to_options()
	assert opts.isolation == .read_committed
	assert opts.readonly
	assert opts.timeout_ms == 5000
	assert opts.rollback_for.len == 1
	assert opts.rollback_for[0] == 'NetworkError'
	assert opts.no_rollback_for.len == 1
	assert opts.no_rollback_for[0] == 'TransientError'
}

fn test_to_options_with_begin_with_options() {
	// End-to-end: parse annotation → to_options → begin_with_options
	attr := parse_transactional_attr('isolation:read_uncommitted;readonly;timeout:5000')
	opts := attr.to_options()

	mut tracker := AttrTracker{}
	mut t := &tracker

	exec_fn := fn [t] (c voidptr, sql_stmt string) ! {
		unsafe { t.exec_sqls << sql_stmt }
	}

	mut tm := new_transaction_manager_with_conn(unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { nil })
	tm.exec_fn = exec_fn
	tm.driver = .sqlite

	tm.begin_with_options(opts)!

	assert unsafe { t.exec_sqls.len } == 1
	assert unsafe { t.exec_sqls[0] } == 'PRAGMA read_uncommitted = 1'
	assert tm.read_only == true
	assert tm.timeout_ms == 5000

	tm.commit()!
}

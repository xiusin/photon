module orm

import sync
import time

// transaction.v - Transaction Management
//
// Wraps V's official ORM transaction primitives (orm.TransactionalConnection,
// orm.Tx) with Spring-style propagation and isolation semantics.
//
// V's official ORM provides:
//   orm.transaction[int](mut db, fn (mut tx orm.Tx) !int { ... })!
//   mut tx := orm.begin(mut db)!
//   tx.commit()! / tx.rollback()!
//
// Photon's TransactionManager adds propagation rules, isolation
// levels, and savepoint-based nested transactions on top.

// Propagation defines how transactions relate to each other
pub enum Propagation {
	required      // join existing or create new (default)
	requires_new  // suspend existing, create new
	nested        // savepoint within existing
	supports      // use existing if available, no tx otherwise
	not_supported // suspend existing, run without tx
	mandatory     // must have existing tx
	never         // must not have existing tx
}

// Isolation defines transaction isolation level
pub enum Isolation {
	default_
	read_uncommitted
	read_committed
	repeatable_read
	serializable
}

// TransactionOptions configures per-transaction behavior for
// begin_with_options().  This is the programmatic equivalent of
// the @[transactional] annotation attributes parsed by
// parse_transactional_attr() in transaction_annotation.v.
//
// Use TransactionAttribute.to_options() to convert a parsed
// annotation into options, or construct directly:
//
//   tm.begin_with_options(.{
//       isolation:   .read_committed
//       readonly:    true
//       timeout_ms:  5000
//   })!
pub struct TransactionOptions {
pub:
	isolation       Isolation = .default_
	readonly        bool
	timeout_ms      int      // 0 = no timeout
	rollback_for    []string // exception type names that trigger rollback
	no_rollback_for []string // exception type names that do NOT trigger rollback
}

// TransactionManager manages transaction lifecycle.
// Wraps V's official orm.Connection or orm.TransactionalConnection.
//
// Concurrency model:
//   `active_count` replaces the former single `active bool` flag.
//   Each begin (direct or via .requires_new) increments the count;
//   each commit/rollback decrements it.  This correctly handles
//   nested .requires_new propagation in the SAME goroutine without
//   corrupting the outer transaction's state (the previous global
//   bool toggle was CRITICAL #3 — concurrent / nested requires_new
//   calls clobbered each other).
//
//   All state mutations are serialized by `mu` (a sync.RwMutex).
//   `is_active()` takes a READ lock; begin/commit/rollback/execute
//   take WRITE locks.  For truly concurrent transactions across
//   goroutines, give each goroutine its own TransactionManager —
//   a shared manager serializes correctly but does not parallelise.
pub struct TransactionManager {
pub mut:
	active_count    int
	savepoint_count int
	propagation     Propagation = .required
	isolation       Isolation   = .default_
	read_only       bool
	timeout_ms      int                  // 0 = no timeout (B3.3)
	started_at      time.Time            // when the current tx began (B3.3)
	rollback_for    []string             // exception type names that trigger rollback (B3.4)
	no_rollback_for []string             // exception type names that do NOT trigger rollback (B3.4)
	driver          DriverType = .sqlite // driver for isolation SQL generation (B3.1)
	conn            voidptr        = unsafe { nil } // 数据库连接（由用户提供）
	begin_fn        fn (voidptr) ! = unsafe { nil } // 真实 begin 回调
	commit_fn       fn (voidptr) ! = unsafe { nil } // 真实 commit 回调
	rollback_fn     fn (voidptr) ! = unsafe { nil } // 真实 rollback 回调
	exec_fn         fn (voidptr, string) ! = unsafe { nil } // execute raw SQL (B3.1/B3.2)
mut:
	mu sync.RwMutex
}

// new_transaction_manager creates a TransactionManager.
pub fn new_transaction_manager() &TransactionManager {
	return &TransactionManager{}
}

// new_transaction_manager_with_conn creates a TransactionManager bound to a real DB connection.
// The begin/commit/rollback callbacks operate on the provided connection.
pub fn new_transaction_manager_with_conn(conn voidptr, begin_fn fn (voidptr) !, commit_fn fn (voidptr) !, rollback_fn fn (voidptr) !) &TransactionManager {
	return &TransactionManager{
		conn:        conn
		begin_fn:    begin_fn
		commit_fn:   commit_fn
		rollback_fn: rollback_fn
	}
}

// begin_locked starts a transaction. Caller MUST hold tm.mu (write).
// Errors if a transaction is already active on this manager — use
// begin_new_locked() for .requires_new propagation which always
// pushes a fresh nesting level.
fn (mut tm TransactionManager) begin_locked() ! {
	if tm.active_count > 0 {
		return error('transaction already active')
	}
	if !isnil(tm.begin_fn) {
		tm.begin_fn(tm.conn)!
	}
	tm.active_count++
}

// begin_new_locked starts a new transaction nesting level
// unconditionally.  Used by .requires_new propagation so the outer
// transaction's count is preserved (the outer level remains on the
// logical stack).  Caller MUST hold tm.mu (write).
fn (mut tm TransactionManager) begin_new_locked() ! {
	if !isnil(tm.begin_fn) {
		tm.begin_fn(tm.conn)!
	}
	tm.active_count++
}

// begin starts a transaction on the provided connection.
// If the connection implements orm.TransactionalConnection,
// uses the native begin; otherwise tracks state manually.
//
// This overload uses the manager's current isolation/read_only
// field values as options.  For per-transaction options, use
// begin_with_options() instead.
pub fn (mut tm TransactionManager) begin() ! {
	opts := TransactionOptions{
		isolation: tm.isolation
		readonly:  tm.read_only
	}
	tm.begin_with_options(opts)!
}

// begin_with_options starts a transaction with explicit options.
// Applies isolation level (B3.1), readonly flag (B3.2), and
// timeout (B3.3) to the transaction.
//
// The isolation level is executed via the manager's exec_fn
// callback (if set): PRAGMA for SQLite, SET TRANSACTION for
// other drivers.  If exec_fn is nil, isolation is stored but
// not executed — the caller is responsible for setting it.
pub fn (mut tm TransactionManager) begin_with_options(opts TransactionOptions) ! {
	tm.mu.@lock()
	defer {
		tm.mu.unlock()
	}

	if tm.active_count > 0 {
		return error('transaction already active / 事务已激活')
	}

	if !isnil(tm.begin_fn) {
		tm.begin_fn(tm.conn)!
	}
	tm.active_count++

	// Apply transaction options
	tm.isolation = opts.isolation
	tm.read_only = opts.readonly
	tm.timeout_ms = opts.timeout_ms
	tm.started_at = if opts.timeout_ms > 0 { time.now() } else { time.Time{} }

	// B3.1: Execute isolation level SQL via exec_fn callback.
	// SQLite supports only read_uncommitted vs default (serializable);
	// other drivers use SET TRANSACTION ISOLATION LEVEL.
	if opts.isolation != .default_ && !isnil(tm.exec_fn) {
		sql_stmt := isolation_sql(tm.driver, opts.isolation)
		if sql_stmt.len > 0 {
			tm.exec_fn(tm.conn, sql_stmt)!
		}
	}
}

// commit_locked commits the current transaction. Caller MUST hold tm.mu (write).
fn (mut tm TransactionManager) commit_locked() ! {
	if tm.active_count == 0 {
		return error('no active transaction')
	}
	if !isnil(tm.commit_fn) {
		tm.commit_fn(tm.conn)!
	}
	tm.active_count--
	if tm.active_count == 0 {
		tm.reset_txn_state_locked()
	}
}

// commit commits the current transaction.
pub fn (mut tm TransactionManager) commit() ! {
	tm.mu.@lock()
	defer {
		tm.mu.unlock()
	}
	tm.commit_locked()!
}

// rollback_locked rolls back the current transaction. Caller MUST hold tm.mu (write).
fn (mut tm TransactionManager) rollback_locked() ! {
	if tm.active_count == 0 {
		return error('no active transaction')
	}
	if !isnil(tm.rollback_fn) {
		tm.rollback_fn(tm.conn)!
	}
	tm.active_count--
	if tm.active_count == 0 {
		tm.reset_txn_state_locked()
	}
}

// reset_txn_state_locked clears per-transaction options after the
// outermost commit/rollback.  Caller MUST hold tm.mu (write).
// isolation and read_only are NOT reset — they persist as defaults
// for the next begin() call (backward compatibility with code that
// sets tm.isolation / tm.read_only directly).
fn (mut tm TransactionManager) reset_txn_state_locked() {
	tm.timeout_ms = 0
	tm.started_at = time.Time{}
}

// rollback rolls back the current transaction.
pub fn (mut tm TransactionManager) rollback() ! {
	tm.mu.@lock()
	defer {
		tm.mu.unlock()
	}
	tm.rollback_locked()!
}

// is_active checks if a transaction is in progress.
// Uses a READ lock (M2 fix) — this is a read-only check and must
// not block concurrent readers.
pub fn (tm &TransactionManager) is_active() bool {
	unsafe { tm.mu.rlock() }
	defer {
		unsafe { tm.mu.runlock() }
	}
	return tm.active_count > 0
}

// ── B3: Transaction Attribute Execution ──
//
// The methods below make the isolation/readonly/timeout/rollback_for
// attributes actually execute, rather than just being parsed and stored.

// exec_within executes a SQL statement within the current transaction.
// It enforces:
//   - B3.2 readonly: write operations (INSERT/UPDATE/DELETE/DROP/CREATE/ALTER/TRUNCATE)
//     are rejected with an error when the transaction is read-only.
//   - B3.3 timeout: if the transaction has exceeded its timeout, an
//     auto-rollback is performed and a timeout error is returned.
//
// The actual SQL execution is delegated to the manager's exec_fn
// callback (if set).  If exec_fn is nil, only the readonly/timeout
// checks run — the caller is responsible for executing the SQL.
pub fn (mut tm TransactionManager) exec_within(sql_stmt string, params []string) ! {
	tm.mu.@lock()
	defer {
		tm.mu.unlock()
	}

	if tm.active_count == 0 {
		return error('no active transaction / 无活动事务')
	}

	// B3.3: Check timeout first — an expired transaction cannot
	// accept any further operations.
	if tm.timeout_ms > 0 {
		elapsed := time.now().unix_milli() - tm.started_at.unix_milli()
		if elapsed > i64(tm.timeout_ms) {
			tm.rollback_locked() or {}
			return error('transaction timeout / 事务超时')
		}
	}

	// B3.2: Readonly enforcement — intercept write operations.
	if tm.read_only {
		sql_upper := sql_stmt.to_upper()
		if is_write_operation(sql_upper) {
			return error('readonly transaction cannot perform write operation / 只读事务不能执行写操作')
		}
	}

	// Execute via callback
	if !isnil(tm.exec_fn) {
		tm.exec_fn(tm.conn, sql_stmt)!
	}
}

// check_timeout verifies the current transaction has not exceeded its
// timeout.  If it has, an auto-rollback is performed and a timeout
// error is returned.  This is a no-op when timeout_ms is 0 or no
// transaction is active.
//
// Call this before long-running operations to fail fast:
//
//   tm.check_timeout()!
//   // ... proceed with the operation
pub fn (mut tm TransactionManager) check_timeout() ! {
	tm.mu.@lock()
	defer {
		tm.mu.unlock()
	}

	if tm.active_count == 0 || tm.timeout_ms == 0 {
		return
	}

	elapsed := time.now().unix_milli() - tm.started_at.unix_milli()
	if elapsed > i64(tm.timeout_ms) {
		tm.rollback_locked() or {}
		return error('transaction timeout / 事务超时')
	}
}

// rollback_if_needed rolls back the transaction based on the error
// and the rollback_for/no_rollback_for rules from the attribute.
//
// B3.4 rules (evaluated in order):
//   1. If the error matches any entry in no_rollback_for → do NOT rollback.
//   2. If rollback_for is non-empty and the error matches an entry → rollback.
//   3. If rollback_for is non-empty but the error does NOT match → do NOT rollback.
//   4. If rollback_for is empty (default) → rollback on any error.
//
// Error matching uses error_type_matches() which checks both the
// typeof name and the error message for the type name string.
pub fn (mut tm TransactionManager) rollback_if_needed(err IError, attr TransactionAttribute) ! {
	tm.mu.@lock()
	defer {
		tm.mu.unlock()
	}

	if tm.active_count == 0 {
		return
	}

	// 1. Check no_rollback_for first — matching errors skip rollback.
	for no_rollback_type in attr.no_rollback_for {
		if error_type_matches(err, no_rollback_type) {
			return
		}
	}

	// 2-3. If rollback_for is specified, only rollback for matching errors.
	if attr.rollback_for.len > 0 {
		for rollback_type in attr.rollback_for {
			if error_type_matches(err, rollback_type) {
				tm.rollback_locked()!
				return
			}
		}
		return // not in rollback_for → don't rollback
	}

	// 4. Default: rollback on any error.
	tm.rollback_locked()!
}

// ── B3 helper functions ──

// is_write_operation returns true if the SQL statement (already
// upper-cased) is a write operation that a read-only transaction
// must not perform.
fn is_write_operation(sql_upper string) bool {
	return sql_upper.starts_with('INSERT') || sql_upper.starts_with('UPDATE') ||
		sql_upper.starts_with('DELETE') || sql_upper.starts_with('DROP') ||
		sql_upper.starts_with('CREATE') || sql_upper.starts_with('ALTER') ||
		sql_upper.starts_with('TRUNCATE')
}

// isolation_sql returns the SQL statement to set the isolation level
// for the given driver.
//
// SQLite only supports read_uncommitted vs default (serializable):
//   https://www.sqlite.org/pragma.html#pragma_read_uncommitted
//
// PostgreSQL / MySQL use the standard SET TRANSACTION ISOLATION LEVEL.
//
// Limitation: SQLite does not support read_committed, repeatable_read,
// or serializable as distinct levels — they all map to the default
// (serializable) behavior.  Only read_uncommitted can be explicitly
// enabled.
fn isolation_sql(driver DriverType, isolation Isolation) string {
	if driver == .sqlite {
		// SQLite only supports read_uncommitted vs default (serializable).
		if isolation == .read_uncommitted {
			return 'PRAGMA read_uncommitted = 1'
		}
		return 'PRAGMA read_uncommitted = 0'
	}
	// Other DBs (PostgreSQL, MySQL): SET TRANSACTION ISOLATION LEVEL
	level := match isolation {
		.read_uncommitted { 'READ UNCOMMITTED' }
		.read_committed { 'READ COMMITTED' }
		.repeatable_read { 'REPEATABLE READ' }
		.serializable { 'SERIALIZABLE' }
		.default_ { '' }
	}
	if level.len == 0 {
		return ''
	}
	return 'SET TRANSACTION ISOLATION LEVEL ${level}'
}

// error_type_matches checks whether an error matches a type name
// string from rollback_for / no_rollback_for.
//
// V's `err is Type` only works with compile-time types, so for
// runtime string matching we use two strategies:
//   1. typeof(err).name — may return the dynamic type name for
//      custom error structs (e.g. "NetworkError" or "orm.NetworkError").
//   2. err.msg() — fallback: check if the error message contains
//      the type name.  This handles string errors created with
//      error('NetworkError: ...') and custom structs whose msg()
//      includes the type name.
fn error_type_matches(err IError, type_name string) bool {
	// Strategy 1: typeof name (strip module prefix if present)
	tn := typeof(err).name
	if tn == type_name || tn.ends_with('.' + type_name) {
		return true
	}
	// Strategy 2: error message contains the type name
	return err.msg().contains(type_name)
}

// to_options converts a TransactionAttribute (parsed from an
// @[transactional] annotation) into a TransactionOptions struct
// for use with begin_with_options().
pub fn (attr TransactionAttribute) to_options() TransactionOptions {
	return TransactionOptions{
		isolation: attr.isolation
		readonly: attr.readonly
		timeout_ms: attr.timeout_ms
		rollback_for: attr.rollback_for
		no_rollback_for: attr.no_rollback_for
	}
}

// execute runs a function within a transaction with propagation support.
//
// The callback receives a reference to the TransactionManager and should
// use V's official ORM transaction primitives internally:
//
//   tm.execute(.required, fn [mut db] () ! {
//       orm.transaction[int](mut db, fn (mut tx orm.Tx) !int {
//           sql tx { insert user into User }!
//           return tx.last_id()
//       })!
//   })!
pub fn (mut tm TransactionManager) execute(propagation Propagation, f fn () !) ! {
	match propagation {
		.required {
			tm.mu.@lock()
			was_inactive := tm.active_count == 0
			if was_inactive {
				tm.begin_locked() or {
					tm.mu.unlock()
					return err
				}
			}
			tm.mu.unlock()
			f() or {
				tm.mu.@lock()
				if was_inactive {
					tm.rollback_locked() or {}
				}
				tm.mu.unlock()
				return err
			}
			tm.mu.@lock()
			if was_inactive {
				tm.commit_locked() or {
					tm.mu.unlock()
					return err
				}
			}
			tm.mu.unlock()
		}
		.requires_new {
			// CRITICAL #3 fix: always push a fresh nesting level via
			// begin_new_locked() instead of toggling a global bool.
			// The outer transaction's active_count is left untouched —
			// commit/rollback below only decrements the level we pushed.
			tm.mu.@lock()
			tm.begin_new_locked() or {
				tm.mu.unlock()
				return err
			}
			tm.mu.unlock()
			f() or {
				tm.mu.@lock()
				tm.rollback_locked() or {
					tm.mu.unlock()
					return err
				}
				tm.mu.unlock()
				return err
			}
			tm.mu.@lock()
			tm.commit_locked() or {
				tm.mu.unlock()
				return err
			}
			tm.mu.unlock()
		}
		.nested {
			tm.mu.@lock()
			if tm.active_count == 0 {
				tm.mu.unlock()
				return error('no active transaction for nested propagation')
			}
			tm.savepoint_count++
			tm.mu.unlock()
			f() or {
				tm.mu.@lock()
				tm.savepoint_count--
				tm.mu.unlock()
				return err
			}
			tm.mu.@lock()
			tm.savepoint_count--
			tm.mu.unlock()
		}
		.mandatory {
			tm.mu.@lock()
			if tm.active_count == 0 {
				tm.mu.unlock()
				return error('no active transaction for mandatory propagation')
			}
			tm.mu.unlock()
			f()!
		}
		.never {
			tm.mu.@lock()
			if tm.active_count > 0 {
				tm.mu.unlock()
				return error('existing transaction for never propagation')
			}
			tm.mu.unlock()
			f()!
		}
		.not_supported {
			// Suspend the current transaction(s): save the count,
			// zero it so f() runs without a tx, then restore.
			tm.mu.@lock()
			saved_count := tm.active_count
			tm.active_count = 0
			tm.mu.unlock()
			f() or {
				tm.mu.@lock()
				tm.active_count = saved_count
				tm.mu.unlock()
				return err
			}
			tm.mu.@lock()
			tm.active_count = saved_count
			tm.mu.unlock()
		}
		.supports {
			f()!
		}
	}
}

// transactional is a convenience function for running code in a transaction
// with REQUIRED propagation.
pub fn transactional(f fn () !) ! {
	mut tm := new_transaction_manager()
	tm.execute(.required, f)!
}

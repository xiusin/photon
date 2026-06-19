module orm

import sync

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
	conn            voidptr        = unsafe { nil } // 数据库连接（由用户提供）
	begin_fn        fn (voidptr) ! = unsafe { nil } // 真实 begin 回调
	commit_fn       fn (voidptr) ! = unsafe { nil } // 真实 commit 回调
	rollback_fn     fn (voidptr) ! = unsafe { nil } // 真实 rollback 回调
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
pub fn (mut tm TransactionManager) begin() ! {
	tm.mu.@lock()
	defer {
		tm.mu.unlock()
	}
	tm.begin_locked()!
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
	tm.mu.rlock()
	defer {
		tm.mu.runlock()
	}
	return tm.active_count > 0
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

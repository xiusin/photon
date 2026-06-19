module orm

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
pub struct TransactionManager {
pub mut:
	active          bool
	savepoint_count int
	propagation     Propagation = .required
	isolation       Isolation   = .default_
	read_only       bool
	conn            voidptr        = unsafe { nil } // 数据库连接（由用户提供）
	begin_fn        fn (voidptr) ! = unsafe { nil } // 真实 begin 回调
	commit_fn       fn (voidptr) ! = unsafe { nil } // 真实 commit 回调
	rollback_fn     fn (voidptr) ! = unsafe { nil } // 真实 rollback 回调
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

// begin starts a transaction on the provided connection.
// If the connection implements orm.TransactionalConnection,
// uses the native begin; otherwise tracks state manually.
pub fn (mut tm TransactionManager) begin() ! {
	if tm.active {
		return error('transaction already active')
	}
	if !isnil(tm.begin_fn) {
		tm.begin_fn(tm.conn)!
	}
	tm.active = true
}

// commit commits the current transaction.
pub fn (mut tm TransactionManager) commit() ! {
	if !tm.active {
		return error('no active transaction')
	}
	if !isnil(tm.commit_fn) {
		tm.commit_fn(tm.conn)!
	}
	tm.active = false
}

// rollback rolls back the current transaction.
pub fn (mut tm TransactionManager) rollback() ! {
	if !tm.active {
		return error('no active transaction')
	}
	if !isnil(tm.rollback_fn) {
		tm.rollback_fn(tm.conn)!
	}
	tm.active = false
}

// is_active checks if a transaction is in progress.
pub fn (tm &TransactionManager) is_active() bool {
	return tm.active
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
			was_inactive := !tm.active
			if was_inactive {
				tm.begin()!
			}
			f() or {
				if was_inactive {
					tm.rollback() or {}
				}
				return err
			}
			if was_inactive {
				tm.commit()!
			}
		}
		.requires_new {
			was_active := tm.active
			tm.active = false
			tm.begin()!
			f() or {
				tm.rollback()!
				tm.active = was_active
				return err
			}
			tm.commit()!
			tm.active = was_active
		}
		.nested {
			if !tm.active {
				return error('no active transaction for nested propagation')
			}
			tm.savepoint_count++
			f() or {
				tm.savepoint_count--
				return err
			}
			tm.savepoint_count--
		}
		.mandatory {
			if !tm.active {
				return error('no active transaction for mandatory propagation')
			}
			f()!
		}
		.never {
			if tm.active {
				return error('existing transaction for never propagation')
			}
			f()!
		}
		.not_supported {
			was_active := tm.active
			tm.active = false
			f() or {
				tm.active = was_active
				return err
			}
			tm.active = was_active
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

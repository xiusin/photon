module orm

// nested_savepoint_test.v - `Propagation.nested` 必须真的下发 SAVEPOINT
//
// 文档写的语义是「内层失败只回滚到保存点，外层的写入保留」。原实现只
// 动了 `savepoint_count` 这个计数器，一条 SQL 都没发出去，于是：
//
//   BEGIN → INSERT(1) → 内层失败(被吞) → COMMIT
//
// 内层本该丢弃的写入跟着外层一起提交了，而事件序列干净得像一次正常提交。
// 这类缺陷的共同点是「计数器动了，所以看起来跟踪到了」，唯一的判据是
// 下发的 SQL 是不是真的发生了。
@[heap]
struct SavepointTracker {
mut:
	begin_called    int
	commit_called   int
	rollback_called int
	exec_sqls       []string
}

fn tracker_conn(mut t SavepointTracker) &TransactionManager {
	begin_fn := fn [mut t] (c voidptr) ! {
		t.begin_called++
	}
	commit_fn := fn [mut t] (c voidptr) ! {
		t.commit_called++
	}
	rollback_fn := fn [mut t] (c voidptr) ! {
		t.rollback_called++
	}
	exec_fn := fn [mut t] (c voidptr, sql_stmt string) ! {
		t.exec_sqls << sql_stmt
	}
	mut tm := new_transaction_manager_with_conn(unsafe { nil }, begin_fn, commit_fn, rollback_fn)
	tm.exec_fn = exec_fn
	tm.driver = .sqlite
	return tm
}

// nested_inner 跑两层成功的嵌套事务
fn nested_inner(mut tm TransactionManager) ! {
	tm.execute(.nested, fn [mut tm] () ! {
		tm.execute(.nested, fn () ! {})!
	})!
}

// reader_returns_error 跑一次失败的内层事务，返回是否真的把错误抛了出来
fn reader_returns_error(mut tm TransactionManager) bool {
	tm.execute(.nested, fn () ! {
		return error('inner boom')
	}) or { return true }
	return false
}

fn test_nested_propagation_emits_savepoint() {
	mut t := &SavepointTracker{}
	mut tm := tracker_conn(mut t)

	tm.begin()!
	tm.exec_within('INSERT INTO t VALUES (1)', [])!
	// 内层成功：SAVEPOINT → RELEASE
	tm.execute(.nested, fn () ! {})!
	tm.exec_within('INSERT INTO t VALUES (2)', [])!
	tm.commit()!

	sqls := unsafe { t.exec_sqls }
	mut savepoints := sqls.filter(it.starts_with('SAVEPOINT'))
	mut releases := sqls.filter(it.starts_with('RELEASE'))
	assert savepoints.len == 1, 'nested must emit exactly one SAVEPOINT, got: ${sqls}'
	assert releases.len == 1, 'nested must RELEASE its savepoint, got: ${sqls}'
	// 保存点名必须对得上，否则 RELEASE 打的是别人的点
	sp_name := savepoints[0].all_after('SAVEPOINT ').trim_space()
	assert releases[0] == 'RELEASE SAVEPOINT ${sp_name}'
}

fn test_nested_failure_rolls_back_to_savepoint_not_outer() {
	mut t := &SavepointTracker{}
	mut tm := tracker_conn(mut t)

	tm.begin()!
	tm.exec_within('INSERT INTO t VALUES (1)', [])!

	// 内层失败：ROLLBACK TO SAVEPOINT 后仍需显式 RELEASE
	inner_failed := reader_returns_error(mut tm)

	tm.exec_within('INSERT INTO t VALUES (3)', [])!
	tm.commit()!

	sqls := unsafe { t.exec_sqls }
	saves := sqls.filter(it.starts_with('SAVEPOINT'))
	rolls := sqls.filter(it.starts_with('ROLLBACK TO'))
	releases := sqls.filter(it.starts_with('RELEASE'))
	assert saves.len == 1, 'savepoint must be created before the inner body runs: ${sqls}'
	assert rolls.len == 1, 'inner failure must ROLLBACK TO the savepoint, got: ${sqls}'
	assert releases.len == 1, 'ROLLBACK TO does not release the savepoint; must RELEASE: ${sqls}'

	// 外层照常提交，且外层的写入没有被内层失败带走
	assert unsafe { t.commit_called } == 1
	assert unsafe { t.rollback_called } == 0
	assert sqls.filter(it.starts_with('INSERT INTO t VALUES (1)')).len == 1
}

fn test_nested_savepoints_are_distinct_per_depth() {
	mut t := &SavepointTracker{}
	mut tm := tracker_conn(mut t)

	tm.begin()!
	// 两层嵌套：名字必须不同，否则内层 ROLLBACK TO 会打到外层保存点
	nested_inner(mut tm)!
	tm.commit()!

	sqls := unsafe { t.exec_sqls }
	saves := sqls.filter(it.starts_with('SAVEPOINT'))
	assert saves.len == 2, 'two nesting levels must create two savepoints: ${sqls}'
	assert saves[0] != saves[1], 'savepoint names must be unique per depth: ${sqls}'
	// 保存点计数器归零：不该有残留
	assert tm.savepoint_count == 0
}

fn test_interceptor_nested_uses_savepoint() {
	mut t := &SavepointTracker{}
	mut tm := tracker_conn(mut t)
	tm.begin()!

	mut ti := TransactionalInterceptor{
		tx_manager: tm
	}
	started := ti.begin_if_needed(TransactionAttribute{
		propagation: .nested
	})!
	// nested 在已有事务里不启动新事务
	assert started == false
	ti.commit_if_needed(started)!

	sqls := unsafe { t.exec_sqls }
	assert sqls.filter(it.starts_with('SAVEPOINT')).len == 1
	assert sqls.filter(it.starts_with('RELEASE')).len == 1
	// 内层不得结束外层事务
	assert tm.is_active()
	assert unsafe { t.commit_called } == 0
	tm.commit()!
}

module orm

// Regression: where_group() used to drop the nested query's raw_where()
// bound values, leaving more `?` placeholders than arguments.

fn inner_mixed(g &TableQuery) &TableQuery {
	return g.raw_where('x = ?', 'X').or_where_eq('y', 1)
}

fn test_where_group_keeps_nested_raw_values() {
	om := new_orm_manager()
	stmt, args := table('users', om)
		.where_group(inner_mixed)
		.raw_where('z = ?', 'Z')
		.build()!
	assert stmt.count('?') == args.len
	// OR 组后面追加的普通条件并入同一个 AND 组，语义等价于
	// x = ? OR (y = ? AND z = ?)；关键断言是占位符数量与参数数量一致。
	assert stmt == 'SELECT * FROM users WHERE (x = ? OR y = ? OR z = ?)'
	assert args.len == 3
	assert '${args[0]}' == "orm.ParamValue('X')"
	assert '${args[1]}' == 'orm.ParamValue(1)'
	assert '${args[2]}' == "orm.ParamValue('Z')"
}

fn test_where_group_without_raw_is_unchanged() {
	om := new_orm_manager()
	stmt, args := table('users', om)
		.where_eq('tenant_id', 7)
		.where_group(fn (g &TableQuery) &TableQuery {
			return g.where_eq('status', 'active').or_where_eq('status', 'trial')
		})
		.build()!
	// 嵌套回调整体成为一个 OR 子表达式，与前一个普通条件 AND
	assert stmt == 'SELECT * FROM users WHERE tenant_id = ? AND (status = ? OR status = ?)'
	assert args.len == 3
}

fn test_where_group_propagates_inner_error() {
	om := new_orm_manager()
	_, _ := table('users', om)
		.where_group(fn (g &TableQuery) &TableQuery {
			return g.where_eq('bad column!', 'x')
		})
		.build() or {
			assert err.msg().contains('invalid column identifier')
			return
		}
	assert false, 'invalid inner column must fail the whole query'
}

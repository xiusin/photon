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
	// 嵌套回调整体是**一个括号内的子表达式**，后面的普通条件在括号外与之 AND。
	//
	// 这里原来的期望值是 `(x = ? OR y = ? OR z = ?)` —— 把 `z = ?` 也并进了
	// OR 括号，于是过滤条件互相放宽。断言「占位符数量与参数数量一致」对这个
	// 错误是免疫的：两者确实都是 3。语义正确的形态必须把 z 挡在括号外。
	assert stmt == 'SELECT * FROM users WHERE (x = ? OR y = ?) AND z = ?'
	assert args.len == 3
	// `${}` 已经在 orm 包里，打印出来的 struct str() 不带包名前缀 ——
	// 断言里再写一遍 `orm.` 会永远失败（而且和被测语义无关）。
	assert '${args[0]}' == "ParamValue('X')"
	assert '${args[1]}' == 'ParamValue(1)'
	assert '${args[2]}' == "ParamValue('Z')"
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

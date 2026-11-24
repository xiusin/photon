module orm

// table_set_operator_test.v —— `in` / `not in` 在通用入口上的可达性
//
// 这两条用例盯着同一句话：**同一个谓词，在专用入口和通用入口上答案必须一致。**
//
// where_in() / where_not_in() 早就把「空列表 = 恒假」「不许自成一组」这些事想清楚了
// （见 table_not_in_test.v）。而 where() / or_where() 的运算符白名单里从来没有
// in / not in —— 于是 `.where('status', 'not in', v)` 回的是「不支持的操作符」，
// 一个合法的 SQL 谓词在通用入口上根本不可达。
//
// 修法不是把 in 塞进白名单（单值占位符表达不了集合），而是**换一句报错**：把调用方
// 直接引到能表达它的那个方法上。所以每条断言的一半是「必须仍然失败」，另一半是
// 「失败信息必须指对路」。

// build_error 跑一次 build 并返回错误文本（无错误时返回 ''）。
fn so_build_error(tq &TableQuery) string {
	tq.to_sql() or { return err.msg() }
	return ''
}

fn so_table() &TableQuery {
	om := new_orm_manager()
	return table('users', om)
}

// `in` 不能被当成单值比较：`column in ?` 不是任何数据库认的语法。
// 关键是报错要说出「该用 where_in()」，而不是只说「不支持」。
fn test_where_in_operator_points_to_where_in() {
	msg := so_build_error(so_table().where('status', 'in', ParamValue('a')))
	assert msg != '', 'where(.., "in", ..) 必须失败：单值占位符表达不了集合'
	assert msg.contains('where_in'), '报错必须指向 where_in()：${msg}'
	assert !msg.contains('unsupported operator'), '不该再落到「不支持的操作符」：${msg}'
}

fn test_where_not_in_operator_points_to_where_not_in() {
	msg := so_build_error(so_table().where('status', 'not in', ParamValue('a')))
	assert msg != '', 'where(.., "not in", ..) 必须失败'
	assert msg.contains('where_not_in'), '报错必须指向 where_not_in()：${msg}'
	assert !msg.contains('unsupported operator'), '不该再落到「不支持的操作符」：${msg}'
}

// or_where 没有 in 变体，所以它必须把调用方引到 where_group()，
// 而不是让调用方去猜「为什么 where_in 能用、or_where 不能」。
fn test_or_where_in_points_to_where_group() {
	msg := so_build_error(so_table().or_where('status', 'in', ParamValue('a')))
	assert msg != '', 'or_where(.., "in", ..) 必须失败'
	assert msg.contains('where_group'), '报错必须指向 where_group()：${msg}'
	assert msg.contains('where_in'), '报错要说出真正要用的方法：${msg}'
}

// 大小写与空白都规范化后再判，别让 'NOT IN' 掉回「不支持的操作符」。
fn test_set_operator_matching_is_case_insensitive() {
	for op in ['IN', ' not in ', 'Not In'] {
		msg := so_build_error(so_table().where('status', op, ParamValue('a')))
		assert msg != '', '${op} 必须失败'
		assert msg.contains('where_'), '${op} 应指向 where_in/where_not_in：${msg}'
	}
}

// 真正的写法仍然可用：专用入口给出一条恒假，通用入口给出「请用专用入口」——
// 两个口径指向同一件事。
fn test_dedicated_entry_is_the_only_way() {
	sql_stmt, args :=
		so_table().where_eq('tenant_id', 7).where_in('status', []ParamValue{}).to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE tenant_id = ? AND 1 = 0'
	assert args.len == 1
}

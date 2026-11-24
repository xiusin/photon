module orm

// where_not_in() 的三处「排除条件反而放宽结果集」的缺陷。
//
// 三处都不在「语法」层面，SQL 长得对、跑得动，只是语义反了：
//   1. 空列表原样 no-op —— 「什么都不排除」= 全表；
//   2. 自成一个 group，被组间连接规则 OR 掉 —— 「排除」变成「多返回」；
//   3. build_where 只用列名判 IN 去重，同列 IN + NOT IN 后一句覆盖前一句的
//      占位符，绑定值整体错位一格。

fn tni_sql(tq &TableQuery) (string, []ParamValue) {
	return tq.to_sql() or { 'ERR: ${err}', []ParamValue{} }
}

fn tni_describe(values []ParamValue) []string {
	mut out := []string{cap: values.len}
	for v in values {
		out << match v {
			string { 'str:${v}' }
			int { 'int:${v}' }
			i64 { 'i64:${v}' }
			bool { 'bool:${v}' }
			f64 { 'f64:${v}' }
		}
	}
	return out
}

fn tni_table() &TableQuery {
	mut om := new_orm_manager()
	return table('users', om)
}

// 空列表 = 什么都不匹配。NOT IN () 是语法错误，而「什么都没排除」是
// 完全相反的意思：过滤条件被反过来执行了。
fn test_not_in_empty_list_matches_nothing() {
	q := tni_table().where_eq('tenant_id', ParamValue(int(7))).where_not_in('status', []ParamValue{})
	qsql, args := tni_sql(q)
	assert qsql.contains('1 = 0')
	assert tni_describe(args) == ['int:7']
}

// 只有 not_in 一个子句、且列表为空时，也必须是一条恒假条件，
// 而不是「没有 WHERE」。
fn test_not_in_empty_list_alone_matches_nothing() {
	q := tni_table().where_not_in('status', []ParamValue{})
	qsql, args := tni_sql(q)
	assert qsql.contains('1 = 0')
	assert args.len == 0
}

// 纯 AND 链里夹一条 not_in：三条条件必须全部 AND 起来。
// 旧实现让 not_in 自己成一组，被组间 OR 连接规则吞掉。
fn test_not_in_stays_inside_and_chain() {
	q := tni_table()
		.where_eq('tenant_id', ParamValue(int(7)))
		.where_not_in('status', [ParamValue('deleted'), ParamValue('banned')])
		.where_eq('active', ParamValue(true))
	qsql, args := tni_sql(q)
	assert qsql.contains('tenant_id = ?')
	assert qsql.contains('status NOT IN (?, ?)')
	assert qsql.contains('active = ?')
	assert !qsql.contains(' OR ')
	assert tni_describe(args) == ['int:7', 'str:deleted', 'str:banned', 'bool:true']
}

// not_in 出现在链首、后面再跟普通条件。
fn test_not_in_first_then_and_condition() {
	q := tni_table()
		.where_not_in('status', [ParamValue('x'), ParamValue('y')])
		.where_eq('active', ParamValue(true))
	qsql, args := tni_sql(q)
	assert qsql.contains('status NOT IN (?, ?)')
	assert !qsql.contains(' OR ')
	assert qsql.contains(" OR ") == false
	// 顺序：NOT IN 的两个值在前，后面那条条件在后。
	assert tni_describe(args) == ['str:x', 'str:y', 'bool:true']
}

// 同一个列上 IN 与 NOT IN 并存（「状态在这些里、但不在那些里」）。
// 只按列名去重时，后一句会把前一句的占位符整段重写掉：
// SQL 里只剩 NOT IN，绑定值却还是三组 —— 后续参数全部错位一格。
fn test_in_and_not_in_on_same_column_keep_both() {
	q := tni_table()
		.where_in('status', [ParamValue('a'), ParamValue('b')])
		.where_not_in('status', [ParamValue('c')])
		.where_eq('tenant_id', ParamValue(int(9)))
	qsql, args := tni_sql(q)
	assert qsql.contains('status IN (?, ?)')
	assert qsql.contains('status NOT IN (?)')
	assert qsql.contains('tenant_id = ?')
	assert qsql.count('?') == args.len
	assert tni_describe(args) == ['str:a', 'str:b', 'str:c', 'int:9']
}

// 反过来：NOT IN 在前、IN 在后，同样两边都要留下。
fn test_not_in_then_in_on_same_column_keep_both() {
	q := tni_table()
		.where_not_in('status', [ParamValue('c')])
		.where_in('status', [ParamValue('a')])
		.where_eq('tenant_id', ParamValue(int(9)))
	qsql, args := tni_sql(q)
	assert qsql.contains('status NOT IN (?)')
	assert qsql.contains('status IN (?)')
	assert qsql.count('?') == args.len
	assert tni_describe(args) == ['str:c', 'str:a', 'int:9']
}

// 和 or_where() 混用：OR 备选组只能挂在它自己那一组里，
// not_in 是独立过滤，不许被并进括号。
fn test_not_in_is_not_absorbed_by_or_group() {
	q := tni_table()
		.where_eq('tenant_id', ParamValue(int(7)))
		.or_where_eq('owner_id', ParamValue(int(7)))
		.where_not_in('status', [ParamValue('deleted')])
	qsql, args := tni_sql(q)
	assert qsql.contains('(owner_id = ?)')
	assert qsql.contains('status NOT IN (?)')
	assert !qsql.contains('(owner_id = ? OR')
	assert tni_describe(args) == ['int:7', 'int:7', 'str:deleted']
}

// 非法列名依然报错，不被静默吞掉。
fn test_not_in_invalid_column_still_errors() {
	q := tni_table().where_not_in('bad column', [ParamValue('x')])
	qsql, _ := tni_sql(q)
	assert qsql.starts_with('ERR:')
}

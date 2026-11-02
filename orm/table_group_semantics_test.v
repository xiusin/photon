module orm

// table_group_semantics_test.v — 分组渲染的唯一规则：**已加的条件不能被放宽**。
//
// 原来分组之间的连接规则是「两个都不是 OR 组就用 OR 连」，于是只要某个
// 子句自己另起了一个分组（`where_in()` 和纯 AND 的 `where_group()` 都会），
// 前面所有过滤就被 OR 掉：
//
//   where_eq('tenant_id', 7).where_in('status', ['a','b'])
//   → WHERE tenant_id = ? OR status IN (?, ?)      ← 租户隔离失效
//
// 另一半是 `where*()` 无条件写进尾组，于是 or_where 之后的条件会被并进
// OR 括号，把一个 AND 过滤变成备选值。
//
// 新规则：组间一律 AND；OR 只能由 or_where*() 显式打开，且只作用于它自己的
// 括号。这里为每种组合固定一条断言。

fn gs_builder() &TableQuery {
	return table('users', unsafe { nil })
}

fn test_in_does_not_widen_prior_filters() {
	stmt, args := gs_builder()
		.where_eq('tenant_id', 7)
		.where_in('status', [ParamValue('a'), ParamValue('b')])
		.where_eq('active', true)
		.build()!
	assert stmt == 'SELECT * FROM users WHERE tenant_id = ? AND status IN (?, ?) AND active = ?'
	assert args.len == 4
}

fn test_plain_and_group_does_not_widen_prior_filters() {
	stmt, _ := gs_builder()
		.where_eq('a', 1)
		.where_group(fn (g &TableQuery) &TableQuery {
			return g.where_eq('x', 1).where_eq('y', 2)
		})
		.where_eq('c', 3)
		.build()!
	assert stmt == 'SELECT * FROM users WHERE a = ? AND x = ? AND y = ? AND c = ?'
}

fn test_and_filter_after_or_is_not_absorbed() {
	stmt, _ := gs_builder()
		.where_eq('a', 1)
		.or_where_eq('b', 2)
		.where_eq('c', 3)
		.build()!
	assert stmt == 'SELECT * FROM users WHERE a = ? AND (b = ?) AND c = ?'
}

fn test_filter_after_or_group_stays_outside_parentheses() {
	stmt, _ := gs_builder()
		.where_eq('tenant_id', 7)
		.or_where_eq('status', 'active')
		.where_eq('deleted', false)
		.build()!
	assert stmt == 'SELECT * FROM users WHERE tenant_id = ? AND (status = ?) AND deleted = ?'
}

fn test_or_alternatives_still_share_one_group() {
	stmt, args := gs_builder()
		.where_eq('tenant_id', 7)
		.or_where_eq('status', 'active')
		.or_where_eq('status', 'trial')
		.build()!
	assert stmt == 'SELECT * FROM users WHERE tenant_id = ? AND (status = ? OR status = ?)'
	assert args.len == 3
}

fn test_or_where_group_keeps_its_parentheses() {
	stmt, args := gs_builder()
		.where_eq('tenant_id', 7)
		.where_group(fn (g &TableQuery) &TableQuery {
			return g.where_eq('status', 'active').or_where_eq('status', 'trial')
		})
		.where_eq('deleted', false)
		.build()!
	assert stmt == 'SELECT * FROM users WHERE tenant_id = ? AND (status = ? OR status = ?) AND deleted = ?'
	assert args.len == 4
}

// has_top_level_or 判断 WHERE 子句里是否有括号外的 OR。
// 组间一律 AND，OR 只允许出现在 or_where*() 自己那对括号里。
fn has_top_level_or(stmt string) bool {
	where_idx := stmt.index(' WHERE ') or { return false }
	where_clause := stmt[where_idx + 7..]
	mut depth := 0
	mut i := 0
	for i < where_clause.len {
		ch := where_clause[i]
		if ch == `(` {
			depth++
		} else if ch == `)` {
			depth--
		} else if depth == 0 && ch == ` ` {
			if i + 4 <= where_clause.len && where_clause[i + 1..i + 4] == 'OR ' {
				return true
			}
		}
		i++
	}
	return false
}

fn test_top_level_or_detector() {
	assert has_top_level_or('SELECT * FROM t WHERE a = ? OR b = ?')
	assert !has_top_level_or('SELECT * FROM t WHERE a = ? AND (b = ? OR c = ?)')
	assert !has_top_level_or('SELECT * FROM t WHERE a = ?')
}

fn test_placeholders_always_match_args() {
	// 组合轰炸：任何组合下渲染出的 `?` 数量都必须等于参数数量。
	cases := [
		gs_builder().where_in('x', [ParamValue('a'), ParamValue('b')]).where_eq('y', 1),
		gs_builder().where_eq('a', 1).or_where_eq('b', 2).where_in('c', [ParamValue('z')]),
		gs_builder().where_group(fn (g &TableQuery) &TableQuery {
			return g.where_eq('x', 1).or_where_eq('y', 2)
		}).where_in('z', [ParamValue('q')]),
		gs_builder().raw_where('lower(email) = ?', 'A').where_in('id', [ParamValue(1), ParamValue(2)]),
		gs_builder().where_null('d').where_in('id', [ParamValue(1)]).or_where_eq('t', 2),
	]
	for i, q in cases {
		stmt, args := q.build()!
		assert stmt.count('?') == args.len, 'case ${i}: ${stmt} has ${stmt.count('?')} ? but ${args.len} args'
		assert !has_top_level_or(stmt), 'case ${i}: unparenthesised OR at top level: ${stmt}'
	}
}

fn test_empty_in_short_circuits_instead_of_widening() {
	stmt, args := gs_builder().where_eq('tenant_id', 7).where_in('id', []ParamValue{}).build()!
	assert stmt == 'SELECT * FROM users WHERE tenant_id = ? AND 1 = 0'
	assert args.len == 1
}

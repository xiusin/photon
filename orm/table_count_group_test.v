module orm

// table_count_group_test.v —— table().count() 在 GROUP BY 上必须包子查询。
//
// 缺陷形状：count_view() 无条件把投影换成 `COUNT(*)` 并保留 GROUP BY。
// 那条 SQL 返回的是「每组一行」，而 count() 只取第一行 ——
// 「按状态分了几组」被答成「第一组有多少行」。两个都是合法整数。

__global g_cg_query string
__global g_cg_rows [][]string

fn cg_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	_ = args
	unsafe {
		g_cg_query = query
		return g_cg_rows.clone()
	}
}

fn cg_builder() &TableQuery {
	unsafe {
		g_cg_query = ''
		g_cg_rows = [][]string{}
	}
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99)) or {}
	return table('users', om).set_query_fn(cg_query)
}

fn test_count_with_group_by_wraps_subquery() {
	q := cg_builder().one_column('status').group_by('status')
	unsafe {
		g_cg_rows = [['4']]
	}
	n := q.count()!
	assert n == 4
	sql_stmt := unsafe { g_cg_query }
	// 子查询里保留 GROUP BY，外层数「有几个分组」
	assert sql_stmt == 'SELECT COUNT(*) AS cnt FROM (SELECT status FROM users GROUP BY status) AS photon_count'
}

fn test_count_with_group_by_and_having_wraps_subquery() {
	q := cg_builder()
		.one_column('tenant_id')
		.group_by('tenant_id')
		.having('COUNT(*) > ?', 5)
	unsafe {
		g_cg_rows = [['2']]
	}
	n := q.count()!
	assert n == 2
	sql_stmt := unsafe { g_cg_query }
	assert sql_stmt.contains('GROUP BY tenant_id HAVING COUNT(*) > ?')
	assert sql_stmt.starts_with('SELECT COUNT(*) AS cnt FROM (SELECT')
}

fn test_count_strips_limit_inside_subquery() {
	// 子查询里的 LIMIT 会改变 COUNT(*) 的语义：数的是「截断后」
	// 的组数，而不是满足条件的组数。
	q := cg_builder().one_column('status').group_by('status').limit(3).offset(6)
	unsafe {
		g_cg_rows = [['9']]
	}
	_ = q.count()!
	sql_stmt := unsafe { g_cg_query }
	assert !sql_stmt.contains('LIMIT')
	assert !sql_stmt.contains('OFFSET')
}

fn test_count_without_group_or_projection_stays_flat() {
	q := cg_builder().where_eq('status', 'active').order_by_desc('id').limit(5)
	unsafe {
		g_cg_rows = [['3']]
	}
	_ = q.count()!
	sql_stmt := unsafe { g_cg_query }
	// 不需要子查询：投影是 *、没有分组
	assert sql_stmt == 'SELECT COUNT(*) AS cnt FROM users WHERE status = ?'
}

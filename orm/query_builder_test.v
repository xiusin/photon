module orm

// query_builder_test.v — regression tests for the legacy QueryBuilder
//
// The fluent facade (table.v) is the recommended API, but QueryBuilder is the
// documented surface in README/TUTORIAL, so its chain semantics are pinned
// here: typed args, OR parenthesisation, and non-mutating terminal calls.

__global g_qbt_last_query string
__global g_qbt_last_args []string

fn qbt_reset() {
	unsafe {
		g_qbt_last_query = ''
		g_qbt_last_args = []string{}
	}
}

fn qbt_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_qbt_last_query = query
		g_qbt_last_args = args.clone()
	}
	return [['1', 'Alice']]
}

fn qbt_builder() &QueryBuilder {
	qbt_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99)) or {}
	mut qb := new_query_builder(om, 'default', 'users')
	qb.set_query_fn(qbt_query)
	return qb
}

fn test_qbt_where_accepts_args() {
	mut qb := qbt_builder()
	qb.where_('age > ?', '18')
	qb.where_('status = ?', 'active')
	sql_stmt, args := qb.to_sql()
	assert sql_stmt == 'SELECT * FROM users WHERE age > ? AND status = ?'
	assert args == ['18', 'active']
}

fn test_qbt_or_where_is_parenthesised() {
	mut qb := qbt_builder()
	qb.where_('tenant_id = ?', '7')
	qb.or_where('status = ?', 'active')
	qb.where_('deleted = ?', '0')
	sql_stmt, _ := qb.to_sql()
	assert sql_stmt == 'SELECT * FROM users WHERE (tenant_id = ? OR status = ?) AND deleted = ?'
}

fn test_qbt_first_does_not_mutate_limit() {
	mut qb := qbt_builder()
	qb.where_('id = ?', '1')
	qb.limit(50)
	_ := qb.first()!
	assert qb.limit_val == 50
	sql_stmt, _ := qb.to_sql()
	assert sql_stmt.ends_with('LIMIT 50')
}

fn test_qbt_pluck_does_not_mutate_columns() {
	mut qb := qbt_builder()
	_ := qb.pluck('name')!
	assert qb.columns == ['*']
}

fn test_qbt_count_ignores_order_and_limit() {
	mut qb := qbt_builder()
	qb.where_('status = ?', 'active')
	qb.order_by('id', .desc)
	qb.limit(5)
	_ := qb.count()!
	assert g_qbt_last_query == 'SELECT COUNT(*) AS cnt FROM users WHERE status = ?'
	sql_stmt, _ := qb.to_sql()
	assert sql_stmt.contains('ORDER BY id DESC') && sql_stmt.contains('LIMIT 5')
}

fn test_qbt_clone_is_independent() {
	mut base := qbt_builder()
	base.where_('tenant_id = ?', '7')
	mut branch := base.clone()
	branch.where_('status = ?', 'active')
	base_sql, base_args := base.to_sql()
	branch_sql, branch_args := branch.to_sql()
	assert base_args.len == 1
	assert branch_args.len == 2
	assert base_sql == 'SELECT * FROM users WHERE tenant_id = ?'
	assert branch_sql == 'SELECT * FROM users WHERE tenant_id = ? AND status = ?'
}

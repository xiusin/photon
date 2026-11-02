module orm

// table_test.v — tests for the fluent table facade (table.v)
//
// Focus: the promises the API makes.
//   1. SQL shape — placeholders, parentheses around OR groups, IN expansion.
//   2. Parameter order — values follow placeholder order exactly.
//   3. Immutability — a clause method never mutates the query it was called on.
//   4. Injection safety — bad identifiers/operators fail loudly, never silently.
//   5. Write guards — update/delete refuse to run without WHERE.

__global g_tbl_rows [][]string
__global g_tbl_last_query string
__global g_tbl_last_args []string
__global g_tbl_exec_query string
__global g_tbl_exec_args []string

fn tbl_reset() {
	unsafe {
		g_tbl_rows = [][]string{}
		g_tbl_last_query = ''
		g_tbl_last_args = []string{}
		g_tbl_exec_query = ''
		g_tbl_exec_args = []string{}
	}
}

fn tbl_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_tbl_last_query = query
		g_tbl_last_args = args.clone()
		return g_tbl_rows.clone()
	}
}

fn tbl_exec(db voidptr, query string, args []string) ! {
	_ = db
	unsafe {
		g_tbl_exec_query = query
		g_tbl_exec_args = args.clone()
	}
}

// tbl_builder returns a wired builder on a fresh mock.
fn tbl_builder() &TableQuery {
	tbl_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99)) or {}
	return table('users', om).set_query_fn(tbl_query).set_exec_fn(tbl_exec)
}

// ── SQL shape ──

fn test_table_basic_select_sql() {
	q := tbl_builder().where_eq('id', 1)
	sql_stmt, args := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE id = ?'
	assert args.len == 1
	assert args[0] == ParamValue(int(1))
}

fn test_table_chained_predicates_use_and() {
	q := tbl_builder().where_gt('age', 18).where_eq('status', 'active')
	sql_stmt, args := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE age > ? AND status = ?'
	assert args.len == 2
	assert args[0] == ParamValue(int(18))
	assert args[1] == ParamValue('active')
}

fn test_table_or_alternative_is_and_ed_with_prior_filters() {
	q := tbl_builder()
		.where_eq('tenant_id', 7)
		.or_where_eq('status', 'active')
		.where_eq('deleted', false)
	sql_stmt, args := q.to_sql()!
	// 已经加上的过滤条件不能被一个 OR 分支放宽：租户隔离必须保持 AND。
	//
	// 而 or_where 之后的 `.where_eq('deleted', false)` 是**新的 AND 过滤**，
	// 不属于那个 OR 备选组。原期望值把它并进了括号（`status = ? OR deleted = ?`），
	// 等于让「已删除」的软删除标记去当 status 的备选值 —— 一行被删除的记录
	// 只要 status 不匹配就会被这条 OR 捞出来。
	assert sql_stmt == 'SELECT * FROM users WHERE tenant_id = ? AND (status = ?) AND deleted = ?'
	assert args.len == 3
	assert args[2] == ParamValue(false)
}

fn test_table_where_group_nests() {
	q := tbl_builder()
		.where_eq('tenant_id', 7)
		.where_group(fn (g &TableQuery) &TableQuery {
			return g.where_eq('status', 'active').or_where_eq('status', 'trial')
		})
	sql_stmt, args := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE tenant_id = ? AND (status = ? OR status = ?)'
	assert args.len == 3
	assert args[0] == ParamValue(int(7))
}

fn test_table_in_expands_placeholders() {
	q := tbl_builder().where_in('id', [ParamValue(int(1)), ParamValue(int(2)), ParamValue(int(3))])
	sql_stmt, args := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE id IN (?, ?, ?)'
	assert args.len == 3
}

fn test_table_empty_in_matches_nothing() {
	// 空 IN 曾经被静默丢掉：调用方从用户输入拼出来的过滤列表为空时，
	// 「一条都不匹配」直接变成「全表」。现在与 QueryBuilder.where_in()
	// 的 `1 = 0` 对齐。
	q := tbl_builder().where_in('id', []ParamValue{})
	sql_stmt, _ := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE 1 = 0'

	// 空 IN 也不能把前面已经加上的条件放宽
	q2 := tbl_builder().where_eq('tenant_id', 7).where_in('id', []ParamValue{})
	sql_stmt2, args2 := q2.to_sql()!
	assert sql_stmt2 == 'SELECT * FROM users WHERE tenant_id = ? AND 1 = 0'
	assert args2.len == 1
}

fn test_table_between_and_null() {
	q := tbl_builder().where_between('age', 18, 65).where_null('deleted_at').where_not_null('email')
	sql_stmt, args := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE age >= ? AND age <= ? AND deleted_at IS NULL AND email IS NOT NULL'
	assert args.len == 2
}

fn test_table_order_group_limit() {
	q := tbl_builder()
		.one_column('tenant_id')
		.where_eq('status', 'active')
		.group_by('tenant_id')
		.having('COUNT(*) > ?', 5)
		.order_by_desc('tenant_id')
		.limit(10)
		.offset(20)
	sql_stmt, args := q.to_sql()!
	assert sql_stmt == 'SELECT tenant_id FROM users WHERE status = ? GROUP BY tenant_id HAVING COUNT(*) > ? ORDER BY tenant_id DESC LIMIT 10 OFFSET 20'
	assert args.len == 2
	assert args[1] == ParamValue(int(5))
}

fn test_table_having_requires_placeholder() {
	q := tbl_builder().group_by('tenant_id').having('COUNT(*) > 5', 5)
	if _, _ := q.to_sql() {
		assert false, 'expected an error: having() value without "?"'
	} else {
		assert true
	}
}

fn test_table_where_like_wraps_pattern() {
	q := tbl_builder().where_like('name', 'ali')
	sql_stmt, args := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE name LIKE ?'
	assert args[0] == ParamValue('%ali%')
}

fn test_table_raw_where_binds_values() {
	q := tbl_builder().where_eq('tenant_id', 3).raw_where('lower(email) = ? OR phone = ?',
		'a@b.com', '138')
	sql_stmt, args := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users WHERE tenant_id = ? AND lower(email) = ? OR phone = ?'
	_ = 0
	assert args.len == 3
	assert args[2] == ParamValue('138')
}

fn test_table_raw_where_arity_mismatch_errors() {
	q := tbl_builder().raw_where('a = ? AND b = ?', 'only-one')
	if _, _ := q.to_sql() {
		assert false, 'expected an error: placeholder/value mismatch'
	} else {
		assert true
	}
}

// ── Injection safety ──

fn test_table_rejects_malicious_column() {
	q := tbl_builder().where_eq('id; DROP TABLE users--', 1)
	if _, _ := q.to_sql() {
		assert false, 'expected an error for a malicious identifier'
	} else {
		assert true
	}
}

fn test_table_rejects_malicious_table() {
	tbl_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99)) or {}
	q := table('users; DROP TABLE x', om)
	if _, _ := q.to_sql() {
		assert false, 'expected an error for a malicious table name'
	} else {
		assert true
	}
}

fn test_table_rejects_unknown_operator() {
	q := tbl_builder().where('age', 'between evil', 1)
	if _, _ := q.to_sql() {
		assert false, 'expected an error for an unknown operator'
	} else {
		assert true
	}
}

fn test_table_rejects_bad_select_column() {
	q := tbl_builder().select_(['id]) --'])
	if _, _ := q.build() {
		assert false, 'expected an error for a malicious projection'
	} else {
		assert true
	}
}

fn test_table_identifier_rules() {
	assert is_safe_identifier('users')
	assert is_safe_identifier('users.id')
	assert is_safe_identifier('t0.col_1')
	assert !is_safe_identifier('')
	assert !is_safe_identifier('1col')
	assert !is_safe_identifier('a b')
	assert !is_safe_identifier('a.b.c.')
	assert !is_safe_identifier('users--')
}

// ── Immutability ──

fn test_table_clause_does_not_mutate_receiver() {
	base := tbl_builder().where_eq('tenant_id', 7)
	branch := base.where_eq('status', 'active')
	base_sql, base_args := base.to_sql()!
	branch_sql, branch_args := branch.to_sql()!
	assert base_args.len == 1
	assert branch_args.len == 2
	assert base_sql == 'SELECT * FROM users WHERE tenant_id = ?'
	assert branch_sql == 'SELECT * FROM users WHERE tenant_id = ? AND status = ?'
}

fn test_table_limit_does_not_leak() {
	base := tbl_builder().where_eq('id', 1)
	limited := base.limit(5)
	base_sql, _ := base.to_sql()!
	limited_sql, _ := limited.to_sql()!
	assert !base_sql.contains('LIMIT')
	assert limited_sql.ends_with('LIMIT 5')
}

// ── Terminal methods ──

fn test_table_get_passes_args_in_order() {
	q := tbl_builder().where_gt('age', 18).where_eq('status', 'active')
	unsafe {
		g_tbl_rows = [['1', 'Alice']]
	}
	rows := q.get()!
	assert rows.len == 1
	assert g_tbl_last_args == ['18', 'active']
}

fn test_table_first_returns_row_and_limits() {
	q := tbl_builder().where_eq('id', 1)
	unsafe {
		g_tbl_rows = [['1', 'Alice']]
	}
	row := q.first()!
	assert row[1] == 'Alice'
	assert g_tbl_last_query.ends_with('LIMIT 1')
}

fn test_table_first_errors_when_empty() {
	q := tbl_builder().where_eq('id', 1)
	if _ := q.first() {
		assert false, 'expected an error for an empty result'
	} else {
		assert true
	}
}

fn test_table_count_ignores_order_and_limit() {
	q := tbl_builder().where_eq('status', 'active').order_by_desc('id').limit(5)
	unsafe {
		g_tbl_rows = [['3']]
	}
	n := q.count()!
	assert n == 3
	assert g_tbl_last_query == 'SELECT COUNT(*) AS cnt FROM users WHERE status = ?'
	// count() built its own view: the original still has ORDER BY / LIMIT.
	sql_stmt, _ := q.to_sql()!
	assert sql_stmt.contains('ORDER BY id DESC')
	assert sql_stmt.contains('LIMIT 5')
}

fn test_table_exists_uses_count() {
	q := tbl_builder().where_eq('status', 'active')
	unsafe {
		g_tbl_rows = [['0']]
	}
	assert !q.exists()!
	unsafe {
		g_tbl_rows = [['2']]
	}
	assert q.exists()!
}

fn test_table_pluck_and_value() {
	q := tbl_builder().one_column('name')
	unsafe {
		g_tbl_rows = [['Alice'], ['Bob']]
	}
	names := q.pluck()!
	assert names == ['Alice', 'Bob']
	unsafe {
		g_tbl_rows = []
	}
	assert q.value()! == ''
}

// ── Write guards ──

fn test_table_update_requires_where() {
	mut pairs := map[string]ParamValue{}
	pairs['name'] = ParamValue('X')
	if _ := tbl_builder().update(pairs) {
		assert false, 'expected an error: UPDATE without WHERE'
	} else {
		assert true
	}
}

fn test_table_update_binds_pairs_then_where() {
	mut pairs := map[string]ParamValue{}
	pairs['name'] = ParamValue('Alice')
	pairs['age'] = ParamValue(30)
	tbl_builder().where_eq('id', 1).update(pairs)!
	assert g_tbl_exec_query == 'UPDATE users SET age = ?, name = ? WHERE id = ?'
	assert g_tbl_exec_args == ['30', 'Alice', '1']
}

fn test_table_update_rejects_bad_column() {
	mut pairs := map[string]ParamValue{}
	pairs['name = 1, admin'] = ParamValue(true)
	if _ := tbl_builder().where_eq('id', 1).update(pairs) {
		assert false, 'expected an error: malicious SET column'
	} else {
		assert true
	}
}

fn test_table_delete_requires_where() {
	if _ := tbl_builder().delete() {
		assert false, 'expected an error: DELETE without WHERE'
	} else {
		assert true
	}
}

fn test_table_delete_binds_where() {
	tbl_builder().where_eq('status', 'stale').delete()!
	assert g_tbl_exec_query == 'DELETE FROM users WHERE status = ?'
	assert g_tbl_exec_args == ['stale']
}

fn test_table_insert_binds_columns() {
	mut values := map[string]ParamValue{}
	values['name'] = ParamValue('Alice')
	values['status'] = ParamValue('active')
	tbl_builder().insert(values)!
	assert g_tbl_exec_query == 'INSERT INTO users (name, status) VALUES (?, ?)'
	assert g_tbl_exec_args == ['Alice', 'active']
}

fn test_table_offset_without_limit_errors() {
	if _ := tbl_builder().offset(10).get() {
		assert false, 'expected an error: OFFSET without LIMIT'
	} else {
		assert true
	}
}

fn test_table_nil_manager_errors() {
	q := &TableQuery{
		table_name: 'users'
	}
	// build() only renders SQL — the manager is not needed for to_sql().
	sql_stmt, _ := q.to_sql()!
	assert sql_stmt == 'SELECT * FROM users'
	if _ := q.get() {
		assert false, 'expected an error: no OrmManager'
	} else {
		assert true
	}
}

// ── Repository integration ──

struct TblRepoUser {
pub mut:
	id    i64
	name  string
	email string
}

fn tbl_repo() !Repository[TblRepoUser] {
	tbl_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	return new_entity_repository[TblRepoUser](om, 'default', 'users', tbl_exec, tbl_query)!
}

fn test_repo_query_maps_entities() {
	repo := tbl_repo()!
	q := repo_query(repo).where_eq('name', 'Alice')
	unsafe {
		g_tbl_rows = [['1', 'Alice', 'a@b.com']]
	}
	users := q.to_entities[TblRepoUser]()!
	assert users.len == 1
	assert users[0].name == 'Alice'
	assert g_tbl_last_query == 'SELECT id, name, email FROM users WHERE name = ?'
	assert g_tbl_last_args == ['Alice']
}

fn test_repo_query_to_entity() {
	repo := tbl_repo()!
	unsafe {
		g_tbl_rows = [['2', 'Bob', 'b@b.com']]
	}
	user := repo_query(repo).where_eq('email', 'b@b.com').to_entity[TblRepoUser]()!
	assert user.id == 2
	assert g_tbl_last_query.ends_with('LIMIT 1')
}

fn test_repo_find_all_with_pages() {
	repo := tbl_repo()!
	unsafe {
		g_tbl_rows = [['2', 'Bob', 'b@b.com']]
	}
	users := find_all_with(repo, repo_query(repo).page(2, 10))!
	assert users.len == 1
	assert users[0].id == 2
	assert g_tbl_last_query.ends_with('LIMIT 10 OFFSET 10')
}

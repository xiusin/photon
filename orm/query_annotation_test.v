module orm

// query_annotation_test.v - Tests for @[query('SELECT ...')] (Task B6)
//
// Verifies:
//   - parse_query_annotation: single quotes, double quotes, no params
//   - convert_named_to_positional: :name → ? with param name extraction
//   - extract_named_params: :age, :name, :user_id, :1 (literal, not param)
//   - execute_query: basic SELECT, WHERE with ?, empty results, ORDER BY
//   - execute_named_query: single param, multiple params, missing param error
//   - extract_query_annotation[T]: comptime extraction from method attrs
//   - No @[query] attribute → none
//
// Uses a mock in-memory database (qa_* prefix to avoid clashing with
// the mock_* helpers in jpa_repository_test.v when the whole module
// is tested together).

// ── Test entity ──

struct QaUser {
pub mut:
	id    i64
	name  string
	age   int
	email string
}

// ── Mock in-memory database (qa_* prefix) ──
//
// Supports SELECT with:
//   - * or explicit column lists
//   - WHERE col > ? / col = ? / col LIKE ? (joined by AND)
//   - ORDER BY col DESC/ASC
//   - COUNT(*)

struct QaRow {
mut:
	cols   []string
	values []string
}

fn (mut r QaRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r QaRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_qa_rows []QaRow
__global g_qa_next_id i64
__global g_qa_last_query string
__global g_qa_last_args []string

fn qa_reset() {
	unsafe {
		g_qa_rows = []QaRow{}
		g_qa_next_id = 1
		g_qa_last_query = ''
		g_qa_last_args = []string{}
	}
}

fn qa_insert_user(name string, age int, email string) {
	mut row := QaRow{}
	id := g_qa_next_id
	row.set('id', '${id}')
	row.set('name', name)
	row.set('age', '${age}')
	row.set('email', email)
	unsafe {
		g_qa_rows << row
		g_qa_next_id = id + 1
	}
}

// qa_exec handles INSERT/UPDATE/DELETE/DDL (minimal — tests focus on SELECT).
fn qa_exec(db voidptr, query string, args []string) ! {
	_ = db
	_ = args
	unsafe {
		g_qa_last_query = query
	}
}

// qa_query handles SELECT statements.
fn qa_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_qa_last_query = query
		g_qa_last_args = args.clone()
	}
	q := query.to_lower()

	// COUNT(*)
	if q.contains('count(*)') {
		return [['${g_qa_rows.len}']]
	}

	// Parse: SELECT <cols> FROM <table> [WHERE ...] [ORDER BY ...]
	after_select := query[7..] // after "SELECT "
	from_idx := after_select.to_lower().index(' from ') or {
		return error('qa: cannot parse SELECT: no FROM clause')
	}
	cols_str := after_select[..from_idx].trim_space()
	// Expand * to all known columns
	cols := if cols_str == '*' {
		['id', 'name', 'age', 'email']
	} else {
		cols_str.split(',').map(it.trim_space())
	}

	// Extract the remainder after FROM <table>
	rest := after_select[from_idx + 6..]

	// Split off ORDER BY if present
	mut where_part := ''
	mut order_part := ''
	ob_idx := rest.to_lower().index(' order by ') or { -1 }
	if ob_idx != -1 {
		where_part = rest[..ob_idx].trim_space()
		order_part = rest[ob_idx + 10..].trim_space()
	} else {
		where_part = rest.trim_space()
	}

	// Parse WHERE conditions: "col > ? AND col2 LIKE ?"
	mut conditions := []QaCondition{}
	w_idx := where_part.to_lower().index(' where ') or { -1 }
	if w_idx != -1 {
		where_clause := where_part[w_idx + 7..].trim_space()
		// Normalize AND to lowercase for splitting (SQL is case-insensitive;
		// test column names are lowercase so this is safe).
		normalized := where_clause.replace(' AND ', ' and ')
		for cond_str in normalized.split(' and ') {
			conditions << qa_parse_condition(cond_str.trim_space())
		}
	}

	// Filter rows
	mut matched := []QaRow{}
	for row in g_qa_rows {
		if qa_row_matches(row, conditions, args) {
			matched << row
		}
	}

	// Apply ORDER BY
	if order_part.len > 0 {
		qa_sort_rows(mut matched, order_part)
	}

	// Build result in column order
	mut result := [][]string{}
	for row in matched {
		mut vals := []string{}
		for col in cols {
			vals << row.get(col)
		}
		result << vals
	}
	return result
}

struct QaCondition {
	col      string
	op       string // '>', '<', '=', '>=', '<=', 'LIKE'
}

fn qa_parse_condition(s string) QaCondition {
	// Find the operator
	mut op := ''
	mut op_idx := -1
	for candidate in ['>=', '<=', '>', '<', '=', 'LIKE'] {
		idx := s.index(candidate) or { continue }
		// For 'LIKE', ensure it's uppercase and standalone
		if candidate == 'LIKE' {
			sub := s[idx..idx + 4]
			if sub == 'LIKE' {
				op = 'LIKE'
				op_idx = idx
				break
			}
		} else {
			op = candidate
			op_idx = idx
			break
		}
	}
	if op_idx == -1 {
		return QaCondition{col: s, op: '='}
	}
	col := s[..op_idx].trim_space()
	return QaCondition{col: col, op: op}
}

fn qa_row_matches(row QaRow, conditions []QaCondition, args []string) bool {
	mut arg_i := 0
	for cond in conditions {
		if arg_i >= args.len {
			return false
		}
		cell := row.get(cond.col)
		arg := args[arg_i]
		arg_i++
		match cond.op {
			'>' { if cell.i64() <= arg.i64() { return false } }
			'<' { if cell.i64() >= arg.i64() { return false } }
			'>=' { if cell.i64() < arg.i64() { return false } }
			'<=' { if cell.i64() > arg.i64() { return false } }
			'=' { if cell != arg { return false } }
			'LIKE' { if !qa_like_match(cell, arg) { return false } }
			else { if cell != arg { return false } }
		}
	}
	return true
}

// qa_like_match checks if `val` matches SQL LIKE pattern `pat`.
// Supports % wildcard only (sufficient for tests).
fn qa_like_match(val string, pat string) bool {
	// Convert LIKE pattern to prefix/suffix/contains check
	if pat.starts_with('%') && pat.ends_with('%') && pat.len > 2 {
		return val.contains(pat[1..pat.len - 1])
	}
	if pat.starts_with('%') {
		return val.ends_with(pat[1..])
	}
	if pat.ends_with('%') {
		return val.starts_with(pat[..pat.len - 1])
	}
	return val == pat
}

fn qa_sort_rows(mut rows []QaRow, order_part string) {
	// Parse "col DESC" or "col ASC"
	parts := order_part.split(' ')
	col := parts[0].trim_space()
	desc := parts.len > 1 && parts[1].to_upper() == 'DESC'
	// Simple insertion sort by numeric value (age) or string (name)
	for i in 1 .. rows.len {
		for j in 0 .. i {
			a := rows[i].get(col)
			b := rows[j].get(col)
			should_swap := if desc {
				a.i64() > b.i64()
			} else {
				a.i64() < b.i64()
			}
			if should_swap {
				rows[i], rows[j] = rows[j], rows[i]
			}
		}
	}
}

// qa_setup creates a JpaRepository[QaUser] backed by the mock, with
// sample data: Alice(30), Bob(25), Charlie(35), Jane(22).
fn qa_setup() !JpaRepository[QaUser] {
	qa_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	repo := new_jpa_repository[QaUser](om, 'default', 'users', qa_exec, qa_query)!
	qa_insert_user('Alice', 30, 'alice@example.com')
	qa_insert_user('Bob', 25, 'bob@example.com')
	qa_insert_user('Charlie', 35, 'charlie@example.com')
	qa_insert_user('Jane', 22, 'jane@example.com')
	return repo
}

// ════════════════════════════════════════════════════════════════
// parse_query_annotation (SubTask B6.1, B6.2)
// ════════════════════════════════════════════════════════════════

fn test_parse_query_annotation_single_quotes() {
	// V stores @[query('SELECT ...')] as: query: 'SELECT ...'
	qa := parse_query_annotation("query: 'SELECT * FROM users WHERE age > :age'") or {
		assert false, 'expected annotation to parse'
		return
	}
	assert qa.sql_text == 'SELECT * FROM users WHERE age > :age'
	assert qa.named_params == ['age']
}

fn test_parse_query_annotation_double_quotes() {
	qa := parse_query_annotation('query: "SELECT * FROM users WHERE name = :name"') or {
		assert false, 'expected annotation to parse'
		return
	}
	assert qa.sql_text == 'SELECT * FROM users WHERE name = :name'
	assert qa.named_params == ['name']
}

fn test_parse_query_annotation_multiple_params() {
	qa := parse_query_annotation("query: 'SELECT * FROM users WHERE age > :age AND name LIKE :name'") or {
		assert false, 'expected annotation to parse'
		return
	}
	assert qa.sql_text == 'SELECT * FROM users WHERE age > :age AND name LIKE :name'
	assert qa.named_params == ['age', 'name']
}

fn test_parse_query_annotation_no_params() {
	qa := parse_query_annotation("query: 'SELECT * FROM users'") or {
		assert false, 'expected annotation to parse'
		return
	}
	assert qa.sql_text == 'SELECT * FROM users'
	assert qa.named_params.len == 0
}

fn test_parse_query_annotation_not_a_query_attr() {
	// Non-query attributes return none
	qa := parse_query_annotation('transactional') or {
		assert true
		return
	}
	_ = qa
	assert false, 'expected none for non-query attribute'
}

fn test_parse_query_annotation_user_id_param() {
	// Underscore and digits in param names
	qa := parse_query_annotation("query: 'SELECT * FROM users WHERE id = :user_id'") or {
		assert false, 'expected annotation to parse'
		return
	}
	assert qa.named_params == ['user_id']
}

// ════════════════════════════════════════════════════════════════
// extract_named_params (SubTask B6.2)
// ════════════════════════════════════════════════════════════════

fn test_extract_named_params_basic() {
	params := extract_named_params('SELECT * FROM users WHERE age > :age AND name = :name')
	assert params == ['age', 'name']
}

fn test_extract_named_params_none() {
	params := extract_named_params('SELECT * FROM users')
	assert params.len == 0
}

fn test_extract_named_params_underscore_and_digits() {
	params := extract_named_params('WHERE id = :user_id AND code = :code2')
	assert params == ['user_id', 'code2']
}

fn test_extract_named_params_digit_only_is_literal() {
	// :123 is NOT a named param (must start with letter or _)
	params := extract_named_params('WHERE port = :123')
	assert params.len == 0
}

// ════════════════════════════════════════════════════════════════
// convert_named_to_positional (SubTask B6.2)
// ════════════════════════════════════════════════════════════════

fn test_convert_named_to_positional_single() {
	sql_out, names := convert_named_to_positional('SELECT * FROM users WHERE age > :age')
	assert sql_out == 'SELECT * FROM users WHERE age > ?'
	assert names == ['age']
}

fn test_convert_named_to_positional_multiple() {
	sql_out, names := convert_named_to_positional('SELECT * FROM users WHERE age > :age AND name = :name')
	assert sql_out == 'SELECT * FROM users WHERE age > ? AND name = ?'
	assert names == ['age', 'name']
}

fn test_convert_named_to_positional_no_params() {
	sql_out, names := convert_named_to_positional('SELECT * FROM users')
	assert sql_out == 'SELECT * FROM users'
	assert names.len == 0
}

fn test_convert_named_to_positional_repeated_param() {
	// Same param used twice — both become ? and name appears twice
	sql_out, names := convert_named_to_positional('WHERE a = :x OR b = :x')
	assert sql_out == 'WHERE a = ? OR b = ?'
	assert names == ['x', 'x']
}

// ════════════════════════════════════════════════════════════════
// execute_query — positional params (SubTask B6.3)
// ════════════════════════════════════════════════════════════════

fn test_execute_query_basic_select_all() {
	mut repo := qa_setup()!
	users := repo.execute_query('SELECT * FROM users', []string{})!
	assert users.len == 4
	assert users[0].name == 'Alice'
	assert users[1].name == 'Bob'
}

fn test_execute_query_where_greater_than() {
	mut repo := qa_setup()!
	users := repo.execute_query('SELECT * FROM users WHERE age > ?', ['25'])!
	// Alice(30), Charlie(35) — Bob(25) is NOT > 25
	assert users.len == 2
	mut names := users.map(it.name)
	assert names.contains('Alice')
	assert names.contains('Charlie')
}

fn test_execute_query_empty_results() {
	mut repo := qa_setup()!
	users := repo.execute_query('SELECT * FROM users WHERE age > ?', ['100'])!
	assert users.len == 0
}

fn test_execute_query_order_by_desc() {
	mut repo := qa_setup()!
	users := repo.execute_query('SELECT * FROM users ORDER BY age DESC', []string{})!
	assert users.len == 4
	// Descending by age: Charlie(35), Alice(30), Bob(25), Jane(22)
	assert users[0].name == 'Charlie'
	assert users[1].name == 'Alice'
	assert users[2].name == 'Bob'
	assert users[3].name == 'Jane'
}

fn test_execute_query_explicit_columns() {
	mut repo := qa_setup()!
	users := repo.execute_query('SELECT id, name, age, email FROM users WHERE age = ?', ['30'])!
	assert users.len == 1
	assert users[0].name == 'Alice'
	assert users[0].age == 30
}

// ════════════════════════════════════════════════════════════════
// execute_named_query — named params (SubTask B6.2, B6.3)
// ════════════════════════════════════════════════════════════════

fn test_execute_named_query_single_param() {
	mut repo := qa_setup()!
	users := repo.execute_named_query('SELECT * FROM users WHERE age > :age', {'age': '25'})!
	assert users.len == 2
	mut names := users.map(it.name)
	assert names.contains('Alice')
	assert names.contains('Charlie')
}

fn test_execute_named_query_multiple_params() {
	mut repo := qa_setup()!
	users := repo.execute_named_query('SELECT * FROM users WHERE age > :age AND name LIKE :name',
		{'age': '20', 'name': 'J%'})!
	// age > 20 AND name starts with 'J' → only Jane(22)
	assert users.len == 1
	assert users[0].name == 'Jane'
}

fn test_execute_named_query_no_params() {
	mut repo := qa_setup()!
	users := repo.execute_named_query('SELECT * FROM users', map[string]string{})!
	assert users.len == 4
}

fn test_execute_named_query_missing_param_error() {
	mut repo := qa_setup()!
	// Missing 'name' param → bilingual error
	if _ := repo.execute_named_query('SELECT * FROM users WHERE age > :age AND name LIKE :name',
		{'age': '20'}) {
		assert false, 'expected error for missing named param'
	} else {
		// Verify the error message mentions the missing param
		assert err.msg().contains('name')
	}
}

fn test_execute_named_query_param_order_preserved() {
	// Ensure params are bound in the order they appear in SQL,
	// not in the map iteration order.
	mut repo := qa_setup()!
	users := repo.execute_named_query('SELECT * FROM users WHERE name = :name AND age = :age',
		{'age': '30', 'name': 'Alice'})!
	assert users.len == 1
	assert users[0].name == 'Alice'
	assert users[0].age == 30
}

// ════════════════════════════════════════════════════════════════
// extract_query_annotation[T] — comptime (SubTask B6.1)
// ════════════════════════════════════════════════════════════════

// QaUserRepo is a test repository struct with @[query]-annotated methods.
struct QaUserRepo {
	om &OrmManager = unsafe { nil }
}

@[query: 'SELECT * FROM users WHERE age > :age']
fn (r QaUserRepo) find_by_age(age int) []QaUser {
	return []
}

@[query: 'SELECT * FROM users WHERE name = :name AND age > :age']
fn (r QaUserRepo) find_by_name_and_age(name string, age int) []QaUser {
	return []
}

@[query: "SELECT * FROM users"]
fn (r QaUserRepo) find_all() []QaUser {
	return []
}

// No @[query] attribute on this method.
fn (r QaUserRepo) count_all() int {
	return 0
}

fn test_extract_query_annotation_single_param() {
	qa := extract_query_annotation[QaUserRepo]('find_by_age') or {
		assert false, 'expected @[query] on find_by_age'
		return
	}
	assert qa.sql_text == 'SELECT * FROM users WHERE age > :age'
	assert qa.named_params == ['age']
}

fn test_extract_query_annotation_multiple_params() {
	qa := extract_query_annotation[QaUserRepo]('find_by_name_and_age') or {
		assert false, 'expected @[query] on find_by_name_and_age'
		return
	}
	assert qa.sql_text == 'SELECT * FROM users WHERE name = :name AND age > :age'
	assert qa.named_params == ['name', 'age']
}

fn test_extract_query_annotation_double_quotes() {
	qa := extract_query_annotation[QaUserRepo]('find_all') or {
		assert false, 'expected @[query] on find_all'
		return
	}
	assert qa.sql_text == 'SELECT * FROM users'
	assert qa.named_params.len == 0
}

fn test_extract_query_annotation_no_attribute_returns_none() {
	// count_all has no @[query] → none
	qa := extract_query_annotation[QaUserRepo]('count_all') or {
		assert true
		return
	}
	_ = qa
	assert false, 'expected none for method without @[query]'
}

fn test_extract_query_annotation_unknown_method_returns_none() {
	qa := extract_query_annotation[QaUserRepo]('nonexistent_method') or {
		assert true
		return
	}
	_ = qa
	assert false, 'expected none for unknown method'
}

// ════════════════════════════════════════════════════════════════
// End-to-end: extract annotation → execute_named_query
// ════════════════════════════════════════════════════════════════

fn test_end_to_end_annotation_to_execution() {
	mut repo := qa_setup()!
	// Extract the @[query] annotation from QaUserRepo.find_by_age
	qa := extract_query_annotation[QaUserRepo]('find_by_age') or {
		assert false, 'expected @[query] on find_by_age'
		return
	}
	// Execute the extracted SQL with named params
	users := repo.execute_named_query(qa.sql_text, {'age': '25'})!
	assert users.len == 2
	mut names := users.map(it.name)
	assert names.contains('Alice')
	assert names.contains('Charlie')
}

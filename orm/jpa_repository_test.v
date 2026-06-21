module orm

// jpa_repository_test.v - Tests for JpaRepository[T] (P0 8.3)
//
// Verifies the comptime-derived zero-callback repository:
//   - Primary key detection (field named 'id' and @[primary_key] attribute)
//   - CRUD: save / find_by_id / find_all / delete / count
//   - DDL: create_table
//   - Error cases: no primary key, find_by_id not found
//
// Since photon/orm cannot import db.sqlite (module-name collision with
// V's standard `orm`), these tests use a mock in-memory database backed
// by __global state (compiled with -enable-globals, matching CI).

// ── Test entities ──

struct JpaTestUser {
pub mut:
	id    i64
	name  string
	email string
}

struct JpaTestArticle {
pub mut:
	article_id i64 @[primary_key]
	title      string
	views      int
}

struct JpaNoPk {
pub mut:
	name  string
	value int
}

// ── Mock in-memory database ──
//
// V function-type callbacks cannot capture state, so the mock uses
// __global variables.  Each test resets state via mock_reset().

struct MockRow {
mut:
	cols   []string
	values []string
}

fn (mut r MockRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r MockRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_mock_rows []MockRow
__global g_mock_next_id i64
__global g_mock_last_query string
__global g_mock_ddl []string
__global g_mock_pk_col string

fn mock_reset() {
	unsafe {
		g_mock_rows = []MockRow{}
		g_mock_next_id = 1
		g_mock_last_query = ''
		g_mock_ddl = []string{}
		g_mock_pk_col = 'id'
	}
}

fn mock_setup[T]() !JpaRepository[T] {
	mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	repo := new_jpa_repository[T](om, 'default', 'jpa_test_table', mock_exec, mock_query)!
	unsafe {
		g_mock_pk_col = repo.primary_key_field
	}
	return repo
}

// mock_exec handles INSERT / DELETE / CREATE TABLE statements.
fn mock_exec(db voidptr, query string, args []string) ! {
	_ = db
	unsafe {
		g_mock_last_query = query
	}
	q := query.to_lower()
	if q.starts_with('create table') {
		unsafe {
			g_mock_ddl << query
		}
		return
	}
	if q.starts_with('insert into') {
		mock_handle_insert(query, args)!
		return
	}
	if q.starts_with('delete from') {
		mock_handle_delete(args)
		return
	}
}

fn mock_handle_insert(query string, args []string) ! {
	open_paren := query.index('(') or { return error('mock: cannot parse INSERT columns') }
	rest := query[open_paren + 1..]
	close_offset := rest.index(')') or { return error('mock: cannot parse INSERT columns') }
	cols_str := rest[..close_offset]
	cols := cols_str.split(',').map(it.trim_space())
	mut row := MockRow{}
	for i, col in cols {
		if i < args.len {
			row.set(col, args[i])
		}
	}
	// Auto-assign PK if missing or zero
	pk_val := row.get(g_mock_pk_col)
	if pk_val == '' || pk_val == '0' {
		next := g_mock_next_id
		row.set(g_mock_pk_col, '${next}')
		unsafe {
			g_mock_next_id = next + 1
		}
	}
	unsafe {
		g_mock_rows << row
	}
}

fn mock_handle_delete(args []string) {
	if args.len == 0 {
		return
	}
	target := args[0]
	pk_col := g_mock_pk_col
	mut kept := []MockRow{}
	for row in g_mock_rows {
		if row.get(pk_col) != target {
			kept << row
		}
	}
	unsafe {
		g_mock_rows = kept
	}
}

// mock_query handles SELECT statements (including COUNT).
fn mock_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_mock_last_query = query
	}
	q := query.to_lower()
	if q.contains('count(*)') {
		count := g_mock_rows.len
		return [['${count}']]
	}
	// Parse: SELECT <cols> FROM <table> [WHERE <col> = ?]
	after_select := query[7..] // after "SELECT "
	from_idx := after_select.to_lower().index(' from ') or {
		return error('mock: cannot parse SELECT: no FROM clause')
	}
	cols_str := after_select[..from_idx]
	cols := cols_str.split(',').map(it.trim_space())
	// Parse WHERE filter if present
	mut filter_col := ''
	mut target := ''
	where_idx := q.index(' where ') or { -1 }
	if where_idx != -1 && args.len > 0 {
		where_str := query[where_idx + 7..]
		eq_idx := where_str.index('=') or { where_str.len }
		filter_col = where_str[..eq_idx].trim_space()
		target = args[0]
	}
	// Build result rows in column order, applying WHERE filter inline
	// (avoid array copies — V requires .clone() for `a := b` on arrays)
	mut result := [][]string{}
	for row in g_mock_rows {
		if filter_col != '' && row.get(filter_col) != target {
			continue
		}
		mut vals := []string{}
		for col in cols {
			vals << row.get(col)
		}
		result << vals
	}
	return result
}

// ════════════════════════════════════════════════════════════════
// Construction & Primary Key Detection (SubTask 13.2)
// ════════════════════════════════════════════════════════════════

fn test_jpa_construct_with_id_field() {
	repo := mock_setup[JpaTestUser]()!
	assert repo.primary_key_field == 'id'
	assert repo.field_names == ['id', 'name', 'email']
	assert repo.table_name == 'jpa_test_table'
}

fn test_jpa_construct_with_primary_key_attr() {
	repo := mock_setup[JpaTestArticle]()!
	assert repo.primary_key_field == 'article_id'
	assert repo.field_names == ['article_id', 'title', 'views']
}

fn test_jpa_construct_no_primary_key_error() {
	mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	if _ := new_jpa_repository[JpaNoPk](om, 'default', 'jpa_test_table', mock_exec, mock_query) {
		assert false, 'expected error: no primary key field'
	} else {
		assert true
	}
}

// ════════════════════════════════════════════════════════════════
// DDL: create_table
// ════════════════════════════════════════════════════════════════

fn test_jpa_create_table() {
	mut repo := mock_setup[JpaTestUser]()!
	repo.create_table()!
	assert g_mock_ddl.len == 1
	ddl := g_mock_ddl[0]
	assert ddl.contains('CREATE TABLE IF NOT EXISTS jpa_test_table')
	assert ddl.contains('id INTEGER PRIMARY KEY')
	assert ddl.contains('name TEXT')
	assert ddl.contains('email TEXT')
}

// ════════════════════════════════════════════════════════════════
// CRUD: save (insert) (SubTask 13.3)
// ════════════════════════════════════════════════════════════════

fn test_jpa_save_insert_auto_increment() {
	mut repo := mock_setup[JpaTestUser]()!
	repo.save(&JpaTestUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	assert g_mock_rows.len == 1
	// PK auto-assigned to 1 (id=0 skipped in INSERT)
	assert g_mock_rows[0].get('id') == '1'
	assert g_mock_rows[0].get('name') == 'Alice'
	assert g_mock_rows[0].get('email') == 'alice@example.com'
}

fn test_jpa_save_with_explicit_id() {
	mut repo := mock_setup[JpaTestUser]()!
	repo.save(&JpaTestUser{
		id:    42
		name:  'Bob'
		email: 'bob@example.com'
	})!
	assert g_mock_rows.len == 1
	assert g_mock_rows[0].get('id') == '42'
}

// ════════════════════════════════════════════════════════════════
// CRUD: find_by_id (SubTask 13.3)
// ════════════════════════════════════════════════════════════════

fn test_jpa_find_by_id() {
	mut repo := mock_setup[JpaTestUser]()!
	repo.save(&JpaTestUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	user := repo.find_by_id(1)!
	assert user.id == 1
	assert user.name == 'Alice'
	assert user.email == 'alice@example.com'
}

fn test_jpa_find_by_id_not_found() {
	mut repo := mock_setup[JpaTestUser]()!
	if _ := repo.find_by_id(999) {
		assert false, 'expected error: entity not found'
	} else {
		assert true
	}
}

// ════════════════════════════════════════════════════════════════
// CRUD: find_all (SubTask 13.3)
// ════════════════════════════════════════════════════════════════

fn test_jpa_find_all() {
	mut repo := mock_setup[JpaTestUser]()!
	repo.save(&JpaTestUser{
		name:  'Alice'
		email: 'a@b.com'
	})!
	repo.save(&JpaTestUser{
		name:  'Bob'
		email: 'b@b.com'
	})!
	users := repo.find_all()!
	assert users.len == 2
	assert users[0].name == 'Alice'
	assert users[1].name == 'Bob'
}

fn test_jpa_find_all_empty() {
	mut repo := mock_setup[JpaTestUser]()!
	users := repo.find_all()!
	assert users.len == 0
}

// ════════════════════════════════════════════════════════════════
// CRUD: delete (SubTask 13.3)
// ════════════════════════════════════════════════════════════════

fn test_jpa_delete() {
	mut repo := mock_setup[JpaTestUser]()!
	repo.save(&JpaTestUser{
		name:  'Alice'
		email: 'a@b.com'
	})!
	assert g_mock_rows.len == 1
	repo.delete(1)!
	assert g_mock_rows.len == 0
}

// ════════════════════════════════════════════════════════════════
// CRUD: count (SubTask 13.3)
// ════════════════════════════════════════════════════════════════

fn test_jpa_count() {
	mut repo := mock_setup[JpaTestUser]()!
	assert repo.count()! == 0
	repo.save(&JpaTestUser{
		name:  'Alice'
		email: 'a@b.com'
	})!
	repo.save(&JpaTestUser{
		name:  'Bob'
		email: 'b@b.com'
	})!
	assert repo.count()! == 2
}

// ════════════════════════════════════════════════════════════════
// Full CRUD cycle
// ════════════════════════════════════════════════════════════════

fn test_jpa_full_crud_cycle() {
	mut repo := mock_setup[JpaTestUser]()!
	repo.create_table()!
	// Save
	repo.save(&JpaTestUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	repo.save(&JpaTestUser{
		name:  'Bob'
		email: 'bob@example.com'
	})!
	assert repo.count()! == 2
	// Find by id
	alice := repo.find_by_id(1)!
	assert alice.name == 'Alice'
	// Find all
	all := repo.find_all()!
	assert all.len == 2
	// Delete
	repo.delete(1)!
	assert repo.count()! == 1
	// Deleted entity no longer found
	if _ := repo.find_by_id(1) {
		assert false, 'deleted entity should not be found'
	} else {
		assert true
	}
}

// ════════════════════════════════════════════════════════════════
// @[primary_key] attribute entity CRUD (SubTask 13.2)
// ════════════════════════════════════════════════════════════════

fn test_jpa_article_crud() {
	mut repo := mock_setup[JpaTestArticle]()!
	repo.create_table()!
	// Verify DDL uses article_id as PRIMARY KEY
	ddl := g_mock_ddl[0]
	assert ddl.contains('article_id INTEGER PRIMARY KEY')
	// Save with explicit PK
	repo.save(&JpaTestArticle{
		article_id: 100
		title:      'Hello'
		views:      42
	})!
	// Find by id
	article := repo.find_by_id(100)!
	assert article.article_id == 100
	assert article.title == 'Hello'
	assert article.views == 42
	// Count
	assert repo.count()! == 1
	// Delete
	repo.delete(100)!
	assert repo.count()! == 0
}

// ════════════════════════════════════════════════════════════════
// @[autowired] pattern (SubTask 13.4)
//
// JpaRepository itself is generic and cannot be a Photon bean, but
// the documented pattern is to autowire &OrmManager into a @[component]
// and call new_jpa_repository[T]() from there.  This test verifies
// that pattern compiles and works.
// ════════════════════════════════════════════════════════════════

struct JpaUserService {
	om &OrmManager
}

fn (s &JpaUserService) repo() !JpaRepository[JpaTestUser] {
	return new_jpa_repository[JpaTestUser](s.om, 'default', 'users', mock_exec, mock_query)!
}

fn test_jpa_autowired_pattern() {
	mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	// Simulate @[autowired] injection of OrmManager
	service := JpaUserService{
		om: om
	}
	mut repo := service.repo()!
	repo.save(&JpaTestUser{
		name:  'Charlie'
		email: 'c@d.com'
	})!
	user := repo.find_by_id(1)!
	assert user.name == 'Charlie'
}

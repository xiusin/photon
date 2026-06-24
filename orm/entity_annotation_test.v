module orm

// entity_annotation_test.v - Tests for JPA entity annotations (Task B7)
//
// Verifies comptime extraction of @[entity]/@[table('name')]/@[column('name')]/@[id]
// and integration with JpaRepository[T] SQL generation.
//
// The mock DB is self-contained (does not share state with other test
// files' mocks), matching the convention used by jpa_pagination_test.v.

// ════════════════════════════════════════════════════════════════
// Test entities
// ════════════════════════════════════════════════════════════════

// Custom table name + custom column name + @[id] primary key.
@[table: 't_user']
struct AnnotCustomUser {
pub mut:
	user_id int    @[id]
	name    string @[column: 'user_name']
	email   string
	age     int
}

// @[entity] marker only — defaults for table/column, @[id] on 'id' field.
@[entity]
struct AnnotDefaultEntity {
pub mut:
	id   int @[id]
	name string
}

// @[primary_key] alternative attribute (backward compat with Task 13).
struct AnnotAltPk {
pub mut:
	uid  i64 @[primary_key]
	data string
}

// No primary-key annotation at all — has_primary_key should be false.
struct AnnotNoPk {
pub mut:
	label string
	value int
}

// Custom column name on the primary key field itself.
@[table: 't_order']
struct AnnotCustomPkColumn {
pub mut:
	oid  int @[id; column: 'order_id']
	name string
}

// Plain struct (no annotations) for backward-compat tests.
struct AnnotPlainUser {
pub mut:
	id    i64
	name  string
	email string
}

// ════════════════════════════════════════════════════════════════
// Self-contained mock in-memory database
// ════════════════════════════════════════════════════════════════

struct AnnotMockRow {
mut:
	cols   []string
	values []string
}

fn (mut r AnnotMockRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r AnnotMockRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_annot_rows []AnnotMockRow
__global g_annot_next_id i64
__global g_annot_last_query string
__global g_annot_ddl []string
__global g_annot_pk_col string

fn annot_mock_reset() {
	unsafe {
		g_annot_rows = []AnnotMockRow{}
		g_annot_next_id = 1
		g_annot_last_query = ''
		g_annot_ddl = []string{}
		g_annot_pk_col = 'id'
	}
}

fn annot_mock_setup[T]() !JpaRepository[T] {
	annot_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	repo := new_jpa_repository[T](om, 'default', 'fallback_table', annot_mock_exec,
		annot_mock_query)!
	unsafe {
		g_annot_pk_col = repo.primary_key_column
	}
	return repo
}

// annot_mock_exec handles INSERT / DELETE / CREATE TABLE statements.
fn annot_mock_exec(db voidptr, query string, args []string) ! {
	_ = db
	unsafe {
		g_annot_last_query = query
	}
	q := query.to_lower()
	if q.starts_with('create table') {
		unsafe {
			g_annot_ddl << query
		}
		return
	}
	if q.starts_with('insert into') {
		annot_handle_insert(query, args)!
		return
	}
	if q.starts_with('delete from') {
		annot_handle_delete(args)
		return
	}
}

fn annot_handle_insert(query string, args []string) ! {
	open_paren := query.index('(') or { return error('mock: cannot parse INSERT columns') }
	rest := query[open_paren + 1..]
	close_offset := rest.index(')') or { return error('mock: cannot parse INSERT columns') }
	cols_str := rest[..close_offset]
	cols := cols_str.split(',').map(it.trim_space())
	mut row := AnnotMockRow{}
	for i, col in cols {
		if i < args.len {
			row.set(col, args[i])
		}
	}
	// Auto-assign PK if missing or zero
	pk_val := row.get(g_annot_pk_col)
	if pk_val == '' || pk_val == '0' {
		next := g_annot_next_id
		row.set(g_annot_pk_col, '${next}')
		unsafe {
			g_annot_next_id = next + 1
		}
	}
	unsafe {
		g_annot_rows << row
	}
}

fn annot_handle_delete(args []string) {
	if args.len == 0 {
		return
	}
	target := args[0]
	pk_col := g_annot_pk_col
	mut kept := []AnnotMockRow{}
	for row in g_annot_rows {
		if row.get(pk_col) != target {
			kept << row
		}
	}
	unsafe {
		g_annot_rows = kept
	}
}

// annot_mock_query handles SELECT statements (including COUNT).
fn annot_mock_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_annot_last_query = query
	}
	q := query.to_lower()
	if q.contains('count(*)') {
		count := g_annot_rows.len
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
	mut result := [][]string{}
	for row in g_annot_rows {
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
// Metadata extraction tests (SubTask B7.1 / B7.2)
// ════════════════════════════════════════════════════════════════

fn test_extract_custom_table_name() {
	meta := extract_entity_metadata[AnnotCustomUser]()
	assert meta.table_name == 't_user'
	assert meta.has_table_annotation == true
}

fn test_extract_default_table_name() {
	meta := extract_entity_metadata[AnnotDefaultEntity]()
	// Default: snake_case(AnnotDefaultEntity) + 's'
	assert meta.table_name == 'annot_default_entitys'
	assert meta.has_table_annotation == false
}

fn test_extract_custom_column_name() {
	meta := extract_entity_metadata[AnnotCustomUser]()
	// The 'name' field has @[column('user_name')] → column_name == 'user_name'
	mut found := false
	for col in meta.columns {
		if col.field_name == 'name' {
			assert col.column_name == 'user_name'
			found = true
		}
	}
	assert found == true
}

fn test_extract_default_column_name() {
	meta := extract_entity_metadata[AnnotCustomUser]()
	// 'email' has no @[column] → column_name == snake_case('email') == 'email'
	mut found := false
	for col in meta.columns {
		if col.field_name == 'email' {
			assert col.column_name == 'email'
			found = true
		}
	}
	assert found == true
}

fn test_extract_primary_key_from_id_attr() {
	meta := extract_entity_metadata[AnnotCustomUser]()
	assert meta.has_primary_key == true
	assert meta.primary_key.field_name == 'user_id'
	assert meta.primary_key.column_name == 'user_id'
	assert meta.primary_key.is_primary == true
}

fn test_extract_primary_key_from_primary_key_attr() {
	meta := extract_entity_metadata[AnnotAltPk]()
	assert meta.has_primary_key == true
	assert meta.primary_key.field_name == 'uid'
	assert meta.primary_key.is_primary == true
}

fn test_extract_has_primary_key_false_without_attr() {
	meta := extract_entity_metadata[AnnotNoPk]()
	// No @[id] or @[primary_key] → has_primary_key is false.
	assert meta.has_primary_key == false
}

fn test_extract_all_columns_in_field_order() {
	meta := extract_entity_metadata[AnnotCustomUser]()
	assert meta.columns.len == 4
	assert meta.columns[0].field_name == 'user_id'
	assert meta.columns[1].field_name == 'name'
	assert meta.columns[2].field_name == 'email'
	assert meta.columns[3].field_name == 'age'
}

fn test_extract_column_types() {
	meta := extract_entity_metadata[AnnotCustomUser]()
	for col in meta.columns {
		match col.field_name {
			'user_id', 'age' { assert col.typ == 'int' }
			'name', 'email' { assert col.typ == 'string' }
			else { assert false, 'unexpected field: ${col.field_name}' }
		}
	}
}

fn test_extract_custom_pk_column_name() {
	// @[id; column('order_id')] → PK field 'oid', column 'order_id'
	meta := extract_entity_metadata[AnnotCustomPkColumn]()
	assert meta.has_primary_key == true
	assert meta.primary_key.field_name == 'oid'
	assert meta.primary_key.column_name == 'order_id'
	assert meta.table_name == 't_order'
}

fn test_is_entity_marker() {
	assert is_entity[AnnotDefaultEntity]() == true
	// AnnotCustomUser has @[table] but not @[entity]
	assert is_entity[AnnotCustomUser]() == false
	assert is_entity[AnnotNoPk]() == false
}

// ════════════════════════════════════════════════════════════════
// JpaRepository[T] integration (SubTask B7.3)
// ════════════════════════════════════════════════════════════════

fn test_jpa_annot_table_name_override() {
	mut repo := annot_mock_setup[AnnotCustomUser]()!
	// @[table('t_user')] overrides the passed 'fallback_table'
	assert repo.table_name == 't_user'
	assert repo.primary_key_field == 'user_id'
	assert repo.primary_key_column == 'user_id'
	// column_names reflect @[column('user_name')] on the 'name' field
	assert repo.column_names == ['user_id', 'user_name', 'email', 'age']
}

fn test_jpa_annot_find_by_id_custom_table_and_column() {
	mut repo := annot_mock_setup[AnnotCustomUser]()!
	repo.save(&AnnotCustomUser{
		user_id: 1
		name:    'Alice'
		email:   'alice@example.com'
		age:     30
	})!
	user := repo.find_by_id(1)!
	assert user.user_id == 1
	assert user.name == 'Alice'
	assert user.email == 'alice@example.com'
	assert user.age == 30
	// The SELECT must target t_user and filter on user_id
	assert g_annot_last_query.contains('FROM t_user')
	assert g_annot_last_query.contains('user_id = ?')
	// The custom column name 'user_name' must appear in the SELECT list
	assert g_annot_last_query.contains('user_name')
}

fn test_jpa_annot_save_generates_custom_column_sql() {
	mut repo := annot_mock_setup[AnnotCustomUser]()!
	repo.save(&AnnotCustomUser{
		user_id: 5
		name:    'Bob'
		email:   'bob@example.com'
		age:     25
	})!
	// INSERT INTO t_user (user_id, user_name, email, age) VALUES (?, ?, ?, ?)
	assert g_annot_last_query.starts_with('INSERT INTO t_user')
	assert g_annot_last_query.contains('user_name')
	assert g_annot_last_query.contains('email')
	assert g_annot_last_query.contains('age')
	// Stored row uses the custom column name
	assert g_annot_rows.len == 1
	assert g_annot_rows[0].get('user_name') == 'Bob'
	assert g_annot_rows[0].get('email') == 'bob@example.com'
}

fn test_jpa_annot_save_auto_increment_skips_pk() {
	mut repo := annot_mock_setup[AnnotCustomUser]()!
	repo.save(&AnnotCustomUser{
		name:  'Carol'
		email: 'carol@example.com'
		age:   40
	})!
	// PK value 0 → omitted from INSERT columns
	assert !g_annot_last_query.contains('user_id, user_name')
	// Auto-assigned by mock
	assert g_annot_rows[0].get('user_id') == '1'
	assert g_annot_rows[0].get('user_name') == 'Carol'
}

fn test_jpa_annot_find_all_custom_table() {
	mut repo := annot_mock_setup[AnnotCustomUser]()!
	repo.save(&AnnotCustomUser{ user_id: 1, name: 'A', email: 'a@b.com', age: 1 })!
	repo.save(&AnnotCustomUser{ user_id: 2, name: 'B', email: 'b@b.com', age: 2 })!
	all := repo.find_all()!
	assert all.len == 2
	assert all[0].name == 'A'
	assert all[1].name == 'B'
	assert g_annot_last_query.contains('FROM t_user')
}

fn test_jpa_annot_delete_custom_pk_column() {
	mut repo := annot_mock_setup[AnnotCustomUser]()!
	repo.save(&AnnotCustomUser{ user_id: 7, name: 'Dan', email: 'd@b.com', age: 50 })!
	assert g_annot_rows.len == 1
	repo.delete(7)!
	assert g_annot_rows.len == 0
	assert g_annot_last_query.contains('DELETE FROM t_user')
	assert g_annot_last_query.contains('user_id = ?')
}

fn test_jpa_annot_count_custom_table() {
	mut repo := annot_mock_setup[AnnotCustomUser]()!
	assert repo.count()! == 0
	repo.save(&AnnotCustomUser{ user_id: 1, name: 'A', email: 'a@b.com', age: 1 })!
	repo.save(&AnnotCustomUser{ user_id: 2, name: 'B', email: 'b@b.com', age: 2 })!
	assert repo.count()! == 2
	assert g_annot_last_query.contains('FROM t_user')
}

fn test_jpa_annot_create_table_custom_names() {
	mut repo := annot_mock_setup[AnnotCustomUser]()!
	repo.create_table()!
	assert g_annot_ddl.len == 1
	ddl := g_annot_ddl[0]
	assert ddl.contains('CREATE TABLE IF NOT EXISTS t_user')
	assert ddl.contains('user_id INTEGER PRIMARY KEY')
	assert ddl.contains('user_name TEXT')
	assert ddl.contains('email TEXT')
	assert ddl.contains('age INTEGER')
}

fn test_jpa_annot_custom_pk_column_integration() {
	mut repo := annot_mock_setup[AnnotCustomPkColumn]()!
	assert repo.table_name == 't_order'
	assert repo.primary_key_field == 'oid'
	assert repo.primary_key_column == 'order_id'
	repo.save(&AnnotCustomPkColumn{ oid: 7, name: 'order1' })!
	// find_by_id uses the custom PK column 'order_id'
	item := repo.find_by_id(7)!
	assert item.oid == 7
	assert item.name == 'order1'
	assert g_annot_last_query.contains('FROM t_order')
	assert g_annot_last_query.contains('order_id = ?')
}

fn test_jpa_annot_create_table_custom_pk_column() {
	mut repo := annot_mock_setup[AnnotCustomPkColumn]()!
	repo.create_table()!
	ddl := g_annot_ddl[0]
	assert ddl.contains('CREATE TABLE IF NOT EXISTS t_order')
	// PK column uses the custom name 'order_id'
	assert ddl.contains('order_id INTEGER PRIMARY KEY')
	assert ddl.contains('name TEXT')
}

// ════════════════════════════════════════════════════════════════
// Backward compatibility: plain structs (no annotations)
// ════════════════════════════════════════════════════════════════

fn test_jpa_annot_backward_compat_plain_struct() {
	// No annotations → table_name from passed param, columns = snake_case(fields)
	annot_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	mut repo := new_jpa_repository[AnnotPlainUser](om, 'default', 'plain_users', annot_mock_exec,
		annot_mock_query)!
	unsafe {
		g_annot_pk_col = repo.primary_key_column
	}
	assert repo.table_name == 'plain_users'
	assert repo.primary_key_field == 'id'
	assert repo.primary_key_column == 'id'
	assert repo.column_names == ['id', 'name', 'email']
	// CRUD still works end-to-end
	repo.save(&AnnotPlainUser{ name: 'Eve', email: 'e@b.com' })!
	user := repo.find_by_id(1)!
	assert user.name == 'Eve'
	assert user.email == 'e@b.com'
}

fn test_jpa_annot_backward_compat_primary_key_attr() {
	// @[primary_key] (the pre-B7 attribute) still works as a PK marker
	meta := extract_entity_metadata[AnnotAltPk]()
	assert meta.has_primary_key == true
	assert meta.primary_key.field_name == 'uid'
	// And the repository detects it
	annot_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	mut repo := new_jpa_repository[AnnotAltPk](om, 'default', 'alt_pk', annot_mock_exec,
		annot_mock_query)!
	unsafe {
		g_annot_pk_col = repo.primary_key_column
	}
	assert repo.primary_key_field == 'uid'
	assert repo.primary_key_column == 'uid'
}

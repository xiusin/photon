module orm

// eager_test.v - Tests for EagerLoader batch relation loading
//
// Verifies that load_has_many / load_belongs_to execute a SINGLE
// batch query with an IN (?, ...) clause for multiple parents
// (solving the N+1 problem) and group results back per parent:
//
//   - load_has_many:  SELECT * FROM child  WHERE fk IN (?, ?, ...)
//   - load_belongs_to: SELECT * FROM parent WHERE id IN (?, ?, ...)
//
// Since photon/orm cannot import db.sqlite (module-name collision
// with V's standard `orm`), these tests use a mock in-memory database
// backed by __global state (compiled with -enable-globals, matching CI).

// ═══════════════════════════════════════════════════════════════════
// Test entities
// ═══════════════════════════════════════════════════════════════════
//
// Table names are derived via get_table_name[T]() = snake_case(T) + 's':
//   EagerUser → eager_users
//   EagerPost → eager_posts

struct EagerUser {
pub mut:
	id   i64
	name string
}

struct EagerPost {
pub mut:
	id      i64
	title   string
	user_id i64
}

// ═══════════════════════════════════════════════════════════════════
// Mock in-memory database
// ═══════════════════════════════════════════════════════════════════
//
// V function-type callbacks cannot capture state, so the mock uses
// __global variables.  Each test resets state via eager_mock_reset().
// The mock is self-contained (does not share state with other test
// files' mocks).

struct EagerMockRow {
mut:
	cols   []string
	values []string
}

fn (mut r EagerMockRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r EagerMockRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_eager_tables map[string][]EagerMockRow
__global g_eager_last_query string
__global g_eager_last_args []string
__global g_eager_query_count int

fn eager_mock_reset() {
	unsafe {
		g_eager_tables = map[string][]EagerMockRow{}
		g_eager_last_query = ''
		g_eager_last_args = []string{}
		g_eager_query_count = 0
	}
}

// eager_mock_insert adds a row to a table.
fn eager_mock_insert(table string, cols []string, vals []string) {
	mut row := EagerMockRow{}
	for i, col in cols {
		if i < vals.len {
			row.set(col, vals[i])
		}
	}
	unsafe {
		if table !in g_eager_tables {
			g_eager_tables[table] = []EagerMockRow{}
		}
		g_eager_tables[table] << row
	}
}

// eager_mock_exec is a no-op for the eager loader (load_* only read).
fn eager_mock_exec(db voidptr, query string, args []string) ! {
	_ = db
	_ = query
	_ = args
}

// eager_mock_query handles: SELECT * FROM <table> WHERE <col> IN (?, ...)
fn eager_mock_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_eager_last_query = query
		g_eager_last_args = args.clone()
		g_eager_query_count++
	}
	q := query.to_lower()
	from_idx := q.index(' from ') or { return error('eager_mock: no FROM clause in: ${query}') }
	after_from := query[from_idx + 6..]
	where_lower := after_from.to_lower().index(' where ') or { after_from.len }
	table := after_from[..where_lower].trim_space()

	// Parse WHERE <col> IN (...)
	mut filter_col := ''
	if where_lower < after_from.len {
		where_str := after_from[where_lower + 7..]
		in_idx := where_str.to_lower().index(' in ') or { where_str.len }
		filter_col = where_str[..in_idx].trim_space()
	}

	rows := unsafe { g_eager_tables[table] or { []EagerMockRow{} } }
	mut result := [][]string{}
	for row in rows {
		if filter_col != '' && row.get(filter_col) !in args {
			continue
		}
		// Return all values in column insertion order
		mut vals := []string{}
		for v in row.values {
			vals << v
		}
		result << vals
	}
	return result
}

// ── Test setup helper ──

fn eager_setup() !&EagerLoader[EagerUser] {
	eager_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	return new_eager_loader_with_fns[EagerUser](om, 'eager_users', 'default', eager_mock_exec,
		eager_mock_query)
}

// ═══════════════════════════════════════════════════════════════════
// load_has_many Tests
// ═══════════════════════════════════════════════════════════════════

fn test_eager_has_many_batch() {
	el := eager_setup()!
	// User 1 has 2 posts, user 2 has 1 post, user 3 (not queried) has 1
	eager_mock_insert('eager_posts', ['id', 'title', 'user_id'], ['1', 'Post 1', '1'])
	eager_mock_insert('eager_posts', ['id', 'title', 'user_id'], ['2', 'Post 2', '1'])
	eager_mock_insert('eager_posts', ['id', 'title', 'user_id'], ['3', 'Post 3', '2'])
	eager_mock_insert('eager_posts', ['id', 'title', 'user_id'], ['4', 'Other', '3'])

	parents := [EagerUser{
		id:   1
		name: 'Alice'
	}, EagerUser{
		id:   2
		name: 'Bob'
	}]
	mut relations := map[int]HasMany[EagerPost]{}
	eager_load_has_many[EagerUser, EagerPost](el, parents, mut relations, 'user_id')!

	// Single batch query (not N+1)
	assert g_eager_query_count == 1
	assert g_eager_last_query.contains('WHERE user_id IN (?, ?)')

	// User 1 → 2 posts
	assert relations[1].loaded == true
	assert relations[1].items.len == 2
	assert relations[1].items[0].title == 'Post 1'
	assert relations[1].items[1].title == 'Post 2'

	// User 2 → 1 post
	assert relations[2].loaded == true
	assert relations[2].items.len == 1
	assert relations[2].items[0].title == 'Post 3'
}

fn test_eager_has_many_parent_without_children() {
	el := eager_setup()!
	eager_mock_insert('eager_posts', ['id', 'title', 'user_id'], ['1', 'Post 1', '1'])

	parents := [EagerUser{
		id:   1
		name: 'Alice'
	}, EagerUser{
		id:   2
		name: 'Bob'
	}]
	mut relations := map[int]HasMany[EagerPost]{}
	eager_load_has_many[EagerUser, EagerPost](el, parents, mut relations, 'user_id')!

	// User 2 has no children → empty but loaded
	assert relations[1].items.len == 1
	assert relations[2].loaded == true
	assert relations[2].items.len == 0
}

fn test_eager_has_many_uses_parameterized_query() {
	el := eager_setup()!
	eager_mock_insert('eager_posts', ['id', 'title', 'user_id'], ['1', 'Post 1', '42'])

	parents := [EagerUser{
		id:   42
		name: 'Bob'
	}]
	mut relations := map[int]HasMany[EagerPost]{}
	eager_load_has_many[EagerUser, EagerPost](el, parents, mut relations, 'user_id')!

	// The query should use ? placeholders, not interpolated values
	assert g_eager_last_query.contains('IN (?)')
	assert !g_eager_last_query.contains('IN (42)')
	assert g_eager_last_args == ['42']
}

fn test_eager_has_many_empty_parents() {
	el := eager_setup()!
	parents := []EagerUser{}
	mut relations := map[int]HasMany[EagerPost]{}
	eager_load_has_many[EagerUser, EagerPost](el, parents, mut relations, 'user_id')!

	// No query executed, no error
	assert g_eager_query_count == 0
	assert relations.len == 0
}

// ═══════════════════════════════════════════════════════════════════
// load_belongs_to Tests
// ═══════════════════════════════════════════════════════════════════

fn eager_setup_post_loader() !&EagerLoader[EagerPost] {
	eager_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	return new_eager_loader_with_fns[EagerPost](om, 'eager_posts', 'default', eager_mock_exec,
		eager_mock_query)
}

fn test_eager_belongs_to_batch() {
	el := eager_setup_post_loader()!
	eager_mock_insert('eager_users', ['id', 'name'], ['1', 'Alice'])
	eager_mock_insert('eager_users', ['id', 'name'], ['2', 'Bob'])

	// Two posts belong to users 1 and 2; third post shares user 1
	parents := [
		EagerPost{
			id:      10
			title:   'P10'
			user_id: 1
		},
		EagerPost{
			id:      11
			title:   'P11'
			user_id: 2
		},
		EagerPost{
			id:      12
			title:   'P12'
			user_id: 1
		},
	]
	mut relations := map[int]BelongsTo[EagerUser]{}
	eager_load_belongs_to[EagerPost, EagerUser](el, parents, mut relations, 'user_id')!

	// Single batch query with distinct FK values (1, 2) — not 3 queries
	assert g_eager_query_count == 1
	assert g_eager_last_query.contains('WHERE id IN (?, ?)')

	assert relations[10].loaded == true
	assert relations[10].item.name == 'Alice'
	assert relations[11].loaded == true
	assert relations[11].item.name == 'Bob'
	assert relations[12].loaded == true
	assert relations[12].item.name == 'Alice'
}

fn test_eager_belongs_to_null_fk() {
	el := eager_setup_post_loader()!
	eager_mock_insert('eager_users', ['id', 'name'], ['1', 'Alice'])

	// Post 10 has user 1; post 11 has null FK (user_id = 0)
	parents := [
		EagerPost{
			id:      10
			title:   'P10'
			user_id: 1
		},
		EagerPost{
			id:      11
			title:   'Orphan'
			user_id: 0
		},
	]
	mut relations := map[int]BelongsTo[EagerUser]{}
	eager_load_belongs_to[EagerPost, EagerUser](el, parents, mut relations, 'user_id')!

	// Null FK must not be queried (only '1' bound)
	assert g_eager_last_args == ['1']
	assert relations[10].item.name == 'Alice'
	assert relations[11].loaded == true
	assert relations[11].item.id == 0
}

fn test_eager_belongs_to_missing_parent() {
	el := eager_setup_post_loader()!
	// No users in DB
	parents := [EagerPost{
		id:      10
		title:   'P10'
		user_id: 999
	}]
	mut relations := map[int]BelongsTo[EagerUser]{}
	eager_load_belongs_to[EagerPost, EagerUser](el, parents, mut relations, 'user_id')!

	// Should not error; item stays zero value, loaded = true
	assert relations[10].loaded == true
	assert relations[10].item.id == 0
}

fn test_eager_belongs_to_all_null_fk_skips_query() {
	el := eager_setup_post_loader()!
	parents := [EagerPost{
		id:      10
		title:   'Orphan'
		user_id: 0
	}]
	mut relations := map[int]BelongsTo[EagerUser]{}
	eager_load_belongs_to[EagerPost, EagerUser](el, parents, mut relations, 'user_id')!

	// Every FK is null → no DB round-trip at all
	assert g_eager_query_count == 0
	assert relations[10].loaded == true
	assert relations[10].item.id == 0
}

// ═══════════════════════════════════════════════════════════════════
// Error cases
// ═══════════════════════════════════════════════════════════════════

fn test_eager_has_many_without_query_fn() {
	eager_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	el := new_eager_loader[EagerUser](om, 'eager_users') // no callbacks

	parents := [EagerUser{
		id:   1
		name: 'Alice'
	}]
	mut relations := map[int]HasMany[EagerPost]{}
	if _ := eager_load_has_many[EagerUser, EagerPost](el, parents, mut relations, 'user_id') {
		assert false, 'expected error: query_fn not configured'
	} else {
		assert true
	}
}

fn test_eager_belongs_to_without_query_fn() {
	eager_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	el := new_eager_loader[EagerPost](om, 'eager_posts') // no callbacks

	parents := [EagerPost{
		id:      10
		title:   'P10'
		user_id: 1
	}]
	mut relations := map[int]BelongsTo[EagerUser]{}
	if _ := eager_load_belongs_to[EagerPost, EagerUser](el, parents, mut relations, 'user_id') {
		assert false, 'expected error: query_fn not configured'
	} else {
		assert true
	}
}

fn test_eager_has_many_invalid_fk() {
	el := eager_setup()!
	parents := [EagerUser{
		id:   1
		name: 'Alice'
	}]
	mut relations := map[int]HasMany[EagerPost]{}
	if _ := eager_load_has_many[EagerUser, EagerPost](el, parents, mut relations, 'user_id; DROP TABLE users') {
		assert false, 'expected error: invalid foreign key'
	} else {
		assert true // rejected by identifier whitelist
	}
}

// ═══════════════════════════════════════════════════════════════════
// Backward compatibility: new_eager_loader / new_eager_repository
// ═══════════════════════════════════════════════════════════════════

fn test_new_eager_loader_backward_compat() {
	om := new_orm_manager()
	el := new_eager_loader[EagerUser](om, 'eager_users')
	assert isnil(el.query_fn)
	assert isnil(el.exec_fn)
}

fn test_new_eager_repository_with_fns() {
	eager_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	repo := new_eager_repository_with_fns[EagerUser](om, 'eager_users', 'default', eager_mock_exec,
		eager_mock_query)
	assert !isnil(repo.eager_loader.query_fn)
	assert repo.eager_loader.db_name == 'default'
}

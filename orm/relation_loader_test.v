module orm

// relation_loader_test.v - Tests for RelationLoader (Task B2)
//
// Verifies the three relation loaders execute correct parameterized
// SQL and backfill HasMany / BelongsTo / ManyToMany placeholders:
//
//   - load_has_many: SELECT * FROM child WHERE fk = ?
//   - load_belongs_to: SELECT * FROM parent WHERE id = ?
//   - load_many_to_many: SELECT t.* FROM target t
//                        INNER JOIN pivot p ON t.id = p.target_fk
//                        WHERE p.local_fk = ?
//
// Since photon/orm cannot import db.sqlite (module-name collision
// with V's standard `orm`), these tests use a mock in-memory database
// backed by __global state (compiled with -enable-globals, matching CI).
// The mock supports multiple tables and JOIN queries.

// ═══════════════════════════════════════════════════════════════════
// Test entities
// ═══════════════════════════════════════════════════════════════════
//
// Table names are derived via get_table_name[T]() = snake_case(T) + 's':
//   RelUser    → rel_users
//   RelPost    → rel_posts
//   RelProfile → rel_profiles
//   RelRole    → rel_roles
//   RelComment → rel_comments  (uses custom FK 'author_id')

struct RelUser {
pub mut:
	id   i64
	name string
}

struct RelPost {
pub mut:
	id      i64
	title   string
	user_id i64
}

struct RelProfile {
pub mut:
	id      i64
	bio     string
	user_id i64
}

struct RelRole {
pub mut:
	id   i64
	name string
}

struct RelComment {
pub mut:
	id        i64
	body      string
	author_id i64
}

// ═══════════════════════════════════════════════════════════════════
// Mock in-memory database (multi-table)
// ═══════════════════════════════════════════════════════════════════
//
// V function-type callbacks cannot capture state, so the mock uses
// __global variables.  Each test resets state via rel_mock_reset().
// The mock is self-contained (does not share state with other test
// files' mocks).

struct RelMockRow {
mut:
	cols   []string
	values []string
}

fn (mut r RelMockRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r RelMockRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_rel_tables map[string][]RelMockRow
__global g_rel_last_query string

fn rel_mock_reset() {
	unsafe {
		g_rel_tables = map[string][]RelMockRow{}
		g_rel_last_query = ''
	}
}

// rel_mock_insert adds a row to a table.
fn rel_mock_insert(table string, cols []string, vals []string) {
	mut row := RelMockRow{}
	for i, col in cols {
		if i < vals.len {
			row.set(col, vals[i])
		}
	}
	unsafe {
		if table !in g_rel_tables {
			g_rel_tables[table] = []RelMockRow{}
		}
		g_rel_tables[table] << row
	}
}

// rel_mock_exec is a no-op for the relation loader (load_* only read).
fn rel_mock_exec(db voidptr, query string, args []string) ! {
	_ = db
	_ = query
	_ = args
}

// rel_mock_query handles SELECT statements:
//   1. SELECT * FROM <table> WHERE <col> = ?
//   2. SELECT t.* FROM <table> t INNER JOIN <pivot> p
//      ON t.id = p.<target_fk> WHERE p.<local_fk> = ?
fn rel_mock_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_rel_last_query = query
	}
	q := query.to_lower()

	if q.contains(' inner join ') {
		return rel_mock_query_join(query, args)
	}
	return rel_mock_query_simple(query, args)
}

// rel_mock_query_simple handles: SELECT * FROM <table> [WHERE <col> = ?]
fn rel_mock_query_simple(query string, args []string) ![][]string {
	q := query.to_lower()
	from_idx := q.index(' from ') or {
		return error('rel_mock: no FROM clause in: ${query}')
	}
	after_from := query[from_idx + 6..]
	where_lower := after_from.to_lower().index(' where ') or { after_from.len }
	table := after_from[..where_lower].trim_space()

	// Parse WHERE clause
	mut filter_col := ''
	mut target := ''
	if where_lower < after_from.len && args.len > 0 {
		where_str := after_from[where_lower + 7..]
		eq_idx := where_str.index('=') or { where_str.len }
		filter_col = where_str[..eq_idx].trim_space()
		target = args[0]
	}

	rows := unsafe { g_rel_tables[table] or { []RelMockRow{} } }
	mut result := [][]string{}
	for row in rows {
		if filter_col != '' && row.get(filter_col) != target {
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

// rel_mock_query_join handles:
//   SELECT t.* FROM <target> t INNER JOIN <pivot> p
//   ON t.id = p.<target_fk> WHERE p.<local_fk> = ?
fn rel_mock_query_join(query string, args []string) ![][]string {
	q := query.to_lower()
	from_idx := q.index(' from ') or {
		return error('rel_mock: no FROM clause in: ${query}')
	}
	after_from := query[from_idx + 6..]
	join_idx := after_from.to_lower().index(' inner join ') or {
		return error('rel_mock: no INNER JOIN in: ${query}')
	}
	// target table + alias: "target_table t"
	target_part := after_from[..join_idx].trim_space()
	target_parts := target_part.split(' ')
	target_table := target_parts[0]

	// pivot part: "pivot p ON t.id = p.target_fk WHERE ..."
	pivot_part := after_from[join_idx + 12..]
	on_idx := pivot_part.to_lower().index(' on ') or {
		return error('rel_mock: no ON clause in: ${query}')
	}
	pivot_table_alias := pivot_part[..on_idx].trim_space()
	pivot_table := pivot_table_alias.split(' ')[0]

	// ON clause + WHERE: "t.id = p.target_fk WHERE p.local_fk = ?"
	on_and_rest := pivot_part[on_idx + 4..]
	where_idx := on_and_rest.to_lower().index(' where ') or { on_and_rest.len }
	on_clause := on_and_rest[..where_idx].trim_space()
	// Parse: t.id = p.target_fk
	on_parts := on_clause.split('=').map(it.trim_space())
	// on_parts[1] = "p.target_fk" → extract "target_fk"
	target_fk_col := on_parts[1].split('.')[1]

	// WHERE clause: "p.local_fk = ?"
	mut local_fk_col := ''
	if where_idx < on_and_rest.len && args.len > 0 {
		where_str := on_and_rest[where_idx + 7..]
		eq_idx := where_str.index('=') or { where_str.len }
		local_fk_full := where_str[..eq_idx].trim_space()
		// e.g. "p.local_fk" → "local_fk"
		local_fk_col = local_fk_full.split('.')[1]
	}

	target_value := if args.len > 0 { args[0] } else { '' }

	// 1. Find pivot rows where local_fk = target_value, collect target_fk values
	pivot_rows := unsafe { g_rel_tables[pivot_table] or { []RelMockRow{} } }
	mut target_ids := []string{}
	for prow in pivot_rows {
		if prow.get(local_fk_col) == target_value {
			target_ids << prow.get(target_fk_col)
		}
	}

	// 2. Fetch target rows matching those IDs
	target_rows := unsafe { g_rel_tables[target_table] or { []RelMockRow{} } }
	mut result := [][]string{}
	for trow in target_rows {
		if trow.get('id') in target_ids {
			mut vals := []string{}
			for v in trow.values {
				vals << v
			}
			result << vals
		}
	}
	return result
}

// ── Test setup helper ──

fn rel_setup() !&RelationLoader {
	rel_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	return new_relation_loader_with_fns(om, 'default', rel_mock_exec, rel_mock_query)
}

// ═══════════════════════════════════════════════════════════════════
// load_has_many Tests (SubTask B2.1)
// ═══════════════════════════════════════════════════════════════════

fn test_load_has_many_basic() {
	rl := rel_setup()!
	// User 1 has 3 posts
	rel_mock_insert('rel_posts', ['id', 'title', 'user_id'], ['1', 'Post 1', '1'])
	rel_mock_insert('rel_posts', ['id', 'title', 'user_id'], ['2', 'Post 2', '1'])
	rel_mock_insert('rel_posts', ['id', 'title', 'user_id'], ['3', 'Post 3', '1'])
	// User 2 has 1 post (should not appear for user 1)
	rel_mock_insert('rel_posts', ['id', 'title', 'user_id'], ['4', 'Other Post', '2'])

	user := RelUser{ id: 1, name: 'Alice' }
	mut posts := new_has_many[RelPost]()
	rl.load_has_many[RelUser, RelPost](user, mut posts, 'user_id')!

	assert posts.loaded == true
	assert posts.items.len == 3
	assert posts.items[0].id == 1
	assert posts.items[0].title == 'Post 1'
	assert posts.items[0].user_id == 1
	assert posts.items[1].title == 'Post 2'
	assert posts.items[2].title == 'Post 3'
}

fn test_load_has_many_empty() {
	rl := rel_setup()!
	// User 1 has no posts
	user := RelUser{ id: 1, name: 'Alice' }
	mut posts := new_has_many[RelPost]()
	rl.load_has_many[RelUser, RelPost](user, mut posts, 'user_id')!

	assert posts.loaded == true
	assert posts.items.len == 0
}

fn test_load_has_many_uses_parameterized_query() {
	rl := rel_setup()!
	rel_mock_insert('rel_posts', ['id', 'title', 'user_id'], ['1', 'Post 1', '1'])

	user := RelUser{ id: 42, name: 'Bob' }
	mut posts := new_has_many[RelPost]()
	rl.load_has_many[RelUser, RelPost](user, mut posts, 'user_id')!

	// The query should use ? placeholder, not interpolated value
	assert g_rel_last_query.contains('WHERE user_id = ?')
	assert !g_rel_last_query.contains('WHERE user_id = 42')
}

// ═══════════════════════════════════════════════════════════════════
// load_belongs_to Tests (SubTask B2.2)
// ═══════════════════════════════════════════════════════════════════

fn test_load_belongs_to_basic() {
	rl := rel_setup()!
	// Parent users
	rel_mock_insert('rel_users', ['id', 'name'], ['2', 'Bob'])
	// Post belongs to user 2
	post := RelPost{ id: 10, title: 'Hello', user_id: 2 }
	mut user_rel := new_belongs_to[RelUser]()
	rl.load_belongs_to[RelPost, RelUser](post, mut user_rel, 'user_id')!

	assert user_rel.loaded == true
	assert user_rel.item.id == 2
	assert user_rel.item.name == 'Bob'
}

fn test_load_belongs_to_null_fk() {
	rl := rel_setup()!
	// Post with user_id = 0 (null FK)
	post := RelPost{ id: 10, title: 'Orphan', user_id: 0 }
	mut user_rel := new_belongs_to[RelUser]()
	rl.load_belongs_to[RelPost, RelUser](post, mut user_rel, 'user_id')!

	// Should not error; item stays as zero value
	assert user_rel.loaded == true
	assert user_rel.item.id == 0
	assert user_rel.item.name == ''
}

fn test_load_belongs_to_not_found() {
	rl := rel_setup()!
	// No users in DB
	post := RelPost{ id: 10, title: 'Hello', user_id: 999 }
	mut user_rel := new_belongs_to[RelUser]()
	rl.load_belongs_to[RelPost, RelUser](post, mut user_rel, 'user_id')!

	// Should not error; item stays as zero value, loaded = true
	assert user_rel.loaded == true
	assert user_rel.item.id == 0
}

fn test_load_belongs_to_uses_parameterized_query() {
	rl := rel_setup()!
	rel_mock_insert('rel_users', ['id', 'name'], ['5', 'Eve'])

	post := RelPost{ id: 1, title: 'Test', user_id: 5 }
	mut user_rel := new_belongs_to[RelUser]()
	rl.load_belongs_to[RelPost, RelUser](post, mut user_rel, 'user_id')!

	assert g_rel_last_query.contains('WHERE id = ?')
	assert !g_rel_last_query.contains('WHERE id = 5')
}

// ═══════════════════════════════════════════════════════════════════
// load_many_to_many Tests (SubTask B2.3)
// ═══════════════════════════════════════════════════════════════════

fn test_load_many_to_many_basic() {
	rl := rel_setup()!
	// Roles
	rel_mock_insert('rel_roles', ['id', 'name'], ['1', 'admin'])
	rel_mock_insert('rel_roles', ['id', 'name'], ['2', 'editor'])
	rel_mock_insert('rel_roles', ['id', 'name'], ['3', 'viewer'])
	// Pivot: user 1 has roles 1 and 2
	rel_mock_insert('rel_user_roles', ['user_id', 'role_id'], ['1', '1'])
	rel_mock_insert('rel_user_roles', ['user_id', 'role_id'], ['1', '2'])
	// Pivot: user 2 has role 3 (should not appear for user 1)
	rel_mock_insert('rel_user_roles', ['user_id', 'role_id'], ['2', '3'])

	user := RelUser{ id: 1, name: 'Alice' }
	mut roles := new_many_to_many[RelRole]()
	rl.load_many_to_many[RelUser, RelRole](user, mut roles, 'rel_user_roles', 'user_id', 'role_id')!

	assert roles.loaded == true
	assert roles.items.len == 2
	assert roles.items[0].id == 1
	assert roles.items[0].name == 'admin'
	assert roles.items[1].id == 2
	assert roles.items[1].name == 'editor'
}

fn test_load_many_to_many_empty() {
	rl := rel_setup()!
	rel_mock_insert('rel_roles', ['id', 'name'], ['1', 'admin'])
	// No pivot entries for user 1

	user := RelUser{ id: 1, name: 'Alice' }
	mut roles := new_many_to_many[RelRole]()
	rl.load_many_to_many[RelUser, RelRole](user, mut roles, 'rel_user_roles', 'user_id', 'role_id')!

	assert roles.loaded == true
	assert roles.items.len == 0
}

fn test_load_many_to_many_uses_join_query() {
	rl := rel_setup()!
	rel_mock_insert('rel_roles', ['id', 'name'], ['1', 'admin'])
	rel_mock_insert('rel_user_roles', ['user_id', 'role_id'], ['1', '1'])

	user := RelUser{ id: 1, name: 'Alice' }
	mut roles := new_many_to_many[RelRole]()
	rl.load_many_to_many[RelUser, RelRole](user, mut roles, 'rel_user_roles', 'user_id', 'role_id')!

	// Verify JOIN query structure
	assert g_rel_last_query.contains('SELECT t.* FROM rel_roles t')
	assert g_rel_last_query.contains('INNER JOIN rel_user_roles p')
	assert g_rel_last_query.contains('ON t.id = p.role_id')
	assert g_rel_last_query.contains('WHERE p.user_id = ?')
}

// ═══════════════════════════════════════════════════════════════════
// Multiple relations on the same entity
// ═══════════════════════════════════════════════════════════════════

fn test_multiple_relations_same_entity() {
	rl := rel_setup()!
	// User 1 has posts and roles
	rel_mock_insert('rel_users', ['id', 'name'], ['1', 'Alice'])
	rel_mock_insert('rel_posts', ['id', 'title', 'user_id'], ['1', 'Post 1', '1'])
	rel_mock_insert('rel_posts', ['id', 'title', 'user_id'], ['2', 'Post 2', '1'])
	rel_mock_insert('rel_roles', ['id', 'name'], ['10', 'admin'])
	rel_mock_insert('rel_user_roles', ['user_id', 'role_id'], ['1', '10'])

	user := RelUser{ id: 1, name: 'Alice' }

	// Load has_many posts
	mut posts := new_has_many[RelPost]()
	rl.load_has_many[RelUser, RelPost](user, mut posts, 'user_id')!
	assert posts.items.len == 2

	// Load many_to_many roles
	mut roles := new_many_to_many[RelRole]()
	rl.load_many_to_many[RelUser, RelRole](user, mut roles, 'rel_user_roles', 'user_id', 'role_id')!
	assert roles.items.len == 1
	assert roles.items[0].name == 'admin'

	// Load belongs_to from a post → user
	post := RelPost{ id: 1, title: 'Post 1', user_id: 1 }
	mut author := new_belongs_to[RelUser]()
	rl.load_belongs_to[RelPost, RelUser](post, mut author, 'user_id')!
	assert author.item.name == 'Alice'
}

// ═══════════════════════════════════════════════════════════════════
// Custom FK column name
// ═══════════════════════════════════════════════════════════════════

fn test_load_has_many_custom_fk_column() {
	rl := rel_setup()!
	// RelComment uses 'author_id' as FK to RelUser
	rel_mock_insert('rel_comments', ['id', 'body', 'author_id'], ['1', 'Nice!', '5'])
	rel_mock_insert('rel_comments', ['id', 'body', 'author_id'], ['2', 'Cool', '5'])
	rel_mock_insert('rel_comments', ['id', 'body', 'author_id'], ['3', 'Other', '6'])

	user := RelUser{ id: 5, name: 'Author' }
	mut comments := new_has_many[RelComment]()
	rl.load_has_many[RelUser, RelComment](user, mut comments, 'author_id')!

	assert comments.items.len == 2
	assert comments.items[0].body == 'Nice!'
	assert comments.items[1].body == 'Cool'
	// Verify the query used the custom FK column
	assert g_rel_last_query.contains('WHERE author_id = ?')
}

fn test_load_belongs_to_custom_fk_column() {
	rl := rel_setup()!
	rel_mock_insert('rel_users', ['id', 'name'], ['5', 'Author'])

	comment := RelComment{ id: 1, body: 'Nice!', author_id: 5 }
	mut author := new_belongs_to[RelUser]()
	rl.load_belongs_to[RelComment, RelUser](comment, mut author, 'author_id')!

	assert author.item.id == 5
	assert author.item.name == 'Author'
}

// ═══════════════════════════════════════════════════════════════════
// @[primary_key] attribute support
// ═══════════════════════════════════════════════════════════════════

struct RelArticle {
pub mut:
	article_id i64 @[primary_key]
	title      string
}

struct RelTag {
pub mut:
	id    i64
	name  string
}

fn test_load_has_many_with_primary_key_attr() {
	rl := rel_setup()!
	// RelArticle uses article_id as PK (via @[primary_key])
	rel_mock_insert('rel_tags', ['id', 'name'], ['1', 'vlang'])
	rel_mock_insert('rel_tags', ['id', 'name'], ['2', 'orm'])
	// Pivot: article 100 has tags 1 and 2
	rel_mock_insert('rel_article_tags', ['article_id', 'tag_id'], ['100', '1'])
	rel_mock_insert('rel_article_tags', ['article_id', 'tag_id'], ['100', '2'])

	article := RelArticle{ article_id: 100, title: 'Hello V' }
	mut tags := new_many_to_many[RelTag]()
	rl.load_many_to_many[RelArticle, RelTag](article, mut tags, 'rel_article_tags', 'article_id', 'tag_id')!

	assert tags.items.len == 2
	assert tags.items[0].name == 'vlang'
	assert tags.items[1].name == 'orm'
}

// ═══════════════════════════════════════════════════════════════════
// Error cases
// ═══════════════════════════════════════════════════════════════════

fn test_load_has_many_without_query_fn() {
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	rl := new_relation_loader(om) // no callbacks

	user := RelUser{ id: 1, name: 'Alice' }
	mut posts := new_has_many[RelPost]()
	if _ := rl.load_has_many[RelUser, RelPost](user, mut posts, 'user_id') {
		assert false, 'expected error: query_fn not configured'
	} else {
		assert true
	}
}

fn test_load_belongs_to_without_query_fn() {
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	rl := new_relation_loader(om)

	post := RelPost{ id: 1, title: 'Test', user_id: 1 }
	mut user_rel := new_belongs_to[RelUser]()
	if _ := rl.load_belongs_to[RelPost, RelUser](post, mut user_rel, 'user_id') {
		assert false, 'expected error: query_fn not configured'
	} else {
		assert true
	}
}

fn test_load_many_to_many_without_query_fn() {
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	rl := new_relation_loader(om)

	user := RelUser{ id: 1, name: 'Alice' }
	mut roles := new_many_to_many[RelRole]()
	if _ := rl.load_many_to_many[RelUser, RelRole](user, mut roles, 'rel_user_roles', 'user_id', 'role_id') {
		assert false, 'expected error: query_fn not configured'
	} else {
		assert true
	}
}

// ═══════════════════════════════════════════════════════════════════
// Backward compatibility: new_relation_loader still works
// ═══════════════════════════════════════════════════════════════════

fn test_new_relation_loader_backward_compat() {
	om := new_orm_manager()
	rl := new_relation_loader(om)
	assert isnil(rl.query_fn)
	assert isnil(rl.exec_fn)
}

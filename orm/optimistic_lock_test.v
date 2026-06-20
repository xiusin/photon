module orm

// optimistic_lock_test.v - Tests for @[version] optimistic locking (Task B8)
//
// Verifies:
//   B8.1 — comptime scan of @[version] field, recording the field name
//   B8.2 — save()/update() UPDATE SQL adds WHERE pk=? AND version=?,
//          SET clause includes version = version + 1
//   B8.3 — affected rows = 0 raises OptimisticLockException
//   B8.4 — concurrent conflict scenario (stale-version writer loses)
//
// The mock DB helpers here use an `ol_` prefix to keep state isolated
// from jpa_repository_test.v's mock (both live in the same module).
// The mock simulates a real DB's row-level version check: an UPDATE
// whose WHERE version=? clause matches nothing reports 0 affected rows.

// ════════════════════════════════════════════════════════════════
// Test entities
// ════════════════════════════════════════════════════════════════

// OlVersionedUser — standard versioned entity (PK via 'id' name fallback).
struct OlVersionedUser {
pub mut:
	id      i64
	name    string
	email   string
	version int @[version]
}

// OlVersionedArticle — version field named 'ver', PK via @[primary_key].
struct OlVersionedArticle {
pub mut:
	article_id i64 @[primary_key]
	title      string
	ver        int @[version]
}

// OlPlainUser — no @[version]; save()/update() must behave as before.
struct OlPlainUser {
pub mut:
	id    i64
	name  string
	email string
}

// ════════════════════════════════════════════════════════════════
// Mock in-memory database (ol_-prefixed, isolated state)
// ════════════════════════════════════════════════════════════════

// OlRow is a self-contained mock row (column→value pairs) so this
// test file does not depend on MockRow from jpa_repository_test.v.
struct OlRow {
mut:
	cols   []string
	values []string
}

fn (mut r OlRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r OlRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_ol_rows []OlRow
__global g_ol_next_id i64
__global g_ol_last_query string
__global g_ol_last_args []string
__global g_ol_affected int
__global g_ol_pk_col string

fn ol_mock_reset() {
	unsafe {
		g_ol_rows = []OlRow{}
		g_ol_next_id = 1
		g_ol_last_query = ''
		g_ol_last_args = []string{}
		g_ol_affected = 0
		g_ol_pk_col = 'id'
	}
}

fn ol_mock_affected_rows(db voidptr) !int {
	_ = db
	return g_ol_affected
}

// ol_mock_setup builds a JpaRepository[T] wired to the ol_ mock,
// with affected_rows_fn configured (required for optimistic locking).
fn ol_mock_setup[T]() !JpaRepository[T] {
	ol_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	mut repo := new_jpa_repository[T](om, 'default', 'ol_test_table', ol_mock_exec, ol_mock_query)!
	repo.set_affected_rows_fn(ol_mock_affected_rows)
	unsafe {
		g_ol_pk_col = repo.primary_key_field
	}
	return repo
}

// ol_mock_exec handles INSERT / UPDATE / DELETE / CREATE TABLE.
fn ol_mock_exec(db voidptr, query string, args []string) ! {
	_ = db
	unsafe {
		g_ol_last_query = query
		g_ol_last_args = args.clone()
	}
	q := query.to_lower()
	if q.starts_with('create table') {
		return
	}
	if q.starts_with('insert into') {
		ol_mock_handle_insert(query, args)!
		return
	}
	if q.starts_with('update ') {
		ol_mock_handle_update(query, args)
		return
	}
	if q.starts_with('delete from') {
		ol_mock_handle_delete(args)
		return
	}
}

fn ol_mock_handle_insert(query string, args []string) ! {
	open_paren := query.index('(') or { return error('ol mock: cannot parse INSERT columns') }
	rest := query[open_paren + 1..]
	close_offset := rest.index(')') or { return error('ol mock: cannot parse INSERT columns') }
	cols_str := rest[..close_offset]
	cols := cols_str.split(',').map(it.trim_space())
	mut row := OlRow{}
	for i, col in cols {
		if i < args.len {
			row.set(col, args[i])
		}
	}
	// Auto-assign PK if missing or zero
	pk_val := row.get(g_ol_pk_col)
	if pk_val == '' || pk_val == '0' {
		next := g_ol_next_id
		row.set(g_ol_pk_col, '${next}')
		unsafe {
			g_ol_next_id = next + 1
		}
	}
	unsafe {
		g_ol_rows << row
		g_ol_affected = 1
	}
}

// ol_mock_handle_update simulates a real DB's UPDATE semantics:
//   1. Parse SET clause → columns with ? placeholders + increment exprs
//   2. Parse WHERE clause → filter columns
//   3. Map args to [set_values..., where_values...]
//   4. Find matching rows (all WHERE conditions must match)
//   5. Apply SET values and version increments to matching rows
//   6. g_ol_affected = number of matched rows (0 → conflict)
fn ol_mock_handle_update(query string, args []string) {
	q := query.to_lower()
	set_idx := q.index(' set ') or { return }
	where_idx := q.index(' where ') or { return }

	set_clause := query[set_idx + 5..where_idx]
	where_clause := query[where_idx + 7..]

	// Parse SET clause: "col1 = ?, col2 = ?, version = version + 1"
	set_parts := set_clause.split(', ')
	mut set_cols := []string{}
	mut increment_cols := []string{}
	mut placeholder_count := 0
	for part in set_parts {
		pt := part.trim_space()
		if pt.contains('?') {
			eq_idx := pt.index('=') or { continue }
			set_cols << pt[..eq_idx].trim_space()
			placeholder_count++
		} else if pt.contains('+ 1') || pt.contains('+1') {
			// "version = version + 1" — increment expression, no placeholder
			eq_idx := pt.index('=') or { continue }
			increment_cols << pt[..eq_idx].trim_space()
		}
	}

	// Parse WHERE clause: "pk = ? AND version = ?" or "pk = ?"
	// Lowercase for case-insensitive 'AND' / 'and' splitting; column
	// names are snake_case so lowercasing is safe.
	where_parts := where_clause.to_lower().split(' and ')
	mut where_cols := []string{}
	for wp in where_parts {
		wpt := wp.trim_space()
		if wpt.contains('?') {
			eq_idx := wpt.index('=') or { continue }
			where_cols << wpt[..eq_idx].trim_space()
		}
	}

	// Args layout: [set placeholder values..., where placeholder values...]
	set_values := if placeholder_count > 0 { args[..placeholder_count] } else { []string{} }
	where_values := args[placeholder_count..]

	// Find and update matching rows
	mut affected := 0
	mut updated_rows := []OlRow{cap: g_ol_rows.len}
	for row in g_ol_rows {
		mut matches := true
		for i, col in where_cols {
			if i < where_values.len && row.get(col) != where_values[i] {
				matches = false
				break
			}
		}
		if matches {
			mut new_row := row
			for i, col in set_cols {
				if i < set_values.len {
					new_row.set(col, set_values[i])
				}
			}
			for col in increment_cols {
				cur := new_row.get(col).int()
				new_row.set(col, '${cur + 1}')
			}
			updated_rows << new_row
			affected++
		} else {
			updated_rows << row
		}
	}
	unsafe {
		g_ol_rows = updated_rows
		g_ol_affected = affected
	}
}

fn ol_mock_handle_delete(args []string) {
	if args.len == 0 {
		return
	}
	target := args[0]
	pk_col := g_ol_pk_col
	mut kept := []OlRow{}
	mut deleted := 0
	for row in g_ol_rows {
		if row.get(pk_col) != target {
			kept << row
		} else {
			deleted++
		}
	}
	unsafe {
		g_ol_rows = kept
		g_ol_affected = deleted
	}
}

// ol_mock_query handles SELECT (including COUNT).
fn ol_mock_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_ol_last_query = query
	}
	q := query.to_lower()
	if q.contains('count(*)') {
		count := g_ol_rows.len
		return [['${count}']]
	}
	after_select := query[7..]
	from_idx := after_select.to_lower().index(' from ') or {
		return error('ol mock: cannot parse SELECT: no FROM clause')
	}
	cols_str := after_select[..from_idx]
	cols := cols_str.split(',').map(it.trim_space())
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
	for row in g_ol_rows {
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
// B8.1 — comptime @[version] field detection
// ════════════════════════════════════════════════════════════════

fn test_ol_version_field_detected() {
	repo := ol_mock_setup[OlVersionedUser]()!
	assert repo.has_version == true
	assert repo.version_field == 'version'
}

fn test_ol_version_field_detected_custom_name() {
	repo := ol_mock_setup[OlVersionedArticle]()!
	assert repo.has_version == true
	assert repo.version_field == 'ver'
	assert repo.primary_key_field == 'article_id'
}

fn test_ol_no_version_field_when_absent() {
	repo := ol_mock_setup[OlPlainUser]()!
	assert repo.has_version == false
	assert repo.version_field == ''
}

// ════════════════════════════════════════════════════════════════
// B8.2 — UPDATE SQL: WHERE pk=? AND version=?, SET version=version+1
// ════════════════════════════════════════════════════════════════

fn test_ol_save_new_entity_inserts_with_version_zero() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	// New entity (id=0) → INSERT, not UPDATE
	assert g_ol_last_query.to_lower().starts_with('insert into')
	assert g_ol_rows.len == 1
	assert g_ol_rows[0].get('version') == '0'
	assert g_ol_rows[0].get('name') == 'Alice'
}

fn test_ol_update_generates_versioned_sql() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	// Now update the existing entity
	repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice2'
		email:   'alice@example.com'
		version: 0
	})!
	// Verify the UPDATE SQL structure
	assert g_ol_last_query.to_lower().starts_with('update ')
	// SET clause must include version = version + 1
	assert g_ol_last_query.contains('version = version + 1')
	// WHERE clause must include both pk and version checks
	assert g_ol_last_query.contains('id = ?')
	assert g_ol_last_query.contains('version = ?')
	// Verify args: [name, email, id, version]
	assert g_ol_last_args.len == 4
	assert g_ol_last_args[0] == 'Alice2'
	assert g_ol_last_args[1] == 'alice@example.com'
	assert g_ol_last_args[2] == '1'
	assert g_ol_last_args[3] == '0'
}

fn test_ol_update_increments_version_in_db() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	// version starts at 0
	user := repo.find_by_id(1)!
	assert user.version == 0
	// Update → version becomes 1
	repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice2'
		email:   'alice@example.com'
		version: 0
	})!
	updated := repo.find_by_id(1)!
	assert updated.version == 1
	assert updated.name == 'Alice2'
}

fn test_ol_update_returns_entity_with_incremented_version() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	// update() returns a copy with version+1
	result := repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice2'
		email:   'alice@example.com'
		version: 0
	})!
	assert result.id == 1
	assert result.name == 'Alice2'
	assert result.version == 1
}

fn test_ol_update_custom_version_column_name() {
	mut repo := ol_mock_setup[OlVersionedArticle]()!
	repo.save(&OlVersionedArticle{
		article_id: 100
		title:      'Hello'
	})!
	repo.update(&OlVersionedArticle{
		article_id: 100
		title:      'World'
		ver:        0
	})!
	// The version column should be 'ver' (snake_case of field name)
	assert g_ol_last_query.contains('ver = ver + 1')
	assert g_ol_last_query.contains('ver = ?')
	// Verify DB state
	article := repo.find_by_id(100)!
	assert article.title == 'World'
	assert article.ver == 1
}

// ════════════════════════════════════════════════════════════════
// B8.3 — affected rows = 0 raises OptimisticLockException
// ════════════════════════════════════════════════════════════════

fn test_ol_optimistic_lock_exception_on_stale_version() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	// First update succeeds (version 0 → 1)
	repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice2'
		email:   'alice@example.com'
		version: 0
	})!
	// Second update with stale version=0 → should fail
	mut caught := false
	mut err_msg := ''
	if _ := repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice3'
		email:   'alice@example.com'
		version: 0
	}) {
		assert false, 'expected OptimisticLockException for stale version'
	} else {
		caught = true
		err_msg = err.msg()
	}
	assert caught == true
	// Verify the error message is bilingual
	assert err_msg.contains('optimistic lock failed')
	assert err_msg.contains('乐观锁冲突')
}

fn test_ol_optimistic_lock_exception_is_typed() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	// Bump version to 1
	repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice2'
		email:   'alice@example.com'
		version: 0
	})!
	// Stale update → OptimisticLockException
	mut typed_err := false
	if _ := repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice3'
		email:   'alice@example.com'
		version: 0
	}) {
		assert false, 'expected OptimisticLockException'
	} else {
		// Verify the error is of the correct type via `is`
		if err is OptimisticLockException {
			typed_err = true
			// After `err is OptimisticLockException`, V smart-casts err
			// so fields are directly accessible.  entity_type includes
			// the module prefix (e.g. 'orm.OlVersionedUser').
			assert err.entity_type.contains('OlVersionedUser')
			assert err.id == '1'
			assert err.code == 409
		}
	}
	assert typed_err == true
}

fn test_ol_optimistic_lock_exception_code_method() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{name: 'Alice', email: 'a@b.com'})!
	repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice2'
		email:   'a@b.com'
		version: 0
	})!
	if _ := repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice3'
		email:   'a@b.com'
		version: 0
	}) {
		assert false, 'expected OptimisticLockException'
	} else {
		// Verify code() method returns 409
		assert err.code() == 409
	}
}

// ════════════════════════════════════════════════════════════════
// B8.4 — concurrent conflict scenario
// ════════════════════════════════════════════════════════════════

// Simulated concurrent conflict: two writers read the same version,
// the first commit wins, the second gets OptimisticLockException.
fn test_ol_concurrent_conflict_first_writer_wins() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	// Both writers read the entity at version=0
	writer_a_copy := repo.find_by_id(1)!
	writer_b_copy := repo.find_by_id(1)!
	assert writer_a_copy.version == 0
	assert writer_b_copy.version == 0
	// Writer A commits first → succeeds, version becomes 1
	a_result := repo.update(&OlVersionedUser{
		id:      writer_a_copy.id
		name:    'WriterA'
		email:   writer_a_copy.email
		version: writer_a_copy.version
	})!
	assert a_result.version == 1
	// Writer B tries to commit with stale version=0 → conflict
	mut b_failed := false
	if _ := repo.update(&OlVersionedUser{
		id:      writer_b_copy.id
		name:    'WriterB'
		email:   writer_b_copy.email
		version: writer_b_copy.version
	}) {
		assert false, 'writer B should have failed with OptimisticLockException'
	} else {
		b_failed = true
		assert err is OptimisticLockException
	}
	assert b_failed == true
	// Verify DB reflects writer A's commit, not B's
	final := repo.find_by_id(1)!
	assert final.name == 'WriterA'
	assert final.version == 1
}

// Sequential updates succeed: each update re-reads the new version.
fn test_ol_sequential_updates_succeed() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'v0'
		email: 'a@b.com'
	})!
	// 0 → 1
	mut u := repo.find_by_id(1)!
	assert u.version == 0
	u = repo.update(&OlVersionedUser{
		id:      1
		name:    'v1'
		email:   'a@b.com'
		version: u.version
	})!
	assert u.version == 1
	// 1 → 2
	u = repo.update(&OlVersionedUser{
		id:      1
		name:    'v2'
		email:   'a@b.com'
		version: u.version
	})!
	assert u.version == 2
	// 2 → 3
	u = repo.update(&OlVersionedUser{
		id:      1
		name:    'v3'
		email:   'a@b.com'
		version: u.version
	})!
	assert u.version == 3
	// Verify final DB state
	final := repo.find_by_id(1)!
	assert final.name == 'v3'
	assert final.version == 3
}

// Multiple sequential updates: version goes 0 → 10.
fn test_ol_multiple_sequential_updates() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'init'
		email: 'a@b.com'
	})!
	mut u := repo.find_by_id(1)!
	assert u.version == 0
	for i in 0 .. 10 {
		u = repo.update(&OlVersionedUser{
			id:      1
			name:    'iter${i}'
			email:   'a@b.com'
			version: u.version
		})!
		assert u.version == i + 1
	}
	// Verify final DB state
	final := repo.find_by_id(1)!
	assert final.name == 'iter9'
	assert final.version == 10
}

// ════════════════════════════════════════════════════════════════
// save() routing: versioned entity with non-zero version → UPDATE
// ════════════════════════════════════════════════════════════════

fn test_ol_save_routes_to_update_for_versioned_entity() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	// Insert new (version=0 → INSERT)
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	assert g_ol_last_query.to_lower().starts_with('insert into')
	// Bump version to 1 via update()
	repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice2'
		email:   'alice@example.com'
		version: 0
	})!
	// Save existing (version=1, non-zero → UPDATE via routing)
	repo.save(&OlVersionedUser{
		id:      1
		name:    'Alice3'
		email:   'alice@example.com'
		version: 1
	})!
	assert g_ol_last_query.to_lower().starts_with('update ')
	assert g_ol_last_query.contains('version = version + 1')
	// Verify version incremented
	updated := repo.find_by_id(1)!
	assert updated.name == 'Alice3'
	assert updated.version == 2
}

fn test_ol_save_new_versioned_entity_with_zero_version_does_insert() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	// version=0 → INSERT even for versioned entity (new entity)
	repo.save(&OlVersionedUser{
		name:  'Bob'
		email: 'b@c.com'
	})!
	assert g_ol_last_query.to_lower().starts_with('insert into')
	assert g_ol_rows.len == 1
	assert g_ol_rows[0].get('version') == '0'
}

// ════════════════════════════════════════════════════════════════
// Backward compatibility: entities without @[version]
// ════════════════════════════════════════════════════════════════

fn test_ol_plain_entity_save_does_insert() {
	mut repo := ol_mock_setup[OlPlainUser]()!
	assert repo.has_version == false
	repo.save(&OlPlainUser{
		name:  'Plain'
		email: 'p@q.com'
	})!
	assert g_ol_last_query.to_lower().starts_with('insert into')
	assert g_ol_rows.len == 1
}

fn test_ol_plain_entity_update_without_version_check() {
	mut repo := ol_mock_setup[OlPlainUser]()!
	repo.save(&OlPlainUser{
		name:  'Plain'
		email: 'p@q.com'
	})!
	// update() without @[version] → plain UPDATE, no version in WHERE
	repo.update(&OlPlainUser{
		id:    1
		name:  'Updated'
		email: 'p@q.com'
	})!
	assert g_ol_last_query.to_lower().starts_with('update ')
	// No version column in SQL
	assert !g_ol_last_query.contains('version')
	// WHERE clause has only pk
	assert g_ol_last_query.contains('id = ?')
	// Verify update applied
	u := repo.find_by_id(1)!
	assert u.name == 'Updated'
}

fn test_ol_plain_entity_save_with_nonzero_pk_still_inserts() {
	mut repo := ol_mock_setup[OlPlainUser]()!
	// For non-versioned entities, save() always does INSERT (backward compat)
	repo.save(&OlPlainUser{
		id:    42
		name:  'Explicit'
		email: 'e@f.com'
	})!
	assert g_ol_last_query.to_lower().starts_with('insert into')
	assert g_ol_rows.len == 1
	assert g_ol_rows[0].get('id') == '42'
}

// ════════════════════════════════════════════════════════════════
// Error handling & configuration
// ════════════════════════════════════════════════════════════════

fn test_ol_update_requires_nonzero_pk() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	// update() with id=0 → error
	if _ := repo.update(&OlVersionedUser{
		id:      0
		name:    'NoPK'
		email:   'a@b.com'
		version: 0
	}) {
		assert false, 'expected error: entity must have non-zero primary key'
	} else {
		assert err.msg().contains('non-zero primary key') || err.msg().contains('主键')
	}
}

fn test_ol_update_versioned_requires_affected_rows_fn() {
	ol_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	// Create repo WITHOUT setting affected_rows_fn
	mut repo := new_jpa_repository[OlVersionedUser](om, 'default', 'ol_test_table', ol_mock_exec, ol_mock_query)!
	unsafe {
		g_ol_pk_col = 'id'
	}
	// Insert with id=0 so save() does an INSERT (not routed to update)
	repo.save(&OlVersionedUser{
		name:    'Alice'
		email:   'a@b.com'
	})!
	// update() should fail because affected_rows_fn is not configured
	if _ := repo.update(&OlVersionedUser{
		id:      1
		name:    'Alice2'
		email:   'a@b.com'
		version: 0
	}) {
		assert false, 'expected error: affected_rows_fn not configured'
	} else {
		assert err.msg().contains('affected_rows_fn')
	}
}

// ════════════════════════════════════════════════════════════════
// SQL injection safety — all user values via ? placeholders
// ════════════════════════════════════════════════════════════════

fn test_ol_update_uses_parameterized_placeholders() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	// Malicious input — must end up as a bound parameter, not interpolated
	repo.update(&OlVersionedUser{
		id:      1
		name:    "'; DROP TABLE users; --"
		email:   'alice@example.com'
		version: 0
	})!
	// The SQL must use ? placeholders, not the raw string
	assert g_ol_last_query.contains('name = ?')
	assert !g_ol_last_query.contains('DROP TABLE')
	// The malicious string is in args, not in the SQL
	assert g_ol_last_args[0] == "'; DROP TABLE users; --"
}

// ════════════════════════════════════════════════════════════════
// Full lifecycle: insert → update → conflict → recover
// ════════════════════════════════════════════════════════════════

fn test_ol_full_lifecycle() {
	mut repo := ol_mock_setup[OlVersionedUser]()!
	// 1. Insert
	repo.save(&OlVersionedUser{
		name:  'Alice'
		email: 'alice@example.com'
	})!
	mut u := repo.find_by_id(1)!
	assert u.version == 0
	// 2. Update (version 0 → 1)
	u = repo.update(&OlVersionedUser{
		id:      u.id
		name:    'Alice2'
		email:   u.email
		version: u.version
	})!
	assert u.version == 1
	// 3. Conflict with stale version
	if _ := repo.update(&OlVersionedUser{
		id:      1
		name:    'Stale'
		email:   'a@b.com'
		version: 0
	}) {
		assert false, 'stale update should fail'
	} else {
		assert err is OptimisticLockException
	}
	// 4. Recover: re-read and update with current version
	current := repo.find_by_id(1)!
	assert current.version == 1
	result := repo.update(&OlVersionedUser{
		id:      current.id
		name:    'Alice3'
		email:   current.email
		version: current.version
	})!
	assert result.version == 2
	// 5. Verify final state
	final := repo.find_by_id(1)!
	assert final.name == 'Alice3'
	assert final.version == 2
}

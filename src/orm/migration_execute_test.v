module orm

// migration_execute_test.v - Tests for real-SQL migration execution (Task B4)
//
// Verifies that MigrationManager.initialize() / migrate() execute real
// SQL against a database via the exec_fn / query_fn callbacks:
//
//   B4.1 — initialize() creates the _photon_migrations tracking table
//   B4.2 — migrate() queries applied versions, runs pending up_sql,
//          inserts version records
//   B4.3 — each migration runs in its own transaction; failure rolls
//          back and aborts the run
//   B4.4 — first run / repeat / failure-rollback coverage
//
// Since photon/orm cannot import db.sqlite (module-name collision with
// V's standard `orm`), these tests use a mock in-memory database backed
// by __global state (compiled with -enable-globals, matching CI).
// The mock supports CREATE TABLE, INSERT (parameterised), SELECT,
// and BEGIN/COMMIT/ROLLBACK transaction control.

// ═══════════════════════════════════════════════════════════════════
// Mock in-memory database
// ═══════════════════════════════════════════════════════════════════
//
// V function-type callbacks cannot capture state, so the mock uses
// __global variables.  Each test resets state via mig_mock_reset().

struct MigMockRow {
mut:
	cols   []string
	values []string
}

fn (mut r MigMockRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r MigMockRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_mig_tables map[string][]MigMockRow
__global g_mig_txn_active bool
__global g_mig_begin_count int
__global g_mig_commit_count int
__global g_mig_rollback_count int
__global g_mig_executed_sql []string

fn mig_mock_reset() {
	unsafe {
		g_mig_tables = map[string][]MigMockRow{}
		g_mig_txn_active = false
		g_mig_begin_count = 0
		g_mig_commit_count = 0
		g_mig_rollback_count = 0
		g_mig_executed_sql = []string{}
	}
}

// mig_mock_exec handles BEGIN/COMMIT/ROLLBACK, CREATE TABLE, INSERT,
// and rejects intentionally-invalid SQL (for failure-rollback tests).
fn mig_mock_exec(db voidptr, query string, args []string) ! {
	_ = db
	unsafe {
		g_mig_executed_sql << query
	}
	q := query.to_lower().trim_space()

	// Transaction control
	if q == 'begin' {
		unsafe {
			g_mig_txn_active = true
			g_mig_begin_count++
		}
		return
	}
	if q == 'commit' {
		unsafe {
			g_mig_txn_active = false
			g_mig_commit_count++
		}
		return
	}
	if q == 'rollback' {
		unsafe {
			g_mig_txn_active = false
			g_mig_rollback_count++
		}
		return
	}

	// Reject intentionally-invalid SQL (for failure tests)
	if q.contains('invalid') || q.contains('syntax error') {
		return error('SQL syntax error / SQL 语法错误: ${query}')
	}

	// CREATE TABLE IF NOT EXISTS <name> (...)
	if q.starts_with('create table') {
		mig_handle_create(query)!
		return
	}

	// INSERT INTO <table> (cols) VALUES (?, ?)
	if q.starts_with('insert into') {
		mig_handle_insert(query, args)!
		return
	}

	// Other DDL/DML — no-op (the mock doesn't fully parse arbitrary SQL)
}

// mig_handle_create parses CREATE TABLE IF NOT EXISTS <name> (...) and
// registers an empty table in the mock.
fn mig_handle_create(query string) ! {
	q := query.to_lower()
	mut name_start := 0
	if idx := q.index('exists') {
		name_start = idx + 6
	} else if idx := q.index('table') {
		name_start = idx + 5
	} else {
		return error('mig_mock: cannot parse CREATE TABLE')
	}
	rest := query[name_start..]
	paren := rest.index('(') or { return error('mig_mock: no paren in CREATE TABLE') }
	table_name := rest[..paren].trim_space()
	unsafe {
		if table_name !in g_mig_tables {
			g_mig_tables[table_name] = []MigMockRow{}
		}
	}
}

// mig_handle_insert parses INSERT INTO <table> (c1, c2) VALUES (?, ?)
// and appends a row using the positional args.
fn mig_handle_insert(query string, args []string) ! {
	q := query.to_lower()
	into_idx := q.index('insert into') or { return error('mig_mock: no INSERT INTO') }
	after_into := query[into_idx + 11..]
	paren_idx := after_into.index('(') or { return error('mig_mock: no columns in INSERT') }
	table_name := after_into[..paren_idx].trim_space()

	rest := after_into[paren_idx + 1..]
	close_paren := rest.index(')') or { return error('mig_mock: no close paren in INSERT') }
	cols_str := rest[..close_paren]
	cols := cols_str.split(',').map(it.trim_space())

	mut row := MigMockRow{}
	for i, col in cols {
		if i < args.len {
			row.cols << col
			row.values << args[i]
		}
	}
	unsafe {
		if table_name !in g_mig_tables {
			g_mig_tables[table_name] = []MigMockRow{}
		}
		g_mig_tables[table_name] << row
	}
}

// mig_mock_query handles SELECT <col> FROM <table> [ORDER BY <col>].
fn mig_mock_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	_ = args
	q := query.to_lower()

	select_idx := q.index('select ') or { return error('mig_mock: no SELECT') }
	after_select := query[select_idx + 7..]
	from_idx := after_select.to_lower().index(' from ') or { return error('mig_mock: no FROM') }
	cols_str := after_select[..from_idx]
	cols := cols_str.split(',').map(it.trim_space())

	after_from := after_select[from_idx + 6..]
	// Strip ORDER BY / WHERE clauses to isolate the table name
	qlower := after_from.to_lower()
	order_idx := qlower.index(' order by ') or { after_from.len }
	where_idx := qlower.index(' where ') or { after_from.len }
	end_idx := if order_idx < where_idx { order_idx } else { where_idx }
	table_name := after_from[..end_idx].trim_space()

	rows := unsafe { g_mig_tables[table_name] or { []MigMockRow{} } }
	mut result := [][]string{}
	for row in rows {
		mut vals := []string{}
		for col in cols {
			vals << row.get(col)
		}
		result << vals
	}
	return result
}

// ── Test setup helper ──

fn mig_setup() !&MigrationManager {
	mig_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	mut mm := new_migration_manager_with_fns(om, 'default', mig_mock_exec, mig_mock_query)
	mm.migration_table = '_photon_migrations'
	return mm
}

// mig_table_exists checks whether a table was created in the mock.
fn mig_table_exists(name string) bool {
	unsafe {
		return name in g_mig_tables
	}
}

// mig_table_row_count returns the number of rows in a mock table.
fn mig_table_row_count(name string) int {
	unsafe {
		rows := g_mig_tables[name] or { return 0 }
		return rows.len
	}
}

// mig_applied_versions reads the _photon_migrations table directly and
// returns the recorded versions (in insertion order).
fn mig_applied_versions() []string {
	mut versions := []string{}
	unsafe {
		rows := g_mig_tables['_photon_migrations'] or { return versions }
		for row in rows {
			versions << row.get('version')
		}
	}
	return versions
}

// ═══════════════════════════════════════════════════════════════════
// B4.1 — initialize() creates the tracking table
// ═══════════════════════════════════════════════════════════════════

fn test_initialize_creates_tracking_table() {
	mut mm := mig_setup()!
	mm.initialize()!
	assert mm.initialized == true
	assert mig_table_exists('_photon_migrations') == true
}

fn test_initialize_idempotent() {
	mut mm := mig_setup()!
	mm.initialize()!
	assert mm.initialized == true
	// Second call should be a no-op (no error, table still exists)
	mm.initialize()!
	assert mig_table_exists('_photon_migrations') == true
	// The table should only have been created once
	assert mig_table_row_count('_photon_migrations') == 0
}

fn test_initialize_does_not_run_in_in_memory_mode() {
	mig_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	mut mm := new_migration_manager_with_fns(om, 'default', mig_mock_exec, mig_mock_query)
	mm.migration_table = '_photon_migrations'
	mm.set_in_memory_mode()
	mm.initialize()!
	// In in-memory mode, no real table is created
	assert mig_table_exists('_photon_migrations') == false
}

// ═══════════════════════════════════════════════════════════════════
// B4.2 — migrate() executes up SQL and records versions
// ═══════════════════════════════════════════════════════════════════

fn test_first_migration_creates_table_and_records_version() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'create users table',
		'CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)', '')

	result := mm.migrate()!
	assert result.applied == 1
	assert result.skipped == 0
	assert result.failed.len == 0
	// The users table should have been created
	assert mig_table_exists('users') == true
	// The version should be recorded
	assert mig_table_row_count('_photon_migrations') == 1
	assert mig_applied_versions() == ['001']
}

fn test_multiple_migrations_all_applied() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'create users', 'CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'create posts', 'CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('003', 'create comments', 'CREATE TABLE IF NOT EXISTS comments (id INTEGER PRIMARY KEY)', '')

	result := mm.migrate()!
	assert result.applied == 3
	assert result.skipped == 0
	assert mig_table_exists('users') == true
	assert mig_table_exists('posts') == true
	assert mig_table_exists('comments') == true
	assert mig_table_row_count('_photon_migrations') == 3
	assert mig_applied_versions() == ['001', '002', '003']
}

fn test_repeat_migration_skips_already_applied() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'create users', 'CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'create posts', 'CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY)', '')

	// First run
	result1 := mm.migrate()!
	assert result1.applied == 2
	assert result1.skipped == 0

	// Second run — all skipped
	result2 := mm.migrate()!
	assert result2.applied == 0
	assert result2.skipped == 2
	assert result2.failed.len == 0
	// Still only 2 versions recorded
	assert mig_table_row_count('_photon_migrations') == 2
}

fn test_empty_migrations_returns_zero() {
	mut mm := mig_setup()!
	result := mm.migrate()!
	assert result.applied == 0
	assert result.skipped == 0
	assert result.failed.len == 0
}

// ═══════════════════════════════════════════════════════════════════
// B4.3 — Transactional migration with rollback on failure
// ═══════════════════════════════════════════════════════════════════

fn test_migration_order_ascending() {
	mut mm := mig_setup()!
	// Add out of order
	mm.add_sql_migration('003', 'third', 'CREATE TABLE IF NOT EXISTS t3 (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('001', 'first', 'CREATE TABLE IF NOT EXISTS t1 (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'second', 'CREATE TABLE IF NOT EXISTS t2 (id INTEGER PRIMARY KEY)', '')

	mm.migrate()!
	// Versions should be recorded in ascending order
	assert mig_applied_versions() == ['001', '002', '003']
}

fn test_failure_rollback_aborts_and_records_no_version() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'good', 'CREATE TABLE IF NOT EXISTS good_table (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'bad', 'INVALID SQL STATEMENT', '')

	rollback_before := unsafe { g_mig_rollback_count }
	result := mm.migrate() or {
		// Expected: migrate() returns an error
		assert true
		// Verify rollback was called
		rollback_after := unsafe { g_mig_rollback_count }
		assert rollback_after > rollback_before
		// 001 should be applied (committed in its own transaction)
		assert mig_applied_versions() == ['001']
		// 002 should NOT be recorded
		assert '002' !in mig_applied_versions()
		return
	}
	_ = result
	assert false, 'migrate() should have returned an error for invalid SQL'
}

fn test_partial_migration_first_applied_second_fails_third_not_attempted() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'first', 'CREATE TABLE IF NOT EXISTS m1 (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'bad', 'INVALID SQL STATEMENT', '')
	mm.add_sql_migration('003', 'third', 'CREATE TABLE IF NOT EXISTS m3 (id INTEGER PRIMARY KEY)', '')

	mm.migrate() or {
		// 001 applied
		assert '001' in mig_applied_versions()
		// 002 NOT recorded (failed + rolled back)
		assert '002' !in mig_applied_versions()
		// 003 NOT attempted
		assert '003' !in mig_applied_versions()
		// m1 table created, m3 table NOT created
		assert mig_table_exists('m1') == true
		assert mig_table_exists('m3') == false
		return
	}
	assert false, 'migrate() should have failed on migration 002'
}

fn test_transaction_isolation_failure_does_not_affect_committed() {
	// Isolation test: after a failed migration, the previously
	// committed migration's table and version record survive.
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'first', 'CREATE TABLE IF NOT EXISTS iso1 (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'bad', 'INVALID SQL STATEMENT', '')

	// First run: 001 succeeds (committed), 002 fails (rolled back)
	mm.migrate() or {
		// 001 committed — table and version survive the 002 failure
		assert mig_table_exists('iso1') == true
		assert '001' in mig_applied_versions()
		// 002 rolled back — not recorded
		assert '002' !in mig_applied_versions()
		return
	}
	assert false, 'first migrate() should have failed on migration 002'
}

fn test_transaction_isolation_committed_survives_failure() {
	// Cleaner isolation test: 3 migrations, 2nd fails.
	// After the run, 1st is committed (survives), 2nd is rolled back,
	// 3rd is not attempted.  Then verify 1st's table still exists.
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'first', 'CREATE TABLE IF NOT EXISTS iso_a (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'bad', 'INVALID SQL STATEMENT', '')
	mm.add_sql_migration('003', 'third', 'CREATE TABLE IF NOT EXISTS iso_c (id INTEGER PRIMARY KEY)', '')

	mm.migrate() or {
		// 1st migration committed — table persists
		assert mig_table_exists('iso_a') == true
		// 1st version recorded
		assert '001' in mig_applied_versions()
		// 2nd rolled back — version NOT recorded
		assert '002' !in mig_applied_versions()
		// 3rd not attempted — table NOT created
		assert mig_table_exists('iso_c') == false
		assert '003' !in mig_applied_versions()
		// At least one BEGIN and one ROLLBACK occurred
		assert unsafe { g_mig_begin_count } >= 2
		assert unsafe { g_mig_rollback_count } >= 1
		return
	}
	assert false, 'migrate() should have failed on migration 002'
}

// ═══════════════════════════════════════════════════════════════════
// B4.2 — get_applied_versions()
// ═══════════════════════════════════════════════════════════════════

fn test_get_applied_versions_empty_before_migrate() {
	mut mm := mig_setup()!
	mm.initialize()!
	versions := mm.get_applied_versions()!
	assert versions.len == 0
}

fn test_get_applied_versions_returns_applied_list() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'first', 'CREATE TABLE IF NOT EXISTS g1 (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'second', 'CREATE TABLE IF NOT EXISTS g2 (id INTEGER PRIMARY KEY)', '')
	mm.migrate()!

	versions := mm.get_applied_versions()!
	assert versions.len == 2
	assert versions[0] == '001'
	assert versions[1] == '002'
}

fn test_get_applied_versions_sorted_ascending() {
	mut mm := mig_setup()!
	mm.add_sql_migration('003', 'c', 'CREATE TABLE IF NOT EXISTS gc (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('001', 'a', 'CREATE TABLE IF NOT EXISTS ga (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'b', 'CREATE TABLE IF NOT EXISTS gb (id INTEGER PRIMARY KEY)', '')
	mm.migrate()!

	versions := mm.get_applied_versions()!
	assert versions.len == 3
	assert versions[0] == '001'
	assert versions[1] == '002'
	assert versions[2] == '003'
}

// ═══════════════════════════════════════════════════════════════════
// B4.2 — migrate() auto-initialises the tracking table
// ═══════════════════════════════════════════════════════════════════

fn test_migrate_auto_initializes_tracking_table() {
	mut mm := mig_setup()!
	// Don't call initialize() explicitly — migrate() should do it
	assert mm.initialized == false
	mm.add_sql_migration('001', 'first', 'CREATE TABLE IF NOT EXISTS auto1 (id INTEGER PRIMARY KEY)', '')
	mm.migrate()!
	assert mm.initialized == true
	assert mig_table_exists('_photon_migrations') == true
	assert '001' in mig_applied_versions()
}

// ═══════════════════════════════════════════════════════════════════
// B4.3 — Each migration runs in its own transaction
// ═══════════════════════════════════════════════════════════════════

fn test_each_migration_in_own_transaction() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'first', 'CREATE TABLE IF NOT EXISTS tx1 (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('002', 'second', 'CREATE TABLE IF NOT EXISTS tx2 (id INTEGER PRIMARY KEY)', '')
	mm.add_sql_migration('003', 'third', 'CREATE TABLE IF NOT EXISTS tx3 (id INTEGER PRIMARY KEY)', '')

	mm.migrate()!

	// 3 migrations → 3 BEGINs and 3 COMMITs
	assert unsafe { g_mig_begin_count } == 3
	assert unsafe { g_mig_commit_count } == 3
	assert unsafe { g_mig_rollback_count } == 0
}

fn test_failed_migration_rolls_back_transaction() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'bad', 'INVALID SQL STATEMENT', '')

	mm.migrate() or {
		// BEGIN was called, then ROLLBACK (not COMMIT)
		assert unsafe { g_mig_begin_count } == 1
		assert unsafe { g_mig_rollback_count } == 1
		assert unsafe { g_mig_commit_count } == 0
		// No version recorded
		assert mig_table_row_count('_photon_migrations') == 0
		return
	}
	assert false, 'migrate() should have failed'
}

// ═══════════════════════════════════════════════════════════════════
// B4.2 — Version record uses parameterised insert (SQL-injection safe)
// ═══════════════════════════════════════════════════════════════════

fn test_version_record_stores_description() {
	mut mm := mig_setup()!
	mm.add_sql_migration('001', 'create users table', 'CREATE TABLE IF NOT EXISTS desc1 (id INTEGER PRIMARY KEY)', '')
	mm.migrate()!

	// Verify the description was stored
	unsafe {
		rows := g_mig_tables['_photon_migrations'] or { []MigMockRow{} }
		assert rows.len == 1
		assert rows[0].get('version') == '001'
		assert rows[0].get('description') == 'create users table'
	}
}

module orm

import sync

// migration.v - Database Migration System (Laravel Migrations + Flyway inspired)
//
// Provides versioned database schema migration with:
//   - Schema builder for DDL generation (CREATE TABLE, ALTER TABLE, etc.)
//   - Migration tracking table (schema_migrations)
//   - Forward migration (migrate) and rollback
//   - Batch-based rollback (rollback the last batch)
//   - Reset (rollback all)
//   - Fresh (drop all tables + re-migrate)
//   - Status reporting
//   - In-memory mode for testing
//
// Usage:
//   mut mm := orm.new_migration_manager(manager)
//   mm.set_db_name('default')
//
//   mm.add(CreateUsersTable{})
//   mm.add(CreatePostsTable{})
//   mm.add(AddEmailToUsers{})
//
//   mm.initialize()!  // create schema_migrations table
//   mm.migrate()!     // run pending migrations
//   mm.status()!      // show migration status
//   mm.rollback()!    // rollback last batch
//
// Schema Builder:
//   fn (m CreateUsersTable) up(mut s orm.Schema) ! {
//       s.create_table('users', fn (mut t orm.TableDef) {
//           t.id()
//           t.string_('username', 255)
//           t.string_('email', 255)
//           t.string_('password', 255)
//           t.timestamp_('created_at')
//           t.timestamp_('updated_at')
//           t.unique_(['username'], 'idx_users_username')
//           t.unique_(['email'], 'idx_users_email')
//       })
//   }

// ── Column Types ──

// ColumnType represents a SQL column data type.
pub enum ColumnType {
	integer
	bigint
	vstring
	text
	vbool
	vfloat
	vdouble
	decimal
	vdate
	vtime
	timestamp
	datetime
	vbinary
	vjson
	vuuid
	enumval
}

// sql_type returns the SQL type string for a ColumnType, driver-aware.
pub fn (ct ColumnType) sql_type(driver DriverType) string {
	return match ct {
		.integer {
			'INTEGER'
		}
		.bigint {
			'BIGINT'
		}
		.vstring {
			if driver == .pg {
				'VARCHAR'
			} else {
				'TEXT'
			}
		}
		.text {
			'TEXT'
		}
		.vbool {
			if driver == .sqlite {
				'INTEGER'
			} else {
				'BOOLEAN'
			}
		}
		.vfloat {
			'REAL'
		}
		.vdouble {
			'DOUBLE PRECISION'
		}
		.decimal {
			'DECIMAL'
		}
		.vdate {
			'DATE'
		}
		.vtime {
			'TIME'
		}
		.timestamp {
			'TIMESTAMP'
		}
		.datetime {
			'DATETIME'
		}
		.vbinary {
			'BLOB'
		}
		.vjson {
			if driver == .pg {
				'JSONB'
			} else {
				'TEXT'
			}
		}
		.vuuid {
			if driver == .pg {
				'UUID'
			} else {
				'TEXT'
			}
		}
		.enumval {
			'TEXT'
		} // SQLite doesn't support ENUM
	}
}

// ── Column Definition ──

// ColumnDef represents a column in a table definition.
pub struct ColumnDef {
pub:
	name           string
	type_          ColumnType
	length         int // for string/varchar
	precision      int // for decimal
	scale          int // for decimal
	is_primary     bool
	auto_increment bool
	is_foreign     bool
	ref_table      string
	ref_column     string = 'id'
	on_delete      string = 'CASCADE'
pub mut:
	is_nullable bool = true // columns are nullable by default
	is_unique   bool
	is_indexed  bool
	default_val string
	is_added    bool   // for ALTER TABLE ADD COLUMN
	is_dropped  bool   // for ALTER TABLE DROP COLUMN
	new_name    string // for ALTER TABLE RENAME COLUMN
}

// to_sql generates the SQL column definition string.
pub fn (c &ColumnDef) to_sql(driver DriverType) string {
	mut s := '${c.name} ${c.type_.sql_type(driver)}'

	// Add length for string type
	if c.type_ == .vstring && c.length > 0 && driver != .sqlite {
		s = '${c.name} VARCHAR(${c.length})'
	}

	// Add precision and scale for decimal
	if c.type_ == .decimal && c.precision > 0 {
		s += '(${c.precision},${c.scale})'
	}

	// Primary key
	if c.is_primary {
		if driver == .sqlite {
			s += ' PRIMARY KEY AUTOINCREMENT'
		} else if driver == .mysql {
			s += ' PRIMARY KEY AUTO_INCREMENT'
		} else {
			s += ' PRIMARY KEY GENERATED ALWAYS AS IDENTITY'
		}
		return s
	}

	// Nullable / Not Null
	if !c.is_nullable {
		s += ' NOT NULL'
	}

	// Unique
	if c.is_unique {
		s += ' UNIQUE'
	}

	// Default value
	if c.default_val.len > 0 {
		if c.default_val.starts_with("'") || c.type_ == .vstring || c.type_ == .text
			|| c.type_ == .vuuid {
			if !c.default_val.starts_with("'") {
				s += " DEFAULT '${c.default_val}'"
			} else {
				s += ' DEFAULT ${c.default_val}'
			}
		} else {
			s += ' DEFAULT ${c.default_val}'
		}
	}

	// Foreign key
	if c.is_foreign && c.ref_table.len > 0 {
		s += ' REFERENCES ${c.ref_table}(${c.ref_column})'
		if c.on_delete.len > 0 {
			s += ' ON DELETE ${c.on_delete}'
		}
	}

	return s
}

// ── Table Definition ──

// TableDef represents a table being created or altered.
pub struct TableDef {
pub:
	name string
pub mut:
	columns     []ColumnDef
	indexes     []IndexDef
	primary_key []string
}

// new_table_def creates a new TableDef.
pub fn new_table_def(name string) &TableDef {
	return &TableDef{
		name:        name
		columns:     []ColumnDef{}
		indexes:     []IndexDef{}
		primary_key: []string{}
	}
}

// ── Column Builder Methods ──

// id adds an auto-incrementing primary key column.
pub fn (mut t TableDef) id() {
	t.columns << ColumnDef{
		name:           'id'
		type_:          .integer
		is_primary:     true
		is_nullable:    false
		auto_increment: true
	}
	t.primary_key << 'id'
}

// big_id adds a big auto-incrementing primary key.
pub fn (mut t TableDef) big_id() {
	t.columns << ColumnDef{
		name:           'id'
		type_:          .bigint
		is_primary:     true
		is_nullable:    false
		auto_increment: true
	}
	t.primary_key << 'id'
}

// string_ adds a string column (VARCHAR/TEXT).
pub fn (mut t TableDef) string_(name string, length int) {
	t.columns << ColumnDef{
		name:   name
		type_:  .vstring
		length: length
	}
}

// text adds a TEXT column.
pub fn (mut t TableDef) text(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .text
	}
}

// integer adds an INTEGER column.
pub fn (mut t TableDef) integer(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .integer
	}
}

// bigint adds a BIGINT column.
pub fn (mut t TableDef) bigint(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .bigint
	}
}

// boolean_ adds a BOOLEAN column.
pub fn (mut t TableDef) boolean_(name string) {
	t.columns << ColumnDef{
		name:        name
		type_:       .vbool
		default_val: 'false'
	}
}

// float_ adds a FLOAT column.
pub fn (mut t TableDef) float_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .vfloat
	}
}

// double_ adds a DOUBLE column.
pub fn (mut t TableDef) double_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .vdouble
	}
}

// decimal_ adds a DECIMAL column.
pub fn (mut t TableDef) decimal_(name string, precision int, scale int) {
	t.columns << ColumnDef{
		name:      name
		type_:     .decimal
		precision: precision
		scale:     scale
	}
}

// date_ adds a DATE column.
pub fn (mut t TableDef) date_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .vdate
	}
}

// time_ adds a TIME column.
pub fn (mut t TableDef) time_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .vtime
	}
}

// timestamp_ adds a TIMESTAMP column.
pub fn (mut t TableDef) timestamp_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .timestamp
	}
}

// datetime_ adds a DATETIME column.
pub fn (mut t TableDef) datetime_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .datetime
	}
}

// binary_ adds a BLOB/BINARY column.
pub fn (mut t TableDef) binary_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .vbinary
	}
}

// json_ adds a JSON/JSONB column.
pub fn (mut t TableDef) json_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .vjson
	}
}

// uuid_ adds a UUID column.
pub fn (mut t TableDef) uuid_(name string) {
	t.columns << ColumnDef{
		name:  name
		type_: .vuuid
	}
}

// enum_ adds an ENUM column (stored as TEXT in SQLite).
pub fn (mut t TableDef) enum_(name string, _values []string) {
	t.columns << ColumnDef{
		name:  name
		type_: .enumval
	}
}

// references adds a foreign key column.
pub fn (mut t TableDef) references(name string, ref_table string) {
	t.columns << ColumnDef{
		name:        name
		type_:       .integer
		is_foreign:  true
		ref_table:   ref_table
		ref_column:  'id'
		on_delete:   'CASCADE'
		is_nullable: false
	}
}

// not_null marks the last added column as NOT NULL.
pub fn (mut t TableDef) not_null() {
	if t.columns.len > 0 {
		mut col := t.columns[t.columns.len - 1]
		col.is_nullable = false
		t.columns[t.columns.len - 1] = col
	}
}

// unique_ marks the specified column as UNIQUE, or creates a composite unique index.
pub fn (mut t TableDef) unique_(columns []string, index_name string) {
	if columns.len == 1 && t.columns.len > 0 {
		// Find the column by name and mark it as unique
		for i in 0 .. t.columns.len {
			if t.columns[i].name == columns[0] {
				mut col := t.columns[i]
				col.is_unique = true
				t.columns[i] = col
				break
			}
		}
	}
	// Also add an explicit index
	t.indexes << IndexDef{
		name:      index_name
		columns:   columns.clone()
		is_unique: true
	}
}

// default_ sets a default value on the last added column.
pub fn (mut t TableDef) default_(value string) {
	if t.columns.len > 0 {
		mut col := t.columns[t.columns.len - 1]
		col.default_val = value
		t.columns[t.columns.len - 1] = col
	}
}

// timestamps adds created_at and updated_at timestamp columns.
pub fn (mut t TableDef) timestamps() {
	t.timestamp_('created_at')
	t.not_null()
	t.default_('CURRENT_TIMESTAMP')
	t.timestamp_('updated_at')
	t.not_null()
	t.default_('CURRENT_TIMESTAMP')
}

// soft_deletes adds a deleted_at timestamp column (nullable).
pub fn (mut t TableDef) soft_deletes() {
	t.columns << ColumnDef{
		name:        'deleted_at'
		type_:       .timestamp
		is_nullable: true
	}
}

// index_ adds a regular index on columns.
pub fn (mut t TableDef) index_(columns []string, index_name string) {
	t.indexes << IndexDef{
		name:      index_name
		columns:   columns.clone()
		is_unique: false
	}
}

// add_column adds a column to an existing table (for ALTER TABLE).
pub fn (mut t TableDef) add_column(col ColumnDef) {
	mut c := col
	c.is_added = true
	t.columns << c
}

// drop_column marks a column for removal (for ALTER TABLE).
pub fn (mut t TableDef) drop_column(name string) {
	t.columns << ColumnDef{
		name:       name
		is_dropped: true
	}
}

// rename_column marks a column for rename.
pub fn (mut t TableDef) rename_column(old_name string, new_name string) {
	t.columns << ColumnDef{
		name:     old_name
		new_name: new_name
	}
}

// ── Index Definition ──

// IndexDef represents a database index.
pub struct IndexDef {
pub:
	name      string
	columns   []string
	is_unique bool
}

// ── Schema ──

// Schema provides a fluent API for building database schemas.
// Generates SQL DDL statements for the configured database driver.
pub struct Schema {
pub mut:
	driver     DriverType
	statements []string
}

// new_schema creates a Schema builder for the given driver.
pub fn new_schema(driver DriverType) &Schema {
	return &Schema{
		driver:     driver
		statements: []string{}
	}
}

// create_table generates a CREATE TABLE statement using a builder callback.
pub fn (mut s Schema) create_table(table_name string, builder fn (mut t TableDef)) {
	mut t := new_table_def(table_name)
	builder(mut t)
	s.statements << s.build_create_table(t)
	// Generate CREATE INDEX statements for table indexes
	for idx in t.indexes {
		unique_kw := if idx.is_unique { 'UNIQUE ' } else { '' }
		s.statements << 'CREATE ${unique_kw}INDEX IF NOT EXISTS ${idx.name} ON ${table_name} (${idx.columns.join(', ')})'
	}
}

// drop_table generates a DROP TABLE statement.
pub fn (mut s Schema) drop_table(table_name string) {
	s.statements << 'DROP TABLE IF EXISTS ${table_name}'
}

// drop_table_if_exists generates a DROP TABLE IF EXISTS statement.
pub fn (mut s Schema) drop_table_if_exists(table_name string) {
	s.statements << 'DROP TABLE IF EXISTS ${table_name}'
}

// rename_table generates an ALTER TABLE RENAME TO statement.
pub fn (mut s Schema) rename_table(old_name string, new_name string) {
	if s.driver == .sqlite {
		s.statements << 'ALTER TABLE ${old_name} RENAME TO ${new_name}'
	} else {
		s.statements << 'ALTER TABLE ${old_name} RENAME TO ${new_name}'
	}
}

// alter_table generates ALTER TABLE statements using a builder callback.
pub fn (mut s Schema) alter_table(table_name string, builder fn (mut t TableDef)) {
	mut t := new_table_def(table_name)
	builder(mut t)
	for col in t.columns {
		if col.is_dropped {
			s.statements << s.build_drop_column(table_name, col.name)
		} else if col.new_name.len > 0 {
			s.statements << s.build_rename_column(table_name, col.name, col.new_name)
		} else if col.is_added {
			s.statements << s.build_add_column(table_name, col)
		}
	}
	for idx in t.indexes {
		s.statements << s.build_create_index(table_name, idx)
	}
}

// add_column adds a single column to an existing table.
pub fn (mut s Schema) add_column(table_name string, col ColumnDef) {
	s.statements << s.build_add_column(table_name, col)
}

// drop_column removes a column from an existing table.
pub fn (mut s Schema) drop_column(table_name string, column_name string) {
	s.statements << s.build_drop_column(table_name, column_name)
}

// create_index creates an index on one or more columns.
pub fn (mut s Schema) create_index(table_name string, index_name string, columns []string, is_unique bool) {
	s.statements << s.build_create_index(table_name, IndexDef{
		name:      index_name
		columns:   columns
		is_unique: is_unique
	})
}

// drop_index drops an index.
pub fn (mut s Schema) drop_index(index_name string) {
	s.statements << 'DROP INDEX IF EXISTS ${index_name}'
}

// to_sql returns all generated SQL statements joined by semicolons.
pub fn (s &Schema) to_sql() string {
	return s.statements.join(';\n') + if s.statements.len > 0 {
		';'
	} else {
		''
	}
}

// statements_count returns the number of generated SQL statements.
pub fn (s &Schema) statements_count() int {
	return s.statements.len
}

// ── Internal SQL Builders ──

// build_create_table generates a CREATE TABLE statement from a TableDef.
fn (s &Schema) build_create_table(t &TableDef) string {
	mut cols := []string{}
	for col in t.columns {
		cols << '  ${col.to_sql(s.driver)}'
	}
	return 'CREATE TABLE IF NOT EXISTS ${t.name} (\n${cols.join(',\n')}\n)'
}

// build_add_column generates an ALTER TABLE ADD COLUMN statement.
fn (s &Schema) build_add_column(table_name string, col ColumnDef) string {
	return 'ALTER TABLE ${table_name} ADD COLUMN ${col.to_sql(s.driver)}'
}

// build_drop_column generates an ALTER TABLE DROP COLUMN statement.
fn (s &Schema) build_drop_column(table_name string, column_name string) string {
	if s.driver == .sqlite {
		// SQLite doesn't support DROP COLUMN before 3.35.0
		// Use the recommended approach: recreate table
		return '-- SQLite: manually recreate table without ${column_name}'
	}
	return 'ALTER TABLE ${table_name} DROP COLUMN ${column_name}'
}

// build_rename_column generates an ALTER TABLE RENAME COLUMN statement.
fn (s &Schema) build_rename_column(table_name string, old_name string, new_name string) string {
	if s.driver == .sqlite {
		return 'ALTER TABLE ${table_name} RENAME COLUMN ${old_name} TO ${new_name}'
	} else if s.driver == .mysql {
		return 'ALTER TABLE ${table_name} RENAME COLUMN ${old_name} TO ${new_name}'
	}
	return 'ALTER TABLE ${table_name} RENAME COLUMN ${old_name} TO ${new_name}'
}

// build_create_index generates a CREATE INDEX statement.
fn (sc &Schema) build_create_index(table_name string, idx IndexDef) string {
	mut s := if idx.is_unique { 'CREATE UNIQUE INDEX' } else { 'CREATE INDEX' }
	columns_str := idx.columns.join(', ')
	s += ' IF NOT EXISTS ${idx.name} ON ${table_name} (${columns_str})'
	return s
}

// ── Migration Interface ──

// Migration is the interface all database migrations must implement.
pub interface Migration {
	version() int
	name() string
	up(mut manager OrmManager) !
	down(mut manager OrmManager) !
}

// ── MigrationManager ──

// AppliedMigration records a migration that has been applied.
pub struct AppliedMigration {
pub:
	version    int
	name       string
	batch      int
	applied_at i64
}

// SqlMigration is a raw-SQL migration record executed by the SQL
// migration path (migrate_with_sql).  Unlike the `Migration` interface
// (which runs `up(mut OrmManager)`), a SqlMigration carries the DDL/DML
// statements directly — the MigrationManager executes them inside a
// per-migration transaction and records the version in
// `_photon_migrations`.
//
// `version` is a string (e.g. '001', '20240101_create_users') to match
// the TEXT PRIMARY KEY column of the tracking table.
pub struct SqlMigration {
pub:
	version     string
	description string
	up_sql      string
	down_sql    string
}

// MigrationResult reports the outcome of a migrate() call.
//
//   applied — number of migrations executed and committed this run
//   skipped — number of migrations already applied (no-op)
//   failed  — versions that failed and were rolled back (the run
//             stops at the first failure; subsequent migrations are
//             not attempted)
pub struct MigrationResult {
pub:
	applied int
	skipped int
	failed  []string
}

// MigrationManager manages migration execution and tracking.
//
// Two execution paths:
//   1. In-memory / interface path (default): migrations implement the
//      `Migration` interface; `up(mut OrmManager)` is called directly.
//      Tracking is held in `applied_versions` / `applied_records`.
//   2. SQL path (when `exec_fn` + `query_fn` are set): raw-SQL
//      migrations (`sql_migrations`) are executed inside per-migration
//      transactions against a real DB; the `_photon_migrations` table
//      is the source of truth for applied versions.
//
// Thread-safety: all SQL-path public methods take `mu` (a sync.RwMutex).
// The in-memory path is single-threaded by design (matches the original
// behaviour); callers that need concurrent in-memory migration should
// externalise synchronisation.
@[heap]
pub struct MigrationManager {
pub mut:
	manager         &OrmManager
	migrations      []&Migration
	sql_migrations  []SqlMigration
	db_name         string = 'default'
	migration_table string = 'schema_migrations'
	in_memory       bool // if true, track migrations in memory (for testing)
	auto_schema     bool // if true, use Schema builder for DDL
	initialized     bool // true after initialize() creates the tracking table
	exec_fn         SqlExecFn  = unsafe { nil } // SQL execution callback (B4)
	query_fn        SqlQueryFn = unsafe { nil } // SQL query callback (B4)
mut:
	applied_versions []int
	applied_records  []AppliedMigration
	applied_batch    int
	schema_cache     map[string]string // table_name → CREATE TABLE SQL
	mu               sync.RwMutex
}

// new_migration_manager creates a new MigrationManager.
pub fn new_migration_manager(manager &OrmManager) &MigrationManager {
	return &MigrationManager{
		manager:          manager
		applied_versions: []int{}
		applied_records:  []AppliedMigration{}
		schema_cache:     map[string]string{}
	}
}

// new_migration_manager_with_fns creates a MigrationManager bound to
// real SQL execution callbacks.  When `exec_fn` and `query_fn` are
// both set, migrate() / initialize() execute real SQL against the
// database identified by `db_name` and track applied versions in the
// `_photon_migrations` table.
//
// The callbacks share the same signature as JpaRepository's
// SqlExecFn / SqlQueryFn (db voidptr, query string, args []string) so
// the same sqlite/pg/mysql adapter works for both.
pub fn new_migration_manager_with_fns(manager &OrmManager, db_name string, exec_fn SqlExecFn, query_fn SqlQueryFn) &MigrationManager {
	return &MigrationManager{
		manager:          manager
		db_name:          db_name
		exec_fn:          exec_fn
		query_fn:         query_fn
		applied_versions: []int{}
		applied_records:  []AppliedMigration{}
		schema_cache:     map[string]string{}
	}
}

// set_db_name sets the database connection name for migrations.
pub fn (mut mm MigrationManager) set_db_name(name string) {
	mm.db_name = name
}

// set_in_memory_mode enables in-memory migration tracking.
pub fn (mut mm MigrationManager) set_in_memory_mode() {
	mm.in_memory = true
}

// set_auto_schema enables automatic schema DDL generation.
pub fn (mut mm MigrationManager) set_auto_schema(enabled bool) {
	mm.auto_schema = enabled
}

// add adds a migration to the list.
pub fn (mut mm MigrationManager) add(migration &Migration) {
	mm.migrations << migration
}

// add_sql_migration registers a raw-SQL migration (B4).
//
// Migrations are executed in version-ascending order inside
// per-migration transactions.  `up_sql` may contain multiple
// statements separated by ';'.  `down_sql` is recorded for future
// rollback support (not yet executed by migrate()).
pub fn (mut mm MigrationManager) add_sql_migration(version string, description string, up_sql string, down_sql string) {
	mm.sql_migrations << SqlMigration{
		version:     version
		description: description
		up_sql:      up_sql
		down_sql:    down_sql
	}
}

// ── Migration Lifecycle ──

// initialize creates the migration tracking table.
//
// When `exec_fn` is set (SQL path, B4.1), executes:
//   CREATE TABLE IF NOT EXISTS <migration_table> (
//       version TEXT PRIMARY KEY,
//       applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
//       description TEXT
//   )
// directly against the database.  Idempotent — safe to call multiple
// times; the `initialized` flag short-circuits subsequent calls.
//
// When `exec_fn` is NOT set (in-memory / interface path), falls back
// to the original Schema-builder behaviour (caches the DDL in
// `schema_cache` without executing it).
pub fn (mut mm MigrationManager) initialize() ! {
	if mm.in_memory {
		return
	}
	if mm.initialized {
		return
	}

	// SQL path: execute real DDL against the database.
	if !isnil(mm.exec_fn) {
		mm.mu.@lock()
		defer {
			mm.mu.unlock()
		}
		db := mm.manager.get_conn(mm.db_name)!
		sql_stmt := 'CREATE TABLE IF NOT EXISTS ${mm.migration_table} (
            version TEXT PRIMARY KEY,
            applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            description TEXT
        )'
		mm.exec_fn(db, sql_stmt, []string{})!
		mm.initialized = true
		return
	}

	// In-memory / interface path: build the DDL via Schema builder
	// and cache it (original behaviour).
	mut schema := new_schema(mm.driver_or_default())
	migration_table_name := mm.migration_table
	schema.create_table(migration_table_name, fn [migration_table_name] (mut t TableDef) {
		t.integer('version')
		t.not_null()
		t.string_('name', 255)
		t.integer('batch')
		t.timestamp_('applied_at')
		t.unique_(['version'], 'idx_${migration_table_name}_version')
	})
	mm.schema_cache[mm.migration_table] = schema.to_sql()
	mm.initialized = true
}

// migrate runs all pending migrations in order.
//
// Returns a MigrationResult reporting how many migrations were
// applied, skipped (already applied), or failed (rolled back).
//
// Two execution paths:
//   1. SQL path (exec_fn + query_fn set, B4.2/B4.3): queries the
//      `_photon_migrations` table for applied versions, then for each
//      pending SqlMigration opens a transaction, executes `up_sql`,
//      inserts the version record, and commits.  On failure the
//      transaction is rolled back and the run aborts.
//   2. In-memory / interface path (default): calls `up(mut OrmManager)`
//      on each Migration interface implementor and tracks applied
//      versions in memory.
pub fn (mut mm MigrationManager) migrate() !MigrationResult {
	// SQL path: real database execution.
	if !isnil(mm.exec_fn) && !isnil(mm.query_fn) && !mm.in_memory {
		return mm.migrate_with_sql()
	}
	return mm.migrate_in_memory()
}

// migrate_in_memory is the original interface-based migration path.
// Tracks applied versions in `applied_versions` / `applied_records`.
fn (mut mm MigrationManager) migrate_in_memory() !MigrationResult {
	mm.sort_migrations()
	mm.applied_batch++

	mut applied := 0
	mut skipped := 0
	for migration in mm.migrations {
		if mm.is_applied(migration.version()) {
			skipped++
			continue
		}

		// Run the migration's up() method
		migration.up(mut mm.manager)!

		// Record as applied
		mm.applied_versions << migration.version()
		mm.applied_records << AppliedMigration{
			version:    migration.version()
			name:       migration.name()
			batch:      mm.applied_batch
			applied_at: 0 // would be time.now().unix()
		}
		applied++
	}

	return MigrationResult{
		applied: applied
		skipped: skipped
		failed: []string{}
	}
}

// migrate_with_sql executes raw-SQL migrations against the database (B4.2/B4.3).
//
// Each migration runs in its own transaction (BEGIN → up_sql → INSERT
// version → COMMIT).  If up_sql or the version insert fails, the
// transaction is rolled back (ROLLBACK) and the run aborts with an
// error; subsequent migrations are NOT attempted.  Already-applied
// migrations are skipped.
fn (mut mm MigrationManager) migrate_with_sql() !MigrationResult {
	if !mm.initialized {
		mm.initialize()!
	}

	mm.mu.@lock()
	defer {
		mm.mu.unlock()
	}

	db := mm.manager.get_conn(mm.db_name)!

	// Get applied versions from the tracking table.
	mut applied_set := mm.get_applied_versions_locked(db)!

	// Sort SQL migrations by version (ascending).
	mut pending := mm.sql_migrations.clone()
	pending.sort(a.version < b.version)

	mut applied_count := 0
	mut skipped_count := 0
	mut failed_migrations := []string{}

	for migration in pending {
		if migration.version in applied_set {
			skipped_count++
			continue
		}

		// Open a per-migration transaction (B4.3).
		mm.exec_fn(db, 'BEGIN', []string{}) or {
			failed_migrations << migration.version
			return error('migration ${migration.version} failed to begin transaction / 开始事务失败: ${err}')
		}

		// Execute the migration's up SQL.
		mm.exec_fn(db, migration.up_sql, []string{}) or {
			mm.exec_fn(db, 'ROLLBACK', []string{}) or {}
			failed_migrations << migration.version
			return error('migration ${migration.version} failed / 迁移失败: ${err}')
		}

		// Record the version (parameterised — SQL-injection safe).
		mm.exec_fn(db, 'INSERT INTO ${mm.migration_table} (version, description) VALUES (?, ?)',
			[migration.version, migration.description]) or {
			mm.exec_fn(db, 'ROLLBACK', []string{}) or {}
			failed_migrations << migration.version
			return error('migration ${migration.version} failed to record version / 记录版本失败: ${err}')
		}

		// Commit the transaction.
		mm.exec_fn(db, 'COMMIT', []string{}) or {
			failed_migrations << migration.version
			return error('migration ${migration.version} failed to commit / 提交事务失败: ${err}')
		}

		applied_set << migration.version
		applied_count++
	}

	return MigrationResult{
		applied: applied_count
		skipped: skipped_count
		failed: failed_migrations
	}
}

// get_applied_versions returns the list of migration versions recorded
// in the tracking table, sorted in ascending version order.
//
// Returns an empty list when the SQL path is not configured
// (exec_fn/query_fn unset) or the tracking table does not yet exist.
pub fn (mut mm MigrationManager) get_applied_versions() ![]string {
	if isnil(mm.query_fn) {
		return []string{}
	}
	mm.mu.@lock()
	defer {
		mm.mu.unlock()
	}
	db := mm.manager.get_conn(mm.db_name)!
	return mm.get_applied_versions_locked(db)
}

// get_applied_versions_locked is the lock-free inner helper.
// Caller MUST hold mm.mu.
fn (mut mm MigrationManager) get_applied_versions_locked(db voidptr) ![]string {
	if isnil(mm.query_fn) {
		return []string{}
	}
	rows := mm.query_fn(db, 'SELECT version FROM ${mm.migration_table} ORDER BY version',
		[]string{}) or {
		// Table might not exist yet — treat as empty.
		return []string{}
	}
	mut versions := []string{}
	for row in rows {
		if row.len > 0 {
			versions << row[0]
		}
	}
	return versions
}

// rollback rolls back the last batch of migrations.
pub fn (mut mm MigrationManager) rollback() ! {
	if mm.applied_records.len == 0 {
		return error('nothing to rollback')
	}

	// Find the last batch number
	last_batch := mm.applied_records[mm.applied_records.len - 1].batch

	// Find migrations in the last batch (in reverse order)
	mut to_rollback := []&Migration{}
	for migration in mm.migrations {
		for record in mm.applied_records {
			if record.version == migration.version() && record.batch == last_batch {
				to_rollback << migration
			}
		}
	}

	// Rollback in reverse order
	to_rollback.reverse()
	for migration in to_rollback {
		migration.down(mut mm.manager)!
		mm.remove_applied(migration.version())
	}

	if to_rollback.len == 0 {
		return error('nothing to rollback')
	}
}

// reset rolls back ALL migrations.
pub fn (mut mm MigrationManager) reset() ! {
	mm.sort_migrations()
	// Rollback in reverse order
	mut i := mm.migrations.len
	for i > 0 {
		i--
		migration := mm.migrations[i]
		if mm.is_applied(migration.version()) {
			migration.down(mut mm.manager)!
			mm.remove_applied(migration.version())
		}
	}
	mm.applied_versions.clear()
	mm.applied_records.clear()
	mm.applied_batch = 0
}

// fresh drops all tables and re-runs all migrations.
pub fn (mut mm MigrationManager) fresh() ! {
	mm.reset()!
	mm.applied_batch = 0
	mm.migrate()!
}

// ── Status & Reporting ──

// status prints the status of all migrations.
pub fn (mut mm MigrationManager) status() ! {
	mm.sort_migrations()
	println('')
	println('  ${'Migration Status':-60s}')
	println('  ${'─'.repeat(60)}')
	println('  ${'Status':-10s} ${'Version':-10s} ${'Batch':-8s} ${'Name'}')
	println('  ${'─'.repeat(60)}')

	for migration in mm.migrations {
		applied := mm.is_applied(migration.version())
		status_str := if applied { '✓ Applied' } else { '… Pending' }
		batch_str := if applied { mm.get_batch(migration.version()).str() } else { '-' }

		println('  ${status_str:-10s} ${migration.version():-10d} ${batch_str:-8s} ${migration.name()}')
	}
	println('  ${'─'.repeat(60)}')
	println('  Total: ${mm.migrations.len} | Applied: ${mm.applied_versions.len} | Pending: ${mm.migrations.len - mm.applied_versions.len}')
	println('')
}

// pending_count returns the number of pending (not yet applied) migrations.
pub fn (mut mm MigrationManager) pending_count() int {
	mm.sort_migrations()
	mut count := 0
	for migration in mm.migrations {
		if !mm.is_applied(migration.version()) {
			count++
		}
	}
	return count
}

// applied_count returns the number of applied migrations.
pub fn (mm &MigrationManager) applied_count() int {
	return mm.applied_versions.len
}

// get_sql generates SQL for all migrations (useful for debugging).
pub fn (mut mm MigrationManager) get_sql() string {
	mut result := ''
	for migration in mm.migrations {
		result += '-- Migration ${migration.version()}: ${migration.name()}\n'
		// The actual SQL depends on the migration's up() implementation
		result += '-- (SQL generated by migration.up() execution)\n\n'
	}
	return result
}

// ── Internal Helpers ──

// is_applied checks if a version is in the applied list.
fn (mm &MigrationManager) is_applied(version int) bool {
	for v in mm.applied_versions {
		if v == version {
			return true
		}
	}
	return false
}

// remove_applied removes a version from the applied list and records.
fn (mut mm MigrationManager) remove_applied(version int) {
	// Remove from versions list
	mut idx := -1
	for i, v in mm.applied_versions {
		if v == version {
			idx = i
			break
		}
	}
	if idx >= 0 {
		mm.applied_versions.delete(idx)
	}

	// Remove from records list
	mut rec_idx := -1
	for i, r in mm.applied_records {
		if r.version == version {
			rec_idx = i
			break
		}
	}
	if rec_idx >= 0 {
		mm.applied_records.delete(rec_idx)
	}
}

// get_batch returns the batch number for a version.
fn (mm &MigrationManager) get_batch(version int) int {
	for r in mm.applied_records {
		if r.version == version {
			return r.batch
		}
	}
	return 0
}

// sort_migrations sorts migrations by version number (ascending).
fn (mut mm MigrationManager) sort_migrations() {
	for i in 0 .. mm.migrations.len {
		for j in 0 .. mm.migrations.len - i - 1 {
			if mm.migrations[j].version() > mm.migrations[j + 1].version() {
				mm.migrations[j], mm.migrations[j + 1] = mm.migrations[j + 1], mm.migrations[j]
			}
		}
	}
}

// driver_or_default returns the driver type for the configured db_name.
fn (mm &MigrationManager) driver_or_default() DriverType {
	d := mm.manager.driver(mm.db_name) or { DriverType.sqlite }
	return d
}

module orm

// migration.v - Database Migration System
pub interface Migration {
	version() int
	name() string
	up(mut manager OrmManager) !
	down(mut manager OrmManager) !
}

// MigrationManager manages migration execution
pub struct MigrationManager {
pub mut:
	manager     &OrmManager
	migrations  []&Migration
	db_name     string
	migration_table string = 'schema_migrations'
}

// new_migration_manager creates a new MigrationManager
pub fn new_migration_manager(manager &OrmManager) &MigrationManager {
	return &MigrationManager{
		manager: manager
	}
}

// add adds a migration
pub fn (mut mm MigrationManager) add(migration &Migration) {
	mm.migrations << migration
}

// initialize creates the migration tracking table.
// Stub: requires a real OrmDB connection.
pub fn (mut mm MigrationManager) initialize() ! {
	_ := mm.manager.get_conn(mm.db_name)!
	return error('initialize requires a real db driver connection')
}

// migrate runs all pending migrations.
// Stub: requires a real OrmDB connection.
pub fn (mut mm MigrationManager) migrate() ! {
	return error('migrate requires a real db driver connection')
}

// rollback rolls back the last batch of migrations.
// Stub: requires a real OrmDB connection.
pub fn (mut mm MigrationManager) rollback() ! {
	_ := mm.manager.get_conn(mm.db_name)!
	return error('rollback requires a real db driver connection')
}

// get_applied_migrations returns the set of applied migration versions.
// Stub: requires a real OrmDB connection.
fn (mm &MigrationManager) get_applied_migrations() ![]int {
	_ := mm.manager.get_conn(mm.db_name)!
	return error('get_applied_migrations requires a real db driver connection')
}

// get_next_batch returns the next batch number.
// Stub: requires a real OrmDB connection.
fn (mm &MigrationManager) get_next_batch() !int {
	_ := mm.manager.get_conn(mm.db_name)!
	return error('get_next_batch requires a real db driver connection')
}

// record_migration records a migration as applied.
// Stub: requires a real OrmDB connection.
fn (mm &MigrationManager) record_migration(version int, name string, batch int) ! {
	_ = version
	_ = name
	_ = batch
	_ := mm.manager.get_conn(mm.db_name)!
	return error('record_migration requires a real db driver connection')
}

// status prints the status of all migrations.
// Stub: requires a real OrmDB connection.
pub fn (mm &MigrationManager) status() ! {
	return error('status requires a real db driver connection')
}

// reset rolls back ALL migrations.
// Stub: requires a real OrmDB connection.
pub fn (mut mm MigrationManager) reset() ! {
	return error('reset requires a real db driver connection')
}

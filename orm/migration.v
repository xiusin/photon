module orm

// migration.v - Database Migration System
// Provides migration tracking, execution, and rollback support.
// For production, requires a real database driver. For testing,
// use set_in_memory_mode() which tracks migrations in memory.

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
	in_memory   bool // if true, track migrations in memory (for testing)
mut:
	applied_versions []int   // in-memory applied version tracking
	applied_batch    int     // current batch number
}

// new_migration_manager creates a new MigrationManager
pub fn new_migration_manager(manager &OrmManager) &MigrationManager {
	return &MigrationManager{
		manager: manager
	}
}

// add adds a migration to the list
pub fn (mut mm MigrationManager) add(migration &Migration) {
	mm.migrations << migration
}

// set_in_memory_mode enables in-memory migration tracking.
// Use for testing or when no real database driver is available.
// Applied migrations are tracked in a list instead of a database table.
pub fn (mut mm MigrationManager) set_in_memory_mode() {
	mm.in_memory = true
}

// initialize creates the migration tracking table.
// In production, requires a real database connection.
// In in-memory mode, this is a no-op.
pub fn (mut mm MigrationManager) initialize() ! {
	if !mm.in_memory {
		_ := mm.manager.get_conn(mm.db_name)!
		return error('initialize requires a real db driver connection — use set_in_memory_mode() for testing')
	}
}

// migrate runs all pending migrations in order.
// In in-memory mode, migrations are tracked locally.
pub fn (mut mm MigrationManager) migrate() ! {
	if !mm.in_memory {
		return error('migrate requires a real db driver connection — use set_in_memory_mode() for testing')
	}

	mm.sort_migrations()
	mm.applied_batch++

	for migration in mm.migrations {
		// Skip already-applied migrations
		if mm.is_applied(migration.version()) {
			continue
		}

		// Run the migration
		migration.up(mut mm.manager)!

		// Record as applied
		mm.applied_versions << migration.version()
	}
}

// rollback rolls back the last batch of migrations.
// In in-memory mode, rolls back ALL applied migrations.
pub fn (mut mm MigrationManager) rollback() ! {
	if !mm.in_memory {
		_ := mm.manager.get_conn(mm.db_name)!
		return error('rollback requires a real db driver connection — use set_in_memory_mode() for testing')
	}

	// Sort in reverse order for rollback
	mm.sort_migrations()

	mut rolled_back := false
	for i := mm.migrations.len; i > 0; i-- {
		migration := mm.migrations[i - 1]
		if mm.is_applied(migration.version()) {
			migration.down(mut mm.manager)!
			mm.remove_applied(migration.version())
			rolled_back = true
		}
	}

	if !rolled_back {
		return error('no migrations to rollback')
	}
}

// status prints the status of all migrations
pub fn (mut mm MigrationManager) status() ! {
	if !mm.in_memory {
		return error('status requires a real db driver connection — use set_in_memory_mode() for testing')
	}

	mm.sort_migrations()
	println('')
	println('Migration Status:')
	println('─────────────────')

	for migration in mm.migrations {
		applied := mm.is_applied(migration.version())
		status_str := if applied { 'Applied' } else { 'Pending' }
		println('  ${status_str}\t${migration.version()}\t${migration.name()}')
	}
	println('')
}

// reset rolls back ALL migrations (in-memory mode).
pub fn (mut mm MigrationManager) reset() ! {
	if !mm.in_memory {
		return error('reset requires a real db driver connection — use set_in_memory_mode() for testing')
	}

	mm.rollback()!
	mm.applied_versions.clear()
	mm.applied_batch = 0
}

// get_applied_migrations returns the set of applied migration versions
fn (mm &MigrationManager) get_applied_migrations() ![]int {
	if !mm.in_memory {
		_ := mm.manager.get_conn(mm.db_name)!
		return error('get_applied_migrations requires a real db driver connection')
	}
	return mm.applied_versions.clone()
}

// get_next_batch returns the next batch number
fn (mm &MigrationManager) get_next_batch() !int {
	if !mm.in_memory {
		_ := mm.manager.get_conn(mm.db_name)!
		return error('get_next_batch requires a real db driver connection')
	}
	return mm.applied_batch + 1
}

// record_migration records a migration as applied
fn (mut mm MigrationManager) record_migration(version int, _name string, _batch int) ! {
	if !mm.in_memory {
		_ := mm.manager.get_conn(mm.db_name)!
		return error('record_migration requires a real db driver connection')
	}
	if !mm.is_applied(version) {
		mm.applied_versions << version
	}
}

// In-memory helpers

// is_applied checks if a version is in the applied list
fn (mm &MigrationManager) is_applied(version int) bool {
	for v in mm.applied_versions {
		if v == version {
			return true
		}
	}
	return false
}

// remove_applied removes a version from the applied list
fn (mut mm MigrationManager) remove_applied(version int) {
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
}

// sort_migrations sorts migrations by version number (ascending)
fn (mut mm MigrationManager) sort_migrations() {
	// Simple bubble sort by version number (sufficient for small migration lists)
	for i in 0 .. mm.migrations.len {
		for j in 0 .. mm.migrations.len - i - 1 {
			if mm.migrations[j].version() > mm.migrations[j + 1].version() {
				mm.migrations[j], mm.migrations[j + 1] = mm.migrations[j + 1], mm.migrations[j]
			}
		}
	}
}

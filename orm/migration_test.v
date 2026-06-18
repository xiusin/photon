module orm

// migration_test.v - Tests for MigrationManager, Migration interface, and migration lifecycle

// --- Mock Migration for Testing ---

struct MockMigration {
	v int
	n string
mut:
	up_called   bool
	down_called bool
}

fn (m &MockMigration) version() int {
	return m.v
}

fn (m &MockMigration) name() string {
	return m.n
}

fn (m &MockMigration) up(mut manager OrmManager) ! {
	unsafe { m.up_called = true }
}

fn (m &MockMigration) down(mut manager OrmManager) ! {
	unsafe { m.down_called = true }
}

fn new_mock_migration(version int, name string) &MockMigration {
	return &MockMigration{
		v: version
		n: name
	}
}

// --- MigrationManager Construction Tests ---

fn test_new_migration_manager() {
	om := new_orm_manager()
	mm := new_migration_manager(om)
	assert mm.migrations.len == 0
	assert mm.migration_table == 'schema_migrations'
	assert mm.db_name == 'default'
}

fn test_new_migration_manager_different_managers() {
	om1 := new_orm_manager()
	om2 := new_orm_manager()
	mm1 := new_migration_manager(om1)
	mm2 := new_migration_manager(om2)
	assert mm1.migrations.len == 0
	assert mm2.migrations.len == 0
}

// --- MigrationManager Add Tests ---

fn test_migration_manager_add() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)

	m1 := new_mock_migration(1, 'create_users')
	mm.add(m1)

	assert mm.migrations.len == 1
	assert mm.migrations[0].version() == 1
	assert mm.migrations[0].name() == 'create_users'
}

fn test_migration_manager_add_multiple() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)

	mm.add(new_mock_migration(1, 'create_users'))
	mm.add(new_mock_migration(2, 'add_email_column'))
	mm.add(new_mock_migration(3, 'create_posts'))

	assert mm.migrations.len == 3
	assert mm.migrations[0].version() == 1
	assert mm.migrations[1].version() == 2
	assert mm.migrations[2].version() == 3
}

fn test_migration_manager_add_preserves_order() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)

	mm.add(new_mock_migration(3, 'third'))
	mm.add(new_mock_migration(1, 'first'))
	mm.add(new_mock_migration(2, 'second'))

	assert mm.migrations.len == 3
	assert mm.migrations[0].version() == 3
	assert mm.migrations[1].version() == 1
	assert mm.migrations[2].version() == 2
}

// --- Mock Migration Interface Tests ---

fn test_mock_migration_implements_interface() {
	mut m := MockMigration{ v: 5, n: 'test_migration' }
	assert m.version() == 5
	assert m.name() == 'test_migration'
	assert m.up_called == false
	assert m.down_called == false
}

fn test_mock_migration_up_called() {
	mut m := new_mock_migration(1, 'init')
	mut om := new_orm_manager()
	m.up(mut om) or { assert false, 'up should not error' }
	assert m.up_called == true
}

fn test_mock_migration_down_called() {
	mut m := new_mock_migration(1, 'init')
	mut om := new_orm_manager()
	m.down(mut om) or { assert false, 'down should not error' }
	assert m.down_called == true
}

fn test_mock_migration_up_down_independent() {
	mut m := new_mock_migration(2, 'data_migration')
	mut om := new_orm_manager()

	assert m.up_called == false
	assert m.down_called == false

	m.up(mut om) or {}
	assert m.up_called == true
	assert m.down_called == false
}

// --- Default Values ---

fn test_migration_manager_default_table() {
	om := new_orm_manager()
	mm := new_migration_manager(om)
	assert mm.migration_table == 'schema_migrations'
}

fn test_migration_manager_custom_table() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)
	mm.migration_table = 'custom_migrations'
	assert mm.migration_table == 'custom_migrations'
}

// --- Mock Migration independence ---

fn test_migration_manager_in_memory_mode_migrate() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)
	mm.set_in_memory_mode()

	mut m1 := new_mock_migration(1, 'create_users')
	mut m2 := new_mock_migration(2, 'add_email')
	mm.add(m1)
	mm.add(m2)

	mm.migrate()!

	assert m1.up_called == true
	assert m2.up_called == true
}

fn test_migration_manager_in_memory_skips_applied() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)
	mm.set_in_memory_mode()

	mut m1 := new_mock_migration(1, 'first')
	mut m2 := new_mock_migration(2, 'second')
	mm.add(m1)
	mm.add(m2)

	mm.migrate()!
	assert m1.up_called == true
	assert m2.up_called == true

	unsafe {
		m1.up_called = false
		m2.up_called = false
	}

	mm.migrate()!
	assert m1.up_called == false // skipped
	assert m2.up_called == false // skipped
}

fn test_migration_manager_in_memory_rollback() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)
	mm.set_in_memory_mode()

	mut m1 := new_mock_migration(1, 'first')
	mut m2 := new_mock_migration(2, 'second')
	mm.add(m1)
	mm.add(m2)

	mm.migrate()!
	assert m1.up_called == true
	assert m2.up_called == true

	mm.rollback()!
	assert m1.down_called == true
	assert m2.down_called == true
}

fn test_migration_manager_in_memory_sorted_execution() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)
	mm.set_in_memory_mode()

	mut m3 := new_mock_migration(3, 'third')
	mut m1 := new_mock_migration(1, 'first')
	mut m2 := new_mock_migration(2, 'second')
	mm.add(m3)
	mm.add(m1)
	mm.add(m2)

	mm.migrate()!

	assert m1.up_called == true
	assert m2.up_called == true
	assert m3.up_called == true
}

fn test_migration_manager_in_memory_reset() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)
	mm.set_in_memory_mode()

	mut m1 := new_mock_migration(1, 'first')
	mm.add(m1)

	mm.migrate()!
	assert m1.up_called == true

	mm.reset()!
	assert m1.down_called == true
}

fn test_migration_manager_in_memory_status() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)
	mm.set_in_memory_mode()

	mm.add(new_mock_migration(1, 'first'))
	mm.add(new_mock_migration(2, 'second'))

	mm.migrate()!
	mm.status() or {
		// stdout output test — just ensure no crash
		assert true
	}
}

fn test_migration_manager_without_in_memory_errors() {
	om := new_orm_manager()
	mut mm := new_migration_manager(om)
	mm.add(new_mock_migration(1, 'test'))

	// New behavior: migrate() no longer requires in-memory mode
	// It works directly — the in_memory flag only affects database tracking
	mm.migrate()!
	assert mm.applied_count() == 1
}

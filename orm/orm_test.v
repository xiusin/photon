module orm

// orm_test.v - Tests for OrmManager connection management
//
// Does NOT import V's `orm` module (module name collision).
// Tests connection registry operations with opaque voidptr
// connections — no real database needed.

// ── Helpers ──

fn dummy_connection() voidptr {
	return voidptr(1) // non-null sentinel
}

// ── OrmManager tests ──

fn test_new_orm_manager_empty() {
	om := new_orm_manager()
	assert om.connections.len == 0
	assert om.default == ''
	assert om.connection_names().len == 0
}

fn test_register_first_becomes_default() {
	mut om := new_orm_manager()
	om.register_connection('primary', .sqlite, dummy_connection()) or {
		assert false, 'register should succeed'
	}
	assert om.default == 'primary'
	assert om.connections.len == 1
	assert om.has_connection('primary') == true
	assert om.has_connection('secondary') == false
}

fn test_register_multiple_connections() {
	mut om := new_orm_manager()

	om.register_connection('primary', .sqlite, dummy_connection())!
	om.register_connection('replica', .pg, dummy_connection())!

	assert om.default == 'primary'
	assert om.connections.len == 2
	assert om.has_connection('primary') == true
	assert om.has_connection('replica') == true
}

fn test_register_duplicate_fails() {
	mut om := new_orm_manager()

	om.register_connection('db', .sqlite, dummy_connection())!
	om.register_connection('db', .sqlite, dummy_connection()) or {
		assert true // error expected
		return
	}
	assert false, 'expected error for duplicate name'
}

fn test_set_default() {
	mut om := new_orm_manager()

	om.register_connection('primary', .sqlite, dummy_connection())!
	om.register_connection('replica', .pg, dummy_connection())!
	assert om.default == 'primary'

	om.set_default('replica')!
	assert om.default == 'replica'
}

fn test_set_default_missing() {
	mut om := new_orm_manager()
	om.set_default('nonexistent') or {
		assert true // error expected
		return
	}
	assert false, 'expected error'
}

fn test_get_conn_by_name() {
	mut om := new_orm_manager()
	om.register_connection('db', .sqlite, dummy_connection())!

	conn := om.get_conn('db')!
	assert conn == dummy_connection()
}

fn test_get_conn_missing() {
	om := new_orm_manager()
	_ := om.get_conn('nonexistent') or {
		assert true // error expected
		return
	}
	assert false, 'expected error for missing connection'
}

fn test_get_conn_empty_name_uses_default() {
	mut om := new_orm_manager()
	om.register_connection('primary', .sqlite, dummy_connection())!

	conn := om.get_conn('')!
	assert conn == dummy_connection()
}

fn test_default_conn() {
	mut om := new_orm_manager()
	om.register_connection('primary', .sqlite, dummy_connection())!

	conn := om.default_conn()!
	assert conn == dummy_connection()
}

fn test_default_conn_missing() {
	om := new_orm_manager()
	if _ := om.default_conn() {
		assert false, 'expected error — no default'
	} else {
		assert true
	}
}

fn test_connection() {
	mut om := new_orm_manager()
	om.register_connection('db', .pg, dummy_connection())!

	oc := om.connection('db')!
	assert oc.driver == .pg
}

fn test_driver() {
	mut om := new_orm_manager()
	om.register_connection('db', .mysql, dummy_connection())!

	d := om.driver('db')!
	assert d == .mysql
}

fn test_driver_missing() {
	om := new_orm_manager()
	if _ := om.driver('nonexistent') {
		assert false, 'expected error'
	} else {
		assert true
	}
}

fn test_is_driver_checks() {
	mut om := new_orm_manager()
	om.register_connection('db', .sqlite, dummy_connection())!

	assert om.is_sqlite('db') == true
	assert om.is_pg('db') == false
	assert om.is_mysql('db') == false
}

fn test_connection_names() {
	mut om := new_orm_manager()
	om.register_connection('a', .sqlite, dummy_connection())!
	om.register_connection('b', .pg, dummy_connection())!

	names := om.connection_names()
	assert names.len == 2
}

fn test_remove_connection() {
	mut om := new_orm_manager()
	om.register_connection('db', .sqlite, dummy_connection())!
	assert om.has_connection('db') == true

	om.remove_connection('db')!
	assert om.has_connection('db') == false
}

fn test_remove_connection_missing() {
	mut om := new_orm_manager()
	if _ := om.remove_connection('nonexistent') {
		assert false, 'expected error'
	} else {
		assert true
	}
}

fn test_remove_default_picks_next() {
	mut om := new_orm_manager()
	om.register_connection('first', .sqlite, dummy_connection())!
	om.register_connection('second', .pg, dummy_connection())!

	assert om.default == 'first'
	om.remove_connection('first')!
	assert om.default == 'second'
}

fn test_driver_type_str() {
	assert DriverType.sqlite.str() == 'sqlite'
	assert DriverType.pg.str() == 'postgresql'
	assert DriverType.mysql.str() == 'mysql'
	assert DriverType.unknown.str() == 'unknown'
}

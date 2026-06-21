module orm

// adapter.v - OrmAdapter[T]
//
// A type-safe adapter that wraps photon's multi-driver OrmManager
// with entity lifecycle hooks.  Lives directly in photon/orm/
// (module orm) — no separate sub-module needed and NO import of
// V's standard `orm` module (avoiding V 0.5.1 name collision).
//
// ── What it does ──
//
//   1. Connection routing — pick the right database by name
//   2. Lifecycle hooks — BeforeCreate, AfterCreate, BeforeUpdate,
//      AfterUpdate, BeforeDelete, AfterDelete, AfterFind
//   3. Auto-touch() — BaseEntity.created_at / updated_at via
//      the Touchable interface
//   4. Callback wrappers — wrap_insert, wrap_update, wrap_save,
//      wrap_delete: run hooks, then your V ORM logic
//
// ── What it does NOT do ──
//
//   This adapter does NOT create V's orm.QueryBuilder[T] or
//   execute SQL queries — that's V's official ORM's job, and
//   photon/orm cannot import V's `orm` module due to the name
//   collision in V 0.5.1.  Use V's ORM in your own code
//   alongside this adapter.
//
// ── Usage ──
//
//   import db.sqlite
//   import orm            // V's standard ORM
//   import photon.orm     // photon's OrmManager + hooks
//
//   mut om := orm.new_orm_manager()
//   db := sqlite.connect(':memory:')!
//   om.register_connection('default', .sqlite, voidptr(db))!
//
//   mut a := orm.new_orm_adapter[User](om, 'default')!
//
//   // Insert with lifecycle hooks:
//   conn := unsafe { &orm.Connection(a.get_conn()!) }
//   mut qb := orm.new_query[User](conn)
//   a.wrap_insert(mut user, fn [mut qb] (mut u User) ! {
//       qb.insert(u)!
//   })!
//
//   // Read with AfterFind hook:
//   users := qb.where('age > ?', orm.Primitive(18))!.query()!
//   for mut u in users {
//       a.after_find(mut u)!
//   }
//
// ── Why not import V's orm here? ──
//
//   V 0.5.1 forbids importing two modules with the same name.
//   Since photon/orm/ IS `module orm`, importing V's `orm`
//   would collide.  This is a V compiler limitation.
//   Future V versions may allow this via import aliasing —
//   when that happens, the adapter can be upgraded to
//   create QueryBuilders internally.

// ── OrmAdapter ──

// OrmAdapter provides lifecycle hooks and connection routing for
// ORM entities backed by the OrmManager.
//
// T should be an ORM-attributed struct that optionally implements
// lifecycle hook interfaces (BeforeCreateHook, AfterCreateHook,
// Touchable, etc.) or embeds BaseEntity.
@[heap]
pub struct OrmAdapter[T] {
pub mut:
	manager &OrmManager
	db_name string
}

// new_orm_adapter creates an adapter backed by the named connection
// in the OrmManager.
//
// Example:
//   mut a := orm.new_orm_adapter[User](om, 'default')!
pub fn new_orm_adapter[T](manager &OrmManager, db_name string) !&OrmAdapter[T] {
	manager.connection(db_name)!
	return &OrmAdapter[T]{
		manager: manager
		db_name: db_name
	}
}

// ── Connection access ──

// get_conn returns the raw database connection pointer.
//
// Prefer with_connection() which encapsulates the unsafe cast.
pub fn (a &OrmAdapter[T]) get_conn() !voidptr {
	return a.manager.get_conn(a.db_name)
}

// with_connection provides the raw connection pointer to a callback
// in a controlled scope.  This is the recommended way to access the
// underlying V ORM connection — you do the unsafe cast once in your
// callback and use V's official QueryBuilder:
//
//   a.with_connection(fn [user] (conn_ptr voidptr) ! {
//       conn := unsafe { &orm.Connection(conn_ptr) }
//       mut qb := orm.new_query[User](conn)
//       qb.insert(user)!
//   })!
pub fn (a &OrmAdapter[T]) with_connection(callback fn (voidptr) !) ! {
	conn_ptr := a.manager.get_conn(a.db_name)!
	callback(conn_ptr)!
}

// ── Lifecycle hooks ──

// before_insert calls BeforeCreateHook and Touchable.touch().
// Call this before your V ORM insert logic.
pub fn (mut a OrmAdapter[T]) before_insert(mut entity T) ! {
	$if T is BeforeCreateHook {
		entity.before_create()
	}
	$if T is Touchable {
		entity.touch()
	}
}

// after_insert calls AfterCreateHook.
// Call this after your V ORM insert logic.
pub fn (mut a OrmAdapter[T]) after_insert(mut entity T) ! {
	$if T is AfterCreateHook {
		entity.after_create()
	}
}

// before_update calls BeforeUpdateHook and Touchable.touch().
// Call this before your V ORM update logic.
pub fn (mut a OrmAdapter[T]) before_update(mut entity T) ! {
	$if T is BeforeUpdateHook {
		entity.before_update()
	}
	$if T is Touchable {
		entity.touch()
	}
}

// after_update calls AfterUpdateHook.
// Call this after your V ORM update logic.
pub fn (mut a OrmAdapter[T]) after_update(mut entity T) ! {
	$if T is AfterUpdateHook {
		entity.after_update()
	}
}

// before_delete calls BeforeDeleteHook.
// Call this before your V ORM delete logic.
pub fn (mut a OrmAdapter[T]) before_delete(entity T) ! {
	$if T is BeforeDeleteHook {
		entity.before_delete()
	}
}

// after_delete calls AfterDeleteHook.
// Call this after your V ORM delete logic.
pub fn (mut a OrmAdapter[T]) after_delete(entity T) ! {
	$if T is AfterDeleteHook {
		entity.after_delete()
	}
}

// after_find calls AfterFindHook.  Call this after loading an
// entity from the database (find_by_id, find_all, find_where, etc.).
//
// Example:
//   users := qb.query()!
//   for mut u in users {
//       a.after_find(mut u)!
//   }
pub fn (mut a OrmAdapter[T]) after_find(mut entity T) ! {
	$if T is AfterFindHook {
		entity.after_find()
	}
}

// after_find_all calls AfterFindHook on every entity in a result set.
// This is the recommended way to trigger AfterFind hooks after
// loading multiple entities from the database.
//
// Example:
//   mut users := qb.query()!
//   a.after_find_all(mut users)!
pub fn (mut a OrmAdapter[T]) after_find_all(mut entities []T) ! {
	for mut entity in entities {
		a.after_find(mut entity)!
	}
}

// ── Combined callback wrappers ──

// wrap_insert runs before_insert → your callback → after_insert.
// The callback receives a mutable reference to the entity so it
// can be passed to V's QueryBuilder methods.
//
// Example:
//   a.wrap_insert(mut user, fn [mut qb] (mut u User) ! {
//       qb.insert(u)!
//   })!
pub fn (mut a OrmAdapter[T]) wrap_insert(mut entity T, callback fn (mut T) !) ! {
	a.before_insert(mut entity)!
	callback(mut entity)!
	a.after_insert(mut entity)!
}

// wrap_update runs before_update → your callback → after_update.
pub fn (mut a OrmAdapter[T]) wrap_update(mut entity T, callback fn (mut T) !) ! {
	a.before_update(mut entity)!
	callback(mut entity)!
	a.after_update(mut entity)!
}

// wrap_save runs insert hooks if the entity is new (is_new() == true)
// or update hooks otherwise.  Uses the Identifiable interface to
// determine newness, which works for any struct embedding BaseEntity.
pub fn (mut a OrmAdapter[T]) wrap_save(mut entity T, callback fn (mut T) !) ! {
	$if T is Identifiable {
		if entity.is_new() {
			a.wrap_insert(mut entity, callback)!
		} else {
			a.wrap_update(mut entity, callback)!
		}
	} $else {
		a.wrap_insert(mut entity, callback)!
	}
}

// wrap_delete runs before_delete → your callback → after_delete.
pub fn (mut a OrmAdapter[T]) wrap_delete(entity T, callback fn () !) ! {
	a.before_delete(entity)!
	callback()!
	a.after_delete(entity)!
}

// ── Derived query helper ──
//
// Method-name parsing is provided by parse_method_name() directly.
// Use it with V's official QueryBuilder:
//
//   parts := orm.parse_method_name('findByNameAndAge')!
//   mut qb := orm.new_query[User](conn)
//   qb.where(parts.to_where_cond(), orm.Primitive(name), orm.Primitive(age))!

module orm

// repository.v - Repository Pattern
//
// Provides the generic Repository[T] trait and BaseRepository[T]
// implementation backed by OrmAdapter.
//
// Follows Spring Data JPA patterns for method naming and
// query derivation (see derive.v).
//
// ── Design ──
//
// BaseRepository[T] wraps OrmAdapter[T] and implements Repository[T].
// Since photon/orm cannot import V's `orm` module (name collision in
// V 0.5.1), the actual ORM operations are provided as callback
// function types by the user (who imports V's `orm` in their module):
//
//   import orm            // V's standard ORM
//   import photon.orm     // BaseRepository + OrmAdapter
//
//   mut repo := orm.new_repository[User](om, 'default',
//       exec_find: fn [om] (conn voidptr, id int) !User { ... },
//       exec_find_all: fn [om] (conn voidptr) ![]User { ... },
//       exec_insert: fn [om] (conn voidptr, u User) ! { ... },
//       exec_update: fn [om] (conn voidptr, u User) ! { ... },
//       exec_delete: fn [om] (conn voidptr, id int) ! { ... },
//       exec_count: fn [om] (conn voidptr) !int { ... },
//       exec_exists: fn [om] (conn voidptr, id int) bool { ... },
//   )!
//
//   // Type-safe CRUD with lifecycle hooks:
//   mut user := User{name: 'Alice'}
//   repo.save(mut user)!  // auto-touch + lifecycle hooks + ORM insert
//   user2 := repo.find_by_id(1)!  // ORM query + AfterFind hook

// Repository is the generic repository trait.
pub interface Repository[T] {
	find_by_id(id int) !T
	find_all() ![]T
	save(mut entity T) !T
	update(mut entity T) !T
	delete_by_id(id int) !
	delete(entity T) !
	count() !int
	exists_by_id(id int) bool
}

// ── ORM executor callbacks (user provides these) ──

// OrmExecFind retrieves a single entity by primary key.
// Implement with V's official orm.QueryBuilder[T].
pub type OrmExecFind[T] = fn (conn voidptr, id int) !T

// OrmExecFindAll retrieves all entities.
pub type OrmExecFindAll[T] = fn (conn voidptr) ![]T

// OrmExecInsert persists a new entity.
pub type OrmExecInsert[T] = fn (conn voidptr, entity T) !

// OrmExecUpdate updates an existing entity.
pub type OrmExecUpdate[T] = fn (conn voidptr, entity T) !

// OrmExecDelete removes an entity by primary key.
pub type OrmExecDelete = fn (conn voidptr, id int) !

// OrmExecCount returns the total entity count.
pub type OrmExecCount = fn (conn voidptr) !int

// OrmExecExists checks existence by primary key.
pub type OrmExecExists = fn (conn voidptr, id int) bool

// ── BaseRepository ──

// BaseRepository implements Repository[T] by wrapping an
// OrmAdapter[T] with user-provided ORM execution callbacks.
//
// The adapter handles lifecycle hooks, auto-touch, and
// connection routing.  The callbacks handle actual V ORM
// operations (QueryBuilder, insert, query, delete, etc.).
//
// No closures are used in the method bodies — V 0.5.1 does
// not support generic type parameters in closure signatures.
pub struct BaseRepository[T] {
pub mut:
	adapter       &OrmAdapter[T]
	exec_find     OrmExecFind[T]
	exec_find_all OrmExecFindAll[T]
	exec_insert   OrmExecInsert[T]
	exec_update   OrmExecUpdate[T]
	exec_delete   OrmExecDelete
	exec_count    OrmExecCount
	exec_exists   OrmExecExists
}

// new_repository creates a BaseRepository backed by the named
// connection in the OrmManager, with all ORM execution callbacks.
//
// All callback fields must be provided.
pub fn new_repository[T](manager &OrmManager, db_name string, exec_find OrmExecFind[T], exec_find_all OrmExecFindAll[T], exec_insert OrmExecInsert[T], exec_update OrmExecUpdate[T], exec_delete OrmExecDelete, exec_count OrmExecCount, exec_exists OrmExecExists) !&BaseRepository[T] {
	mut adapter := new_orm_adapter[T](manager, db_name)!
	return &BaseRepository[T]{
		adapter: adapter
		exec_find: exec_find
		exec_find_all: exec_find_all
		exec_insert: exec_insert
		exec_update: exec_update
		exec_delete: exec_delete
		exec_count: exec_count
		exec_exists: exec_exists
	}
}

// ── Repository[T] implementation (no closures — direct calls) ──

// find_by_id finds an entity by primary key and runs AfterFind hook.
pub fn (mut r BaseRepository[T]) find_by_id(id int) !T {
	conn := r.adapter.get_conn()!
	mut entity := r.exec_find(conn, id)!
	r.adapter.after_find(mut entity)!
	return entity
}

// find_all returns all entities and runs AfterFind hooks.
pub fn (mut r BaseRepository[T]) find_all() ![]T {
	conn := r.adapter.get_conn()!
	mut entities := r.exec_find_all(conn)!
	r.adapter.after_find_all(mut entities)!
	return entities
}

// save inserts or updates an entity with lifecycle hooks.
// Uses Identifiable to detect new vs existing entities.
//
// NOTE: This reimplements OrmAdapter.wrap_save() logic inline because
// V 0.5.1 does not support generic type parameters in closure signatures
// (fn [r] (mut e T) ! would need T to be concrete, but T is generic here).
pub fn (mut r BaseRepository[T]) save(mut entity T) !T {
	$if T is Identifiable {
		if entity.is_new() {
			r.adapter.before_insert(mut entity)!
			conn := r.adapter.get_conn()!
			r.exec_insert(conn, entity)!
			r.adapter.after_insert(mut entity)!
		} else {
			r.adapter.before_update(mut entity)!
			conn := r.adapter.get_conn()!
			r.exec_update(conn, entity)!
			r.adapter.after_update(mut entity)!
		}
	} $else {
		r.adapter.before_insert(mut entity)!
		conn := r.adapter.get_conn()!
		r.exec_insert(conn, entity)!
		r.adapter.after_insert(mut entity)!
	}
	return entity
}

// update updates an existing entity with lifecycle hooks.
pub fn (mut r BaseRepository[T]) update(mut entity T) !T {
	$if T is Identifiable {
		if entity.is_new() {
			return error('update requires an existing entity (id != 0)')
		}
	}
	r.adapter.before_update(mut entity)!
	conn := r.adapter.get_conn()!
	r.exec_update(conn, entity)!
	r.adapter.after_update(mut entity)!
	return entity
}

// delete_by_id deletes an entity by primary key.
pub fn (r &BaseRepository[T]) delete_by_id(id int) ! {
	conn := r.adapter.get_conn()!
	r.exec_delete(conn, id)!
}

// delete deletes an entity instance with lifecycle hooks.
pub fn (mut r BaseRepository[T]) delete(entity T) ! {
	$if T is Identifiable {
		r.adapter.before_delete(entity)!
		conn := r.adapter.get_conn()!
		r.exec_delete(conn, entity.id())!
		r.adapter.after_delete(entity)!
	} $else {
		return error('delete requires an entity with an id')
	}
}

// count returns the total number of entities.
pub fn (r &BaseRepository[T]) count() !int {
	conn := r.adapter.get_conn()!
	return r.exec_count(conn)
}

// exists_by_id checks if an entity exists by primary key.
pub fn (r &BaseRepository[T]) exists_by_id(id int) bool {
	conn := r.adapter.get_conn() or { return false }
	return r.exec_exists(conn, id)
}

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
	exec_find     OrmExecFind[T]    = unsafe { nil }
	exec_find_all OrmExecFindAll[T] = unsafe { nil }
	exec_insert   OrmExecInsert[T]  = unsafe { nil }
	exec_update   OrmExecUpdate[T]  = unsafe { nil }
	exec_delete   OrmExecDelete     = unsafe { nil }
	exec_count    OrmExecCount      = unsafe { nil }
	exec_exists   OrmExecExists     = unsafe { nil }
}

// new_repository creates a BaseRepository backed by the named
// connection in the OrmManager, with all ORM execution callbacks.
//
// All callback fields must be provided.
pub fn new_repository[T](manager &OrmManager, db_name string, exec_find OrmExecFind[T], exec_find_all OrmExecFindAll[T], exec_insert OrmExecInsert[T], exec_update OrmExecUpdate[T], exec_delete OrmExecDelete, exec_count OrmExecCount, exec_exists OrmExecExists) !&BaseRepository[T] {
	mut adapter := new_orm_adapter[T](manager, db_name)!
	return &BaseRepository[T]{
		adapter:       adapter
		exec_find:     exec_find
		exec_find_all: exec_find_all
		exec_insert:   exec_insert
		exec_update:   exec_update
		exec_delete:   exec_delete
		exec_count:    exec_count
		exec_exists:   exec_exists
	}
}

// ── Repository[T] implementation (no closures — direct calls) ──

// find_by_id finds an entity by primary key and runs AfterFind hook.
pub fn (mut r BaseRepository[T]) find_by_id(id int) !T {
	if isnil(r.exec_find) {
		return error('find_by_id: exec_find callback not configured')
	}
	conn := r.adapter.get_conn()!
	mut entity := r.exec_find(conn, id)!
	r.adapter.after_find(mut entity)!
	return entity
}

// find_all returns all entities and runs AfterFind hooks.
pub fn (mut r BaseRepository[T]) find_all() ![]T {
	if isnil(r.exec_find_all) {
		return error('find_all: exec_find_all callback not configured')
	}
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
			if isnil(r.exec_insert) {
				return error('save: exec_insert callback not configured')
			}
			r.exec_insert(conn, entity)!
			r.adapter.after_insert(mut entity)!
		} else {
			r.adapter.before_update(mut entity)!
			conn := r.adapter.get_conn()!
			if isnil(r.exec_update) {
				return error('save: exec_update callback not configured')
			}
			r.exec_update(conn, entity)!
			r.adapter.after_update(mut entity)!
		}
	} $else {
		r.adapter.before_insert(mut entity)!
		conn := r.adapter.get_conn()!
		if isnil(r.exec_insert) {
			return error('save: exec_insert callback not configured')
		}
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
	if isnil(r.exec_update) {
		return error('update: exec_update callback not configured')
	}
	r.adapter.before_update(mut entity)!
	conn := r.adapter.get_conn()!
	r.exec_update(conn, entity)!
	r.adapter.after_update(mut entity)!
	return entity
}

// delete_by_id deletes an entity by primary key.
pub fn (r &BaseRepository[T]) delete_by_id(id int) ! {
	if isnil(r.exec_delete) {
		return error('delete_by_id: exec_delete callback not configured')
	}
	conn := r.adapter.get_conn()!
	r.exec_delete(conn, id)!
}

// delete deletes an entity instance with lifecycle hooks.
pub fn (mut r BaseRepository[T]) delete(entity T) ! {
	if isnil(r.exec_delete) {
		return error('delete: exec_delete callback not configured')
	}
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
	if isnil(r.exec_count) {
		return error('count: exec_count callback not configured')
	}
	conn := r.adapter.get_conn()!
	return r.exec_count(conn)
}

// exists_by_id checks if an entity exists by primary key.
pub fn (r &BaseRepository[T]) exists_by_id(id int) bool {
	if isnil(r.exec_exists) {
		return false
	}
	conn := r.adapter.get_conn() or { return false }
	return r.exec_exists(conn, id)
}

// ── Derived Query Executor callbacks (user provides these) ──
//
// Each callback receives the raw connection, parsed QueryParts,
// and an opaque parameter list ([]voidptr — cast each element to
// orm.Primitive in your implementation).
//
// photon/orm cannot import V's orm.Primitive, so []voidptr is
// used for maximum flexibility.

// OrmExecDerivedFind executes a derived SELECT and returns entities.
// Map QueryParts to V's QueryBuilder: where, order, limit, query.
pub type OrmExecDerivedFind[T] = fn (conn voidptr, parts QueryParts, params []voidptr) ![]T

// OrmExecDerivedCount executes a derived SELECT COUNT(*).
pub type OrmExecDerivedCount = fn (conn voidptr, parts QueryParts, params []voidptr) !int

// OrmExecDerivedExists executes a derived existence check.
pub type OrmExecDerivedExists = fn (conn voidptr, parts QueryParts, params []voidptr) bool

// OrmExecDerivedDelete executes a derived DELETE.
pub type OrmExecDerivedDelete = fn (conn voidptr, parts QueryParts, params []voidptr) !

// ── DerivedRepository ──

// DerivedRepository wraps BaseRepository with Spring Data-style
// derived query support.  It parses method names via
// parse_method_name() and delegates to user-provided executor
// callbacks that build and run V's QueryBuilder.
//
// The adapter's lifecycle hooks (after_find, after_find_all) are
// applied automatically to query results.
//
// Usage:
//   import orm
//   import photon.orm
//
//   mut dr := orm.new_derived_repository[User](om, 'default',
//       exec_find, exec_find_all, exec_insert, exec_update,
//       exec_delete, exec_count, exec_exists,
//       exec_derived_find, exec_derived_count,
//       exec_derived_exists, exec_derived_delete)!
//
//   // Spring Data-style queries:
//   users := dr.find('findByNameAndAge',
//       orm.Primitive('Alice'), orm.Primitive(30))!
//   n := dr.count('countByStatus', orm.Primitive('active'))!
//   dr.delete_by('deleteByStatus', orm.Primitive('expired'))!
pub struct DerivedRepository[T] {
pub mut:
	repo                &BaseRepository[T]
	exec_derived_find   OrmExecDerivedFind[T] = unsafe { nil }
	exec_derived_count  OrmExecDerivedCount   = unsafe { nil }
	exec_derived_exists OrmExecDerivedExists  = unsafe { nil }
	exec_derived_delete OrmExecDerivedDelete  = unsafe { nil }
}

// new_derived_repository creates a DerivedRepository backed by the
// named connection.  Requires all BaseRepository callbacks plus
// four derived-query executor callbacks.
pub fn new_derived_repository[T](manager &OrmManager,
	db_name string,
	exec_find OrmExecFind[T],
	exec_find_all OrmExecFindAll[T],
	exec_insert OrmExecInsert[T],
	exec_update OrmExecUpdate[T],
	exec_delete OrmExecDelete,
	exec_count OrmExecCount,
	exec_exists OrmExecExists,
	exec_derived_find OrmExecDerivedFind[T],
	exec_derived_count OrmExecDerivedCount,
	exec_derived_exists OrmExecDerivedExists,
	exec_derived_delete OrmExecDerivedDelete) !&DerivedRepository[T] {
	mut repo := new_repository[T](manager, db_name, exec_find, exec_find_all, exec_insert,
		exec_update, exec_delete, exec_count, exec_exists)!
	return &DerivedRepository[T]{
		repo:                repo
		exec_derived_find:   exec_derived_find
		exec_derived_count:  exec_derived_count
		exec_derived_exists: exec_derived_exists
		exec_derived_delete: exec_derived_delete
	}
}

// ── Derived query methods ──

// find parses a Spring Data-style method name and executes the
// derived query.  Params should match the number of WHERE
// conditions extracted by parse_method_name().
//
// Lifecycle hooks (after_find, after_find_all) are applied
// automatically via the adapter.
//
// Example:
//   users := dr.find('findByNameAndAge',
//       orm.Primitive('Alice'), orm.Primitive(30))!
pub fn (mut dr DerivedRepository[T]) find(method string, params ...voidptr) ![]T {
	if isnil(dr.exec_derived_find) {
		return error('find: exec_derived_find callback not configured')
	}
	parts := parse_method_name(method)!
	if parts.operation != .find {
		return error('find() requires a find* method, got: ${method}')
	}
	expected := parts.to_where_param_count()
	if params.len != expected {
		return error('${method}: expected ${expected} params, got ${params.len}')
	}
	conn := dr.repo.adapter.get_conn()!
	mut results := dr.exec_derived_find(conn, parts, params)!
	dr.repo.adapter.after_find_all(mut results)!
	return results
}

// count parses a count*-style method name and executes it.
//
// Example:
//   n := dr.count('countByStatus', orm.Primitive('active'))!
pub fn (r &DerivedRepository[T]) count(method string, params ...voidptr) !int {
	if isnil(r.exec_derived_count) {
		return error('count: exec_derived_count callback not configured')
	}
	parts := parse_method_name(method)!
	if parts.operation != .count {
		return error('count() requires a count* method, got: ${method}')
	}
	expected := parts.to_where_param_count()
	if params.len != expected {
		return error('${method}: expected ${expected} params, got ${params.len}')
	}
	conn := r.repo.adapter.get_conn()!
	return r.exec_derived_count(conn, parts, params)
}

// exists parses an exists*-style method name and executes it.
//
// Example:
//   has := dr.exists('existsByEmail', orm.Primitive('a@b.com'))!
pub fn (r &DerivedRepository[T]) exists(method string, params ...voidptr) bool {
	if isnil(r.exec_derived_exists) {
		return false
	}
	parts := parse_method_name(method) or { return false }
	if parts.operation != .exists {
		return false
	}
	expected := parts.to_where_param_count()
	if params.len != expected {
		return false
	}

	conn := r.repo.adapter.get_conn() or { return false }
	return r.exec_derived_exists(conn, parts, params)
}

// delete_by parses a delete*-style method name and executes it.
//
// Example:
//   dr.delete_by('deleteByStatus', orm.Primitive('expired'))!
pub fn (r &DerivedRepository[T]) delete_by(method string, params ...voidptr) ! {
	if isnil(r.exec_derived_delete) {
		return error('delete_by: exec_derived_delete callback not configured')
	}
	parts := parse_method_name(method)!
	if parts.operation != .delete_all {
		return error('delete_by() requires a delete* method, got: ${method}')
	}
	expected := parts.to_where_param_count()
	if params.len != expected {
		return error('${method}: expected ${expected} params, got ${params.len}')
	}
	conn := r.repo.adapter.get_conn()!
	r.exec_derived_delete(conn, parts, params)!
}

// ── Non-generic wrappers for test compatibility ──
// V compiler has trouble resolving generic methods with variadic parameters
// in test files. These wrapper functions provide a workaround.

// derived_find is a non-generic wrapper for DerivedRepository.find
pub fn derived_find[T](mut dr DerivedRepository[T], method string, params ...voidptr) ![]T {
	return dr.find(method, ...params)
}

// derived_count is a non-generic wrapper for DerivedRepository.count
pub fn derived_count[T](dr &DerivedRepository[T], method string, params ...voidptr) !int {
	return dr.count(method, ...params)
}

// derived_exists is a non-generic wrapper for DerivedRepository.exists
pub fn derived_exists[T](dr &DerivedRepository[T], method string, params ...voidptr) bool {
	return dr.exists(method, ...params)
}

// derived_delete_by is a non-generic wrapper for DerivedRepository.delete_by
pub fn derived_delete_by[T](dr &DerivedRepository[T], method string, params ...voidptr) ! {
	dr.delete_by(method, ...params)!
}

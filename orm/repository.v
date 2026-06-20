module orm

import support

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
//
// NOTE: The exec_* fields default to `unsafe { nil }` because V
// requires an explicit default for function-pointer field types.
// In practice these are always set by new_repository / new_derived_repository,
// so the nil state is never observed through the public API. The
// isnil() guards in each method are retained as defense-in-depth.
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

// RepositoryConfig[T] bundles all ORM execution callbacks for
// BaseRepository[T] into a single struct, making construction less
// error-prone than passing 7 positional parameters to new_repository.
//
// Use with new_repository_with_config[T]():
//
//   cfg := orm.RepositoryConfig[User]{
//       exec_find:     fn [om] (conn voidptr, id int) !User { ... }
//       exec_find_all: fn [om] (conn voidptr) ![]User { ... }
//       exec_insert:   fn [om] (conn voidptr, u User) ! { ... }
//       exec_update:   fn [om] (conn voidptr, u User) ! { ... }
//       exec_delete:   fn [om] (conn voidptr, id int) ! { ... }
//       exec_count:    fn [om] (conn voidptr) !int { ... }
//       exec_exists:   fn [om] (conn voidptr, id int) bool { ... }
//   }
//   repo := orm.new_repository_with_config[User](om, 'default', cfg)!
pub struct RepositoryConfig[T] {
pub:
	exec_find     OrmExecFind[T]    = unsafe { nil }
	exec_find_all OrmExecFindAll[T] = unsafe { nil }
	exec_insert   OrmExecInsert[T]  = unsafe { nil }
	exec_update   OrmExecUpdate[T]  = unsafe { nil }
	exec_delete   OrmExecDelete     = unsafe { nil }
	exec_count    OrmExecCount      = unsafe { nil }
	exec_exists   OrmExecExists     = unsafe { nil }
}

// new_repository_with_config creates a BaseRepository backed by the
// named connection in the OrmManager, with all ORM execution callbacks
// supplied via a RepositoryConfig[T] struct.
//
// This is the preferred constructor — it avoids the 7 positional
// parameters of new_repository, reducing the risk of argument
// misordering.
pub fn new_repository_with_config[T](manager &OrmManager, db_name string, config RepositoryConfig[T]) !&BaseRepository[T] {
	mut adapter := new_orm_adapter[T](manager, db_name)!
	return &BaseRepository[T]{
		adapter:       adapter
		exec_find:     config.exec_find
		exec_find_all: config.exec_find_all
		exec_insert:   config.exec_insert
		exec_update:   config.exec_update
		exec_delete:   config.exec_delete
		exec_count:    config.exec_count
		exec_exists:   config.exec_exists
	}
}

// new_repository creates a BaseRepository backed by the named
// connection in the OrmManager, with all ORM execution callbacks.
//
// All callback fields must be provided.
@[deprecated: 'use new_repository_with_config instead']
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

// DerivedRepositoryConfig[T] bundles all callbacks for
// DerivedRepository[T] (the 7 BaseRepository callbacks plus 4
// derived-query executors) into a single struct, avoiding the 11
// positional parameters of new_derived_repository.
//
// Use with new_derived_repository_with_config[T]():
//
//   cfg := orm.DerivedRepositoryConfig[User]{
//       base: orm.RepositoryConfig[User]{
//           exec_find:     fn [om] (conn voidptr, id int) !User { ... }
//           // ...other base callbacks...
//       }
//       exec_derived_find:   fn [om] (conn voidptr, parts orm.QueryParts, params []voidptr) ![]User { ... }
//       exec_derived_count:  fn [om] (conn voidptr, parts orm.QueryParts, params []voidptr) !int { ... }
//       exec_derived_exists: fn [om] (conn voidptr, parts orm.QueryParts, params []voidptr) bool { ... }
//       exec_derived_delete: fn [om] (conn voidptr, parts orm.QueryParts, params []voidptr) ! { ... }
//   }
//   dr := orm.new_derived_repository_with_config[User](om, 'default', cfg)!
pub struct DerivedRepositoryConfig[T] {
pub:
	base                RepositoryConfig[T]
	exec_derived_find   OrmExecDerivedFind[T] = unsafe { nil }
	exec_derived_count  OrmExecDerivedCount   = unsafe { nil }
	exec_derived_exists OrmExecDerivedExists  = unsafe { nil }
	exec_derived_delete OrmExecDerivedDelete  = unsafe { nil }
}

// new_derived_repository_with_config creates a DerivedRepository
// backed by the named connection, with all callbacks supplied via a
// DerivedRepositoryConfig[T] struct.
//
// This is the preferred constructor — it avoids the 11 positional
// parameters of new_derived_repository.
pub fn new_derived_repository_with_config[T](manager &OrmManager, db_name string, config DerivedRepositoryConfig[T]) !&DerivedRepository[T] {
	mut repo := new_repository_with_config[T](manager, db_name, config.base)!
	return &DerivedRepository[T]{
		repo:                repo
		exec_derived_find:   config.exec_derived_find
		exec_derived_count:  config.exec_derived_count
		exec_derived_exists: config.exec_derived_exists
		exec_derived_delete: config.exec_derived_delete
	}
}

// new_derived_repository creates a DerivedRepository backed by the
// named connection.  Requires all BaseRepository callbacks plus
// four derived-query executor callbacks.
@[deprecated: 'use new_derived_repository_with_config instead']
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

// ═══════════════════════════════════════════════════════════════════
// JpaRepository[T] — Comptime-Derived Repository (P0 8.3)
// ═══════════════════════════════════════════════════════════════════
//
// Inspired by Spring Data's JpaRepository.  Uses V's comptime to
// derive SQL from the entity struct T, eliminating the need for the
// 7 CRUD-specific callbacks that BaseRepository requires.
//
// ── Two Generic Callbacks Instead of Seven ──
//
//   BaseRepository requires 7 CRUD-specific callbacks (exec_find,
//   exec_find_all, exec_insert, exec_update, exec_delete, exec_count,
//   exec_exists) — each containing hand-written ORM logic.
//
//   JpaRepository replaces them with 2 GENERIC callbacks:
//     • exec_fn  — execute non-query SQL (INSERT/UPDATE/DELETE/DDL)
//     • query_fn — execute SELECT, return rows as [][]string
//
//   The CRUD SQL itself is generated by comptime — you only supply
//   raw SQL execution.  This is a dramatic reduction in boilerplate.
//
//   NOTE: photon/orm cannot import db.sqlite (or any module that
//   imports V's standard `orm`) due to the module-name collision in
//   V 0.5.1.  Therefore the exec/query functions are supplied by the
//   caller, who imports the DB driver in their own module.  See
//   jpa_repository_test.v for a mock-based example, and the example/
//   app for a real sqlite-backed usage.
//
// ── Usage ──
//
//       // In your module (imports db.sqlite + photon.orm):
//       exec_fn := fn (db voidptr, query string, args []string) ! {
//           real := unsafe { &sqlite.DB(db) }
//           if args.len == 0 { real.exec(query)! } else { real.exec_param_many(query, args)! }
//       }
//       query_fn := fn (db voidptr, query string, args []string) ![][]string {
//           real := unsafe { &sqlite.DB(db) }
//           rows := if args.len == 0 { real.exec(query)! } else { real.exec_param_many(query, args)! }
//           return rows.map(it.vals)
//       }
//
//       mut repo := orm.new_jpa_repository[User](om, 'default', 'users', exec_fn, query_fn)!
//       repo.create_table()!                       // CREATE TABLE IF NOT EXISTS
//       repo.save(&User{name: 'Alice', ...})!      // INSERT (comptime-derived)
//       user := repo.find_by_id(1)!                // SELECT ... WHERE id = ?
//       all  := repo.find_all()!                   // SELECT * FROM users
//       n    := repo.count()!                      // SELECT COUNT(*)
//       repo.delete(1)!                            // DELETE WHERE id = ?
//
// ── @[autowired] / DI Integration (SubTask 13.4) ──
//
//   JpaRepository itself is not a Photon bean (it is generic, and V's
//   comptime DI cannot instantiate arbitrary T at container startup).
//   Instead, autowire the &OrmManager into a @[component] factory and
//   call new_jpa_repository[T]() from there:
//
//       @[component]
//       pub struct UserService {
//           @[autowired]
//           om &OrmManager
//       }
//
//       fn (s &UserService) repo() !JpaRepository[User] {
//           return new_jpa_repository[User](s.om, 'default', 'users',
//               my_exec_fn, my_query_fn)!
//       }
//
// ── Primary Key Detection ──
//
//   The constructor scans T's fields at compile time and picks the
//   primary key in this priority order:
//     1. A field with the @[primary_key] attribute
//     2. A field named 'id'
//   If neither exists, the constructor returns an error.

// SqlExecFn executes a non-query SQL statement (INSERT/UPDATE/DELETE/
// CREATE TABLE).  `db` is the raw connection pointer from
// OrmManager.get_conn().  `args` are positional `?` placeholders.
pub type SqlExecFn = fn (db voidptr, query string, args []string) !

// SqlQueryFn executes a SELECT and returns rows as a 2D string array.
// Each inner []string is one row's column values, in field order.
pub type SqlQueryFn = fn (db voidptr, query string, args []string) ![][]string

// JpaRepository[T] is a comptime-derived repository backed by two
// generic SQL execution callbacks.  See the module-level docs above.
pub struct JpaRepository[T] {
pub:
	entity_type string
	table_name  string
	orm_manager &OrmManager = unsafe { nil }
mut:
	db_name           string
	primary_key_field string
	field_names       []string
	exec_fn           SqlExecFn  = unsafe { nil }
	query_fn          SqlQueryFn = unsafe { nil }
}

// new_jpa_repository creates a JpaRepository[T] with comptime-derived
// field metadata and two generic SQL execution callbacks.
//
// The entity struct T must have either a field with the
// @[primary_key] attribute or a field named 'id'.
//
// `exec_fn`  — executes INSERT/UPDATE/DELETE/DDL statements.
// `query_fn` — executes SELECT, returns rows as [][]string.
pub fn new_jpa_repository[T](orm_manager &OrmManager, db_name string, table_name string, exec_fn SqlExecFn, query_fn SqlQueryFn) !JpaRepository[T] {
	mut repo := JpaRepository[T]{
		entity_type: typeof[T]().name
		table_name:  table_name
		orm_manager: orm_manager
		db_name:     db_name
		exec_fn:     exec_fn
		query_fn:    query_fn
	}
	// Comptime: extract field names and find primary key
	$for field in T.fields {
		repo.field_names << field.name
		// Detect primary key via @[primary_key] attribute
		for attr in field.attrs {
			if attr == 'primary_key' {
				repo.primary_key_field = field.name
			}
		}
		// Fallback: field named 'id'
		if repo.primary_key_field == '' && field.name == 'id' {
			repo.primary_key_field = field.name
		}
	}
	if repo.primary_key_field == '' {
		return error('no primary key field found in ${typeof[T]().name}')
	}
	return repo
}

// ── CRUD methods ──

// find_by_id retrieves a single entity by primary key.
// Returns an error ('entity not found') if no entity is found.
pub fn (mut repo JpaRepository[T]) find_by_id(id i64) !T {
	if isnil(repo.query_fn) {
		return error('find_by_id: query_fn not configured')
	}
	pk_col := support.snake(repo.primary_key_field)
	query := 'SELECT ${repo.columns_clause()} FROM ${repo.table_name} WHERE ${pk_col} = ?'
	db := repo.orm_manager.get_conn(repo.db_name)!
	rows := repo.query_fn(db, query, ['${id}'])!
	if rows.len == 0 {
		return error('entity not found: ${repo.entity_type} with ${pk_col}=${id}')
	}
	mut entity := T{}
	jpa_map_row(mut entity, rows[0])
	return entity
}

// save inserts a new entity.  The primary key field is omitted from
// the INSERT when its value is 0 (auto-increment support).
pub fn (mut repo JpaRepository[T]) save(entity &T) ! {
	if isnil(repo.exec_fn) {
		return error('save: exec_fn not configured')
	}
	mut columns := []string{}
	mut placeholders := []string{}
	mut args := []string{}
	$for field in T.fields {
		val_str := entity.$(field.name).str()
		// Skip auto-increment PK when value is 0 (continue is not
		// allowed in comptime $for, so guard with an inverted if)
		is_auto_pk := field.name == repo.primary_key_field && val_str == '0'
		if !is_auto_pk {
			columns << support.snake(field.name)
			placeholders << '?'
			args << val_str
		}
	}
	if columns.len == 0 {
		return error('save: no columns to insert')
	}
	query := 'INSERT INTO ${repo.table_name} (${columns.join(', ')}) VALUES (${placeholders.join(', ')})'
	db := repo.orm_manager.get_conn(repo.db_name)!
	repo.exec_fn(db, query, args)!
}

// delete removes an entity by primary key.
pub fn (mut repo JpaRepository[T]) delete(id i64) ! {
	if isnil(repo.exec_fn) {
		return error('delete: exec_fn not configured')
	}
	pk_col := support.snake(repo.primary_key_field)
	query := 'DELETE FROM ${repo.table_name} WHERE ${pk_col} = ?'
	db := repo.orm_manager.get_conn(repo.db_name)!
	repo.exec_fn(db, query, ['${id}'])!
}

// find_all retrieves all entities.
pub fn (mut repo JpaRepository[T]) find_all() ![]T {
	if isnil(repo.query_fn) {
		return error('find_all: query_fn not configured')
	}
	query := 'SELECT ${repo.columns_clause()} FROM ${repo.table_name}'
	db := repo.orm_manager.get_conn(repo.db_name)!
	rows := repo.query_fn(db, query, []string{})!
	mut entities := []T{cap: rows.len}
	for row in rows {
		mut entity := T{}
		jpa_map_row(mut entity, row)
		entities << entity
	}
	return entities
}

// find_all_paged retrieves a page of entities with pagination metadata.
//
// Executes two SQL queries (no full-table scan):
//   1. SELECT COUNT(*) FROM <table>                          — total entity count
//   2. SELECT <cols> FROM <table> [ORDER BY ...] LIMIT ? OFFSET ? — page items
//
// The PageRequest's sort orders are applied as an ORDER BY clause with
// snake_case column name conversion (so callers may pass either camelCase
// field names or snake_case column names).  Page numbers are 1-based;
// a page_number < 1 is normalized to 1.  A page_size <= 0 returns an error.
//
// Out-of-bounds pages return an empty items slice with the correct total
// and total_pages.  All SQL uses positional `?` placeholders — no string
// interpolation of user values, preventing SQL injection.
//
// Example:
//   pr := support.page_request(2, 10)            // page 2, 10 items per page
//   page := repo.find_all_paged(pr)!             // Page[User]
//   assert page.items.len == 10
//   assert page.total == 25
//   assert page.total_pages == 3
pub fn (mut repo JpaRepository[T]) find_all_paged(page_request support.PageRequest) !support.Page[T] {
	if isnil(repo.query_fn) {
		return error('find_all_paged: query_fn not configured')
	}
	if page_request.size <= 0 {
		return error('find_all_paged: page size must be positive, got ${page_request.size}')
	}

	// Normalize page number: treat 0 or negative as page 1
	page_num := if page_request.page < 1 { 1 } else { page_request.page }
	offset := (page_num - 1) * page_request.size

	db := repo.orm_manager.get_conn(repo.db_name)!

	// 1. Get total count via SELECT COUNT(*)
	count_query := 'SELECT COUNT(*) FROM ${repo.table_name}'
	count_rows := repo.query_fn(db, count_query, []string{})!
	mut total := i64(0)
	if count_rows.len > 0 && count_rows[0].len > 0 {
		total = count_rows[0][0].i64()
	}

	// 2. Build SELECT query with optional ORDER BY + LIMIT/OFFSET
	mut query := 'SELECT ${repo.columns_clause()} FROM ${repo.table_name}'
	mut args := []string{}

	// Build ORDER BY clause with snake_case column conversion
	if page_request.sort.orders.len > 0 {
		mut order_parts := []string{cap: page_request.sort.orders.len}
		for order in page_request.sort.orders {
			col := support.snake(order.property)
			dir := if order.direction == .desc { 'DESC' } else { 'ASC' }
			order_parts << '${col} ${dir}'
		}
		query += ' ORDER BY ${order_parts.join(', ')}'
	}

	// LIMIT/OFFSET use positional ? placeholders (parameterized)
	query += ' LIMIT ? OFFSET ?'
	args << '${page_request.size}'
	args << '${offset}'

	rows := repo.query_fn(db, query, args)!

	// 3. Map rows to entities
	mut entities := []T{cap: rows.len}
	for row in rows {
		mut entity := T{}
		jpa_map_row(mut entity, row)
		entities << entity
	}

	// 4. Build Page[T] with computed total_pages (ceiling division)
	return support.new_page[T](entities, total, page_num, page_request.size)
}

// count returns the total number of entities.
pub fn (mut repo JpaRepository[T]) count() !i64 {
	if isnil(repo.query_fn) {
		return error('count: query_fn not configured')
	}
	query := 'SELECT COUNT(*) FROM ${repo.table_name}'
	db := repo.orm_manager.get_conn(repo.db_name)!
	rows := repo.query_fn(db, query, []string{})!
	if rows.len == 0 || rows[0].len == 0 {
		return 0
	}
	return rows[0][0].i64()
}

// ── DDL helper ──

// create_table creates the table if it does not exist, using
// comptime-derived column definitions from T's fields.  The primary
// key column gets a `PRIMARY KEY` constraint.
pub fn (mut repo JpaRepository[T]) create_table() ! {
	if isnil(repo.exec_fn) {
		return error('create_table: exec_fn not configured')
	}
	mut col_defs := []string{}
	$for field in T.fields {
		col_name := support.snake(field.name)
		mut col_type := 'TEXT'
		$if field.typ is string {
			col_type = 'TEXT'
		} $else $if field.typ is int {
			col_type = 'INTEGER'
		} $else $if field.typ is i64 {
			col_type = 'INTEGER'
		} $else $if field.typ is f64 {
			col_type = 'REAL'
		} $else $if field.typ is bool {
			col_type = 'INTEGER'
		}
		if field.name == repo.primary_key_field {
			col_defs << '${col_name} ${col_type} PRIMARY KEY'
		} else {
			col_defs << '${col_name} ${col_type}'
		}
	}
	query := 'CREATE TABLE IF NOT EXISTS ${repo.table_name} (${col_defs.join(', ')})'
	db := repo.orm_manager.get_conn(repo.db_name)!
	repo.exec_fn(db, query, []string{})!
}

// ── Internal helpers ──

// columns_clause returns a comma-separated list of snake_case column
// names derived from the entity's field names.
fn (repo JpaRepository[T]) columns_clause() string {
	mut cols := []string{cap: repo.field_names.len}
	for name in repo.field_names {
		cols << support.snake(name)
	}
	return cols.join(', ')
}

// jpa_map_row maps a string row (column values in field order) to a
// struct T using comptime field type dispatch.
fn jpa_map_row[T](mut entity T, row []string) {
	mut i := 0
	$for field in T.fields {
		if i < row.len {
			val := row[i]
			$if field.typ is string {
				entity.$(field.name) = val
			} $else $if field.typ is int {
				entity.$(field.name) = val.int()
			} $else $if field.typ is i64 {
				entity.$(field.name) = val.i64()
			} $else $if field.typ is f64 {
				entity.$(field.name) = val.f64()
			} $else $if field.typ is bool {
				entity.$(field.name) = val == '1' || val == 'true'
			}
			i++
		}
	}
}

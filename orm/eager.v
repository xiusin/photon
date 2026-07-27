module orm

// eager.v - Eager Loading for Relations (Laravel Eloquent with() inspired)
//
// Provides eager loading to prevent the N+1 query problem.
// Instead of lazy-loading relations one at a time, `with()` preloads
// related entities in a single batch query.
//
// Usage:
//   repo.with('comments').find_by_id(1)
//   repo.with(['comments', 'author']).find_all()

// EagerLoadSpec describes a relation to eager-load
pub struct EagerLoadSpec {
pub:
	name        string // relation name (e.g., 'comments', 'author')
	foreign_key string // the FK column in the target table
	local_key   string // the local column (default: 'id')
}

// EagerLoader preloads relations for entities.
//
// SQL execution is delegated to user-supplied callbacks (SqlExecFn /
// SqlQueryFn — the same types used by RelationLoader and Repository),
// because photon/orm cannot import db drivers (module-name collision
// in V 0.5.1).  Use new_eager_loader_with_fns() to configure them.
pub struct EagerLoader[T] {
pub mut:
	manager    &OrmManager
	table_name string
	db_name    string
	withs      []EagerLoadSpec
	exec_fn    SqlExecFn  = unsafe { nil }
	query_fn   SqlQueryFn = unsafe { nil }
}

// new_eager_loader creates an EagerLoader.  SQL callbacks are NOT set —
// use new_eager_loader_with_fns() if you intend to call
// load_has_many / load_belongs_to.
pub fn new_eager_loader[T](manager &OrmManager, table_name string) &EagerLoader[T] {
	return &EagerLoader[T]{
		manager:    manager
		table_name: table_name
	}
}

// new_eager_loader_with_fns creates an EagerLoader with SQL execution
// callbacks.  This is the preferred constructor for actually loading
// relations.
//
// `exec_fn`  — executes INSERT/UPDATE/DELETE/DDL (unused by load_*
//              methods today, accepted for symmetry with RelationLoader).
// `query_fn` — executes SELECT, returns rows as [][]string.
pub fn new_eager_loader_with_fns[T](manager &OrmManager, table_name string, db_name string, exec_fn SqlExecFn, query_fn SqlQueryFn) &EagerLoader[T] {
	return &EagerLoader[T]{
		manager:    manager
		table_name: table_name
		db_name:    db_name
		exec_fn:    exec_fn
		query_fn:   query_fn
	}
}

// with specifies relations to eager-load (chainable)
// Supports both string and []string for convenience
pub fn (mut el EagerLoader[T]) with(relations []string) &EagerLoader[T] {
	for rel in relations {
		el.withs << EagerLoadSpec{
			name:        rel
			foreign_key: get_relation_fk(rel)
			local_key:   'id'
		}
	}
	return el
}

// with_single adds a single relation
pub fn (mut el EagerLoader[T]) with_single(relation string) &EagerLoader[T] {
	return el.with([relation])
}

// EagerRepository provides eager loading support.
// Use with the adapter module for ORM-backed operations.
pub struct EagerRepository[T] {
pub mut:
	manager      &OrmManager
	table_name   string
	db_name      string
	eager_loader &EagerLoader[T]
}

// new_eager_repository creates an EagerRepository.  SQL callbacks are
// NOT set on the underlying EagerLoader — use
// new_eager_repository_with_fns() if you intend to call
// load_has_many / load_belongs_to.
pub fn new_eager_repository[T](manager &OrmManager, table_name string) &EagerRepository[T] {
	return &EagerRepository[T]{
		manager:      manager
		table_name:   table_name
		eager_loader: new_eager_loader[T](manager, table_name)
	}
}

// new_eager_repository_with_fns creates an EagerRepository whose
// EagerLoader is configured with SQL execution callbacks.
pub fn new_eager_repository_with_fns[T](manager &OrmManager, table_name string, db_name string, exec_fn SqlExecFn, query_fn SqlQueryFn) &EagerRepository[T] {
	return &EagerRepository[T]{
		manager:      manager
		table_name:   table_name
		db_name:      db_name
		eager_loader: new_eager_loader_with_fns[T](manager, table_name, db_name, exec_fn,
			query_fn)
	}
}

// with specifies relations to eager-load on the next query
pub fn (mut r EagerRepository[T]) with(relations []string) &EagerRepository[T] {
	r.eager_loader.with(relations)
	return r
}

// with_single is a convenience wrapper for a single relation
pub fn (mut r EagerRepository[T]) with_single(relation string) &EagerRepository[T] {
	r.eager_loader.with_single(relation)
	return r
}

// find_by_id_with loads an entity with eager-loaded relations.
// Stub: actual query execution requires adapter integration.
pub fn (r &EagerRepository[T]) find_by_id_with(id int) !T {
	_ := r.manager.get_conn(r.db_name)!
	return error('find_by_id_with requires adapter integration')
}

// Helper: guess foreign key from relation name
fn get_relation_fk(relation_name string) string {
	// Singularize: 'comments' → 'comment_id', 'author' → 'author_id'
	mut fk := relation_name
	if fk.ends_with('s') {
		fk = fk[..fk.len - 1]
	}
	return '${fk}_id'
}

// Helper: get table name from relation name
fn get_table_name_by_relation(relation_name string) string {
	return relation_name
}

// Helper: extract a field value from a struct
fn get_field_value[T](entity T, field_name string) string {
	$for field in T.fields {
		if field.name == field_name {
			return entity.$(field.name).str()
		}
	}
	return '0'
}

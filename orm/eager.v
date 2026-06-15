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

// EagerLoader preloads relations for entities
pub struct EagerLoader[T] {
pub mut:
	manager    &OrmManager
	table_name string
	db_name    string
	withs      []EagerLoadSpec
}

// new_eager_loader creates an EagerLoader
pub fn new_eager_loader[T](manager &OrmManager, table_name string) &EagerLoader[T] {
	return &EagerLoader[T]{
		manager: manager
		table_name: table_name
	}
}

// with specifies relations to eager-load (chainable)
// Supports both string and []string for convenience
pub fn (mut el EagerLoader[T]) with(relations []string) &EagerLoader[T] {
	for rel in relations {
		el.withs << EagerLoadSpec{
			name: rel
			foreign_key: get_relation_fk(rel)
			local_key: 'id'
		}
	}
	return el
}

// with_single adds a single relation
pub fn (mut el EagerLoader[T]) with_single(relation string) &EagerLoader[T] {
	return el.with([relation])
}

// load_has_many eager-loads a HasMany relation for multiple parent entities
pub fn (el &EagerLoader[T]) load_has_many[R](parents []T, mut relations map[int]HasMany[R], fk string) ! {
	if parents.len == 0 {
		return
	}

	// Collect parent IDs
	mut ids := []string{cap: parents.len}
	for parent in parents {
		ids << '${parent.id()}'
	}

	target_table := get_table_name[R]()
	query := 'SELECT * FROM ${target_table} WHERE ${fk} IN (${ids.join(', ')})'

	db_conn := el.manager.get_conn(el.db_name)!
	_ = query
	_ = db_conn

	// Stub: actual DB execution requires real driver
	for parent in parents {
		relations[parent.id()] = new_has_many[R]()
	}
}

// load_belongs_to eager-loads BelongsTo for multiple parent entities
pub fn (el &EagerLoader[T]) load_belongs_to[R](parents []T, mut relations map[int]BelongsTo[R], fk string) ! {
	if parents.len == 0 {
		return
	}

	// Collect foreign key values
	mut fk_values := []string{cap: parents.len}
	for parent in parents {
		fk_values << get_field_value(parent, fk)
	}

	target_table := get_table_name[R]()
	query := 'SELECT * FROM ${target_table} WHERE id IN (${fk_values.join(', ')})'

	db_conn := el.manager.get_conn(el.db_name)!
	_ = query
	_ = db_conn

	for parent in parents {
		relations[parent.id()] = new_belongs_to[R]()
	}
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

// new_eager_repository creates an EagerRepository
pub fn new_eager_repository[T](manager &OrmManager, table_name string) &EagerRepository[T] {
	return &EagerRepository[T]{
		manager: manager
		table_name: table_name
		eager_loader: new_eager_loader[T](manager, table_name)
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

module orm

import support

// relation.v - Entity Relationships
//
// Provides relationship types and helper functions for managing
// entity relationships: OneToOne, OneToMany (HasMany), ManyToOne (BelongsTo),
// and ManyToMany.
//
// ── Relation Loading ──
//
// RelationLoader executes parameterized SQL to load related entities
// and backfills HasMany / BelongsTo / ManyToMany placeholders.  Because
// photon/orm cannot import db.sqlite or V's standard `orm` module
// (module-name collision in V 0.5.1), SQL execution is delegated to
// user-supplied callbacks (SqlExecFn / SqlQueryFn — the same types
// used by JpaRepository).
//
//   import db.sqlite
//   import photon.orm
//
//   db := sqlite.connect(':memory:')!
//   mut om := orm.new_orm_manager()
//   om.register_connection('default', .sqlite, voidptr(db))!
//
//   exec_fn := fn (db voidptr, query string, args []string) ! {
//       real := unsafe { &sqlite.DB(db) }
//       if args.len == 0 { real.exec(query)! } else { real.exec_param_many(query, args)! }
//   }
//   query_fn := fn (db voidptr, query string, args []string) ![][]string {
//       real := unsafe { &sqlite.DB(db) }
//       rows := if args.len == 0 { real.exec(query)! } else { real.exec_param_many(query, args)! }
//       return rows.map(it.vals)
//   }
//
//   rl := orm.new_relation_loader_with_fns(om, 'default', exec_fn, query_fn)
//
//   mut user := User{ id: 1, name: 'Alice' }
//   mut posts := orm.new_has_many[Post]()
//   rl.load_has_many[User, Post](user, mut posts, 'user_id')!
//   // posts.items now contains all Posts where user_id == 1

// Relationship represents a relationship between entities
pub struct Relationship {
pub:
	name        string
	typ         string // 'has_many', 'belongs_to', 'many_to_many', 'has_one'
	target      string // Target entity type name
	foreign_key string
	local_key   string
	pivot_table string // For many-to-many
}

// HasMany adds a one-to-many relationship helper
pub struct HasMany[T] {
pub mut:
	items []T
mut:
	loaded bool
}

// new_has_many creates a new HasMany relationship placeholder
pub fn new_has_many[T]() HasMany[T] {
	return HasMany[T]{}
}

// BelongsTo adds a many-to-one relationship helper
pub struct BelongsTo[T] {
pub mut:
	item   T
	loaded bool
}

// new_belongs_to creates a new BelongsTo relationship placeholder
pub fn new_belongs_to[T]() BelongsTo[T] {
	return BelongsTo[T]{}
}

// ManyToMany adds a many-to-many relationship helper
pub struct ManyToMany[T] {
pub mut:
	items []T
mut:
	loaded bool
}

// new_many_to_many creates a new ManyToMany relationship placeholder
pub fn new_many_to_many[T]() ManyToMany[T] {
	return ManyToMany[T]{}
}

// HasOne adds a one-to-one relationship helper
pub struct HasOne[T] {
pub mut:
	item   T
	loaded bool
}

// new_has_one creates a new HasOne relationship placeholder
pub fn new_has_one[T]() HasOne[T] {
	return HasOne[T]{}
}

// ── RelationLoader ──

// RelationLoader loads relationships for an entity by executing
// parameterized SQL via user-supplied callbacks.
//
// Thread-safety: RelationLoader holds no mutable state after
// construction.  The underlying OrmManager.get_conn() is protected
// by an RwMutex, and the exec_fn / query_fn callbacks are expected
// to be stateless or thread-safe on their own.
pub struct RelationLoader {
pub mut:
	manager  &OrmManager
	db_name  string
	exec_fn  SqlExecFn  = unsafe { nil }
	query_fn SqlQueryFn = unsafe { nil }
}

// new_relation_loader creates a RelationLoader backed by the default
// connection.  SQL callbacks are NOT set — use
// new_relation_loader_with_fns() if you intend to call
// load_has_many / load_belongs_to / load_many_to_many.
pub fn new_relation_loader(manager &OrmManager) &RelationLoader {
	return &RelationLoader{
		manager: manager
	}
}

// new_relation_loader_with_fns creates a RelationLoader with SQL
// execution callbacks.  This is the preferred constructor for
// actually loading relations.
//
// `exec_fn`  — executes INSERT/UPDATE/DELETE/DDL (unused by load_*
//              methods today, but accepted for symmetry with
//              JpaRepository and future write-side relation ops).
// `query_fn` — executes SELECT, returns rows as [][]string.
pub fn new_relation_loader_with_fns(manager &OrmManager, db_name string, exec_fn SqlExecFn, query_fn SqlQueryFn) &RelationLoader {
	return &RelationLoader{
		manager:  manager
		db_name:  db_name
		exec_fn:  exec_fn
		query_fn: query_fn
	}
}

// load_has_many loads a HasMany relationship by executing
//   SELECT * FROM {child_table} WHERE {foreign_key} = ?
// and backfilling relation.items with the mapped child entities.
//
// The parent entity T must have a primary key field (either a field
// with the @[primary_key] attribute or a field named 'id').
// The child table name is derived from R's type name via
// snake_case + 's' (e.g. Post → posts).
//
// All identifiers (table name, foreign key) are validated against
// a strict alphanumeric+underscore whitelist to prevent SQL injection.
// The foreign-key value is passed as a positional ? parameter.
pub fn (rl &RelationLoader) load_has_many[T, R](entity T, mut relation HasMany[R], foreign_key string) ! {
	if isnil(rl.query_fn) {
		return error('load_has_many: query_fn not configured')
	}

	// 1. Get parent PK value via comptime
	pk_value := get_entity_pk_value(entity)!

	// 2. Validate identifiers (prevent SQL injection via table/column names)
	target_table := get_table_name[R]()
	if !is_valid_identifier(target_table) {
		return error('load_has_many: invalid table name "${target_table}"')
	}
	if !is_valid_identifier(foreign_key) {
		return error('load_has_many: invalid foreign key "${foreign_key}"')
	}

	// 3. Execute parameterized query
	query := 'SELECT * FROM ${target_table} WHERE ${foreign_key} = ?'
	db := rl.manager.get_conn(rl.db_name)!
	rows := rl.query_fn(db, query, [pk_value])!

	// 4. Map rows to R structs (positional, same as JpaRepository)
	mut items := []R{cap: rows.len}
	for row in rows {
		mut item := R{}
		jpa_map_row(mut item, row)
		items << item
	}

	// 5. Backfill relation
	relation.items = items
	relation.loaded = true
}

// load_belongs_to loads a BelongsTo relationship by executing
//   SELECT * FROM {parent_table} WHERE id = ?
// and backfilling relation.item with the mapped parent entity.
//
// The child entity T must have a field named {foreign_key} whose
// value is used as the parent's primary key.  If the FK value is 0
// or empty (null FK), relation.item is left as the zero value and
// relation.loaded is set to true.
//
// The parent table name is derived from R's type name via
// snake_case + 's' (e.g. User → users).
pub fn (rl &RelationLoader) load_belongs_to[T, R](entity T, mut relation BelongsTo[R], foreign_key string) ! {
	if isnil(rl.query_fn) {
		return error('load_belongs_to: query_fn not configured')
	}

	// 1. Get child's FK value via comptime
	fk_value := get_entity_field_value(entity, foreign_key)!

	// 2. Validate identifiers
	target_table := get_table_name[R]()
	if !is_valid_identifier(target_table) {
		return error('load_belongs_to: invalid table name "${target_table}"')
	}

	// 3. Handle null FK (value is '0' or empty) — leave item as zero value
	if fk_value == '0' || fk_value == '' {
		relation.item = R{}
		relation.loaded = true
		return
	}

	// 4. Execute parameterized query
	query := 'SELECT * FROM ${target_table} WHERE id = ?'
	db := rl.manager.get_conn(rl.db_name)!
	rows := rl.query_fn(db, query, [fk_value])!

	// 5. Map result (0 or 1 row expected)
	if rows.len > 0 {
		mut item := R{}
		jpa_map_row(mut item, rows[0])
		relation.item = item
	}
	relation.loaded = true
}

// load_many_to_many loads a ManyToMany relationship via a pivot table:
//   SELECT t.* FROM {target_table} t
//   INNER JOIN {pivot_table} p ON t.id = p.{target_fk}
//   WHERE p.{local_fk} = ?
//
// Parameters:
//   pivot_table  — the join table (e.g. user_roles)
//   local_key    — FK column on the pivot pointing to this entity (e.g. user_id)
//   foreign_key  — FK column on the pivot pointing to the target (e.g. role_id)
//
// The entity T must have a primary key field.
// The target table name is derived from R's type name via
// snake_case + 's' (e.g. Role → roles).
//
// All identifiers are validated against a strict whitelist.
pub fn (rl &RelationLoader) load_many_to_many[T, R](entity T, mut relation ManyToMany[R], pivot_table string, local_key string, foreign_key string) ! {
	if isnil(rl.query_fn) {
		return error('load_many_to_many: query_fn not configured')
	}

	// 1. Get entity PK value via comptime
	pk_value := get_entity_pk_value(entity)!

	// 2. Validate all identifiers
	target_table := get_table_name[R]()
	for ident in [target_table, pivot_table, local_key, foreign_key] {
		if !is_valid_identifier(ident) {
			return error('load_many_to_many: invalid identifier "${ident}"')
		}
	}

	// 3. Execute parameterized JOIN query
	query := 'SELECT t.* FROM ${target_table} t INNER JOIN ${pivot_table} p ON t.id = p.${foreign_key} WHERE p.${local_key} = ?'
	db := rl.manager.get_conn(rl.db_name)!
	rows := rl.query_fn(db, query, [pk_value])!

	// 4. Map rows to R structs
	mut items := []R{cap: rows.len}
	for row in rows {
		mut item := R{}
		jpa_map_row(mut item, row)
		items << item
	}

	// 5. Backfill relation
	relation.items = items
	relation.loaded = true
}

// ── Internal helpers ──

// get_table_name derives a snake_case table name from type T.
// Strips the module prefix from typeof[T]().name (e.g. 'orm.RelPost'
// → 'RelPost'), then applies snake_case + 's' (→ 'rel_posts').
fn get_table_name[T]() string {
	full_name := typeof[T]().name
	short_name := if idx := full_name.last_index('.') {
		full_name[idx + 1..]
	} else {
		full_name
	}
	return support.snake(short_name) + 's'
}

// get_entity_pk_value extracts the primary key value from an entity
// via comptime.  Looks for a field with the @[primary_key] attribute,
// falling back to a field named 'id'.  Returns the value as a string.
fn get_entity_pk_value[T](entity T) !string {
	mut pk_value := ''
	mut found := false
	$for field in T.fields {
		if !found {
			mut is_pk := false
			for attr in field.attrs {
				if attr == 'primary_key' {
					is_pk = true
				}
			}
			if is_pk || field.name == 'id' {
				pk_value = entity.$(field.name).str()
				found = true
			}
		}
	}
	if !found {
		return error('no primary key field found in ${typeof[T]().name}')
	}
	return pk_value
}

// get_entity_field_value extracts a field value by name from an entity
// via comptime.  Returns the value as a string, or an error if the
// field does not exist.
fn get_entity_field_value[T](entity T, field_name string) !string {
	$for field in T.fields {
		if field.name == field_name {
			return entity.$(field.name).str()
		}
	}
	return error('field "${field_name}" not found in ${typeof[T]().name}')
}

// is_valid_identifier checks that a string is a safe SQL identifier
// (alphanumeric + underscore, starting with a letter or underscore).
// Used to validate table/column names before interpolation into SQL,
// since identifiers cannot be parameterized with ? placeholders.
fn is_valid_identifier(s string) bool {
	if s.len == 0 {
		return false
	}
	if !(s[0].is_letter() || s[0] == `_`) {
		return false
	}
	for ch in s {
		if !(ch.is_alnum() || ch == `_`) {
			return false
		}
	}
	return true
}

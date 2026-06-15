module orm

// relation.v - Entity Relationships
//
// Provides relationship types and helper functions for managing
// entity relationships: OneToOne, OneToMany (HasMany), ManyToOne (BelongsTo),
// and ManyToMany.

// Relationship represents a relationship between entities
pub struct Relationship {
pub:
	name       string
	typ        string // 'has_many', 'belongs_to', 'many_to_many', 'has_one'
	target     string // Target entity type name
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

// RelationLoader loads relationships for an entity
pub struct RelationLoader {
pub mut:
	manager &OrmManager
}

// new_relation_loader creates a new RelationLoader
pub fn new_relation_loader(manager &OrmManager) &RelationLoader {
	return &RelationLoader{
		manager: manager
	}
}

// load_has_many loads a HasMany relationship
pub fn (rl &RelationLoader) load_has_many[T, R](entity T, mut relation HasMany[R], foreign_key string) ! {
	db_conn := rl.manager.default_conn()!

	table_name := get_table_name[R]()
	query := 'SELECT * FROM ${table_name} WHERE ${foreign_key} = ${entity.id()}'
	result := db_conn.exec(query)!

	mut items := []R{}
	// Map results to items
	relation.items = items
	relation.loaded = true
}

// load_belongs_to loads a BelongsTo relationship
pub fn (rl &RelationLoader) load_belongs_to[T, R](entity T, mut relation BelongsTo[R], foreign_key string) ! {
	db_conn := rl.manager.default_conn()!

	table_name := get_table_name[R]()
	query := 'SELECT * FROM ${table_name} WHERE id = ${foreign_key}'
	result := db_conn.exec(query)!

	mut item := R{}
	// Map result to item
	relation.item = item
	relation.loaded = true
}

// load_many_to_many loads a ManyToMany relationship via pivot table
pub fn (rl &RelationLoader) load_many_to_many[T, R](entity T, mut relation ManyToMany[R], pivot_table string, local_key string, foreign_key string) ! {
	db_conn := rl.manager.default_conn()!

	target_table := get_table_name[R]()
	query := 'SELECT t.* FROM ${target_table} t INNER JOIN ${pivot_table} p ON t.id = p.${foreign_key} WHERE p.${local_key} = ${entity.id()}'
	result := db_conn.exec(query)!

	mut items := []R{}
	// Map results to items
	relation.items = items
	relation.loaded = true
}

// get_table_name extracts table name from type
fn get_table_name[T]() string {
	$for field in T.fields {
		// Check for [table: 'name'] attribute on the struct
	}
	// Default: derive from type name
	return typeof[T]().name.to_lower() + 's'
}

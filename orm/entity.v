module orm

// entity.v - Entity Base & Lifecycle Hooks
//
// Provides base entity traits with lifecycle hooks similar to JPA/Hibernate.
// Entities can implement hooks: BeforeCreate, AfterCreate, BeforeUpdate,
// AfterUpdate, BeforeDelete, AfterDelete, AfterFind.
import support
import time

// Touchable is implemented by BaseEntity (and any struct embedding it).
// Used by the adapter to auto-call touch() before insert/update.
pub interface Touchable {
mut:
	touch()
}

// Identifiable provides primary-key access for entities.
// BaseEntity (and any struct embedding it) satisfies this.
// Used by the adapter's wrap_save() to detect new vs existing entities.
pub interface Identifiable {
	id() int
	is_new() bool
}

// Entity extends Identifiable with table-name awareness.
// All ORM entities should implement this.
pub interface Entity {
	Identifiable
	table_name() string
}

// BeforeCreateHook is called before inserting a new record
pub interface BeforeCreateHook {
	before_create()
}

// AfterCreateHook is called after inserting a new record
pub interface AfterCreateHook {
	after_create()
}

// BeforeUpdateHook is called before updating a record
pub interface BeforeUpdateHook {
	before_update()
}

// AfterUpdateHook is called after updating a record
pub interface AfterUpdateHook {
	after_update()
}

// BeforeDeleteHook is called before deleting a record
pub interface BeforeDeleteHook {
	before_delete()
}

// AfterDeleteHook is called after deleting a record
pub interface AfterDeleteHook {
	after_delete()
}

// AfterFindHook is called after loading a record from the database
pub interface AfterFindHook {
	after_find()
}

// BaseEntity provides common fields for all entities
pub struct BaseEntity {
pub mut:
	id         int @[primary_key; sql: 'id'; sql_type: 'INTEGER']
	created_at i64 @[sql: 'created_at'; sql_type: 'INTEGER']
	updated_at i64 @[sql: 'updated_at'; sql_type: 'INTEGER']
	version    int @[sql: 'version'; sql_type: 'INTEGER']
}

// id returns the entity ID
pub fn (e &BaseEntity) id() int {
	return e.id
}

// touch updates the timestamps
pub fn (mut e BaseEntity) touch() {
	now := time.now().unix()
	if e.created_at == 0 {
		e.created_at = now
	}
	e.updated_at = now
	e.version++
}

// is_new returns whether this entity has been persisted
pub fn (e &BaseEntity) is_new() bool {
	return e.id == 0
}

// SoftDeletableEntity adds soft delete support
pub struct SoftDeletableEntity {
	BaseEntity
pub mut:
	deleted_at i64 @[sql: 'deleted_at'; sql_type: 'INTEGER']
}

// is_deleted returns whether this entity has been soft-deleted
pub fn (e &SoftDeletableEntity) is_deleted() bool {
	return e.deleted_at > 0
}

// soft_delete marks the entity as deleted
pub fn (mut e SoftDeletableEntity) soft_delete() {
	e.deleted_at = time.now().unix()
}

// restore unmarks the entity as deleted
pub fn (mut e SoftDeletableEntity) restore() {
	e.deleted_at = 0
}

// ═══════════════════════════════════════════════════════════════════
// JPA Entity Annotation Reading (Task B7)
// ═══════════════════════════════════════════════════════════════════
//
// Spring Data JPA-inspired entity annotations, read entirely at
// compile time via V's comptime facilities (zero runtime reflection):
//
//   @[entity]              — marks a struct as a JPA entity (marker)
//   @[table('name')]       — custom DB table name
//                            (default: snake_case(T.name) + 's')
//   @[id]                  — marks a field as the primary key
//   @[primary_key]         — alias for @[id] (backward compat)
//   @[column('name')]      — custom DB column name
//                            (default: snake_case(field.name))
//
// Defaults are backward compatible: plain structs without annotations
// behave exactly as before (snake_case column names, 'id' field PK
// fallback in JpaRepository).
//
// V 0.5.1 comptime notes:
//   - Struct-level attributes use `$for attr in T.attributes`, where
//     `attr` is a `builtin.VAttribute` with `.name`, `.has_arg`, `.arg`.
//   - Field-level attributes use `field.attrs` ([]string). Both
//     `@[column('x')]` and `@[column: 'x']` normalize to the string
//     `column: 'x'` in `field.attrs`.

// ColumnMetadata describes a single entity field's DB mapping.
pub struct ColumnMetadata {
pub:
	field_name  string // V struct field name
	column_name string // DB column name
	is_primary  bool   // true if @[id] or @[primary_key]
	typ         string // V type name (string/int/i64/f64/bool/…)
}

// EntityMetadata holds the comptime-extracted JPA mapping info for type T.
pub struct EntityMetadata {
pub:
	table_name           string           // resolved DB table name
	has_table_annotation bool             // true if @[table('…')] was present
	columns              []ColumnMetadata // field-order column descriptors
	primary_key          ColumnMetadata   // the @[id]/@[primary_key] column (empty if none)
	has_primary_key      bool             // true if @[id]/@[primary_key] found
}

// extract_entity_metadata scans type T at compile time and returns its
// JPA mapping metadata.  Pure comptime — zero runtime reflection cost.
//
// Example:
//   meta := orm.extract_entity_metadata[User]()
//   println(meta.table_name)              // 'users' (default) or @[table] value
//   println(meta.primary_key.column_name) // 'id'
//   println(meta.columns.len)             // number of mapped fields
pub fn extract_entity_metadata[T]() EntityMetadata {
	mut columns := []ColumnMetadata{}
	mut pk := ColumnMetadata{}
	mut has_pk := false

	// Resolve table name from @[table('name')] struct attribute
	mut tbl_name := ''
	mut has_table := false
	$for attr in T.attributes {
		if attr.name == 'table' && attr.has_arg {
			tbl_name = strip_attr_quotes(attr.arg)
			has_table = true
		}
	}
	if !has_table {
		tbl_name = default_table_name[T]()
	}

	// Scan fields for column names and primary key
	$for field in T.fields {
		col_name := extract_column_name(field.name, field.attrs)
		is_pk := is_primary_key_field(field.attrs)

		mut type_name := 'unknown'
		$if field.typ is string {
			type_name = 'string'
		} $else $if field.typ is int {
			type_name = 'int'
		} $else $if field.typ is i64 {
			type_name = 'i64'
		} $else $if field.typ is f64 {
			type_name = 'f64'
		} $else $if field.typ is bool {
			type_name = 'bool'
		}

		col := ColumnMetadata{
			field_name:  field.name
			column_name: col_name
			is_primary:  is_pk
			typ:         type_name
		}
		columns << col

		if is_pk && !has_pk {
			pk = col
			has_pk = true
		}
	}
	return EntityMetadata{
		table_name:           tbl_name
		has_table_annotation: has_table
		columns:              columns
		primary_key:          pk
		has_primary_key:      has_pk
	}
}

// is_entity returns true if type T carries the @[entity] attribute.
// Pure comptime check — useful for validating that a type is a JPA entity.
pub fn is_entity[T]() bool {
	mut found := false
	$for attr in T.attributes {
		if attr.name == 'entity' {
			found = true
		}
	}
	return found
}

// extract_column_name resolves the DB column name for a field, honoring
// @[column('name')] / @[column: 'name'].  Falls back to snake_case(field_name)
// when no @[column] attribute is present (backward compatible).
//
// Both attribute forms normalize to the string `column: 'value'` in V's
// comptime `field.attrs` list; the paren form is handled defensively too.
pub fn extract_column_name(field_name string, attrs []string) string {
	for attr in attrs {
		if attr.starts_with('column:') {
			rest := attr['column:'.len..].trim_space()
			return strip_attr_quotes(rest)
		}
		if attr.starts_with('column(') {
			mut rest := attr['column('.len..]
			if rest.ends_with(')') {
				rest = rest[..rest.len - 1]
			}
			return strip_attr_quotes(rest.trim_space())
		}
	}
	return support.snake(field_name)
}

// is_primary_key_field returns true if the field carries @[id] or
// @[primary_key].  It does NOT include the 'id'-name fallback — that
// remains a repository-level concern (so EntityMetadata.has_primary_key
// reflects only explicit annotations).
pub fn is_primary_key_field(attrs []string) bool {
	for attr in attrs {
		if attr == 'id' || attr == 'primary_key' {
			return true
		}
	}
	return false
}

// strip_attr_quotes removes surrounding single or double quotes from a
// string, normalizing attribute arguments like `'t_user'` → `t_user`.
fn strip_attr_quotes(s string) string {
	mut val := s.trim_space()
	if val.len >= 2 {
		if (val[0] == `'` && val[val.len - 1] == `'`) || (val[0] == `"` && val[val.len - 1] == `"`) {
			return val[1..val.len - 1]
		}
	}
	return val
}

// default_table_name derives the default table name from type T:
// snake_case(short_type_name) + 's'.  e.g. 'orm.User' → 'users'.
fn default_table_name[T]() string {
	full_name := typeof[T]().name
	short_name := if idx := full_name.last_index('.') {
		full_name[idx + 1..]
	} else {
		full_name
	}
	return support.snake(short_name) + 's'
}

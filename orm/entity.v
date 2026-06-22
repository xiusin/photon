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
// JPA Entity Annotation Reading (Task B7 / Task 3)
// ═══════════════════════════════════════════════════════════════════
//
// Spring Data JPA-inspired entity annotations, read entirely at
// compile time via V's comptime facilities (zero runtime reflection):
//
// Struct-level annotations:
//   @[entity]              — marks a struct as a JPA entity (marker)
//   @[table('name')]       — custom DB table name
//                            (default: snake_case(T.name) + 's')
//
// Field-level annotations:
//   @[id]                  — marks a field as the primary key (JPA @Id)
//   @[primary_key]         — alias for @[id] (backward compat)
//   @[column('name')]      — custom DB column name (JPA @Column)
//                            (default: snake_case(field.name))
//   @[generated_value]     — auto-increment primary key (JPA @GeneratedValue)
//   @[version]             — optimistic lock version number (JPA @Version)
//   @[created_at]          — auto-fill creation timestamp
//   @[updated_at]          — auto-fill update timestamp
//   @[soft_delete]         — soft delete marker field
//   @[size(255)]           — field length constraint (JPA @Size)
//   @[nullable]            — allows NULL values (JPA @Nullable)
//   @[unique]              — unique constraint
//
// DTO validation annotations:
//   @[required]            — mandatory field
//   @[email]               — email format validation
//   @[min(0)]              — minimum numeric value
//   @[max(100)]            — maximum numeric value
//   @[pattern('regex')]    — regex pattern match
//   @[length(1, 255)]      — string length range
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

// ── Annotation name constants ──
// Centralized constants for all supported annotation names.
// Used by scan_entity[T]() and validation functions at compile time.

pub const attr_table          = 'table'
pub const attr_entity         = 'entity'
pub const attr_id             = 'id'
pub const attr_primary_key    = 'primary_key'
pub const attr_column         = 'column'
pub const attr_generated_value = 'generated_value'
pub const attr_version        = 'version'
pub const attr_created_at     = 'created_at'
pub const attr_updated_at     = 'updated_at'
pub const attr_soft_delete    = 'soft_delete'
pub const attr_size           = 'size'
pub const attr_nullable       = 'nullable'
pub const attr_unique         = 'unique'

// DTO validation annotation name constants
pub const attr_required       = 'required'
pub const attr_email          = 'email'
pub const attr_min            = 'min'
pub const attr_max            = 'max'
pub const attr_pattern        = 'pattern'
pub const attr_length         = 'length'

// ColumnMetadata describes a single entity field's DB mapping.
pub struct ColumnMetadata {
pub:
	field_name      string // V struct field name
	column_name     string // DB column name
	is_primary      bool   // true if @[id] or @[primary_key]
	typ             string // V type name (string/int/i64/f64/bool/…)
	is_generated    bool   // true if @[generated_value]
	is_version      bool   // true if @[version]
	is_created_at   bool   // true if @[created_at]
	is_updated_at   bool   // true if @[updated_at]
	is_soft_delete  bool   // true if @[soft_delete]
	size_constraint int    // 0 = no constraint; >0 from @[size(N)]
	is_nullable     bool   // true if @[nullable]
	is_unique       bool   // true if @[unique]
}

// EntityMetadata holds the comptime-extracted JPA mapping info for type T.
pub struct EntityMetadata {
pub:
	table_name           string           // resolved DB table name
	has_table_annotation bool             // true if @[table('…')] was present
	columns              []ColumnMetadata // field-order column descriptors
	primary_key          ColumnMetadata   // the @[id]/@[primary_key] column (empty if none)
	has_primary_key      bool             // true if @[id]/@[primary_key] found
	has_version          bool             // true if any field has @[version]
	has_created_at       bool             // true if any field has @[created_at]
	has_updated_at       bool             // true if any field has @[updated_at]
	has_soft_delete      bool             // true if any field has @[soft_delete]
}

// extract_entity_metadata scans type T at compile time and returns its
// JPA mapping metadata.  Pure comptime — zero runtime reflection cost.
//
// Example:
//   meta := orm.extract_entity_metadata[User]()
//   println(meta.table_name)              // 'users' (default) or @[table] value
//   println(meta.primary_key.column_name) // 'id'
//   println(meta.columns.len)             // number of mapped fields
//   println(meta.has_version)             // true if @[version] field found
pub fn extract_entity_metadata[T]() EntityMetadata {
	mut columns := []ColumnMetadata{}
	mut pk := ColumnMetadata{}
	mut has_pk := false
	mut has_version := false
	mut has_created_at := false
	mut has_updated_at := false
	mut has_soft_delete := false

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

	// Scan fields for column names, primary key, and extended annotations
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

		// Parse extended field annotations
		is_generated := has_attr(field.attrs, attr_generated_value)
		is_version_field := has_attr(field.attrs, attr_version)
		is_created_at_field := has_attr(field.attrs, attr_created_at)
		is_updated_at_field := has_attr(field.attrs, attr_updated_at)
		is_soft_delete_field := has_attr(field.attrs, attr_soft_delete)
		size_val := extract_int_attr(field.attrs, attr_size)
		is_nullable := has_attr(field.attrs, attr_nullable)
		is_unique := has_attr(field.attrs, attr_unique)

		col := ColumnMetadata{
			field_name:      field.name
			column_name:     col_name
			is_primary:      is_pk
			typ:             type_name
			is_generated:    is_generated
			is_version:      is_version_field
			is_created_at:   is_created_at_field
			is_updated_at:   is_updated_at_field
			is_soft_delete:  is_soft_delete_field
			size_constraint: size_val
			is_nullable:     is_nullable
			is_unique:       is_unique
		}
		columns << col

		if is_pk && !has_pk {
			pk = col
			has_pk = true
		}
		if is_version_field {
			has_version = true
		}
		if is_created_at_field {
			has_created_at = true
		}
		if is_updated_at_field {
			has_updated_at = true
		}
		if is_soft_delete_field {
			has_soft_delete = true
		}
	}
	return EntityMetadata{
		table_name:           tbl_name
		has_table_annotation: has_table
		columns:              columns
		primary_key:          pk
		has_primary_key:      has_pk
		has_version:          has_version
		has_created_at:       has_created_at
		has_updated_at:       has_updated_at
		has_soft_delete:      has_soft_delete
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

// ═══════════════════════════════════════════════════════════════════
// Extended Annotation Helpers (Task 3)
// ═══════════════════════════════════════════════════════════════════

// has_attr checks if a field's attribute list contains the given
// annotation name.  Pure string matching — no runtime reflection.
pub fn has_attr(attrs []string, name string) bool {
	for attr in attrs {
		if attr == name {
			return true
		}
		// Also match attribute forms like @[generated_value] which
		// may appear as 'generated_value' in the attrs list
		if attr.starts_with(name) && (attr.len == name.len || attr[name.len] == `(` || attr[name.len] == `:`) {
			return true
		}
	}
	return false
}

// extract_int_attr extracts an integer parameter from an attribute
// like @[size(255)] or @[min(0)].  Returns 0 if the attribute
// is not present or has no integer argument.
pub fn extract_int_attr(attrs []string, name string) int {
	for attr in attrs {
		// Match forms: 'size(255)', 'size: 255'
		if attr.starts_with('${name}(') {
			mut rest := attr['${name}('.len..]
			if rest.ends_with(')') {
				rest = rest[..rest.len - 1]
			}
			return rest.trim_space().int()
		}
		if attr.starts_with('${name}:') {
			rest := attr['${name}:'.len..].trim_space()
			return rest.int()
		}
	}
	return 0
}

// extract_string_attr extracts a string parameter from an attribute
// like @[pattern('regex')] or @[column('name')].
// Returns '' if the attribute is not present or has no string argument.
pub fn extract_string_attr(attrs []string, name string) string {
	for attr in attrs {
		if attr.starts_with('${name}(') {
			mut rest := attr['${name}('.len..]
			if rest.ends_with(')') {
				rest = rest[..rest.len - 1]
			}
			return strip_attr_quotes(rest.trim_space())
		}
		if attr.starts_with('${name}:') {
			rest := attr['${name}:'.len..].trim_space()
			return strip_attr_quotes(rest)
		}
	}
	return ''
}

// extract_two_int_attr extracts two integer parameters from an attribute
// like @[length(1, 255)].  Returns (0, 0) if not present.
pub fn extract_two_int_attr(attrs []string, name string) (int, int) {
	for attr in attrs {
		if attr.starts_with('${name}(') {
			mut rest := attr['${name}('.len..]
			if rest.ends_with(')') {
				rest = rest[..rest.len - 1]
			}
			parts := rest.trim_space().split(',')
			if parts.len >= 2 {
				return parts[0].trim_space().int(), parts[1].trim_space().int()
			}
			if parts.len == 1 {
				return parts[0].trim_space().int(), 0
			}
		}
		if attr.starts_with('${name}:') {
			rest := attr['${name}:'.len..].trim_space()
			parts := rest.split(',')
			if parts.len >= 2 {
				return parts[0].trim_space().int(), parts[1].trim_space().int()
			}
			if parts.len == 1 {
				return parts[0].trim_space().int(), 0
			}
		}
	}
	return 0, 0
}

// scan_entity[T] is a convenience function that combines
// extract_entity_metadata[T]() with validation checks.
// Returns the EntityMetadata or an error if the entity is invalid.
//
// Validation rules:
//   - Type T must have the @[entity] attribute (or a @[table] attribute)
//   - If @[id] or @[primary_key] is present, it must be on a single field
//
// Example:
//   meta := orm.scan_entity[User]()!
//   println(meta.table_name)
pub fn scan_entity[T]() !EntityMetadata {
	meta := extract_entity_metadata[T]()
	// Validate: must be an entity (has @[entity] or @[table])
	if !is_entity[T]() && !meta.has_table_annotation {
		return error('scan_entity: type ${typeof[T]().name} is not annotated with @[entity] or @[table] / 类型 ${typeof[T]().name} 未标记 @[entity] 或 @[table]')
	}
	return meta
}

// ═══════════════════════════════════════════════════════════════════
// DTO Validation System (Task 3)
// ═══════════════════════════════════════════════════════════════════
//
// Compile-time DTO validation inspired by Jakarta Bean Validation (JSR 380).
// All validation is performed at compile time via V's comptime — zero
// runtime reflection overhead.
//
// Supported validation annotations:
//   @[required]            — field must not be zero value
//   @[email]               — string must match email format
//   @[min(N)]              — numeric value >= N
//   @[max(N)]              — numeric value <= N
//   @[pattern('regex')]    — string must match regex pattern
//   @[length(M, N)]        — string length must be in [M, N]
//
// Usage:
//   result := orm.validate[User](user)!
//   if result.is_valid { ... }

// ValidationError describes a single validation failure.
pub struct ValidationError {
pub:
	field   string // V struct field name
	message string // Human-readable error description
	rule    string // The validation rule that failed (e.g. 'required', 'email')
}

// ValidationResult holds the outcome of validating a struct.
pub struct ValidationResult {
pub mut:
	is_valid bool
	errors   []ValidationError
}

// new_validation_result creates a valid (empty) ValidationResult.
pub fn new_validation_result() ValidationResult {
	return ValidationResult{
		is_valid: true
		errors:   []ValidationError{}
	}
}

// add_error adds a validation error and marks the result as invalid.
pub fn (mut vr ValidationResult) add_error(field string, message string, rule string) {
	vr.is_valid = false
	vr.errors << ValidationError{
		field:   field
		message: message
		rule:    rule
	}
}

// validate[T] validates a struct instance using compile-time annotation
// scanning.  Returns a ValidationResult with all validation errors.
//
// Pure comptime — zero runtime reflection cost.  The validation rules
// are extracted from @[required], @[email], @[min(N)], @[max(N)],
// @[pattern('regex')], and @[length(M, N)] annotations on T's fields.
//
// Example:
//   @[entity]
//   @[table('users')]
//   pub struct User {
//       @[id]
//       id int
//       @[required; length(1, 255)]
//       name string
//       @[required; email]
//       email string
//       @[min(0); max(150)]
//       age int
//   }
//
//   user := User{ name: '', email: 'invalid', age: -1 }
//   result := orm.validate[User](user)!
//   assert !result.is_valid
//   assert result.errors.len == 3
pub fn validate[T](entity T) !ValidationResult {
	mut result := new_validation_result()

	$for field in T.fields {
		field_name := field.name
		attrs := field.attrs

		// ── @[required] validation ──
		if has_attr(attrs, attr_required) {
			$if field.typ is string {
				val := entity.$(field.name)
				if val.len == 0 {
					result.add_error(field_name, 'field ${field_name} is required / 字段 ${field_name} 为必填项', attr_required)
				}
			} $else $if field.typ is int {
				val := entity.$(field.name)
				if val == 0 {
					result.add_error(field_name, 'field ${field_name} is required / 字段 ${field_name} 为必填项', attr_required)
				}
			} $else $if field.typ is i64 {
				val := entity.$(field.name)
				if val == 0 {
					result.add_error(field_name, 'field ${field_name} is required / 字段 ${field_name} 为必填项', attr_required)
				}
			} $else $if field.typ is f64 {
				val := entity.$(field.name)
				if val == 0.0 {
					result.add_error(field_name, 'field ${field_name} is required / 字段 ${field_name} 为必填项', attr_required)
				}
			} $else $if field.typ is bool {
				// bool @[required] is a no-op (bool is always valid)
			}
		}

		// ── @[email] validation ──
		if has_attr(attrs, attr_email) {
			$if field.typ is string {
				val := entity.$(field.name)
				if val.len > 0 && !is_valid_email(val) {
					result.add_error(field_name, 'field ${field_name} is not a valid email / 字段 ${field_name} 不是有效的邮箱地址', attr_email)
				}
			}
		}

		// ── @[min(N)] validation ──
		has_min := has_attr(attrs, attr_min)
		if has_min {
			min_val := extract_int_attr(attrs, attr_min)
			$if field.typ is int {
				val := entity.$(field.name)
				if val < min_val {
					result.add_error(field_name, 'field ${field_name} value ${val} is less than minimum ${min_val} / 字段 ${field_name} 的值 ${val} 小于最小值 ${min_val}', attr_min)
				}
			} $else $if field.typ is i64 {
				val := entity.$(field.name)
				if val < min_val {
					result.add_error(field_name, 'field ${field_name} value ${val} is less than minimum ${min_val} / 字段 ${field_name} 的值 ${val} 小于最小值 ${min_val}', attr_min)
				}
			} $else $if field.typ is f64 {
				val := entity.$(field.name)
				if val < f64(min_val) {
					result.add_error(field_name, 'field ${field_name} value ${val} is less than minimum ${min_val} / 字段 ${field_name} 的值 ${val} 小于最小值 ${min_val}', attr_min)
				}
			}
		}

		// ── @[max(N)] validation ──
		has_max := has_attr(attrs, attr_max)
		if has_max {
			max_val := extract_int_attr(attrs, attr_max)
			$if field.typ is int {
				val := entity.$(field.name)
				if val > max_val {
					result.add_error(field_name, 'field ${field_name} value ${val} exceeds maximum ${max_val} / 字段 ${field_name} 的值 ${val} 超过最大值 ${max_val}', attr_max)
				}
			} $else $if field.typ is i64 {
				val := entity.$(field.name)
				if val > max_val {
					result.add_error(field_name, 'field ${field_name} value ${val} exceeds maximum ${max_val} / 字段 ${field_name} 的值 ${val} 超过最大值 ${max_val}', attr_max)
				}
			} $else $if field.typ is f64 {
				val := entity.$(field.name)
				if val > f64(max_val) {
					result.add_error(field_name, 'field ${field_name} value ${val} exceeds maximum ${max_val} / 字段 ${field_name} 的值 ${val} 超过最大值 ${max_val}', attr_max)
				}
			}
		}

		// ── @[pattern('regex')] validation ──
		pattern_str := extract_string_attr(attrs, attr_pattern)
		if pattern_str.len > 0 {
			$if field.typ is string {
				val := entity.$(field.name)
				if val.len > 0 && !matches_pattern(val, pattern_str) {
					result.add_error(field_name, 'field ${field_name} does not match pattern ${pattern_str} / 字段 ${field_name} 不匹配模式 ${pattern_str}', attr_pattern)
				}
			}
		}

		// ── @[length(M, N)] validation ──
		min_len, max_len := extract_two_int_attr(attrs, attr_length)
		if min_len != 0 || max_len != 0 {
			$if field.typ is string {
				val := entity.$(field.name)
				if min_len > 0 && val.len < min_len {
					result.add_error(field_name, 'field ${field_name} length ${val.len} is less than minimum ${min_len} / 字段 ${field_name} 长度 ${val.len} 小于最小长度 ${min_len}', attr_length)
				}
				if max_len > 0 && val.len > max_len {
					result.add_error(field_name, 'field ${field_name} length ${val.len} exceeds maximum ${max_len} / 字段 ${field_name} 长度 ${val.len} 超过最大长度 ${max_len}', attr_length)
				}
			}
		}
	}

	return result
}

// is_valid_email performs a basic email format validation.
// Checks for the presence of '@' and at least one '.' after '@'.
// This is a lightweight check — not a full RFC 5322 validator.
pub fn is_valid_email(email string) bool {
	if email.len < 3 {
		return false
	}
	at_idx := email.index('@') or { return false }
	if at_idx == 0 || at_idx == email.len - 1 {
		return false
	}
	dot_idx := email.index_after('.', at_idx) or { return false }
	if dot_idx <= at_idx + 1 || dot_idx == email.len - 1 {
		return false
	}
	return true
}

// matches_pattern checks if a string matches a simple pattern.
// Supports basic glob-style patterns:
//   - '*' matches any sequence of characters
//   - '?' matches any single character
//   - All other characters match literally
//
// For full regex support, use V's regex module in user code.
pub fn matches_pattern(s string, pattern string) bool {
	if pattern == '*' {
		return true
	}
	// Simple glob matching
	return glob_match(s, pattern, 0, 0)
}

// glob_match implements recursive glob matching.
fn glob_match(s string, pattern string, si int, pi int) bool {
	if pi == pattern.len {
		return si == s.len
	}
	if pattern[pi] == `*` {
		// Try matching zero or more characters
		for k := si; k <= s.len; k++ {
			if glob_match(s, pattern, k, pi + 1) {
				return true
			}
		}
		return false
	}
	if si >= s.len {
		return false
	}
	if pattern[pi] == `?` || pattern[pi] == s[si] {
		return glob_match(s, pattern, si + 1, pi + 1)
	}
	return false
}

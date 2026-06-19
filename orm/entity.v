module orm

// entity.v - Entity Base & Lifecycle Hooks
//
// Provides base entity traits with lifecycle hooks similar to JPA/Hibernate.
// Entities can implement hooks: BeforeCreate, AfterCreate, BeforeUpdate,
// AfterUpdate, BeforeDelete, AfterDelete, AfterFind.
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

module orm

// entity_test.v - Tests for BaseEntity, SoftDeletableEntity, and lifecycle hooks

import time

// --- BaseEntity Tests ---

struct TestEntity {
	BaseEntity
}

fn test_base_entity_id_default() {
	e := BaseEntity{}
	assert e.id() == 0
	assert e.is_new() == true
}

fn test_base_entity_is_new_with_id() {
	mut e := BaseEntity{
		id: 42
	}
	assert e.id() == 42
	assert e.is_new() == false
}

fn test_base_entity_touch_sets_timestamps() {
	mut e := BaseEntity{}
	assert e.created_at == 0
	assert e.updated_at == 0
	assert e.version == 0

	e.touch()

	assert e.created_at > 0
	assert e.updated_at > 0
	assert e.version == 1
}

fn test_base_entity_touch_preserves_created_at() {
	now := time.now().unix()
	mut e := BaseEntity{
		created_at: now
	}
	e.touch()

	assert e.created_at == now
	assert e.updated_at >= now
	assert e.version == 1
}

fn test_base_entity_touch_increments_version() {
	mut e := BaseEntity{}
	e.touch()
	assert e.version == 1
	e.touch()
	assert e.version == 2
	e.touch()
	assert e.version == 3
}

fn test_base_entity_struct_fields() {
	mut e := BaseEntity{
		id: 1
		created_at: 100
		updated_at: 200
		version: 5
	}
	assert e.id == 1
	assert e.created_at == 100
	assert e.updated_at == 200
	assert e.version == 5
	assert e.is_new() == false
}

fn test_test_entity_embeds_base_entity() {
	mut te := TestEntity{
		BaseEntity{
			id: 99
		}
	}
	assert te.id() == 99
	assert te.is_new() == false
}

// --- SoftDeletableEntity Tests ---

fn test_soft_deletable_default_not_deleted() {
	e := SoftDeletableEntity{}
	assert e.is_deleted() == false
	assert e.deleted_at == 0
}

fn test_soft_deletable_soft_delete() {
	mut e := SoftDeletableEntity{}
	e.soft_delete()
	assert e.is_deleted() == true
	assert e.deleted_at > 0
}

fn test_soft_deletable_restore() {
	mut e := SoftDeletableEntity{}
	e.soft_delete()
	assert e.is_deleted() == true
	e.restore()
	assert e.is_deleted() == false
	assert e.deleted_at == 0
}

fn test_soft_deletable_multiple_cycles() {
	mut e := SoftDeletableEntity{}

	e.soft_delete()
	assert e.is_deleted() == true
	e.restore()
	assert e.is_deleted() == false

	e.soft_delete()
	assert e.is_deleted() == true
	e.restore()
	assert e.is_deleted() == false
}

fn test_soft_deletable_inherits_base_entity() {
	mut e := SoftDeletableEntity{}
	assert e.id() == 0
	assert e.is_new() == true
	assert e.version == 0

	e.touch()
	assert e.version == 1
	assert e.created_at > 0
}

// --- is_new edge cases ---

fn test_base_entity_is_new_negative_id() {
	e := BaseEntity{
		id: -1
	}
	// id != 0 so not new
	assert e.is_new() == false
	assert e.id() == -1
}

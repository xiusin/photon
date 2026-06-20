module migrations

// 20260101000005_create_tags_table.v — 标签表迁移
//
// 创建 tags 表，包含名称、slug 字段。slug 唯一索引。

import photon.orm as phorm
import db.sqlite
import database

pub struct CreateTagsTable {}

fn (m CreateTagsTable) version() int {
	return 5
}

fn (m CreateTagsTable) name() string {
	return 'create_tags_table'
}

fn (m CreateTagsTable) up(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	mut schema := phorm.new_schema(.sqlite)
	schema.create_table('tags', fn (mut t phorm.TableDef) {
		t.id()
		t.string_('name', 255)
		t.not_null()
		t.string_('slug', 255)
		t.not_null()
		t.integer('created_at')
		t.integer('updated_at')
		t.integer('version')
		t.unique_(['slug'], 'idx_tags_slug')
		t.index_(['name'], 'idx_tags_name')
	})
	database.execute_schema(db, schema)!
}

fn (m CreateTagsTable) down(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS tags')!
}

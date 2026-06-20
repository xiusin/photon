module migrations

// 20260101000004_create_categories_table.v — 分类表迁移
//
// 创建 categories 表，包含名称、slug、描述字段。slug 唯一索引。

import photon.orm as phorm
import db.sqlite
import database

pub struct CreateCategoriesTable {}

fn (m CreateCategoriesTable) version() int {
	return 4
}

fn (m CreateCategoriesTable) name() string {
	return 'create_categories_table'
}

fn (m CreateCategoriesTable) up(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	mut schema := phorm.new_schema(.sqlite)
	schema.create_table('categories', fn (mut t phorm.TableDef) {
		t.id()
		t.string_('name', 255)
		t.not_null()
		t.string_('slug', 255)
		t.not_null()
		t.string_('description', 512)
		t.integer('created_at')
		t.integer('updated_at')
		t.integer('version')
		t.unique_(['slug'], 'idx_categories_slug')
		t.index_(['name'], 'idx_categories_name')
	})
	database.execute_schema(db, schema)!
}

fn (m CreateCategoriesTable) down(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS categories')!
}

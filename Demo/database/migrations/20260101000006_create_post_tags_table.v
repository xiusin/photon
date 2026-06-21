module migrations

// 20260101000006_create_post_tags_table.v — 文章-标签关联表迁移
//
// 创建 post_tags 关联表，实现文章与标签的多对多关系。
// (post_id, tag_id) 联合唯一索引防止重复关联。

import photon.orm as phorm
import database

pub struct CreatePostTagsTable {}

fn (m CreatePostTagsTable) version() int {
	return 6
}

fn (m CreatePostTagsTable) name() string {
	return 'create_post_tags_table'
}

fn (m CreatePostTagsTable) up(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	mut schema := phorm.new_schema(.sqlite)
	schema.create_table('post_tags', fn (mut t phorm.TableDef) {
		t.id()
		t.integer('post_id')
		t.not_null()
		t.integer('tag_id')
		t.not_null()
		t.integer('created_at')
		t.integer('updated_at')
		t.integer('version')
		t.unique_(['post_id', 'tag_id'], 'idx_post_tags_unique')
		t.index_(['post_id'], 'idx_post_tags_post')
		t.index_(['tag_id'], 'idx_post_tags_tag')
	})
	database.execute_schema(db, schema)!
}

fn (m CreatePostTagsTable) down(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS post_tags')!
}

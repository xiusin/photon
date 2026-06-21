module migrations

// 20260101000002_create_posts_table.v — 文章表迁移
//
// 创建 posts 表，包含标题、内容、摘要、作者、分类、状态、浏览数等字段。
// 添加 deleted_at 列以支持框架级软删除（当前实现使用 status='archived' 状态删除）。

import photon.orm as phorm
import database

struct CreatePostsTable {}

pub fn (m CreatePostsTable) version() int {
	return 2
}

pub fn (m CreatePostsTable) name() string {
	return 'create_posts_table'
}

pub fn (m CreatePostsTable) up(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	mut schema := phorm.new_schema(.sqlite)
	schema.create_table('posts', fn (mut t phorm.TableDef) {
		t.id()
		t.string_('title', 255)
		t.not_null()
		t.text('content')
		t.not_null()
		t.string_('summary', 512)
		t.integer('author_id')
		t.not_null()
		t.integer('category_id')
		t.string_('status', 20)
		t.default_('draft')
		t.integer('views')
		t.default_('0')
		t.integer('deleted_at') // 软删除时间戳（0 = 未删除）
		t.default_('0')
		t.integer('created_at')
		t.integer('updated_at')
		t.integer('version')
		t.index_(['author_id'], 'idx_posts_author')
		t.index_(['category_id'], 'idx_posts_category')
		t.index_(['status'], 'idx_posts_status')
		t.index_(['created_at'], 'idx_posts_created_at')
	})
	database.execute_schema(db, schema)!
}

pub fn (m CreatePostsTable) down(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS posts')!
}

module migrations

// 20260101000003_create_comments_table.v — 评论表迁移
//
// 创建 comments 表，支持嵌套评论（parent_id 自引用）。
// 添加 deleted_at 列以支持框架级软删除（当前实现使用 status='deleted' 状态删除）。

import photon.orm as phorm
import db.sqlite
import database

pub struct CreateCommentsTable {}

fn (m CreateCommentsTable) version() int {
	return 3
}

fn (m CreateCommentsTable) name() string {
	return 'create_comments_table'
}

fn (m CreateCommentsTable) up(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	mut schema := phorm.new_schema(.sqlite)
	schema.create_table('comments', fn (mut t phorm.TableDef) {
		t.id()
		t.integer('post_id')
		t.not_null()
		t.integer('user_id')
		t.not_null()
		t.text('content')
		t.not_null()
		t.integer('parent_id')
		t.default_('0')
		t.string_('status', 20)
		t.default_('visible')
		t.integer('deleted_at') // 软删除时间戳（0 = 未删除）
		t.default_('0')
		t.integer('created_at')
		t.integer('updated_at')
		t.integer('version')
		t.index_(['post_id'], 'idx_comments_post')
		t.index_(['user_id'], 'idx_comments_user')
		t.index_(['parent_id'], 'idx_comments_parent')
		t.index_(['status'], 'idx_comments_status')
	})
	database.execute_schema(db, schema)!
}

fn (m CreateCommentsTable) down(mut manager phorm.OrmManager) ! {
	db := database.get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS comments')!
}

module migrations

// 20260101000001_create_users_table.v — 用户表迁移
//
// 创建 users 表，包含用户名、邮箱、密码、昵称、头像、状态、角色等字段。
// 添加 deleted_at 列以支持框架级软删除（当前实现使用 status=-1 状态删除，
// deleted_at 为未来 SoftDeletableEntity 自动过滤预留）。

import photon.orm as phorm

struct CreateUsersTable {}

fn (m CreateUsersTable) version() int {
	return 1
}

fn (m CreateUsersTable) name() string {
	return 'create_users_table'
}

fn (m CreateUsersTable) up(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
	mut schema := phorm.new_schema(.sqlite)
	schema.create_table('users', fn (mut t phorm.TableDef) {
		t.id()
		t.string_('username', 255)
		t.not_null()
		t.string_('email', 255)
		t.not_null()
		t.string_('password', 255)
		t.not_null()
		t.string_('nickname', 255)
		t.string_('avatar', 512)
		t.integer('status')
		t.default_('1')
		t.string_('role', 50)
		t.default_('USER')
		t.integer('deleted_at') // 软删除时间戳（0 = 未删除）
		t.default_('0')
		t.integer('created_at')
		t.integer('updated_at')
		t.integer('version')
		t.unique_(['username'], 'idx_users_username')
		t.unique_(['email'], 'idx_users_email')
		t.index_(['status'], 'idx_users_status')
		t.index_(['role'], 'idx_users_role')
	})
	execute_schema(db, schema)!
}

fn (m CreateUsersTable) down(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS users')!
}

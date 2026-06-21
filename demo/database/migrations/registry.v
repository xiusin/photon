module migrations

// registry.v — 迁移注册表
//
// all() 返回本应用的全部迁移（按 version 升序）。
// MigrationManager 会按 version 排序后依次执行 up()。

import photon.orm as phorm

// all 返回所有已定义的迁移
pub fn all() []&phorm.Migration {
	return [
		&phorm.Migration(CreateUsersTable{}),
		&phorm.Migration(CreatePostsTable{}),
		&phorm.Migration(CreateCommentsTable{}),
		&phorm.Migration(CreateCategoriesTable{}),
		&phorm.Migration(CreateTagsTable{}),
		&phorm.Migration(CreatePostTagsTable{}),
	]
}

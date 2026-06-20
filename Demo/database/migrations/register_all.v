module migrations

// register_all.go — 迁移注册辅助
//
// 将所有迁移结构体注册到 MigrationManager。
// 由调用方（providers/commands/tests）在创建 MigrationManager 后调用，
// 避免 database 模块直接依赖 migrations 模块（打破循环依赖）。

import photon.orm as phorm

// register_all 注册全部迁移到 MigrationManager（按版本顺序）
pub fn register_all(mut mm phorm.MigrationManager) {
	mm.add(CreateUsersTable{})       // v1: 用户表
	mm.add(CreatePostsTable{})       // v2: 文章表
	mm.add(CreateCommentsTable{})    // v3: 评论表
	mm.add(CreateCategoriesTable{})  // v4: 分类表
	mm.add(CreateTagsTable{})        // v5: 标签表
	mm.add(CreatePostTagsTable{})    // v6: 文章-标签关联表
}

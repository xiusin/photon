module main

// database.v — PhotonBlog 数据库连接与迁移
//
// 使用 Photon orm 模块的 OrmManager + MigrationManager + Schema 构建器，
// 实现 SQLite 数据库连接管理与版本化迁移。
//
// 迁移表结构：
//   1. users       — 用户表
//   2. categories  — 分类表
//   3. posts       — 文章表
//   4. comments    — 评论表
//   5. tags        — 标签表
//   6. post_tags   — 文章-标签关联表

import photon.orm as phorm
import db.sqlite

// 全局数据库连接，确保 sqlite.DB 在应用生命周期内存活
__global (
	g_db sqlite.DB
)

// ═══════════════════════════════════════════════════════════
// 数据库初始化
// ═══════════════════════════════════════════════════════════

// init_database 初始化数据库连接并注册到 OrmManager
//
// 根据 DatabaseConfig 创建 SQLite 连接，注册为 'default' 连接。
// 支持 :memory: 内存数据库和文件路径两种模式。
pub fn init_database(cfg DatabaseConfig) !&phorm.OrmManager {
	unsafe {
		g_db = sqlite.connect(cfg.path)!
	}
	mut om := phorm.new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(&g_db))!
	return om
}

// get_db 从 OrmManager 获取底层 sqlite.DB 指针
pub fn get_db(om &phorm.OrmManager) !&sqlite.DB {
	conn := om.get_conn('default')!
	return unsafe { &sqlite.DB(conn) }
}

// ═══════════════════════════════════════════════════════════
// 迁移结构体
// ═══════════════════════════════════════════════════════════

// CreateUsersTable — 创建用户表（版本 1）
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

// CreateCategoriesTable — 创建分类表（版本 2）
struct CreateCategoriesTable {}

fn (m CreateCategoriesTable) version() int {
	return 2
}

fn (m CreateCategoriesTable) name() string {
	return 'create_categories_table'
}

fn (m CreateCategoriesTable) up(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
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
	execute_schema(db, schema)!
}

fn (m CreateCategoriesTable) down(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS categories')!
}

// CreatePostsTable — 创建文章表（版本 3）
struct CreatePostsTable {}

fn (m CreatePostsTable) version() int {
	return 3
}

fn (m CreatePostsTable) name() string {
	return 'create_posts_table'
}

fn (m CreatePostsTable) up(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
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
		t.integer('created_at')
		t.integer('updated_at')
		t.integer('version')
		t.index_(['author_id'], 'idx_posts_author')
		t.index_(['category_id'], 'idx_posts_category')
		t.index_(['status'], 'idx_posts_status')
		t.index_(['created_at'], 'idx_posts_created_at')
	})
	execute_schema(db, schema)!
}

fn (m CreatePostsTable) down(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS posts')!
}

// CreateCommentsTable — 创建评论表（版本 4）
struct CreateCommentsTable {}

fn (m CreateCommentsTable) version() int {
	return 4
}

fn (m CreateCommentsTable) name() string {
	return 'create_comments_table'
}

fn (m CreateCommentsTable) up(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
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
		t.integer('created_at')
		t.integer('updated_at')
		t.integer('version')
		t.index_(['post_id'], 'idx_comments_post')
		t.index_(['user_id'], 'idx_comments_user')
		t.index_(['parent_id'], 'idx_comments_parent')
		t.index_(['status'], 'idx_comments_status')
	})
	execute_schema(db, schema)!
}

fn (m CreateCommentsTable) down(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS comments')!
}

// CreateTagsTable — 创建标签表（版本 5）
struct CreateTagsTable {}

fn (m CreateTagsTable) version() int {
	return 5
}

fn (m CreateTagsTable) name() string {
	return 'create_tags_table'
}

fn (m CreateTagsTable) up(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
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
	execute_schema(db, schema)!
}

fn (m CreateTagsTable) down(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS tags')!
}

// CreatePostTagsTable — 创建文章-标签关联表（版本 6）
struct CreatePostTagsTable {}

fn (m CreatePostTagsTable) version() int {
	return 6
}

fn (m CreatePostTagsTable) name() string {
	return 'create_post_tags_table'
}

fn (m CreatePostTagsTable) up(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
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
	execute_schema(db, schema)!
}

fn (m CreatePostTagsTable) down(mut manager phorm.OrmManager) ! {
	db := get_db(&manager)!
	db.exec('DROP TABLE IF EXISTS post_tags')!
}

// ═══════════════════════════════════════════════════════════
// 迁移辅助函数
// ═══════════════════════════════════════════════════════════

// execute_schema 执行 Schema 构建器生成的所有 SQL 语句
fn execute_schema(db &sqlite.DB, schema &phorm.Schema) ! {
	for stmt in schema.statements {
		db.exec(stmt)!
	}
}

// ═══════════════════════════════════════════════════════════
// 迁移管理入口
// ═══════════════════════════════════════════════════════════

// new_migration_manager 创建迁移管理器并注册所有迁移
pub fn new_migration_manager(om &phorm.OrmManager) !&phorm.MigrationManager {
	mut mm := phorm.new_migration_manager(om)
	mm.set_db_name('default')

	// 按版本顺序注册迁移
	mm.add(CreateUsersTable{})
	mm.add(CreateCategoriesTable{})
	mm.add(CreatePostsTable{})
	mm.add(CreateCommentsTable{})
	mm.add(CreateTagsTable{})
	mm.add(CreatePostTagsTable{})

	return mm
}

// run_migrations 执行所有待运行的迁移
pub fn run_migrations(mm &phorm.MigrationManager) ! {
	mut mm_mut := unsafe { mut mm }
	mm_mut.initialize()!
	mm_mut.migrate()!
}

// rollback_migrations 回滚最后一个 batch 的迁移
pub fn rollback_migrations(mm &phorm.MigrationManager) ! {
	mut mm_mut := unsafe { mut mm }
	mm_mut.rollback() or { return }
}

// reset_migrations 回滚所有迁移
pub fn reset_migrations(mm &phorm.MigrationManager) ! {
	mut mm_mut := unsafe { mut mm }
	mm_mut.reset()!
}

// fresh_migrations 重置并重新执行所有迁移
pub fn fresh_migrations(mm &phorm.MigrationManager) ! {
	mut mm_mut := unsafe { mut mm }
	mm_mut.fresh()!
}

// migration_status 打印迁移状态
pub fn migration_status(mm &phorm.MigrationManager) ! {
	mut mm_mut := unsafe { mut mm }
	mm_mut.status()!
}

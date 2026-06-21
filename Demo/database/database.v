module database

// database.v — PhotonBlog 数据库连接与迁移
//
// 使用 Photon orm 模块的 OrmManager + MigrationManager + Schema 构建器，
// 实现 SQLite 数据库连接管理与版本化迁移。
//
// 迁移结构体已拆分到 database/migrations/ 目录，按文件名时间戳排序加载：
//   1. users       — 用户表
//   2. posts       — 文章表
//   3. comments    — 评论表
//   4. categories  — 分类表
//   5. tags        — 标签表
//   6. post_tags   — 文章-标签关联表
//
// 本文件仅保留连接初始化、Schema 执行辅助、迁移管理器装配与生命周期入口。

import photon.orm as phorm
import db.sqlite
import config

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
pub fn init_database(cfg config.DatabaseConfig) !&phorm.OrmManager {
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
// 迁移辅助函数
// ═══════════════════════════════════════════════════════════

// execute_schema 执行 Schema 构建器生成的所有 SQL 语句
pub fn execute_schema(db &sqlite.DB, schema &phorm.Schema) ! {
	for stmt in schema.statements {
		db.exec(stmt)!
	}
}

// ═══════════════════════════════════════════════════════════
// 迁移管理入口
// ═══════════════════════════════════════════════════════════

// new_migration_manager 创建迁移管理器（不注册具体迁移）
//
// 返回空的 MigrationManager，具体迁移由调用方通过 migrations.register_all() 注册。
// 这避免了 database <-> migrations 的循环依赖。
pub fn new_migration_manager(om &phorm.OrmManager) !&phorm.MigrationManager {
	mut mm := phorm.new_migration_manager(om)
	mm.set_db_name('default')
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

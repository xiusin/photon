module database

import photon.orm as phorm
import db.sqlite
import config

// 全局数据库连接
__global (
	g_db sqlite.DB
)

// init_database 初始化数据库连接并注册到 OrmManager
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

// execute_schema 执行 Schema 构建器生成的所有 SQL 语句
pub fn execute_schema(db &sqlite.DB, schema &phorm.Schema) ! {
	for stmt in schema.statements {
		db.exec(stmt)!
	}
}

// do_run_migrations 执行所有待运行的迁移
pub fn do_run_migrations(mm &phorm.MigrationManager) !bool {
	mut mm_mut := unsafe { mut mm }
	mm_mut.initialize()!
	mm_mut.migrate()!
	return true
}

// do_rollback_migrations 回滚最后一个 batch 的迁移
pub fn do_rollback_migrations(mm &phorm.MigrationManager) !bool {
	mut mm_mut := unsafe { mut mm }
	mm_mut.rollback() or { return false }
	return true
}

// do_reset_migrations 回滚所有迁移
pub fn do_reset_migrations(mm &phorm.MigrationManager) !bool {
	mut mm_mut := unsafe { mut mm }
	mm_mut.reset()!
	return true
}

// do_fresh_migrations 重置并重新执行所有迁移
pub fn do_fresh_migrations(mm &phorm.MigrationManager) !bool {
	mut mm_mut := unsafe { mut mm }
	mm_mut.fresh()!
	return true
}

// do_migration_status 打印迁移状态
pub fn do_migration_status(mm &phorm.MigrationManager) !bool {
	mut mm_mut := unsafe { mut mm }
	mm_mut.status()!
	return true
}

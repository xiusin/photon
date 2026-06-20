module providers

// providers/database_service_provider.v — 数据库服务提供者
//
// 注册 OrmManager 与 MigrationManager，并在 boot() 阶段执行数据库迁移。
//
// Laravel 等价：App\Providers\DatabaseServiceProvider
// Spring 等价：DataSourceAutoConfiguration

import photon.core
import photon.orm as phorm
import database
import database.migrations

pub struct DatabaseServiceProvider {
	ctx &BootContext
}

// new_database_provider 创建数据库服务提供者
pub fn new_database_provider(ctx &BootContext) &DatabaseServiceProvider {
	return &DatabaseServiceProvider{
		ctx: ctx
	}
}

// register 创建 OrmManager 并注册到容器
pub fn (sp &DatabaseServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	cfg := sp.ctx.cfg
	log := sp.ctx.log

	orm_mgr := database.init_database(cfg.database)!
	sp.ctx.orm_mgr = orm_mgr
	log.info('OrmManager initialized — ${cfg.database.driver} (${cfg.database.path})')

	app_ctx.register_instance('OrmManager', unsafe { voidptr(orm_mgr) })!
}

// boot 执行数据库迁移（所有 Provider 注册完成后调用）
pub fn (sp &DatabaseServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
	log := sp.ctx.log
	orm_mgr := sp.ctx.orm_mgr

	mm := database.new_migration_manager(orm_mgr)!
	database.migrations.register_all(mut mm)
	log.info('Running database migrations...')
	database.run_migrations(mm)!
	log.info('Database migrations applied')
}

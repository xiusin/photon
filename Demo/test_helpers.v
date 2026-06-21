module main

// test_helpers.v — PhotonBlog 测试共享辅助函数
//
// 此文件为非测试文件（不以 _test.v 结尾），因此其中定义的函数
// 在所有测试文件中均可使用。test_setup() 创建独立的内存数据库
// Bootstrap，确保每个测试使用独立的数据库实例。

import config
import bootstrap
import database
import database.migrations

// test_setup 创建测试用 Bootstrap（使用内存数据库 + 运行迁移）
// 所有测试文件共享此函数，确保每个测试使用独立的内存数据库
pub fn test_setup() !&bootstrap.Bootstrap {
	cfg := config.load_config('test')!
	kernel := bootstrap.new_app_kernel(cfg)!
	kernel.bootstrap()!
	boot := kernel.to_bootstrap()
	mut mm := database.new_migration_manager(boot.orm_mgr)!
	migrations.register_all(mut mm)
	database.run_migrations(mm)!
	return boot
}

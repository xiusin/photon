module tests

// tests/refresh_database.v — RefreshDatabase 数据库刷新 trait
//
// Laravel 风格的 RefreshDatabase trait，在每个测试前自动重置数据库。
// 通过 struct 嵌入实现 "trait" 效果：嵌入 RefreshDatabase 的测试结构体
// 自动获得 refresh_database() 方法。
//
// 用法：
//   // 方式 1：直接使用 TestCase（已内置 refresh_database）
//   fn test_something() {
//       mut t := TestCase{}
//       t.setup()!           // 等价于 refresh_database
//       defer { t.teardown() }
//       // ... 测试逻辑
//   }
//
//   // 方式 2：嵌入 RefreshDatabase 到自定义测试结构体
//   struct MyTestCase {
//       TestCase
//       RefreshDatabase
//   }
//
//   fn test_with_custom_case() {
//       mut t := MyTestCase{}
//       t.refresh_database()!
//       defer { t.teardown() }
//       // ... 测试逻辑
//   }
//
// 设计说明：
//   V 语言无 trait 关键字，通过 struct 嵌入 + 方法提升实现类似效果。
//   RefreshDatabase 提供独立的数据库刷新逻辑，可嵌入任意测试结构体。

import photon.cli

// RefreshDatabase 数据库刷新 trait（struct 嵌入实现）
// 嵌入此 struct 的测试类获得 refresh_database() 方法
pub struct RefreshDatabase {
mut:
	boot &Bootstrap = unsafe { nil }
}

// refresh_database 重置数据库：创建全新内存数据库 + 运行所有迁移
//
// 等价于 CLI 命令 `migrate:fresh`：
//   1. 创建新的 :memory: SQLite 数据库
//   2. 按时间戳顺序执行所有迁移文件
//   3. 数据库处于干净状态，无任何业务数据
//
// 每个测试调用此方法后获得独立数据库，确保测试间无状态泄漏。
pub fn (mut r RefreshDatabase) refresh_database() !&Bootstrap {
	r.boot = test_setup()!
	return r.boot
}

// refresh_database_with_seed 重置数据库并运行种子
//
// 等价于 `migrate:fresh --seed`：
//   1. 创建新数据库 + 运行迁移
//   2. 运行 DatabaseSeeder 插入种子数据
//
// 适用于需要预填充数据的集成测试。
pub fn (mut r RefreshDatabase) refresh_database_with_seed() !&Bootstrap {
	r.boot = test_setup()!
	// 运行种子（静默输出，避免测试日志污染）
	mut seeder := new_database_seeder(r.boot)
	mut output := cli.new_output()
	output.style = .quiet
	seeder.run(output)!
	return r.boot
}

// boot_context 获取当前 Bootstrap 引用
pub fn (r &RefreshDatabase) boot_context() &Bootstrap {
	return r.boot
}

// reset 清理引用（用于 teardown）
pub fn (mut r RefreshDatabase) reset() {
	r.boot = unsafe { nil }
}

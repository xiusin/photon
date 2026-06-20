module main

// seeder.v — Seeder 接口定义
//
// 所有种子类必须实现 Seeder 接口，由 DatabaseSeeder 统一编排调用。
// Seeder 通过持有 &Bootstrap 引用访问已装配的服务与仓储。
//
// 使用方式：
//   mut seeder := new_database_seeder(boot)
//   seeder.run(output)!

import photon.cli

// Seeder 种子接口 — 所有具体 Seeder 必须实现此接口
pub interface Seeder {
	run(output &cli.CommandOutput) !
}

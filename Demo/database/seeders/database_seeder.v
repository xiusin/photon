module seeders

// database_seeder.v — DatabaseSeeder 种子编排器
//
// 统一编排所有 Seeder 的执行顺序：
//   1. UserSeeder   — 用户（ADMIN + EDITOR + USER）
//   2. PostSeeder   — 分类 + 文章（依赖用户存在）
//   3. CommentSeeder — 评论（依赖文章与用户存在）
//
// 用法：
//   mut seeder := new_database_seeder(boot)
//   seeder.run(output)!
//
// 或选择性执行：
//   seeder.run_only('users', output)!  // 仅种子用户

import photon.cli

// DatabaseSeeder 种子编排器
pub struct DatabaseSeeder {
pub:
	bootstrap &Bootstrap
mut:
	seeders map[string]&Seeder
}

// new_database_seeder 创建种子编排器，注册所有子 Seeder
pub fn new_database_seeder(boot &Bootstrap) &DatabaseSeeder {
	mut ds := &DatabaseSeeder{
		bootstrap: boot
		seeders:   map[string]&Seeder{}
	}

	// 按依赖顺序注册
	ds.seeders['users']    = new_user_seeder(boot)
	ds.seeders['posts']    = new_post_seeder(boot)
	ds.seeders['comments'] = new_comment_seeder(boot)

	return ds
}

// run 执行所有种子（按注册顺序）
pub fn (mut s DatabaseSeeder) run(output &cli.CommandOutput) ! {
	output.title('Seeding database')

	for name, seeder in s.seeders {
		seeder.run(output) or {
			output.error('Seeder "${name}" failed: ${err}')
			return err
		}
	}

	output.success('Seed data inserted successfully')
}

// run_only 仅执行指定的种子
pub fn (mut s DatabaseSeeder) run_only(name string, output &cli.CommandOutput) ! {
	seeder := s.seeders[name] or {
		return error('Seeder not found: ${name} / 未找到种子: ${name}')
	}
	output.title('Running seeder: ${name}')
	seeder.run(output)!
	output.success('Seeder "${name}" completed')
}

// list_seeders 列出所有已注册的种子名称
pub fn (s &DatabaseSeeder) list_seeders() []string {
	mut names := []string{}
	for name in s.seeders.keys() {
		names << name
	}
	return names
}

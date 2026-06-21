module seeders

// user_seeder.v — UserSeeder 用户种子数据
//
// 创建 8 个用户：1 ADMIN + 2 EDITOR + 5 USER
// 账号密码从 .env 读取（SEED_ADMIN_PASSWORD / SEED_EDITOR_PASSWORD / SEED_USER_PASSWORD），
// 未设置时使用默认值。
//
// 幂等性：若用户名已存在则跳过创建。

import bootstrap
import photon.cli
import os
import database.factories

// UserSeeder 用户种子
pub struct UserSeeder {
pub:
	bootstrap &bootstrap.Bootstrap
}

// new_user_seeder 创建用户种子实例
pub fn new_user_seeder(boot &bootstrap.Bootstrap) &UserSeeder {
	return &UserSeeder{
		bootstrap: boot
	}
}

// run 执行用户种子数据填充
pub fn (s &UserSeeder) run(output &cli.CommandOutput) ! {
	output.section('  Seeding users')

	mut admin_password := os.getenv('SEED_ADMIN_PASSWORD')
	if admin_password.len == 0 {
		admin_password = 'admin123'
	}
	mut editor_password := os.getenv('SEED_EDITOR_PASSWORD')
	if editor_password.len == 0 {
		editor_password = 'editor123'
	}
	mut user_password := os.getenv('SEED_USER_PASSWORD')
	if user_password.len == 0 {
		user_password = 'user123'
	}

	mut created_count := 0

	// ── 1. 创建 1 个 ADMIN ──
	admin := factories.new_user_factory(s.bootstrap).
		with_username('admin').
		with_email('admin@photonblog.dev').
		with_password(admin_password).
		with_nickname('Administrator').
		with_role('ADMIN').
		create_or_first()!
	if admin.id > 0 {
		output.success('    Created admin: ${admin.username} (id=${admin.id})')
		created_count++
	}

	// ── 2. 创建 2 个 EDITOR ──
	editor_names := ['editor1', 'editor2']
	for i, name in editor_names {
		user := factories.new_user_factory(s.bootstrap).
			with_username(name).
			with_email('${name}@photonblog.dev').
			with_password(editor_password).
			with_nickname('Editor ${i + 1}').
			with_role('EDITOR').
			create_or_first() or {
			output.warning('    Failed to create editor ${name}: ${err}')
			continue
		}
		if user.id > 0 {
			output.success('    Created editor: ${user.username} (id=${user.id})')
			created_count++
		}
	}

	// ── 3. 创建 5 个 USER ──
	for i in 1 .. 6 {
		name := 'user${i}'
		user := factories.new_user_factory(s.bootstrap).
			with_username(name).
			with_email('${name}@photonblog.dev').
			with_password(user_password).
			with_nickname('User ${i}').
			with_role('USER').
			create_or_first() or {
			output.warning('    Failed to create user ${name}: ${err}')
			continue
		}
		if user.id > 0 {
			output.success('    Created user: ${user.username} (id=${user.id})')
			created_count++
		}
	}

	output.writeln('    Users seeded: ${created_count} total')
}

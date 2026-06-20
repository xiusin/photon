module main

// commands.v — PhotonBlog CLI 命令系统
//
// 实现 9 个业务 CLI 命令，通过 CliApplication 统一调度：
//   1. serve            — 启动 Web 服务（--port/--host 参数）
//   2. migrate          — 执行数据库迁移
//   3. migrate:rollback — 回滚最后一个 batch 的迁移
//   4. migrate:status   — 查看迁移状态
//   5. seed             — 种子数据（1 ADMIN + 2 EDITOR + 5 USER + 10 文章 + 20 评论）
//   6. queue:work       — 启动队列 Worker（阻塞轮询）
//   7. scheduler:run    — 启动定时调度器（阻塞）
//   8. stats            — 输出博客统计信息
//   9. routes           — 打印所有路由表
//
// 所有命令持有 &Bootstrap 引用，访问已装配的服务与基础设施组件。
// main() 在启动时通过 register_commands() 注册到 CliApplication。

import photon.cli
import photon.web
import time

// ═══════════════════════════════════════════════════════════
// ServeCommand — 启动 Web 服务
// ═══════════════════════════════════════════════════════════

pub struct ServeCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

// new_serve_command 创建启动 Web 服务的命令
pub fn new_serve_command(boot &Bootstrap) &ServeCommand {
	return &ServeCommand{
		BaseCommand: cli.BaseCommand{
			name:        'serve'
			description: 'Start the HTTP server'
			sig:         '[--port=8080] [--host=0.0.0.0]'
		}
		bootstrap: boot
	}
}

pub fn (c &ServeCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	port := input.get_option_or('port', c.bootstrap.cfg.server.port.str())
	host := input.get_option_or('host', c.bootstrap.cfg.server.host)

	output.writeln('')
	output.success('Starting PhotonBlog HTTP server...')
	output.writeln('  Host: ${host}')
	output.writeln('  Port: ${port}')
	output.writeln('  Profile: ${c.bootstrap.cfg.profile}')
	output.writeln('')

	// 实际的 veb.run_at 由 main() 在 cmd_app.run() 返回后执行
	return
}

// ═══════════════════════════════════════════════════════════
// MigrateCommand — 执行数据库迁移
// ═══════════════════════════════════════════════════════════

pub struct MigrateCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_migrate_command(boot &Bootstrap) &MigrateCommand {
	return &MigrateCommand{
		BaseCommand: cli.BaseCommand{
			name:        'migrate'
			description: 'Run database migrations'
			sig:         ''
		}
		bootstrap: boot
	}
}

pub fn (c &MigrateCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Running database migrations')

	mm := new_migration_manager(c.bootstrap.orm_mgr)!
	run_migrations(mm) or {
		output.error('Migration failed: ${err}')
		return
	}

	output.success('Migrations completed successfully')
	return
}

// ═══════════════════════════════════════════════════════════
// MigrateRollbackCommand — 回滚迁移
// ═══════════════════════════════════════════════════════════

pub struct MigrateRollbackCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_migrate_rollback_command(boot &Bootstrap) &MigrateRollbackCommand {
	return &MigrateRollbackCommand{
		BaseCommand: cli.BaseCommand{
			name:        'migrate:rollback'
			description: 'Rollback the last batch of migrations'
			sig:         ''
		}
		bootstrap: boot
	}
}

pub fn (c &MigrateRollbackCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Rolling back database migrations')

	mm := new_migration_manager(c.bootstrap.orm_mgr)!
	rollback_migrations(mm) or {
		output.error('Rollback failed: ${err}')
		return
	}

	output.success('Rollback completed successfully')
	return
}

// ═══════════════════════════════════════════════════════════
// MigrateStatusCommand — 迁移状态
// ═══════════════════════════════════════════════════════════

pub struct MigrateStatusCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_migrate_status_command(boot &Bootstrap) &MigrateStatusCommand {
	return &MigrateStatusCommand{
		BaseCommand: cli.BaseCommand{
			name:        'migrate:status'
			description: 'Show migration status'
			sig:         ''
		}
		bootstrap: boot
	}
}

pub fn (c &MigrateStatusCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Migration Status')

	mm := new_migration_manager(c.bootstrap.orm_mgr)!
	migration_status(mm) or {
		output.error('Failed to get migration status: ${err}')
		return
	}

	return
}

// ═══════════════════════════════════════════════════════════
// SeedCommand — 种子数据
// ═══════════════════════════════════════════════════════════

pub struct SeedCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_seed_command(boot &Bootstrap) &SeedCommand {
	return &SeedCommand{
		BaseCommand: cli.BaseCommand{
			name:        'seed'
			description: 'Seed database with sample data (1 ADMIN + 2 EDITOR + 5 USER + 10 posts + 20 comments)'
			sig:         '[--only=users|posts|comments]'
		}
		bootstrap: boot
	}
}

pub fn (c &SeedCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	mut seeder := new_database_seeder(c.bootstrap)

	// 支持 --only 参数选择性执行种子
	only := input.get_option_or('only', '')
	if only.len > 0 {
		seeder.run_only(only, output)!
		return
	}

	seeder.run(output)!
	return
}

// ═══════════════════════════════════════════════════════════
// QueueWorkCommand — 启动队列 Worker
// ═══════════════════════════════════════════════════════════

pub struct QueueWorkCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_queue_work_command(boot &Bootstrap) &QueueWorkCommand {
	return &QueueWorkCommand{
		BaseCommand: cli.BaseCommand{
			name:        'queue:work'
			description: 'Start processing queued jobs'
			sig:         ''
		}
		bootstrap: boot
	}
}

pub fn (c &QueueWorkCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Starting queue worker')
	output.writeln('Press Ctrl+C to stop')
	output.writeln('')

	// Bootstrap 在初始化时已注册 Job 工厂，直接复用 worker
	mut worker := unsafe { c.bootstrap.worker }
	worker.run()
	output.success('Worker is running (polling every 1s)')

	// 阻塞轮询队列
	for worker.is_running() {
		worker.tick()
		time.sleep(1 * time.second)
	}
	return
}

// ═══════════════════════════════════════════════════════════
// SchedulerRunCommand — 启动定时调度器
// ═══════════════════════════════════════════════════════════

pub struct SchedulerRunCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_scheduler_run_command(boot &Bootstrap) &SchedulerRunCommand {
	return &SchedulerRunCommand{
		BaseCommand: cli.BaseCommand{
			name:        'scheduler:run'
			description: 'Start the scheduled task scheduler'
			sig:         ''
		}
		bootstrap: boot
	}
}

pub fn (c &SchedulerRunCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Starting scheduler')
	output.writeln('Press Ctrl+C to stop')
	output.writeln('')

	sched := new_scheduler(c.bootstrap.stats_svc, c.bootstrap.cache_mgr, c.bootstrap.log)!
	start_scheduler(sched)

	output.success('Scheduler is running (${sched.task_count()} tasks registered)')
	sched.print_status()

	// 阻塞主线程，保持调度器运行
	for {
		time.sleep(1 * time.second)
	}
	return
}

// ═══════════════════════════════════════════════════════════
// StatsCommand — 输出统计信息
// ═══════════════════════════════════════════════════════════

pub struct StatsCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_stats_command(boot &Bootstrap) &StatsCommand {
	return &StatsCommand{
		BaseCommand: cli.BaseCommand{
			name:        'stats'
			description: 'Display blog statistics'
			sig:         ''
		}
		bootstrap: boot
	}
}

pub fn (c &StatsCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('PhotonBlog Statistics')

	stats := c.bootstrap.stats_svc.aggregate_stats() or {
		output.error('Failed to aggregate stats: ${err}')
		return
	}

	output.table(
		['Metric', 'Value'],
		[
			['Users', stats.user_count.str()],
			['Posts', stats.post_count.str()],
			['Published', stats.published_count.str()],
			['Drafts', stats.draft_count.str()],
			['Comments', stats.comment_count.str()],
		]
	)

	aggregated_at := time.unix(stats.aggregated_at)
	output.writeln('  Aggregated at: ${aggregated_at.format()}')
	return
}

// ═══════════════════════════════════════════════════════════
// RoutesCommand — 打印路由表
// ═══════════════════════════════════════════════════════════

pub struct RoutesCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_routes_command(boot &Bootstrap) &RoutesCommand {
	return &RoutesCommand{
		BaseCommand: cli.BaseCommand{
			name:        'routes'
			description: 'List all registered routes'
			sig:         ''
		}
		bootstrap: boot
	}
}

pub fn (c &RoutesCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Registered Routes')

	// 通过 comptime 扫描 App 控制器的路由注解
	routes := web.scan_controller[App]()
	output.writeln('  Found ${routes.len} routes:')
	output.writeln('')

	if routes.len > 0 {
		output.table(
			['Method', 'Path', 'Handler'],
			routes.map(fn (r web.RouteInfo) []string {
				return [r.method, r.path, r.handler_name]
			})
		)
	}

	return
}

// ═══════════════════════════════════════════════════════════
// register_commands — 注册所有命令到 CliApplication
// ═══════════════════════════════════════════════════════════

// register_commands 将所有业务命令注册到 CliApplication
pub fn register_commands(mut app &cli.CliApplication, boot &Bootstrap) {
	app.add_command(new_serve_command(boot))
	app.add_command(new_migrate_command(boot))
	app.add_command(new_migrate_rollback_command(boot))
	app.add_command(new_migrate_status_command(boot))
	app.add_command(new_seed_command(boot))
	app.add_command(new_queue_work_command(boot))
	app.add_command(new_scheduler_run_command(boot))
	app.add_command(new_stats_command(boot))
	app.add_command(new_routes_command(boot))
}

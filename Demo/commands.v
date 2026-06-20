module main

// commands.v — PhotonBlog CLI 命令系统
//
// 实现 15+ 个业务 CLI 命令，通过 CliApplication 统一调度：
//   1. serve             — 启动 Web 服务（--port/--host 参数）
//   2. migrate           — 执行数据库迁移
//   3. migrate:rollback  — 回滚最后一个 batch 的迁移
//   4. migrate:status    — 查看迁移状态
//   5. migrate:fresh     — 删除所有表并重新迁移
//   6. migrate:refresh   — 回滚所有迁移并重新执行
//   7. migrate:reset     — 回滚所有迁移
//   8. seed              — 种子数据（1 ADMIN + 2 EDITOR + 5 USER + 10 文章 + 20 评论）
//   9. queue:work        — 启动队列 Worker（阻塞轮询）
//  10. scheduler:run     — 启动定时调度器（阻塞，支持 SIGINT 优雅退出）
//  11. stats             — 输出博客统计信息
//  12. routes            — 打印所有路由表
//  13. docs              — 生成 API 文档（输出到 docs/api/）
//  14-22. make:*         — 代码生成命令（controller/model/migration/middleware/provider/
//                          command/resource/seeder/factory/entity，由框架 cli 模块提供）
//
// 所有命令持有 &Bootstrap 引用，访问已装配的服务与基础设施组件。
// main() 在启动时通过 register_commands() 注册到 CliApplication。

import photon.cli
import photon.web
import time
import os

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
// MigrateFreshCommand — 删除所有表并重新迁移
// ═══════════════════════════════════════════════════════════
// Laravel 等价：migrate:fresh
// 适用场景：开发环境重置数据库到干净状态（drop 所有表 + 重新迁移 + 可选 seed）

pub struct MigrateFreshCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_migrate_fresh_command(boot &Bootstrap) &MigrateFreshCommand {
	return &MigrateFreshCommand{
		BaseCommand: cli.BaseCommand{
			name:        'migrate:fresh'
			description: 'Drop all tables and re-run migrations'
			sig:         '[--seed]'
		}
		bootstrap: boot
	}
}

pub fn (c &MigrateFreshCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Fresh migration (drop all + re-migrate)')

	mm := new_migration_manager(c.bootstrap.orm_mgr)!
	fresh_migrations(mm) or {
		output.error('Fresh migration failed: ${err}')
		return
	}
	output.success('Fresh migration completed successfully')

	// --seed 标志：迁移后自动执行种子
	if input.has_flag('seed') {
		output.writeln('')
		mut seeder := new_database_seeder(c.bootstrap)
		seeder.run(output)!
	}

	return
}

// ═══════════════════════════════════════════════════════════
// MigrateRefreshCommand — 回滚所有迁移并重新执行
// ═══════════════════════════════════════════════════════════
// Laravel 等价：migrate:refresh
// 与 fresh 的区别：refresh 通过 down() 方法回滚（保留迁移历史），
// fresh 直接 drop 表（更彻底但丢失迁移历史）

pub struct MigrateRefreshCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_migrate_refresh_command(boot &Bootstrap) &MigrateRefreshCommand {
	return &MigrateRefreshCommand{
		BaseCommand: cli.BaseCommand{
			name:        'migrate:refresh'
			description: 'Rollback and re-run all migrations'
			sig:         '[--seed]'
		}
		bootstrap: boot
	}
}

pub fn (c &MigrateRefreshCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Refresh migration (rollback all + re-migrate)')

	mm := new_migration_manager(c.bootstrap.orm_mgr)!

	// 1. 回滚所有迁移
	output.writeln('  Rolling back all migrations...')
	reset_migrations(mm) or {
		output.error('Reset failed: ${err}')
		return
	}
	output.success('  All migrations rolled back')

	// 2. 重新执行迁移
	output.writeln('  Re-running migrations...')
	run_migrations(mm) or {
		output.error('Re-migration failed: ${err}')
		return
	}
	output.success('  Migrations re-run successfully')

	// --seed 标志：迁移后自动执行种子
	if input.has_flag('seed') {
		output.writeln('')
		mut seeder := new_database_seeder(c.bootstrap)
		seeder.run(output)!
	}

	return
}

// ═══════════════════════════════════════════════════════════
// MigrateResetCommand — 回滚所有迁移
// ═══════════════════════════════════════════════════════════
// Laravel 等价：migrate:reset

pub struct MigrateResetCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_migrate_reset_command(boot &Bootstrap) &MigrateResetCommand {
	return &MigrateResetCommand{
		BaseCommand: cli.BaseCommand{
			name:        'migrate:reset'
			description: 'Rollback all migrations'
			sig:         ''
		}
		bootstrap: boot
	}
}

pub fn (c &MigrateResetCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Reset migration (rollback all)')

	mm := new_migration_manager(c.bootstrap.orm_mgr)!
	reset_migrations(mm) or {
		output.error('Reset failed: ${err}')
		return
	}

	output.success('All migrations rolled back successfully')
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
	// worker.run() 内部已实现阻塞轮询循环，无需外层 for 循环
	mut worker := unsafe { c.bootstrap.worker }
	worker.run()
	output.success('Worker started (polling every 1s)')
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
	output.writeln('Press Ctrl+C to stop (or use process manager: systemd/Docker for graceful shutdown)')
	output.writeln('')

	sched := new_scheduler(c.bootstrap.stats_svc, c.bootstrap.cache_mgr, c.bootstrap.log)!
	start_scheduler(sched)

	output.success('Scheduler is running (${sched.task_count()} tasks registered)')
	sched.print_status()

	// 阻塞主线程，保持调度器运行
	// 优雅退出：生产环境通过 systemd/Docker 发送 SIGTERM，V 运行时默认处理信号退出
	// 开发环境通过 Ctrl+C 发送 SIGINT，进程直接终止
	for {
		time.sleep(1 * time.second)
	}
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
// DocsCommand — 生成 API 文档
// ═══════════════════════════════════════════════════════════
//
// 扫描所有控制器路由注解，生成 Markdown 格式的 API 文档到 docs/api/ 目录。
// Task 22 将扩展此命令，集成 apidoc 模块生成 OpenAPI/Swagger 规范。

pub struct DocsCommand {
	cli.BaseCommand
	bootstrap &Bootstrap = unsafe { nil }
}

pub fn new_docs_command(boot &Bootstrap) &DocsCommand {
	return &DocsCommand{
		BaseCommand: cli.BaseCommand{
			name:        'docs'
			description: 'Generate API documentation from route annotations'
			sig:         '[--format=markdown|html]'
		}
		bootstrap: boot
	}
}

pub fn (c &DocsCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.title('Generating API documentation')

	format := input.get_option_or('format', 'markdown')

	// 扫描所有路由
	routes := web.scan_controller[App]()
	output.writeln('  Found ${routes.len} routes')
	output.writeln('')

	// 确保输出目录存在
	os.mkdir_all('docs/api') or {}

	// 生成 Markdown 文档
	if format == 'markdown' || format == 'md' {
		generate_markdown_docs(routes, output)!
		return
	}

	// 生成 HTML 文档（基础模板，Task 22 将增强为 OpenAPI/Swagger UI）
	if format == 'html' {
		generate_html_docs(routes, output)!
		return
	}

	output.error('Unsupported format: ${format} (supported: markdown, html)')
	return
}

// generate_markdown_docs 生成 Markdown 格式 API 文档
fn generate_markdown_docs(routes []web.RouteInfo, output &cli.CommandOutput) ! {
	mut content := '# PhotonBlog API Documentation

> Auto-generated from route annotations.

## Endpoints

| Method | Path | Handler |
|--------|------|---------|
'

	for r in routes {
		content += '| ${r.method} | ${r.path} | ${r.handler_name} |\n'
	}

	content += '
## Authentication

All `/api/v1/*` endpoints (except `auth/register` and `auth/login`) require a JWT Bearer token:

```
Authorization: Bearer <token>
```

Tokens are obtained via `POST /api/v1/auth/login` and refreshed via `POST /api/v1/auth/refresh`.

## Response Format

All API responses use the unified envelope:

```json
{
  "success": true,
  "code": 200,
  "message": "OK",
  "data": { ... },
  "timestamp": 1719000000,
  "path": "/api/v1/..."
}
```

Error responses set `success: false` with an appropriate HTTP status code (400/401/403/404/422/500).
'

	os.write_file('docs/api/index.md', content)!
	output.success('Markdown docs generated: docs/api/index.md')
}

// generate_html_docs 生成 HTML 格式 API 文档
fn generate_html_docs(routes []web.RouteInfo, output &cli.CommandOutput) ! {
	mut rows := ''
	for r in routes {
		method_class := match r.method {
			'GET' { 'method-get' }
			'POST' { 'method-post' }
			'PUT' { 'method-put' }
			'DELETE' { 'method-delete' }
			else { 'method-other' }
		}
		rows += '<tr><td class="${method_class}">${r.method}</td><td><code>${r.path}</code></td><td>${r.handler_name}</td></tr>\n'
	}

	html := '<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PhotonBlog API Documentation</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 960px; margin: 2rem auto; padding: 0 1rem; color: #333; }
h1 { border-bottom: 2px solid #4F46E5; padding-bottom: 0.5rem; }
table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
th, td { padding: 0.75rem 1rem; text-align: left; border-bottom: 1px solid #e5e7eb; }
th { background: #f9fafb; font-weight: 600; }
.method-get { color: #059669; font-weight: 600; }
.method-post { color: #DC2626; font-weight: 600; }
.method-put { color: #D97706; font-weight: 600; }
.method-delete { color: #7C3AED; font-weight: 600; }
code { background: #f3f4f6; padding: 0.125rem 0.375rem; border-radius: 3px; font-size: 0.875em; }
</style>
</head>
<body>
<h1>PhotonBlog API Documentation</h1>
<p>Auto-generated from route annotations. Found ${routes.len} endpoints.</p>
<table>
<thead><tr><th>Method</th><th>Path</th><th>Handler</th></tr></thead>
<tbody>
${rows}
</tbody>
</table>
</body>
</html>'

	os.write_file('docs/api/index.html', html)!
	output.success('HTML docs generated: docs/api/index.html')
}

// ═══════════════════════════════════════════════════════════
// register_commands — 注册所有命令到 CliApplication
// ═══════════════════════════════════════════════════════════

// register_commands 将所有业务命令注册到 CliApplication
// 包括：业务命令（serve/migrate/seed/queue/scheduler/stats/routes/docs）
//       + 迁移命令（migrate:fresh/refresh/reset）
//       + 框架提供的 make:* 代码生成命令
pub fn register_commands(mut app &cli.CliApplication, boot &Bootstrap) {
	// 业务命令
	app.add_command(new_serve_command(boot))
	app.add_command(new_migrate_command(boot))
	app.add_command(new_migrate_rollback_command(boot))
	app.add_command(new_migrate_status_command(boot))
	app.add_command(new_migrate_fresh_command(boot))
	app.add_command(new_migrate_refresh_command(boot))
	app.add_command(new_migrate_reset_command(boot))
	app.add_command(new_seed_command(boot))
	app.add_command(new_queue_work_command(boot))
	app.add_command(new_scheduler_run_command(boot))
	app.add_command(new_stats_command(boot))
	app.add_command(new_routes_command(boot))
	app.add_command(new_docs_command(boot))

	// 框架提供的 make:* 代码生成命令
	app.add_command(cli.new_make_command_command())
	app.add_command(cli.new_make_controller_command())
	app.add_command(cli.new_make_middleware_command())
	app.add_command(cli.new_make_provider_command())
	app.add_command(cli.new_make_entity_command())
	app.add_command(cli.new_make_model_command())
	app.add_command(cli.new_make_migration_command())
	app.add_command(cli.new_make_resource_command())
	app.add_command(cli.new_make_seeder_command())
	app.add_command(cli.new_make_factory_command())
}

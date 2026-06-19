module main

// main.v — PhotonBlog 应用入口
//
// 组装 CLI + Bootstrap + veb.run_at，完成应用启动流程：
//   1. 读取 profile（APP_PROFILE 环境变量，默认 dev）
//   2. 加载配置（load_config）
//   3. 创建 Bootstrap（装配所有组件）
//   4. 创建中间件管理器
//   5. 创建 App 并注册全局中间件
//   6. 注册 CLI 命令并运行
//   7. 扫描路由并打印路由表
//   8. 启动 veb HTTP 服务

import os
import veb
import time
import photon.cli
import photon.web

fn main() {
	// ── 1. 确定 profile ──
	profile := os.getenv('APP_PROFILE')
	actual_profile := if profile.len > 0 { profile } else { 'dev' }

	// ── 2. 加载配置 ──
	cfg := load_config(actual_profile) or {
		eprintln('Failed to load config (profile=${actual_profile}): ${err}')
		exit(1)
	}

	// ── 3. 创建 Bootstrap ──
	boot := new_bootstrap(cfg) or {
		eprintln('Bootstrap failed: ${err}')
		exit(1)
	}
	boot.print_banner()

	// ── 4. 创建中间件管理器 ──
	mm := new_middleware_manager(boot.auth_svc, boot.role_hierarchy, boot.log)

	// ── 5. 创建 App ──
	mut web_app := &App{
		start_time: time.ticks()
		bootstrap:  boot
		middleware: mm
	}

	// ── 6. 注册全局中间件（每次请求执行） ──
	// 顺序：请求计数 → 全局中间件（request_id + CORS + 请求日志）→ 限流
	web_app.use(veb.MiddlewareOptions[Context]{
		handler: fn [mut web_app](mut ctx Context) bool {
			web_app.req_count++

			if !isnil(web_app.middleware) {
				// 全局中间件：request_id 注入 logger MDC + CORS + 请求日志
				web_app.middleware.apply_global(mut ctx.Context) or {}

				// 限流：基于客户端 IP 的滑动窗口（60 次/分钟）
				ip := web.client_ip(&ctx.Context)
				web_app.middleware.apply_rate_limit(ip) or {
					ctx.res.set_status(.too_many_requests)
					ctx.send_response_to_client('application/json', '{"success":false,"code":429,"message":"rate limit exceeded / 请求过于频繁，请稍后重试"}')
					return false
				}
			}
			return true
		}
	})

	// ── 7. 注册 CLI 命令 ──
	mut cmd_app := cli.new_application(cfg.app.name, cfg.app.version)
	// 注册内置命令（serve/list/help）
	cmd_app.add_command(cli.new_serve_command())
	cmd_app.add_command(cli.new_list_command(cmd_app))
	cmd_app.add_command(cli.new_help_command(cmd_app))
	// 注册业务命令（migrate/seed/queue:scheduler/stats/routes 等）
	register_commands(mut cmd_app, boot)

	// ── 8. 运行 CLI（处理 list/help/serve 等命令） ──
	cmd_app.run() or {
		boot.log.error('CLI error: ${err}')
	}

	// ── 9. 决定是否启动 Web 服务 ──
	// 无参数或 'serve' 命令时启动；其他命令（list/help）执行后退出
	should_serve := os.args.len <= 1 || (os.args.len > 1 && os.args[1] == 'serve')
	if !should_serve {
		return
	}

	// ── 10. 扫描路由并打印路由表 ──
	routes := web.scan_controller[App]()
	web.print_routes(routes)
	boot.print_routes()

	// ── 11. 启动 HTTP 服务 ──
	port := cfg.server.port
	host := cfg.server.host
	boot.log.info('Starting HTTP server on ${host}:${port} ...')
	boot.log.info('Press Ctrl+C to stop')

	veb.run_at[App, Context](mut web_app, host: host, port: port, family: .ip) or {
		boot.log.error('Server failed: ${err}')
		panic(err)
	}
}

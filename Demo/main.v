module main

// main.v — PhotonBlog 应用入口
//
// 启动流程：
//   1. 加载 .env 文件（开发环境自动加载）
//   2. 读取 profile（APP_PROFILE 环境变量，默认 dev）
//   3. 加载配置（load_config）
//   4. 创建 AppKernel 并 bootstrap（ServiceProvider 装配）
//   5. 创建中间件组注册表（从 config/web.v 读取参数）
//   6. 创建 HTTP 内核（统一响应与异常处理）
//   7. 创建 App（线程安全 req_count）并注册全局中间件
//   8. 注册 CLI 命令并运行
//   9. 扫描路由并打印路由表
//  10. 启动 veb HTTP 服务

import os
import veb
import time
import sync
import photon.cli
import photon.web
import photon.apidoc

fn main() {
	// ── 1. 加载 .env 文件（开发环境） ──
	load_env_file('.env')

	// ── 2. 确定 profile ──
	profile := os.getenv('APP_PROFILE')
	actual_profile := if profile.len > 0 { profile } else { 'dev' }

	// ── 3. 加载配置 ──
	cfg := load_config(actual_profile) or {
		eprintln('Failed to load config (profile=${actual_profile}): ${err}')
		exit(1)
	}

	// ── 4. 创建 AppKernel 并 bootstrap ──
	kernel := new_app_kernel(cfg) or {
		eprintln('AppKernel creation failed: ${err}')
		exit(1)
	}
	kernel.bootstrap() or {
		eprintln('Bootstrap failed: ${err}')
		exit(1)
	}
	boot := kernel.to_bootstrap()
	boot.print_banner()

	// ── 5. 创建中间件组注册表（CORS/限流参数从 config/web.v 读取） ──
	middleware_registry := new_middleware_group_registry(cfg.web, boot.auth_svc, boot.role_hierarchy, boot.csrf_mgr, boot.log)

	// ── 6. 创建 HTTP 内核（统一响应与异常处理） ──
	http_kernel := new_http_kernel()

	// ── 7. 创建 App（线程安全 req_count） ──
	// apidoc_handler 仅在非生产环境启用（生产环境避免请求收集开销）
	apidoc_handler := if cfg.profile != 'prod' { apidoc.enable() } else { &apidoc.ApidocHandler(unsafe { nil }) }

	mut web_app := &App{
		start_time:          time.ticks()
		req_mu:              sync.new_mutex()
		bootstrap:           boot
		middleware_registry: middleware_registry
		http_kernel:         http_kernel
		apidoc_handler:      apidoc_handler
	}

	// ── 8. 注册全局中间件（每次请求执行） ──
	// 顺序：请求计数（互斥锁保护）→ api 组中间件（request_id + CORS + 请求日志 + 限流）
	web_app.use(veb.MiddlewareOptions[Context]{
		handler: fn [mut web_app](mut ctx Context) bool {
			// 线程安全递增请求计数（修复数据竞争）
			web_app.req_mu.@lock()
			web_app.req_count++
			web_app.req_mu.unlock()

			if !isnil(web_app.middleware_registry) {
				// api 组中间件：request_id 注入 + CORS + 请求日志 + 限流
				web_app.middleware_registry.apply_api_group(mut ctx) or {
					ctx.res.set_status(.too_many_requests)
					ctx.set_content_type('application/json')
					ctx.text(web.fail(429, 'rate limit exceeded / 请求过于频繁，请稍后重试').to_json())
					return false
				}
			}

			// apidoc 请求收集（非生产环境）
			if !isnil(web_app.apidoc_handler) {
				unsafe {
					mut h := web_app.apidoc_handler
					h.collector.collect(mut ctx.Context)
				}
			}
			return true
		}
	})

	// apidoc 响应收集（after middleware，非生产环境）
	if !isnil(apidoc_handler) {
		web_app.use(veb.MiddlewareOptions[Context]{
			after:   true
			handler: fn [apidoc_handler](mut ctx Context) bool {
				unsafe {
					mut h := apidoc_handler
					h.collector.collect_response(mut ctx.Context)
				}
				return true
			}
		})
	}

	// ── 9. 注册 CLI 命令 ──
	mut cmd_app := cli.new_application(cfg.app.name, cfg.app.version)
	// 注册内置命令（serve/list/help）
	cmd_app.add_command(cli.new_serve_command())
	cmd_app.add_command(cli.new_list_command(cmd_app))
	cmd_app.add_command(cli.new_help_command(cmd_app))
	// 注册业务命令（migrate/seed/queue:scheduler/stats/routes 等）
	register_commands(mut cmd_app, boot)

	// ── 10. 运行 CLI（处理 list/help/serve 等命令） ──
	cmd_app.run() or {
		boot.log.error('CLI error: ${err}')
	}

	// ── 11. 决定是否启动 Web 服务 ──
	// 无参数或 'serve' 命令时启动；其他命令（list/help）执行后退出
	should_serve := os.args.len <= 1 || (os.args.len > 1 && os.args[1] == 'serve')
	if !should_serve {
		return
	}

	// ── 12. 扫描路由并打印路由表 ──
	routes := web.scan_controller[App]()
	web.print_routes(routes)
	boot.print_routes()

	// ── 13. 启动 HTTP 服务 ──
	port := cfg.server.port
	host := cfg.server.host
	boot.log.info('Starting HTTP server on ${host}:${port} ...')
	boot.log.info('Press Ctrl+C to stop')

	veb.run_at[App, Context](mut web_app, host: host, port: port, family: .ip) or {
		boot.log.error('Server failed: ${err}')
		panic(err)
	}
}

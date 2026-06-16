module main

// main.v — Photon Web Application 入口
//
// 架构层次（从上到下）：
//
//   ┌──────────────────────────────────────┐
//   │  main.v      — 入口 + CLI 调度       │
//   ├──────────────────────────────────────┤
//   │  bootstrap.v — 配置 + 服务注册 + DI  │
//   ├──────────────────────────────────────┤
//   │  controllers.v — 控制器 + 路由注解   │
//   ├──────────────────────────────────────┤
//   │  middleware.v — 中间件链编排          │
//   ├──────────────────────────────────────┤
//   │  services.v  — 业务逻辑层             │
//   ├──────────────────────────────────────┤
//   │  models.v    — 数据模型 + DTO         │
//   └──────────────────────────────────────┘
//
// 编译运行：
//   v -enable-globals run example/main.v
// 或:
//   v -enable-globals -o bin/photon-api example/main.v
//
// 前置条件：
//   ln -sf $(pwd) ~/.vmodules/photon

import cli
import veb
import time
import web
import logger

// ═══════════════════════════════════════════════════════════
// App — 全局应用上下文（Spring Boot ApplicationContext 等价）
// ═══════════════════════════════════════════════════════════

pub struct App {
	veb.Context
pub mut:
	start_time i64
	req_count  int
	services   &ServiceRegistry = unsafe { nil }
	middleware  &MiddlewareManager = unsafe { nil }
	app_config &AppConfig = unsafe { nil }
	log_       &logger.Logger = unsafe { nil }
}

// Context — 请求级上下文（Spring Boot HttpServletRequest 等价）
pub struct Context {
	veb.Context
}

// ═══════════════════════════════════════════════════════════
// veb 生命周期钩子
// ═══════════════════════════════════════════════════════════

pub fn (mut app App) before_request(mut ctx Context) {
	app.req_count++
	app.middleware.apply_global(mut ctx.Context) or {}
}

pub fn (mut app App) after_request(mut ctx Context) {
	_ = ctx
}

// ═══════════════════════════════════════════════════════════
// 入口
// ═══════════════════════════════════════════════════════════

pub fn main() {
	// ── CLI Application ──
	mut cmd_app := cli.new_application('photon', '0.4.0')
	cmd_app.add_command(cli.new_serve_command())
	cmd_app.add_command(cli.new_list_command(cmd_app))
	cmd_app.add_command(cli.new_help_command(cmd_app))

	// ── Bootstrap: config -> logger -> cache -> services -> middleware ──
	boot := new_bootstrap() or {
		eprintln('Bootstrap failed: ${err}')
		panic(err)
	}
	boot.print_banner()

	// ── 装配 App 实例 ──
	mut web_app := &App{
		start_time: time.ticks()
		log_: boot.log_
		services: boot.services
		middleware: boot.middleware
		app_config: &boot.app_cfg
	}

	// ── CLI 命令调度 ──
	cmd_app.run() or { eprintln('CLI error: ${err}') }

	// ── 启动 HTTP 服务器 ──
	port := boot.app_cfg.server_port
	boot.log_.info('=== Starting HTTP server on 0.0.0.0:${port} ===')
	boot.print_routes()

	// 扫描并打印路由表
	routes := web.scan_controller[App]()
	web.print_routes(routes)

	// 启动 veb 服务器
	veb.run_at[App, Context](mut web_app, host: '0.0.0.0', port: port, family: .ip) or {
		panic(err)
	}
}

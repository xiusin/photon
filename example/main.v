module main

// main.v — Photon Web Application 入口

import cli
import veb
import time
import web
import logger
import apidoc

// App — 全局应用上下文
pub struct App {
	veb.Context
	apidoc.ApidocHandler // apidoc 自托管（一行嵌入）
pub mut:
	start_time i64
	req_count  int
	services   &ServiceRegistry = unsafe { nil }
	middleware  &MiddlewareManager = unsafe { nil }
	app_config &AppConfig = unsafe { nil }
	log_       &logger.Logger = unsafe { nil }
}

// Context — 请求级上下文
pub struct Context {
	veb.Context
}

// before_request — 应用级预处理钩子
pub fn (mut app App) before_request(mut ctx Context) {
	// apidoc: capture request metadata
	mut ve := unsafe { &ctx.Context }
	app.ApidocHandler.capture_request(mut ve)

	app.req_count++
	app.middleware.apply_global(mut ctx.Context) or {}
}

// after_request — 应用级后处理钩子
pub fn (mut app App) after_request(mut ctx Context) {
	mut ve := unsafe { &ctx.Context }
	app.ApidocHandler.capture_response(mut ve)
}

// main 入口
pub fn main() {
	mut cmd_app := cli.new_application('photon', '0.4.0')
	cmd_app.add_command(cli.new_serve_command())
	cmd_app.add_command(cli.new_list_command(cmd_app))
	cmd_app.add_command(cli.new_help_command(cmd_app))

	boot := new_bootstrap() or {
		eprintln('Bootstrap failed: ${err}')
		panic(err)
	}
	boot.print_banner()

	// 激活 apidoc（一行）
	apidoc_handler := apidoc.enable()
	boot.log_.info('API Documentation module ready')

	mut web_app := &App{
		start_time: time.ticks()
		log_: boot.log_
		services: boot.services
		middleware: boot.middleware
		app_config: &boot.app_cfg
		ApidocHandler: *apidoc_handler
	}

	cmd_app.run() or { eprintln('CLI error: ${err}') }

	port := boot.app_cfg.server_port
	boot.log_.info('=== Starting HTTP server on 0.0.0.0:${port} ===')
	boot.print_routes()

	routes := web.scan_controller[App]()
	web.print_routes(routes)

	veb.run_at[App, Context](mut web_app, host: '0.0.0.0', port: port, family: .ip) or {
		panic(err)
	}
}

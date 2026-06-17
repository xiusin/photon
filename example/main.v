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
	veb.Middleware[Context]
pub mut:
	start_time   i64
	req_count    int
	services     &ServiceRegistry = unsafe { nil }
	middleware   &MiddlewareManager = unsafe { nil }
	app_config   &AppConfig = unsafe { nil }
	log_         &logger.Logger = unsafe { nil }
	apidoc_handler &apidoc.ApidocHandler = unsafe { nil }
}

// Context — 请求级上下文
pub struct Context {
	veb.Context
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

	// 激活 apidoc
	mut apidoc_handler := apidoc.enable()
	boot.log_.info('API Documentation module ready')

	mut web_app := &App{
		start_time: time.ticks()
		log_: boot.log_
		services: boot.services
		middleware: boot.middleware
		app_config: &boot.app_cfg
		apidoc_handler: apidoc_handler
	}

	// 注册 apidoc middleware（自动劫持请求/响应采集）
	web_app.use(apidoc_handler.before_middleware[Context]())
	web_app.use(apidoc_handler.after_middleware[Context]())
	boot.log_.info('API Documentation middleware registered')

	// 注册全局应用 middleware（请求计数 + CORS + 日志）
	web_app.use(veb.MiddlewareOptions[Context]{
		handler: fn [mut web_app](mut ctx Context) bool {
			web_app.req_count++
			if !isnil(web_app.middleware) {
				web_app.middleware.apply_global(mut ctx.Context) or {}
			}
			return true
		}
	})

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
module main

// main.v — PhotonBlog 应用入口

import os
import veb
import time
import sync
import photon.cli
import photon.web
import photon.apidoc
import config
import bootstrap
import app.http.middleware
import app.http
import app.http.controllers

fn main() {
	// ── 1. 确定 profile ──
	profile := os.getenv('APP_PROFILE')
	actual_profile := if profile.len > 0 { profile } else { 'dev' }

	// ── 2. 加载配置（含 .env 文件） ──
	cfg := config.load_config_with_env(actual_profile) or {
		eprintln('Failed to load config (profile=${actual_profile}): ${err}')
		exit(1)
	}

	// ── 4. 创建 AppKernel 并 bootstrap ──
	mut kernel := bootstrap.new_app_kernel(cfg) or {
		eprintln('AppKernel creation failed: ${err}')
		exit(1)
	}
	kernel.bootstrap() or {
		eprintln('Bootstrap failed: ${err}')
		exit(1)
	}
	boot := kernel.to_bootstrap()
	bootstrap.print_banner()

	// ── 5. 创建中间件组注册表 ──
	middleware_registry := middleware.new_middleware_group_registry(cfg.web, boot.auth_svc, boot.role_hierarchy, boot.csrf_mgr, boot.log)

	// ── 6. 创建 HTTP 内核 ──
	http_kernel := http.new_http_kernel()

	// ── 7. 创建 App ──
	apidoc_handler := if cfg.profile != 'prod' { apidoc.enable() } else { &apidoc.ApidocHandler(unsafe { nil }) }
	start_time_ticks := time.ticks()

	mut web_app := &App{
		start_time:          start_time_ticks
		req_mu:              sync.new_mutex()
		bootstrap:           boot
		middleware_registry: middleware_registry
		http_kernel:         http_kernel
		apidoc_handler:      apidoc_handler
		// Laravel 风格控制器初始化
		system_ctrl: &controllers.SystemController{
			base: controllers.BaseController{bootstrap: boot, middleware_registry: middleware_registry}
			apidoc_handler: apidoc_handler
			start_time: start_time_ticks
		}
		auth_ctrl: &controllers.AuthController{
			base: controllers.BaseController{bootstrap: boot, middleware_registry: middleware_registry}
		}
		user_ctrl: &controllers.UserController{
			base: controllers.BaseController{bootstrap: boot, middleware_registry: middleware_registry}
		}
		post_ctrl: &controllers.PostController{
			base: controllers.BaseController{bootstrap: boot, middleware_registry: middleware_registry}
		}
		comment_ctrl: &controllers.CommentController{
			base: controllers.BaseController{bootstrap: boot, middleware_registry: middleware_registry}
		}
		category_ctrl: &controllers.CategoryController{
			base: controllers.BaseController{bootstrap: boot, middleware_registry: middleware_registry}
		}
		tag_ctrl: &controllers.TagController{
			base: controllers.BaseController{bootstrap: boot, middleware_registry: middleware_registry}
		}
		upload_ctrl: &controllers.UploadController{
			base: controllers.BaseController{bootstrap: boot, middleware_registry: middleware_registry}
		}
	}

	// ── 8. 注册全局中间件 ──
	web_app.use(veb.MiddlewareOptions[http.Context]{
		handler: fn [mut web_app](mut ctx http.Context) bool {
			web_app.req_mu.@lock()
			web_app.req_count++
			web_app.req_mu.unlock()

			if !isnil(web_app.middleware_registry) {
				request_id := web_app.middleware_registry.apply_api_group(mut ctx.Context) or {
					ctx.res.set_status(.too_many_requests)
					ctx.set_content_type('application/json')
					ctx.text(web.fail(429, 'rate limit exceeded / 请求过于频繁，请稍后重试').to_json())
					return false
				}
				ctx.request_id = request_id
			}

			if !isnil(web_app.apidoc_handler) {
				unsafe {
					mut h := web_app.apidoc_handler
					h.collector.collect(mut ctx.Context)
				}
			}
			return true
		}
	})

	// apidoc 响应收集
	if !isnil(apidoc_handler) {
		web_app.use(veb.MiddlewareOptions[http.Context]{
			after:   true
			handler: fn [apidoc_handler](mut ctx http.Context) bool {
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
	cmd_app.add_command(cli.new_serve_command())
	cmd_app.add_command(cli.new_list_command(cmd_app))
	cmd_app.add_command(cli.new_help_command(cmd_app))
	register_commands(mut cmd_app, boot)

	// ── 10. 运行 CLI ──
	cmd_app.run() or {
		boot.log.error('CLI error: ${err}')
	}

	// ── 11. 决定是否启动 Web 服务 ──
	should_serve := os.args.len <= 1 || (os.args.len > 1 && os.args[1] == 'serve')
	if !should_serve {
		return
	}

	// ── 12. 扫描路由并打印路由表 ──
	routes := web.scan_controller[App]()
	web.print_routes(routes)
	route_strs := routes.map(fn (r web.RouteInfo) string {
		return '${r.method}\t${r.path}\t${r.handler_name}'
	})
	bootstrap.print_routes(route_strs)

	// ── 13. 启动 HTTP 服务 ──
	port := cfg.server.port
	host := cfg.server.host
	boot.log.info('Starting HTTP server on ${host}:${port} ...')
	boot.log.info('Press Ctrl+C to stop')

	veb.run_at[App, http.Context](mut web_app, host: host, port: port, family: .ip) or {
		boot.log.error('Server failed: ${err}')
		panic(err)
	}
}

module main

// main.v — Photon Web Application 入口（DI 容器驱动，P0 7.1）
//
// 启动流程：
//   1. 创建 ApplicationContext（DI 容器）
//   2. bootstrap() 注册所有 Bean（配置、日志、缓存、服务、中间件）
//   3. ctx.refresh() 完成单例初始化与生命周期回调
//   4. ctx.resolve_typed[T]() 从容器获取 Bean，装配到 veb App
//   5. 启动 veb HTTP 服务器
//   6. 服务器退出后 ctx.shutdown() 优雅关闭
import cli
import veb
import time
import web
import logger
import apidoc
import core

// App — 全局应用上下文（veb 控制器，持有从 DI 容器解析的 Bean）
@[controller]
pub struct App {
	veb.Context
	veb.Middleware[Context]
pub mut:
	start_time i64
	req_count  int
	// 从 ApplicationContext 解析注入的服务（@[autowired] 标记注入意图）
	user_service   &UserService          = unsafe { nil }       @[autowired]
	auth_service   &AuthService          = unsafe { nil }       @[autowired]
	cache_service  &CacheService         = unsafe { nil }      @[autowired]
	health_service &HealthService        = unsafe { nil }     @[autowired]
	middleware     &MiddlewareManager    = unsafe { nil } @[autowired]
	app_config     &AppConfig            = unsafe { nil }         @[autowired]
	log_           &logger.Logger        = unsafe { nil }     @[autowired]
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

	// ── 1. 创建 DI 容器 ──
	mut ctx := core.new_application_context()

	// ── 2. Bootstrap：注册所有 Bean ──
	bootstrap(mut ctx) or {
		eprintln('Bootstrap failed: ${err}')
		ctx.shutdown()
		panic(err)
	}

	// ── 3. refresh()：初始化所有非懒加载单例、触发生命周期回调 ──
	ctx.refresh() or {
		eprintln('Context refresh failed: ${err}')
		ctx.shutdown()
		panic(err)
	}

	// ── 4. 从容器解析 Bean，装配到 veb App ──
	log_ := ctx.resolve_typed[logger.Logger]('Logger') or {
		ctx.shutdown()
		panic(err)
	}
	app_cfg := ctx.resolve_typed[AppConfig]('AppConfig') or {
		ctx.shutdown()
		panic(err)
	}
	user_svc := ctx.resolve_typed[UserService]('UserService') or {
		ctx.shutdown()
		panic(err)
	}
	auth_svc := ctx.resolve_typed[AuthService]('AuthService') or {
		ctx.shutdown()
		panic(err)
	}
	health_svc := ctx.resolve_typed[HealthService]('HealthService') or {
		ctx.shutdown()
		panic(err)
	}
	cache_svc := ctx.resolve_typed[CacheService]('CacheService') or {
		ctx.shutdown()
		panic(err)
	}
	mw := ctx.resolve_typed[MiddlewareManager]('MiddlewareManager') or {
		ctx.shutdown()
		panic(err)
	}

	print_banner(app_cfg)

	// 激活 apidoc
	mut apidoc_handler := apidoc.enable()
	log_.info('API Documentation module ready')

	mut web_app := &App{
		start_time:     time.ticks()
		log_:           log_
		user_service:   user_svc
		auth_service:   auth_svc
		cache_service:  cache_svc
		health_service: health_svc
		middleware:     mw
		app_config:     app_cfg
		apidoc_handler: apidoc_handler
	}

	// 注册 apidoc middleware（自动劫持请求/响应采集）
	web_app.use(apidoc_handler.before_middleware[Context]())
	web_app.use(apidoc_handler.after_middleware[Context]())
	log_.info('API Documentation middleware registered')

	// 注册全局应用 middleware（请求计数 + CORS + 日志）
	web_app.use(veb.MiddlewareOptions[Context]{
		handler: fn [mut web_app] (mut ctx2 Context) bool {
			web_app.req_count++
			if !isnil(web_app.middleware) {
				web_app.middleware.apply_global(mut ctx2.Context) or {}
			}
			return true
		}
	})

	cmd_app.run() or { eprintln('CLI error: ${err}') }

	port := app_cfg.server_port
	log_.info('=== Starting HTTP server on 0.0.0.0:${port} ===')
	print_routes()

	routes := web.scan_controller[App]()
	web.print_routes(routes)

	veb.run_at[App, Context](mut web_app, host: '0.0.0.0', port: port, family: .ip) or {
		eprintln('HTTP server error: ${err}')
		ctx.shutdown()
		panic(err)
	}

	// ── 6. 优雅关闭 DI 容器（触发 @[pre_destroy]、DisposableBean、有序关闭阶段） ──
	ctx.shutdown()
}

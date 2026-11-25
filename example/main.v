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
import photon.cli
import veb
import time
import photon.web
import photon.logger
import photon.apidoc
import photon.core

// App — 全局应用上下文（veb 控制器）
//
// 路由不再由 App 代持：每个控制器把自己的 veb 注解方法直接注册成路由，
// veb 在编译期扫描 App 自身方法生成路由表（veb.run_at[App, Context]）。
// 因此 App 上没有任何路由方法 —— 它只负责持有 Bean、挂中间件、跑服务。
//
// 分层：
//   - *_controller.v : @['/path'; get] 注解 + 业务处理（路由与逻辑同处一室）
//   - services.v     : 业务服务层
//   - middleware.v   : 横切中间件
@[controller]
pub struct App {
	veb.Context
	veb.Middleware[Context]
pub mut:
	start_time int
	req_count  int
	// 应用级依赖（全局中间件用）
	middleware &MiddlewareManager = unsafe { nil }
	log_       &logger.Logger     = unsafe { nil }
	// 控制器：各自持有依赖，路由注解就在它们自己的方法上
	home_controller   &HomeController   = unsafe { nil }
	auth_controller   &AuthController   = unsafe { nil }
	user_controller   &UserController   = unsafe { nil }
	apidoc_controller &ApiDocController = unsafe { nil }
}

// 全局请求计数：App 的全局中间件每请求 +1，HomeController 读同一个数。
// 用 __global 而不是让控制器持一个 &int —— 少一层间接就少一次 nil 崩溃的机会。
__global (
	g_req_count int
)

// app_req_count 读全局请求计数。is_globals_enabled() 先判一次：不带
// -enable-globals 编译时计数恒为 0，而不是一次非法访问。
fn app_req_count() int {
	if !is_globals_enabled() {
		return 0
	}
	return g_req_count
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

	start := time.ticks()

	// ── 5. 构造控制器（注入 service 依赖）──
	// 控制器各自持有自己的依赖和路由注解；App 只装载它们，
	// 不再像旧版那样再写一层转发方法把请求转给控制器。
	mut web_app := &App{
		middleware: mw
		log_:       log_
	}
	web_app.start_time = int(start)
	web_app.home_controller = new_home_controller(user_svc, cache_svc, health_svc, app_cfg, start)
	web_app.auth_controller = new_auth_controller(auth_svc, user_svc, mw)
	web_app.user_controller = new_user_controller(user_svc, mw)
	web_app.apidoc_controller = new_apidoc_controller(apidoc_handler)

	// 注册 apidoc middleware（自动劫持请求/响应采集）
	web_app.use(apidoc_handler.before_middleware[Context]())
	web_app.use(apidoc_handler.after_middleware[Context]())
	log_.info('API Documentation middleware registered')

	// 注册全局应用 middleware（请求计数 + CORS + 日志）
	web_app.use(veb.MiddlewareOptions[Context]{
		handler: fn [mut web_app] (mut ctx2 Context) bool {
			// web_app 要在同一个闭包里读两次（计数 + 全局中间件），
			// 所以捕获 mut 引用而不是拷贝一份。
			web_app.req_count++
			if is_globals_enabled() {
				g_req_count++
			}
			if !isnil(web_app.middleware) {
				web_app.middleware.apply_global(mut ctx2.Context) or {}
			}
			return true
		}
	})

	cmd_app.run() or { eprintln('CLI error: ${err}') }

	port := app_cfg.server_port
	log_.info('=== Starting HTTP server on 0.0.0.0:${port} ===')

	// 路由表来自编译期扫描：扫的是 App 自己的方法，路由注解就写在那些方法上。
	// 所以「加一条路由」和「路由表里出现一条」是同一件事，不需要谁去记得同步。
	web.print_routes(web.scan_controller[App]())

	veb.run_at[App, Context](mut web_app, host: '0.0.0.0', port: port, family: .ip) or {
		eprintln('HTTP server error: ${err}')
		ctx.shutdown()
		panic(err)
	}

	// ── 6. 优雅关闭 DI 容器（触发 @[pre_destroy]、DisposableBean、有序关闭阶段） ──
	ctx.shutdown()
}

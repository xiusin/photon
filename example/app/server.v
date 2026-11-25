module app

// server.v — Photon Web Application 启动逻辑（DI 容器驱动）
//
// 启动流程：
//   1. 创建 ApplicationContext（DI 容器）
//   2. bootstrap 注册所有 Bean（配置、日志、缓存、服务、中间件）
//   3. ctx.refresh() 完成单例初始化与生命周期回调
//   4. ctx.resolve_typed[T]() 从容器获取 Bean，装配控制器
//   5. init_app() 把控制器挂到 WebModule —— 路由注解在编译期被扫成路由表
//   6. 启动 veb HTTP 服务器
//   7. 服务器退出后 ctx.shutdown() 优雅关闭
//
// 这里没有一条路由方法。路由属于各自的控制器（controllers/），
// 「加一个接口」等于「在控制器里加一个带注解的方法」。
import app.bootstrap
import app.http
import app.state
import photon.cli
import veb
import time
import photon.web
import photon.logger
import photon.apidoc
import photon.core

// run 启动应用；example/main.v 只做一件事：import app + 调用 run()。
pub fn run() {
	mut cmd_app := cli.new_application('photon', '0.4.0')
	cmd_app.add_command(cli.new_serve_command())
	cmd_app.add_command(cli.new_list_command(cmd_app))
	cmd_app.add_command(cli.new_help_command(cmd_app))

	// ── 1. 创建 DI 容器 ──
	mut ctx := core.new_application_context()

	// ── 2. Bootstrap：注册所有 Bean ──
	bootstrap.bootstrap(mut ctx) or {
		eprintln('Bootstrap failed: ${err}')
		ctx.shutdown()
		panic(err)
	}

	// apidoc 处理器也作为 Bean 注册，供 ApiDocController 的 @[autowired] 注入。
	// refresh() 会冻结 BeanDefinition，所以必须在 refresh 之前注册。
	mut apidoc_handler := apidoc.enable()
	ctx.register_instance('ApidocHandler', voidptr(apidoc_handler)) or { panic(err) }

	// ── 3. refresh()：初始化所有非懒加载单例、触发生命周期回调 ──
	ctx.refresh() or {
		eprintln('Context refresh failed: ${err}')
		ctx.shutdown()
		panic(err)
	}

	// ── 4. 从容器解析 Bean，装配控制器 ──
	log_ := ctx.resolve_typed[logger.Logger]('Logger') or {
		ctx.shutdown()
		panic(err)
	}
	app_cfg := ctx.resolve_typed[bootstrap.AppConfig]('AppConfig') or {
		ctx.shutdown()
		panic(err)
	}
	bootstrap.print_banner(app_cfg)

	log_.info('API Documentation module ready')

	start := time.ticks()

	// ── 5. 控制器由容器创建并注入 @[autowired] 字段，然后挂载 ──
	// 路由注解在编译期被扫成路由表；这里不再手写构造函数与依赖装配。
	mut web_app := init_app(mut ctx, start)

	// 注册 apidoc middleware（自动劫持请求/响应采集）
	web_app.use(apidoc_handler.before_middleware[http.Context]())
	web_app.use(apidoc_handler.after_middleware[http.Context]())
	log_.info('API Documentation middleware registered')

	// 全局 middleware：路由分发 + 请求计数 + CORS + 访问日志
	//
	// 路由分发排在最前：命中就把响应写完（ctx.done），后面的中间件会被
	// veb 停掉；没命中返回 false 交给 veb 走 404。把分发放在这里而不是
	// before_request，是因为 veb 的 before_request 挂在 Context 上，
	// 而路由表在 App 里 —— 只有 App 侧的中间件闭包两边都够得着。
	web_app.use(veb.MiddlewareOptions[http.Context]{
		handler: fn [mut web_app] (mut ctx2 http.Context) bool {
			// web_app 要在同一个闭包里读两次（计数 + 全局中间件），
			// 所以捕获 mut 引用而不是拷贝一份。
			web_app.req_count++
			state.inc()
			if !isnil(web_app.middleware) {
				web_app.middleware.apply_global(mut ctx2.Context) or {}
			}
			// veb 约定：中间件写出响应后必须返回 false，告诉 veb「别再走路由表」。
			// 这里返回 true 会让 veb 继续跑 404 分支，把状态码覆盖成 404。
			return !web_app.web_module.handle_request(voidptr(&ctx2))
		}
	})

	cmd_app.run() or { eprintln('CLI error: ${err}') }

	port := app_cfg.server_port
	log_.info('=== Starting HTTP server on 0.0.0.0:${port} ===')

	// 路由表从各控制器自己扫出来：挂载用什么扫描，横幅就用什么扫描。
	// App 自己一条路由都没有（它只持 Bean），扫 App 只会得到一张空表。
	web.print_routes(app_routes())

	veb.run_at[App, http.Context](mut web_app, host: '0.0.0.0', port: port, family: .ip) or {
		eprintln('HTTP server error: ${err}')
		ctx.shutdown()
		panic(err)
	}

	// ── 6. 优雅关闭 DI 容器（触发 @[pre_destroy]、DisposableBean、有序关闭阶段） ──
	ctx.shutdown()
}

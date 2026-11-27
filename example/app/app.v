module app

// app.v — 应用装配（路由全部来自各控制器的注解，这里不写任何路由）
//
// 本文件只负责三件事：
//   1. 持有全局状态与中间件管理器
//   2. 把控制器挂到 WebModule —— 编译期扫描注解 → 路由表
//   3. 在请求进入时把路由表里命中的那条交给它自己执行
import app.controllers
import app.http
import app.middleware
import veb
import photon.web
import photon.core

// App — 全局应用状态
//
// 分层：App 只持 Bean 和中间件；路由属于各个控制器（见 controllers/）。
// 以前 App 上有一堆 @['/path'; get] 的转发方法，方法体都只有一行
// 转发到控制器 —— 那正是要清掉的东西。
//
// 控制器不放在 App 上：分发只认 web_module 里的路由表，
// 多存一份引用没有任何读取方，只会让装配代码变长。
pub struct App {
	veb.Context
	veb.Middleware[http.Context]
pub mut:
	web_module web.WebModule
	middleware &middleware.MiddlewareManager = unsafe { nil } @[qualifier('MiddlewareManager'); autowired]
	req_count  int
}

// mount_controllers 是控制器注册表 —— V 没有运行时反射，也没有
// comptime「列出包内所有类型」的能力，所以新增控制器必须在这里加一行。
// 除此之外，创建、@[autowired] 注入、路由挂载都由 wire_and_mount 完成。
fn (mut app App) mount_controllers(mut di_ctx core.ApplicationContext) {
	app.web_module.wire_and_mount[controllers.HomeController, http.Context](mut di_ctx) or {
		panic(err)
	}
	app.web_module.wire_and_mount[controllers.AuthController, http.Context](mut di_ctx) or {
		panic(err)
	}
	app.web_module.wire_and_mount[controllers.UserController, http.Context](mut di_ctx) or {
		panic(err)
	}
	app.web_module.wire_and_mount[controllers.ApiDocController, http.Context](mut di_ctx) or {
		panic(err)
	}
}

// init_app 创建 App：注入自身依赖 + 一次装载全部控制器。
//
// 没有 start_time 参数了：控制器的启动时刻来自容器里的 ProcessRuntime，
// 由 @[autowired] 注入。挂载这块现在只剩「列控制器」这一件事。
pub fn init_app(mut di_ctx core.ApplicationContext) &App {
	mut app := &App{
		web_module: web.init_web_module()
	}
	di_ctx.autowire_controller[App](app) or { panic(err) }
	app.mount_controllers(mut di_ctx)
	return app
}

// app_routes 返回启动横幅要打印的路由清单。
//
// 与真正挂载用的是同一套扫描（parse_route_attrs + @[prefix]），所以横幅上
// 看到的就是能访问到的。App 自身一条路由都没有，扫它只会得到空表。
pub fn app_routes() []web.RouteInfo {
	mut routes := []web.RouteInfo{}
	routes << web.scan_controller[controllers.HomeController]()
	routes << web.scan_controller[controllers.AuthController]()
	routes << web.scan_controller[controllers.UserController]()
	routes << web.scan_controller[controllers.ApiDocController]()
	routes.sort(a.path < b.path)
	return routes
}

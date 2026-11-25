module main

// app.v — 应用装配（路由全部来自各控制器的注解，这里不写任何路由）
//
// 本文件只负责三件事：
//   1. 持有全局状态与中间件管理器
//   2. 把控制器挂到 WebModule —— 编译期扫描注解 → 路由表
//   3. 在请求进入时把路由表里命中的那条交给它自己执行
import veb
import photon.web

// App — 全局应用状态
//
// 分层：App 只持 Bean 和中间件；路由属于各个控制器（见 *_controller.v）。
// 以前 App 上有一堆 `@['/path'; get]` 的转发方法，方法体都只有一行
// `return app.xxx_controller.yyy(mut ctx)` —— 那正是要清掉的东西。
pub struct App {
	veb.Context
	veb.Middleware[Context]
pub mut:
	web_module web.WebModule
	middleware &MiddlewareManager = unsafe { nil }
	req_count  int
}

// __global 请求计数器。
//
// 控制器方法签名是 veb 原生形态（只收 ctx），拿不到 App 的字段地址，
// 所以计数走全局量。Makefile / ci-test.sh 都带 -enable-globals。
__global (
	g_req_count int
)

// app_req_count 读取当前请求计数（控制器用它填响应体）
pub fn app_req_count() int {
	return g_req_count
}

// init_app 创建 App 并挂载全部控制器。
//
// 前缀直接写在路由注解里（示例要的是「一眼看到完整 URL」），所以这里用
// mount 就行 —— 它会去读 @[prefix]，没有就等于不拼前缀。
pub fn init_app(mw &MiddlewareManager, apidoc_handler &ApidocHandler, home_ctrl &HomeController,
	auth_ctrl &AuthController, user_ctrl &UserController) &App {
	mut app := &App{
		web_module: web.init_web_module()
		middleware: mw
	}
	// 一次 mount 一条：注解已经是完整路径，挂载点不需要再补任何东西。
	app.web_module.mount[HomeController, Context](home_ctrl)
	app.web_module.mount[AuthController, Context](auth_ctrl)
	app.web_module.mount[UserController, Context](user_ctrl)
	app.web_module.mount[ApidocController, Context](new_apidoc_controller(apidoc_handler))
	return app
}

// app_routes 返回启动横幅要打印的路由清单。
//
// 与真正挂载用的是同一套扫描（parse_route_attrs + @[prefix]），所以横幅上
// 看到的就是能访问到的。早先这里是手写清单，越改越旧，一度少列了整组
// /__docs 路由而没人发现。
pub fn app_routes() []web.RouteInfo {
	mut routes := []web.RouteInfo{}
	routes << web.scan_controller[HomeController]()
	routes << web.scan_controller[AuthController]()
	routes << web.scan_controller[UserController]()
	routes << web.scan_controller[ApidocController]()
	routes.sort(a.path < b.path)
	return routes
}

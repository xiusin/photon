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
import photon.logger
import photon.apidoc

// App — 全局应用状态
//
// 分层：App 只持 Bean 和中间件；路由属于各个控制器（见 controllers/）。
// 以前 App 上有一堆 @['/path'; get] 的转发方法，方法体都只有一行
// 转发到控制器 —— 那正是要清掉的东西。
//
// 控制器字段保留在 App 上，是为了「谁被装进了这个应用」一眼可见；
// 分发并不经过它们，路由表在 web_module 里。
pub struct App {
	veb.Context
	veb.Middleware[http.Context]
pub mut:
	web_module web.WebModule
	middleware &middleware.MiddlewareManager = unsafe { nil }
	log_       &logger.Logger                = unsafe { nil }
	start_time i64
	req_count  int
	// 控制器：各自持有依赖，路由注解就在它们自己的方法上
	home_controller   &controllers.HomeController   = unsafe { nil }
	auth_controller   &controllers.AuthController   = unsafe { nil }
	user_controller   &controllers.UserController   = unsafe { nil }
	apidoc_controller &controllers.ApiDocController = unsafe { nil }
}

// init_app 创建 App 并挂载全部控制器。
//
// 前缀直接写在路由注解里（示例要的是「一眼看到完整 URL」），所以这里用
// mount 就行 —— 它会去读 @[prefix]，没有就等于不拼前缀。
pub fn init_app(mw &middleware.MiddlewareManager, apidoc_handler &apidoc.ApidocHandler, home_ctrl &controllers.HomeController,
	auth_ctrl &controllers.AuthController, user_ctrl &controllers.UserController) &App {
	apidoc_ctrl := controllers.new_apidoc_controller(apidoc_handler)
	mut app := &App{
		web_module:        web.init_web_module()
		middleware:        mw
		home_controller:   home_ctrl
		auth_controller:   auth_ctrl
		user_controller:   user_ctrl
		apidoc_controller: apidoc_ctrl
	}
	// 一次 mount 一条：注解已经是完整路径，挂载点不需要再补任何东西。
	app.web_module.mount[controllers.HomeController, http.Context](home_ctrl)
	app.web_module.mount[controllers.AuthController, http.Context](auth_ctrl)
	app.web_module.mount[controllers.UserController, http.Context](user_ctrl)
	app.web_module.mount[controllers.ApiDocController, http.Context](apidoc_ctrl)
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

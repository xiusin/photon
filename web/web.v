module web

// web.v — Photon Web Module 核心（Spring WebMvc 等价）
//
// 架构概述：
//
//   1. WebModule（可嵌入结构体）
//      嵌入到 App 中，提供路由分发能力。
//      before_request 中调用 WebModule.handle_request()。
//
//   2. Controller（接口）
//      每个控制器是一个独立的 struct，通过 @[controller] 和 @[get/post] 注解。
//      mount_controller[T]() 编译期扫描并生成闭包处理器。
//
//   3. Router（路由注册表）
//      以 RouteHandler 闭包形式存储所有路由。
//      dispatch() 匹配 URL 路径并执行对应闭包。
//
// 使用示例（example/main.v）：
//
//   module main
//
//   pub struct App {
//       veb.Context
//       web.WebModule               // ← 嵌入 WebModule
//   }
//
//   pub struct Context {
//       veb.Context
//       app &App                    // ← App 反向引用
//   }
//
//   // 覆写 veb.Context.before_request()
//   pub fn (mut ctx Context) before_request() {
//       ctx.app.WebModule.handle_request(mut ctx) // 分发到控制器
//   }
//
//   pub fn main() {
//       mut app := &App{...}
//       app.WebModule.mount(&user_controller, '/api/v1')
//       veb.run_at[App, Context](mut app)
//   }
import veb

// WebModule — 可嵌入的 Web 模块
// 嵌入到 App 中，提供路由分发、控制器挂载、中间件链能力。
//
// 用法：
//   pub struct App {
//       veb.Context
//       web.WebModule
//   }
pub struct WebModule {
pub mut:
	router &RouteRegistry
}

// init_web_module 初始化 WebModule
pub fn init_web_module() WebModule {
	return WebModule{
		router: new_route_registry()
	}
}

// ============================================================
// 控制器挂载
// ============================================================

// register 注册控制器（实现 Controller 接口的 struct）
// 用法：
//   app.WebModule.register(&UserController{user_service: svc})
pub fn (mut wm WebModule) register(controller Controller) {
	controller.register_routes(mut wm.router)
}

// mount 是 register 的别名（保持 API 一致性）
pub fn (mut wm WebModule) mount(controller Controller) {
	wm.register(controller)
}

// ============================================================
// 路由分发（在 Context.before_request 中调用）
// ============================================================

// handle_request 从路由表中匹配并执行处理器
// 返回 true 表示已匹配并处理，false 表示无匹配
// 若已处理，ctx.done 会被设置为 true（由 ctx.text() 等触发）
//
// 用法：
//   pub fn (mut ctx Context) before_request() {
//       if ctx.app.WebModule.handle_request(mut ctx) {
//           return  // 已处理
//       }
//       // 未匹配，veb 会自动处理 404
//   }
pub fn (mut wm WebModule) handle_request(mut ctx veb.Context) bool {
	path := ctx.req.url
	method := ctx.req.method.str()
	return wm.router.dispatch(method, path, mut ctx)
}

// ============================================================
// 手动注册路由（无需控制器结构体）
// ============================================================

// get 注册 GET 路由
pub fn (mut wm WebModule) get(path string, handler RouteHandler) {
	wm.router.get(path, handler)
}

// post 注册 POST 路由
pub fn (mut wm WebModule) post(path string, handler RouteHandler) {
	wm.router.post(path, handler)
}

// put 注册 PUT 路由
pub fn (mut wm WebModule) put(path string, handler RouteHandler) {
	wm.router.put(path, handler)
}

// delete 注册 DELETE 路由
pub fn (mut wm WebModule) delete(path string, handler RouteHandler) {
	wm.router.delete(path, handler)
}

// patch 注册 PATCH 路由
pub fn (mut wm WebModule) patch(path string, handler RouteHandler) {
	wm.router.patch(path, handler)
}

// group 创建路由组
pub fn (mut wm WebModule) group(prefix string, cb fn (mut sub RouteRegistry)) {
	wm.router.group(prefix, cb)
}

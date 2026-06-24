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
import core

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

// ============================================================
// mount[T] — 编译期控制器挂载（Spring @RestController + 组件扫描等价）
// ============================================================
//
// mount[T] 扫描控制器类型 T 的方法，为每个带 HTTP 路由注解的方法
// 生成包装闭包并注册到路由表。控制器可定义在任意包中。
//
// 与 register(controller Controller) 的区别：
//   - register(controller) 需要控制器实现 Controller 接口（手动注册路由）
//   - mount[T] 通过编译期注解扫描自动注册路由（声明式）
//
// 用法：
//   mut wm := init_web_module()
//   mut ctx := core.new_application_context()
//   wm.mount[UserController](mut ctx)
//   wm.mount[OrderController](mut ctx, MountOptions{prefix: '/api/v2'})

// mount 扫描控制器类型 T 并注册其路由
// opts 可指定额外路径前缀与中间件；无选项时传 MountOptions{} 即可
//
// 用法：
//   wm.mount[UserController](mut ctx, MountOptions{})
//   wm.mount[OrderController](mut ctx, MountOptions{prefix: '/api/v2'})
pub fn (mut wm WebModule) mount[T](mut ctx core.ApplicationContext, opts MountOptions) {
	wm.router.mount[T](mut ctx, opts)
}

// ============================================================
// 路由分发（在 Context.before_request 中调用）
// ============================================================

// handle_request 从路由表中匹配并执行处理器
// 返回 true 表示已匹配并处理，false 表示无匹配。
//
// 响应就绪标志同步：mount[T] 注册的控制器在嵌入的 veb.Context 副本上
// 写入响应（ctx.text() 等会设置副本的 done=true），copy_controller_response
// 通过整结构赋值将 done 标志同步回原始请求上下文，使 veb 在 before_request
// 返回后能识别响应已就绪并提前返回（不再走 veb 自带的路由匹配）。
//
// 用法（完整 before_request 模式）：
//   pub struct App {
//       veb.Context
//       web.WebModule
//   }
//   pub struct Context {
//       veb.Context
//       app &App
//   }
//   // 覆写 before_request：将请求分发到挂载的控制器
//   pub fn (mut ctx Context) before_request() {
//       // handle_request 返回 true 表示已匹配并处理；
//       // 此时 ctx.done 已被设为 true，veb 会直接发送响应
//       ctx.app.WebModule.handle_request(mut ctx)
//   }
//   pub fn main() {
//       mut app := &App{...}
//       mut ctx := core.new_application_context()
//       app.WebModule.mount[UserController](mut ctx, MountOptions{prefix: '/api'})
//       veb.run_at[App, Context](mut app)
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

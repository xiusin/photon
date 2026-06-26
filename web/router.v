module web

// router.v — Photon 路由注册表（Spring WebMvc 等价）
//
// 支持两种注册方式：
//   1. 手动注册：router.get('/path', handler)
//   2. 自动挂载：router.mount[T](&controller, prefix)  ← 编译期扫描注解
//
// 每个路由存储一个闭包处理器，在 before_request 中按路径调度。
import veb

// ═══════════════════════════════════════════════════════════
// 旧版 RouteInfo（向后兼容，用于 actuator introspection）
// ═══════════════════════════════════════════════════════════

// RouteInfo describes a single route (legacy, for introspection/debug output)
pub struct RouteInfo {
pub:
	method       string   // HTTP method: GET, POST, PUT, DELETE, PATCH
	path         string   // Route path: /users/:id
	handler_name string   // Method name
	middlewares  []string // Middleware names to apply
}

// scan_controller uses comptime to scan a controller for route attributes.
// Returns RouteInfo for display/debugging (does NOT register routes).
pub fn scan_controller[T]() []RouteInfo {
	mut routes := []RouteInfo{}

	$for method in T.methods {
		mut found_route := false
		mut http_method := ''
		mut path := ''

		// Check for HTTP method attributes (annotation-based)
		for attr in method.attrs {
			if attr == 'get' || attr == 'post' || attr == 'put' || attr == 'delete'
				|| attr == 'patch' {
				http_method = attr.to_upper()
				found_route = true
			}
			if attr.starts_with('/') {
				path = attr
			}
		}

		// Convention-based: methods returning veb.Result are routes
		$if method.return_type is veb.Result {
			if !found_route {
				http_method = 'GET'
				found_route = true
			}
		}

		if found_route {
			name := method.name
			// Skip lifecycle hooks
			if name != 'before_request' && name != 'after_request' {
				if path.len == 0 {
					if name == 'index' {
						path = '/'
					} else {
						path = '/${name}'
					}
				}
				mut middlewares := []string{}
				mut collecting := false
				for attr in method.attrs {
					if attr == 'middleware' {
						collecting = true
						continue
					}
					if collecting {
						trimmed := attr.trim_space().trim("'").trim('"')
						if trimmed.len > 0 && trimmed[0] != `/` {
							middlewares << trimmed
							continue
						}
						collecting = false
					}
				}
				routes << RouteInfo{
					method:       http_method
					path:         path
					handler_name: name
					middlewares:  middlewares
				}
			}
		}
	}
	return routes
}

// print_routes prints all registered routes in a clean table format
pub fn print_routes(routes []RouteInfo) {
	if routes.len == 0 {
		return
	}
	println('')
	println('  Registered Routes:')
	println('  ${'─'.repeat(60)}')
	println('  ${'METHOD':-8s} ${'PATH':-30s} ${'HANDLER'}')
	println('  ${'─'.repeat(60)}')
	for route in routes {
		println('  ${route.method:-8s} ${route.path:-30s} ${route.handler_name}')
	}
	println('  ${'─'.repeat(60)}')
	println('  Total: ${routes.len} route(s)')
	println('')
}

// print_registered_routes scans a controller type and prints all its routes
pub fn print_registered_routes[T]() {
	routes := scan_controller[T]()
	print_routes(routes)
}

// ═══════════════════════════════════════════════════════════
// 新版路由系统
// ═══════════════════════════════════════════════════════════

// RouteRegistry — 路由注册表（@[heap] 确保指针安全跨模块传递）
@[heap]
pub struct RouteRegistry {
pub mut:
	routes []&RouteDef
}

// new_route_registry 创建路由注册表
pub fn new_route_registry() &RouteRegistry {
	return &RouteRegistry{}
}

// register 注册一条路由（带闭包处理器）
pub fn (mut rr RouteRegistry) register(method string, path string, handler RouteHandler) {
	rr.routes << &RouteDef{
		method:   method
		path:     path
		handler:  handler
		segments: parse_path(path)
	}
}

// register_with_host 注册一条带 host 限制的路由。
// 只有当请求的 Host 头匹配 host 参数时，路由才会匹配。
// host 为空字符串时等同于 register()。
//
// 桥接 veb.controller_host() 的 host 级路由隔离能力。
//
// 用法：
//   rr.register_with_host('GET', '/api/admin', handler, 'admin.example.com')
pub fn (mut rr RouteRegistry) register_with_host(method string, path string, handler RouteHandler, host string) {
	rr.routes << &RouteDef{
		method:   method
		path:     path
		handler:  handler
		segments: parse_path(path)
		host:     host.to_lower()
	}
}

// register_with_middleware 注册一条路由，附带路由级中间件和可选 host 限制。
// 路由级中间件仅在匹配该路由时执行，不影响其他路由。
//
// 执行顺序：全局前置 → 路由前置 → handler → 路由后置 → 全局后置
//
// 用法：
//   rr.register_with_middleware('GET', '/api/admin', handler, [auth_middleware, role_middleware], [audit_middleware])
//   // 带 host 限制：
//   rr.register_with_middleware('GET', '/api/admin', handler, [auth_middleware], [], 'admin.example.com')
pub fn (mut rr RouteRegistry) register_with_middleware(method string, path string, handler RouteHandler, middlewares []MiddlewareFunc, after_middlewares []MiddlewareFunc, host string) {
	rr.routes << &RouteDef{
		method:            method
		path:              path
		handler:           handler
		segments:          parse_path(path)
		middlewares:       middlewares
		after_middlewares: after_middlewares
		host:              host.to_lower()
	}
}

// ============================================================
// 便捷方法（手动注册）
// ============================================================

// get 注册 GET 路由
pub fn (mut rr RouteRegistry) get(path string, handler RouteHandler) {
	rr.register('GET', path, handler)
}

// post 注册 POST 路由
pub fn (mut rr RouteRegistry) post(path string, handler RouteHandler) {
	rr.register('POST', path, handler)
}

// put 注册 PUT 路由
pub fn (mut rr RouteRegistry) put(path string, handler RouteHandler) {
	rr.register('PUT', path, handler)
}

// delete 注册 DELETE 路由
pub fn (mut rr RouteRegistry) delete(path string, handler RouteHandler) {
	rr.register('DELETE', path, handler)
}

// patch 注册 PATCH 路由
pub fn (mut rr RouteRegistry) patch(path string, handler RouteHandler) {
	rr.register('PATCH', path, handler)
}

// ============================================================
// 路由组
// ============================================================

// group 创建共享前缀的路由组
pub fn (mut rr RouteRegistry) group(prefix string, cb fn (mut sub RouteRegistry)) {
	mut sub := new_route_registry()
	cb(mut sub)
	for route in sub.routes {
		rr.register(route.method, prefix + route.path, route.handler)
	}
}

// ============================================================
// 控制器路由注册（Controller 接口）
// ============================================================

// mount_controller 为 Controller.register_routes() 的别名
pub fn mount_controller(mut rr RouteRegistry, controller Controller) {
	controller.register_routes(mut rr)
}

// Controller — 控制器接口
// 实现此接口的 struct 可以通过 register_controller() 注册路由。
//
// 用法：
//   struct UserController {
//       web.BaseController
//       user_service &UserService
//   }
//   pub fn (c &UserController) register_routes(mut r web.RouteRegistry) {
//       r.get('/users', fn [c] (mut ctx veb.Context, p map[string]string) veb.Result {
//           return c.list(mut ctx, p)
//       })
//   }
//
//   // 注册：
//   app.WebModule.register(&UserController{...})
pub interface Controller {
	register_routes(mut router RouteRegistry)
}

// ============================================================
// 分发
// ============================================================

// dispatch 在路由表中查找并执行匹配的处理器
// 返回 true 表示已处理（请求发送完成），false 表示未匹配
// ctx_ptr 是上下文指针（voidptr），支持任意嵌入 veb.Context 的自定义 Context 类型
// 在 handle_request 中从 veb.Context 转换而来
//
// 注意：此方法不执行中间件。如需中间件支持，请使用 dispatch_with_chain()。
// host 参数用于 host 级路由隔离（空字符串 = 不限制）。
pub fn (rr &RouteRegistry) dispatch(method string, url_path string, host string, ctx_ptr voidptr) bool {
	route, params := find_route(rr.routes, method, url_path, host) or {
		return false
	}
	route.handler(ctx_ptr, params)
	return true
}

// dispatch_with_chain 在路由表中查找并执行匹配的处理器，
// 同时执行全局中间件链和路由级中间件。
//
// 执行顺序：
//   1. 全局前置中间件（chain.middlewares）
//   2. 路由级前置中间件（route.middlewares）
//   3. 路由 handler
//   4. 路由级后置中间件（route.after_middlewares）
//   5. 全局后置中间件（chain.after_middlewares）
//
// 如果前置中间件返回 false 或出错，handler 不会执行（短路）。
// 后置中间件错误不会阻止后续后置中间件执行。
//
// host 参数用于 host 级路由隔离（空字符串 = 不限制）。
//
// 用法：
//   wm.router.dispatch_with_chain(method, path, host, ctx_ptr, wm.chain)
pub fn (rr &RouteRegistry) dispatch_with_chain(method string, url_path string, host string, ctx_ptr voidptr, chain &MiddlewareChain) bool {
	route, params := find_route(rr.routes, method, url_path, host) or {
		return false
	}

	mut mctx := new_middleware_context(unsafe { &veb.Context(ctx_ptr) })
	mctx.route_path = url_path
	mctx.route_method = method

	// 1. 执行全局前置中间件
	if chain.len() > 0 {
		allowed := chain.execute(mctx) or {
			eprintln('[middleware] before-chain error: ${err}')
			false
		}
		if !allowed {
			return true // 中间件短路，响应已发送
		}
	}

	// 2. 执行路由级前置中间件
	for mw in route.middlewares {
		allowed := mw(mctx) or {
			eprintln('[middleware] route before-middleware error: ${err}')
			false
		}
		if !allowed {
			return true // 中间件短路
		}
	}

	// 3. 执行路由 handler
	route.handler(ctx_ptr, params)

	// 4. 执行路由级后置中间件
	for mw in route.after_middlewares {
		mw(mctx) or {
			eprintln('[middleware] route after-middleware error: ${err}')
			continue
		}
	}

	// 5. 执行全局后置中间件
	if chain.after_len() > 0 {
		chain.execute_after(mctx) or {
			eprintln('[middleware] after-chain error: ${err}')
		}
	}

	return true
}

// route_count 返回注册的路由数
pub fn (rr &RouteRegistry) route_count() int {
	return rr.routes.len
}

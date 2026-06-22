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

// RouteRegistry — 路由注册表
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
pub fn (rr &RouteRegistry) dispatch(method string, url_path string, mut ctx veb.Context) bool {
	route, params := find_route(rr.routes, method, url_path) or {
		return false
	}
	route.handler(mut ctx, params)
	return true
}

// route_count 返回注册的路由数
pub fn (rr &RouteRegistry) route_count() int {
	return rr.routes.len
}

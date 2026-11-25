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
	controller   string   // 控制器类型名（横幅上看出这条路由归谁管）
	middlewares  []string // Middleware names to apply
}

// scan_controller uses comptime to scan a controller for route attributes.
// Returns RouteInfo for display/debugging (does NOT register routes).
pub fn scan_controller[T]() []RouteInfo {
	mut routes := []RouteInfo{}
	// 控制器前缀（@[prefix: '/api/v1']）。mount_controller 挂载时会拼上它，
	// 这里不拼就会让「启动横幅 / actuator /mappings 显示的路径」和
	// 「真正能被访问到的路径」差一段前缀 —— 排查 404 时最误导人的那种差。
	prefix := extract_controller_prefix[T]()

	$for method in T.methods {
		// 三种写法都要认：
		//   分离式  @[get]  @['/users']  → attrs = ['get', '/users']
		//   合并式  @[get: '/users']     → attrs = ["get: '/users'"]
		//   元组式  @['/users'; get]     → attrs = ['/users', 'get']
		// 早先只认前两种，合并式被整条漏掉：mount_controller 明明用的是
		// 同一套 parse_route_attrs（它认三种），于是出现「路由能挂上、
		// 启动横幅和 actuator /mappings 里却一条都没有」的错位。
		mut found_route := false
		mut http_method := ''
		mut path := ''
		if route_attr := parse_route_attrs(method.name, method.attrs) {
			found_route = true
			http_method = route_attr.method
			path = route_attr.path
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
				// 默认路径：index → /，其余 → /方法名。
				// 两种来路都会走到这里：显式写了 @[get] 但没写路径，以及
				// 完全靠约定（返回 veb.Result 即路由）判出来的方法 ——
				// 后者的 path 从来没人填过，不补就会漏成空串。
				if path.len == 0 {
					if name == 'index' {
						path = '/'
					} else {
						path = '/${name}'
					}
				}
				// 前缀拼接走 join_route_path：mount_controller 用的是同一个
				// 函数，两边才会给出同一条路径（横幅少个斜杠、多个斜杠都算错）。
				if prefix.len > 0 {
					path = join_route_path(prefix, path)
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
					controller:   T.name
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
	println('  ${'METHOD':-8s} ${'PATH':-30s} HANDLER')
	println('  ${'─'.repeat(60)}')
	for route in routes {
		handler := if route.controller.len > 0 {
			'${route.controller}.${route.handler_name}'
		} else {
			route.handler_name
		}
		println('  ${route.method:-8s} ${route.path:-30s} ${handler}')
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
//
// 索引结构（注册时由 add_route 维护）：
//   static_routes: 全静态路由哈希表，键为 method:host:path，O(1) 精确匹配
//   param_routes:  含 :param 的路由按段数分桶，仅与同段数 URL 比较
@[heap]
pub struct RouteRegistry {
pub mut:
	routes        []&RouteDef
	static_routes map[string]&RouteDef
	param_routes  map[int][]&RouteDef
}

// new_route_registry 创建路由注册表
pub fn new_route_registry() &RouteRegistry {
	return &RouteRegistry{
		static_routes: map[string]&RouteDef{}
		param_routes:  map[int][]&RouteDef{}
	}
}

// add_route 将路由定义加入注册表，并维护静态/参数索引。
// 全静态路由进入 static_routes 哈希表（O(1) 查找）；
// 含 :param 的路由按段数进入 param_routes 分桶列表（桶内保持注册顺序）。
fn (mut rr RouteRegistry) add_route(def &RouteDef) {
	// static_count 是参数路由之间的「具体程度」排序依据，只在注册期算一次，
	// 匹配路径上不再重复遍历 segments（见 static_segment_score）。
	mut has_params := false
	route := &RouteDef{
		...def
		static_count: static_segment_score_of(def.segments)
	}
	for seg in route.segments {
		if seg.is_param {
			has_params = true
			break
		}
	}

	rr.routes << route

	if has_params {
		n := route.segments.len
		mut bucket := rr.param_routes[n] or { []&RouteDef{} }
		bucket << route
		rr.param_routes[n] = bucket
	} else {
		key := route_static_key(route.method, route.host, route.path)
		// 先注册者优先（与旧线性扫描的首匹配语义一致）
		if key !in rr.static_routes {
			rr.static_routes[key] = route
		}
	}
}

// register 注册一条路由（带闭包处理器）
pub fn (mut rr RouteRegistry) register(method string, path string, handler RouteHandler) &RouteRegistry {
	rr.add_route(&RouteDef{
		method:   method
		path:     path
		handler:  handler
		segments: parse_path(path)
	})
	return rr
}

// register_with_host 注册一条带 host 限制的路由。
// 只有当请求的 Host 头匹配 host 参数时，路由才会匹配。
// host 为空字符串时等同于 register()。
//
// 桥接 veb.controller_host() 的 host 级路由隔离能力。
//
// 用法：
//   rr.register_with_host('GET', '/api/admin', handler, 'admin.example.com')
pub fn (mut rr RouteRegistry) register_with_host(method string, path string, handler RouteHandler, host string) &RouteRegistry {
	rr.add_route(&RouteDef{
		method:   method
		path:     path
		handler:  handler
		segments: parse_path(path)
		host:     host.to_lower()
	})
	return rr
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
pub fn (mut rr RouteRegistry) register_with_middleware(method string, path string, handler RouteHandler, middlewares []MiddlewareFunc, after_middlewares []MiddlewareFunc, host string) &RouteRegistry {
	rr.add_route(&RouteDef{
		method:            method
		path:              path
		handler:           handler
		segments:          parse_path(path)
		middlewares:       middlewares
		after_middlewares: after_middlewares
		host:              host.to_lower()
	})
	return rr
}

// ============================================================
// 便捷方法（手动注册）— 返回 &RouteRegistry 支持链式��用
// ============================================================

// get 注册 GET 路由
pub fn (mut rr RouteRegistry) get(path string, handler RouteHandler) &RouteRegistry {
	rr.register('GET', path, handler)
	return rr
}

// post 注册 POST 路由
pub fn (mut rr RouteRegistry) post(path string, handler RouteHandler) &RouteRegistry {
	rr.register('POST', path, handler)
	return rr
}

// put 注册 PUT 路由
pub fn (mut rr RouteRegistry) put(path string, handler RouteHandler) &RouteRegistry {
	rr.register('PUT', path, handler)
	return rr
}

// delete 注册 DELETE 路由
pub fn (mut rr RouteRegistry) delete(path string, handler RouteHandler) &RouteRegistry {
	rr.register('DELETE', path, handler)
	return rr
}

// patch 注册 PATCH 路由
pub fn (mut rr RouteRegistry) patch(path string, handler RouteHandler) &RouteRegistry {
	rr.register('PATCH', path, handler)
	return rr
}

// ============================================================
// 路由组
// ============================================================

// group 创建共享前缀的路由组。返回 &RouteRegistry 支持链式调用。
//
// 组内路由是整体搬进父注册表的，不是重新 register() 一遍：
// register() 只认识 method/path/handler，会把 register_with_middleware()
// 挂上的路由级中间件和 register_with_host() 的 host 限制一起丢掉 ——
// 组里的鉴权中间件就此静默失效，请求照常打进 handler。
pub fn (mut rr RouteRegistry) group(prefix string, cb fn (mut sub RouteRegistry)) &RouteRegistry {
	mut sub := new_route_registry()
	cb(mut sub)
	for route in sub.routes {
		path := prefix + route.path
		rr.add_route(&RouteDef{
			method:            route.method
			path:              path
			handler:           route.handler
			segments:          parse_path(path)
			middlewares:       route.middlewares
			after_middlewares: route.after_middlewares
			host:              route.host
		})
	}
	return rr
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
	route, params := find_route(rr, method, url_path, host) or { return false }
	store_path_params(ctx_ptr, params)
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
	route, params := find_route(rr, method, url_path, host) or { return false }

	mut mctx := new_middleware_context(unsafe { &veb.Context(ctx_ptr) })
	mctx.route_path = url_path
	mctx.route_method = method

	// 路径参数在匹配时就切好了，直接交给 ctx：控制器方法用的是 veb 原生
	// 签名（收不到 map），取参数只能靠 ctx.path('id')。挂在这里而不是在
	// mount 的闭包里，是因为路由级中间件也该看得到它们。
	store_path_params(ctx_ptr, params)

	// 前置中间件短路后，后置中间件仍然要跑。
	//
	// 后置中间件不是「handler 的收尾」，而是「响应的收尾」——CORS 头、
	// 压缩、耗时统计都是在这一步挂到 ctx.res 上的。短路路径（鉴权失败
	// 发的 401、CORS 预检发的空响应）同样是一条真实响应，跳过它们的结果
	// 就是：401 没有 CORS 头，浏览器把本该看到的错误信息拦成不透明失败；
	// 预检响应缺 Access-Control-Allow-*，整个跨域请求直接失败。
	//
	// 顺序不变：短路时不执行 handler，但仍按「路由级 → 全局」跑完后置链。
	mut short_circuited := false

	// 1. 执行全局前置中间件
	if chain.len() > 0 {
		allowed := chain.execute(mctx) or {
			eprintln('[middleware] before-chain error: ${err}')
			false
		}
		if !allowed {
			short_circuited = true
		}
	}

	// 2. 执行路由级前置中间件
	if !short_circuited {
		for mw in route.middlewares {
			allowed := mw(mctx) or {
				eprintln('[middleware] route before-middleware error: ${err}')
				false
			}
			if !allowed {
				short_circuited = true
				break
			}
		}
	}

	// 3. 执行路由 handler
	if !short_circuited {
		route.handler(ctx_ptr, params)
	}

	// 4. 执行路由级后置中间件
	for mw in route.after_middlewares {
		mw(mctx) or {
			eprintln('[middleware] route after-middleware error: ${err}')
			continue
		}
	}

	// 5. 执行全局后置中间件
	if chain.after_len() > 0 {
		chain.execute_after(mctx) or { eprintln('[middleware] after-chain error: ${err}') }
	}

	return true
}

// route_count 返回注册的路由数
pub fn (rr &RouteRegistry) route_count() int {
	return rr.routes.len
}

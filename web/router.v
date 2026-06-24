module web

// router.v — Photon 路由注册表（Spring WebMvc 等价）
//
// 支持两种注册方式：
//   1. 手动注册：router.get('/path', handler)
//   2. 自动挂载：router.mount[T](&controller, prefix)  ← 编译期扫描注解
//
// 每个路由存储一个闭包处理器，在 before_request 中按路径调度。
import veb
import core

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
	routes       []&RouteDef
	mw_registry  &MiddlewareRegistry = unsafe { nil } // 命名中间件注册表
}

// new_route_registry 创建路由注册表（含中间件注册表）
pub fn new_route_registry() &RouteRegistry {
	return &RouteRegistry{
		mw_registry: new_middleware_registry()
	}
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

// register_with_middleware 注册一条带中间件名的路由
// middlewares 为中间件名列表，分发时按顺序执行；任一返回 false 则中止。
pub fn (mut rr RouteRegistry) register_with_middleware(method string, path string, handler RouteHandler, middlewares []string) {
	rr.routes << &RouteDef{
		method:      method
		path:        path
		handler:     handler
		segments:    parse_path(path)
		middlewares: middlewares
	}
}

// use_middleware 注册一个命名路由中间件到注册表
// 用法：rr.use_middleware('auth', fn (mut ctx veb.Context) bool { ... })
pub fn (mut rr RouteRegistry) use_middleware(name string, mw RouteMiddleware) {
	rr.mw_registry.register(name, mw)
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
// 返回 true 表示已处理（请求发送完成），false 表示未匹配。
// 执行顺序：路由级中间件（按注册顺序）→ 处理器。
// 任一中间件返回 false 则中止（中间件应已自行写入响应），仍返回 true。
pub fn (rr &RouteRegistry) dispatch(method string, url_path string, mut ctx veb.Context) bool {
	route, params := find_route(rr.routes, method, url_path) or { return false }
	// 执行路由级中间件
	if route.middlewares.len > 0 && !isnil(rr.mw_registry) {
		for mw_name in route.middlewares {
			// 直接 map 成员检查，避免函数类型 optional 的 codegen 问题
			if mw_name in rr.mw_registry.middlewares {
				mw := rr.mw_registry.middlewares[mw_name]
				if !mw(mut ctx) {
					// 中间件中止请求（已自行写入响应）
					return true
				}
			}
		}
	}
	route.handler(mut ctx, params)
	return true
}

// route_count 返回注册的路由数
pub fn (rr &RouteRegistry) route_count() int {
	return rr.routes.len
}

// ═══════════════════════════════════════════════════════════
// mount[T] — 编译期控制器挂载（Spring @RestController + 组件扫描等价）
// ═══════════════════════════════════════════════════════════
//
// mount[T] 扫描控制器类型 T 的方法，为每个带 HTTP 路由注解的方法
// 生成包装闭包并注册到路由表。这使得控制器可以定义在任意包中，
// 而不必全部放在传给 veb.run_at[A, X] 的单个 App 结构体上。
//
// 设计决策（基于 V 0.5.1 comptime 能力测试）：
//   1. field.offset 不可用 → 无法用 unsafe 指针算术注入字段
//   2. v.reflection 模块会导致编译器 panic → 不可用
//   3. typeof(ctrl.$(field.name)).name 可获取字段类型名字符串 ✓
//   4. unsafe { ctrl.$(field.name) = voidptr值 } 可直接赋值指针字段 ✓
//   5. $if field.typ is veb.Context 可检测嵌入的 Context 字段 ✓
//   6. $for attr in T.attributes 可扫描 struct 级别注解 ✓
//
// V 0.5.1 comptime 限制：闭包内无法访问 $for method 变量，
// 因此方法调用通过顶层泛型函数 dispatch_route_method[T] 完成
// （与 core.dispatch_scheduled_method[T] 模式相同）。

// MountOptions — 挂载控制器时的选项
pub struct MountOptions {
pub:
	prefix      string   // 额外路径前缀（与 @[group] 前缀拼接）
	middlewares []string // 应用于该控制器所有路由的中间件名
}

// extract_group_prefix 从 T 的 struct 级别注解中提取 @[group('/prefix')] 前缀
// 返回去引号后的前缀字符串，如 '/api/v1'；无注解时返回空字符串
fn extract_group_prefix[T]() string {
	mut prefix := ''
	$for attr in T.attributes {
		if attr.name == 'group' {
			$if attr.has_arg {
				prefix = attr.arg.trim("'").trim('"').trim_space()
			}
		}
	}
	return prefix
}

// dispatch_route_method 在 comptime 上下文中调用控制器方法。
// V 0.5.1 限制：闭包内无法访问 $for method 变量，必须用顶层泛型函数。
// 运行时通过 method_name 字符串匹配，编译期 $for 循环为每个方法生成一个分支。
//
// 支持三种返回类型（Task A5）：
//   1. veb.Result      — 直接返回方法结果（$if 分支）
//   2. !veb.Result     — 作为语句调用；成功时方法已写响应，失败时补写 500（$else 分支）
//   3. !               — 同 !veb.Result（$else 分支）
//
// V 0.5.1 comptime 限制：
//   - $if method.return_type is !veb.Result 语法不支持（"invalid $if right expr"）
//   - $else 分支中 ctrl.$method() or { ... } 触发 C codegen bug
//   - $else 分支中 ctrl.$method()! 报 "invalid expression"
//   - $else 分支中 return ctrl.$method() 报 "ComptimeCall used as value"
//   - 但 $else 分支中 ctrl.$method() 作为语句（无 or/!/return）可以编译并执行
//   - V 允许 !T 方法作为语句调用，错误被静默丢弃
//
// 解决方案（后写模式）：在 $else 分支中，先作为语句调用方法（错误被静默丢弃），
// 再通过 postwrite_error_response 检查是否已写入响应。
//   - 方法成功时通常会调用 c.text()/c.ok() 等写入响应（res.status_code != 0），
//     此时 postwrite 不做任何事，保留方法写入的响应。
//   - 方法失败时（错误被丢弃）不写响应（res.status_code == 0），
//     postwrite 调用 server_error 补写 500 错误响应。
// 注意：不能用"预写 500 再调用方法"的方式，因为 veb.Context.send_response_to_client
// 在 done==true 时会拒绝后续写入（见 veb/context.v 第 109 行）。
pub fn dispatch_route_method[T](ctrl_ptr voidptr, method_name string) veb.Result {
	mut ctrl := unsafe { &T(ctrl_ptr) }
	$for method in T.methods {
		$if method.return_type is veb.Result {
			// 返回 veb.Result 的方法：直接调用并返回结果
			if method_name == method.name {
				return ctrl.$method()
			}
		} $else {
			// 返回 !veb.Result / ! / 其他类型的方法：
			// 作为语句调用（错误被静默丢弃），再检查是否需要补写 500。
			if method_name == method.name {
				ctrl.$method()
				postwrite_error_response[T](mut ctrl)
				// 响应已写入控制器嵌入的 context，由 copy_controller_response 传播
			}
		}
	}
	return veb.no_result()
}

// postwrite_error_response 检查控制器嵌入的 veb.Context 是否已写入响应。
// 若未写入（res.status_code == 0，表示方法出错或未写响应），则补写 500 错误响应。
// 方法成功时通常会调用 c.text()/c.ok() 等写入响应（res.status_code != 0），
// 此时本函数不做任何事，保留方法写入的响应。
// 方法失败时（错误被丢弃）不写响应，本函数补写 500。
fn postwrite_error_response[T](mut ctrl T) {
	$for field in T.fields {
		$if field.typ is veb.Context {
			if ctrl.$(field.name).res.status_code == 0 {
				_ = ctrl.$(field.name).server_error('Internal Server Error')
			}
		}
	}
}

// new_controller_instance 创建控制器的新实例（prototype 语义：每请求新实例）。
// V 0.5.1 限制：闭包内无法引用类型参数 T，故通过此工厂函数间接创建。
pub fn new_controller_instance[T]() T {
	return T{}
}

// set_controller_context 将请求上下文设置到控制器嵌入的 veb.Context 字段
pub fn set_controller_context[T](mut ctrl T, mut ctx veb.Context) {
	$for field in T.fields {
		$if field.typ is veb.Context {
			ctrl.$(field.name) = ctx
		}
	}
}

// inject_autowired_fields 从预解析的服务映射中注入 @[autowired] 字段。
// 使用 typeof(ctrl.$(field.name)).name 获取字段类型名，
// 再通过 unsafe 直接赋值 voidptr（适用于所有引用/指针类型）。
pub fn inject_autowired_fields[T](mut ctrl T, services map[string]voidptr) {
	$for field in T.fields {
		$if field.typ is veb.Context {
			// 跳过嵌入的 veb.Context（由 set_controller_context 单独处理）
		} $else {
			// 检查是否有 @[autowired] 注解
			mut has_autowired := false
			for attr in field.attrs {
				if attr == 'autowired' {
					has_autowired = true
				}
			}
			if has_autowired {
				// 通过 typeof 获取字段类型名（如 '&web.MountTestService'）
				type_name := typeof(ctrl.$(field.name)).name
				if type_name in services {
					ptr := services[type_name] or { unsafe { nil } }
					if !isnil(ptr) {
						unsafe {
							ctrl.$(field.name) = ptr
						}
					}
				}
			}
		}
	}
}

// copy_controller_response 将控制器嵌入 context 的响应复制回原始请求上下文。
// veb.Context 按值嵌入，控制器方法写入的是副本，需将响应复制回原始 ctx。
// 采用整结构赋值以同步 veb 内部私有字段（如 done 标志）：
// 控制器方法调用 ctx.text() 等会在副本上设置 done=true，整结构赋值将其带回原始 ctx，
// 使 veb 在 before_request 返回后能正确识别响应已就绪并提前返回。
// done 字段对 veb 模块私有（mut: 非 pub mut:），无法单独访问，故用整结构拷贝。
pub fn copy_controller_response[T](mut ctrl T, mut ctx veb.Context) {
	$for field in T.fields {
		$if field.typ is veb.Context {
			// 整结构赋值：复制 res（响应体+头）与 done（响应就绪标志）等全部字段
			ctx = ctrl.$(field.name)
		}
	}
}

// join_path 将前缀和路径拼接，避免双斜杠。
// 特殊处理：当 path == '/'（索引路由）时，结果为 prefix + '/'，
// 保留尾部斜杠以区分组根路径（如 /test/ 表示 test 组的索引）。
fn join_path(prefix string, path string) string {
	if prefix.len == 0 {
		return path
	}
	if path.len == 0 {
		return prefix
	}
	if path == '/' {
		// 索引路由：前缀 + '/'（若前缀已以 '/' 结尾则不重复）
		if prefix.ends_with('/') {
			return prefix
		}
		return '${prefix}/'
	}
	mut p := prefix
	mut s := path
	if p.ends_with('/') {
		p = p[..p.len - 1]
	}
	if s.starts_with('/') {
		s = s[1..]
	}
	return '${p}/${s}'
}

// mount 扫描控制器类型 T 的方法，为每个带 HTTP 路由注解的方法
// 生成包装闭包并注册到路由表。控制器可定义在任意包中。
//
// 用法：
//   mut wm := init_web_module()
//   wm.mount[UserController](mut ctx)
//   wm.mount[OrderController](mut ctx, MountOptions{prefix: '/api/v2'})
pub fn (mut rr RouteRegistry) mount[T](mut ctx core.ApplicationContext, opts MountOptions) {
	// 1. 提取 @[group('/prefix')] 类级别前缀
	group_prefix := extract_group_prefix[T]()

	// 2. 计算最终前缀 = opts.prefix + group_prefix
	final_prefix := join_path(opts.prefix, group_prefix)

	// 3. 预解析 @[autowired] 字段所需服务（挂载时一次性解析）
	//    通过工厂函数创建 T 实例（V 0.5.1 限制：mount[T] 体内无法直接用 T{} 字面量）
	//    类型名归一化：typeof 返回 '&UserService'，但 bean 通常注册为 'UserService'，
	//    故尝试两种形式：先原始类型名，再去掉 '&' 前缀。
	//    注意：此处内联 $for field in T.fields 而非调用独立函数，
	//    因为 V 0.5.1 中独立泛型函数的 $for field in T.fields 会报错
	//    "T is not a type or variable name"（仅在方法体内可用）。
	mut tmp := new_controller_instance[T]()
	mut services := map[string]voidptr{}
	$for field in T.fields {
		$if field.typ is veb.Context {
			// 跳过嵌入的 veb.Context（由 set_controller_context 单独处理）
		} $else {
			mut has_autowired := false
			for attr in field.attrs {
				if attr == 'autowired' {
					has_autowired = true
				}
			}
			if has_autowired {
				// 通过 tmp 实例获取字段类型名（如 '&web.MountTestService'）
				type_name := typeof(tmp.$(field.name)).name
				// 尝试多种类型名形式解析（typeof 返回 '&module.TypeName'，
				// 但 bean 可能注册为 'TypeName'、'module.TypeName' 或 '&module.TypeName'）
				mut ptr := ctx.resolve(type_name) or { unsafe { nil } }
				// 形式 2：去掉 '&' 前缀（如 'web.MountTestService'）
				if isnil(ptr) && type_name.starts_with('&') {
					ptr = ctx.resolve(type_name[1..]) or { unsafe { nil } }
				}
				// 形式 3：去掉 '&' 前缀和模块前缀（如 'MountTestService'）
				if isnil(ptr) && type_name.contains('.') {
					short_name := type_name.after('.')
					ptr = ctx.resolve(short_name) or { unsafe { nil } }
				}
				if !isnil(ptr) {
					services[type_name] = ptr
				}
			}
		}
	}
	// 4. 扫描方法，为每个路由方法生成闭包并注册
	$for method in T.methods {
		method_name := method.name

		// 跳过生命周期钩子方法
		if method_name !in ['before_request', 'after_request', 'init', 'free'] {
			// 扫描方法注解：HTTP 方法 + 路径
			mut found_route := false
			mut http_method := ''
			mut method_path := ''

			for attr in method.attrs {
				if attr == 'get' || attr == 'post' || attr == 'put' || attr == 'delete'
					|| attr == 'patch' {
					http_method = attr.to_upper()
					found_route = true
				}
				if attr.starts_with('/') {
					method_path = attr
				}
			}

			// 约定式路由：返回 veb.Result 的方法视为 GET 路由
			$if method.return_type is veb.Result {
				if !found_route {
					http_method = 'GET'
					found_route = true
				}
			}

			if found_route {
				// 路径约定：无显式路径时，index → '/'，其他 → '/${method_name}'
				if method_path.len == 0 {
					if method_name == 'index' {
						method_path = '/'
					} else {
						method_path = '/${method_name}'
					}
				}

				// 计算完整路径 = final_prefix + method_path
				full_path := join_path(final_prefix, method_path)

				// 扫描 @[middleware('name1','name2')] 注解
				mut middlewares := opts.middlewares.clone()
				mut collecting := false
				for attr in method.attrs {
					if attr == 'middleware' {
						collecting = true
					} else if collecting {
						trimmed := attr.trim_space().trim("'").trim('"')
						if trimmed.len > 0 && trimmed[0] != `/` {
							middlewares << trimmed
						} else {
							collecting = false
						}
					}
				}

			// 5. 生成包装闭包并注册
			// 闭包捕获：services（预解析的服务映射）、method_name（方法名）
			// 以及五个顶层泛型函数的单态化实例（factory/dispatcher/injector/setter/copier）
			// V 0.5.1 限制：闭包内无法引用类型参数 T，故通过 factory 间接创建实例
			factory := new_controller_instance[T]
			dispatcher := dispatch_route_method[T]
			injector := inject_autowired_fields[T]
			setter := set_controller_context[T]
			copier := copy_controller_response[T]

			handler := fn [services, method_name, factory, dispatcher, injector, setter, copier] (mut rctx veb.Context, params map[string]string) veb.Result {
				// 创建控制器实例（prototype 语义：每请求新实例）
				mut ctrl := factory()

				// 设置嵌入的 veb.Context
				setter(mut ctrl, mut rctx)

				// 注入 @[autowired] 字段
				injector(mut ctrl, services)

				// 调用控制器方法
				result := dispatcher(voidptr(&ctrl), method_name)

				// 将响应复制回原始请求上下文
				copier(mut ctrl, mut rctx)

				return result
			}

			// 注册路由（带方法级中间件名，分发时按顺序执行）
			rr.register_with_middleware(http_method, full_path, handler, middlewares)
			}
		}
	}
}

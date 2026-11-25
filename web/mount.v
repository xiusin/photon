module web

// mount.v — 编译期控制器挂载（Spring @Controller + @RequestMapping 等价）
//
// 控制器自己带路由注解，框架在编译期把它们扫成路由表 —— 路由和它的处理
// 逻辑待在同一处，改一条路由不用跨文件对齐两处。
//
// 核心能力：
//   通过 comptime $for 扫描任意控制器类型 T 的方法，自动发现路由注解
//   （@[get]、@[post]、@[put]、@[delete]、@[patch]、@[head]、@[options]），
//   把匹配的方法注册成 RouteHandler 闭包。
//
//   控制器可以在任意目录、任意包中定义，只要在挂载点 import 即可。
//
// 控制器方法签名 = veb 原生签名：
//   pub fn (mut c MyController) handler(mut ctx Context) veb.Result
//
//   注解和签名都跟「直接写在 App 上」一样，控制器只是换个文件放。
//   路径参数在 ctx 上：`/users/:id` 的 id 用 ctx.path('id') 取
//   （Context 需嵌入 web.RouterContext，见 context_helpers.v）。
//
// 路由注解写法（三种都认）：
//   分离式  @[get]  @['/users']
//   合并式  @[get: '/users']
//   元组式  @['/users'; get]
//
// 控制器前缀注解：
//   @[prefix: '/api/v1']
//   pub struct UserController { ... }
//
// 依赖注入：
//   控制器字段标注 @[autowired] 后，可通过 core.ApplicationContext 的
//   wire_controller[T]() / wire_and_mount[T]() 自动注入。
//
// 用法：
//   // 1. 定义控制器（可在任意文件/包中）
//   @[controller]
//   @[prefix: '/api/v1']
//   pub struct UserController {
//       user_service &UserService @[autowired]
//   }
//
//   @[get: '/users']
//   pub fn (mut c UserController) list(mut ctx Context) veb.Result {
//       return ctx.json({ 'users': '[]' })
//   }
//
//   @[get: '/users/:id']
//   pub fn (mut c UserController) show(mut ctx Context) veb.Result {
//       return ctx.text(ctx.path('id'))
//   }
//
//   // 2. 挂载（前缀取自 @[prefix]，不用重复写）
//   app.WebModule.mount[UserController, Context](user_ctrl)
//
//   // 3. 在 before_request 中分发
//   pub fn (mut ctx Context) before_request() {
//       ctx.app.WebModule.handle_request(voidptr(ctx))
//   }
import veb
import net.http
import photon.core

// ═══════════════════════════════════════════════════════════
// 路由属性解析
// ═══════════════════════════════════════════════════════════

// http_method_prefixes 是框架认的路由属性名，顺序即匹配优先级。
const http_method_prefixes = ['get', 'post', 'put', 'delete', 'patch', 'head', 'options']

// route_attr_named_prefixes 是属性参数可能带的具名前缀
// （veb 风格的 `@[get: path: '/users']`）。
const route_attr_named_prefixes = [
	'path: ',
	"path: '",
	'path: "',
	"path='",
	'path="',
	'path=',
]

// RouteAttr 解析后的路由属性
pub struct RouteAttr {
pub:
	method string // GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
	path   string // 路由路径，如 /users/:id
}

// parse_route_attrs 从方法属性列表中解析 HTTP 方法和路径。
//
// 支持的写法（都会被 $for method in T.methods 取到的 `method.attrs` 归一成
// 下面这些字符串形态）：
//
//	分离式  @[get] + @['/users']        → ['get', '/users']
//	合并式  @[get: '/users']            → ["get: '/users'"]
//	带名式  @[get: path: '/users']      → ["get: path: '/users'"]
//	元组式  @['/users'; get]            → ['/users', 'get']
//
// 参数里带空的 `[]`、单双引号、甚至转义引号，都可能随编译器版本的属性
// 序列化方式一起出现，所以这里不做字符串比对，只认「属性名 += 分隔符」
// 这个前缀，剩下的原样剥壳。
pub fn parse_route_attrs(method_name string, attrs []string) ?RouteAttr {
	mut http_method := ''
	mut path := ''

	for attr in attrs {
		trimmed := attr.trim_space()
		// 分离式：检查 HTTP 方法
		if trimmed in http_method_prefixes {
			http_method = trimmed.to_upper()
			continue
		}
		lowered := trimmed.to_lower()

		// 分离式：检查路径（写出 @['/users'] 时整个属性就是路径）
		if trimmed.starts_with('/') {
			path = trimmed
			continue
		}

		for prefix in http_method_prefixes {
			// 合并式 / 带名式 / 元组式：get: '/path'、get('/path')、get: path: '/path'
			if lowered.starts_with('${prefix}:') || lowered.starts_with('${prefix}(') {
				if http_method.len == 0 {
					http_method = prefix.to_upper()
				}
				// 去掉属性名和紧跟的分隔符，剩下的交给 route_attr_candidates 剥壳。
				mut arg := trimmed[prefix.len..].trim_space()
				arg = arg.trim_string_left(':').trim_space()
				if arg.starts_with('(') {
					arg = arg[1..].trim_space()
					// `('hello')` 这种带左括号的写法
					if arg.ends_with(')') {
						arg = arg[..arg.len - 1].trim_space()
					}
				}
				for candidate in route_attr_candidates(arg) {
					if candidate.len > 0 {
						path = candidate
						break
					}
				}
				// 同一个属性里已经拿到的路径不再被后续属性覆盖。
				if path.len > 0 {
					break
				}
			}
		}
	}

	if http_method.len == 0 {
		return none
	}

	// 默认路径：方法名转路径
	if path.len == 0 {
		if method_name == 'index' {
			path = '/'
		} else {
			path = '/${method_name}'
		}
	}

	return RouteAttr{
		method: http_method
		path:   path
	}
}

// route_attr_candidates 把「属性参数」剥成路径本身。
//
// 属性参数的字符串化方式跟 V 的版本有关，实测至少见过这几种：
//
//	'/users'          原样带引号
//	path: '/users'    veb 风格的具名参数
//	path: ['/users']  具名参数 + 数组字面量
//	'[\'/users\']'    整个参数被再套一层引号 + 转义
//
// 与其猜一种，不如把这几层壳逐个剥掉，直到剩下以 '/' 开头的那串。
// 剥不出来就返回空，让调用方退回「方法名即路径」的约定。
fn route_attr_candidates(arg string) []string {
	mut cur := arg.trim_space()
	// 层数上限只为防止意外的死循环：壳最多就三四层。
	for _ in 0 .. 8 {
		unquoted := cur.trim("'").trim('"').trim_space()
		if unquoted != cur {
			cur = unquoted
			continue
		}
		mut named := false
		for prefix in route_attr_named_prefixes {
			if cur.starts_with(prefix) {
				cur = cur[prefix.len..].trim_space()
				named = true
				break
			}
		}
		if named {
			continue
		}
		if cur.starts_with('[') && cur.ends_with(']') {
			cur = cur[1..cur.len - 1].trim_space()
			continue
		}
		if cur.starts_with('{') && cur.ends_with('}') {
			cur = cur[1..cur.len - 1].trim_space()
			continue
		}
		break
	}
	if cur.starts_with('/') {
		return [cur]
	}
	return []
}

// extract_controller_prefix 从结构体属性中解析 @[prefix: '/api/v1'] 前缀。
// 返回前缀字符串，如果没有则返回空字符串。
//
// 属性参数会被再套一层壳（`@[prefix: '/api/v1']` 的 arg 可能是
// `'/api/v1'`、`path: '/api/v1'`、`['/api/v1']` 三种之一），所以这里复用
// route_attr_candidates 把壳剥掉；剥不出来就返回空串，而不是把
// `path: '/api/v1'` 这种半成品拼进每条路由里。
pub fn extract_controller_prefix[T]() string {
	mut raw := ''
	$for attr in T.attributes {
		$if attr.name == 'prefix' {
			$if attr.has_arg {
				raw = attr.arg
			}
		}
	}
	if raw.len == 0 {
		return ''
	}
	for candidate in route_attr_candidates(raw) {
		return candidate.trim_right('/')
	}
	return ''
}

// join_route_path 拼接控制器前缀与路由路径，避免出现 `//users` 或 `/apiusers`。
pub fn join_route_path(prefix string, path string) string {
	mut p := path.trim_space()
	if p.len == 0 {
		p = '/'
	}
	if !p.starts_with('/') {
		p = '/' + p
	}
	mut pre := prefix.trim_space()
	pre = pre.trim_right('/')
	if pre.len == 0 {
		return p
	}
	if pre.starts_with('/') == false {
		pre = '/' + pre
	}
	if p == '/' {
		return pre
	}
	return pre + p
}

// ═══════════════════════════════════════════════════════════
// 控制器方法分发（comptime 顶层函数）
// ═══════════════════════════════════════════════════════════

// dispatch_controller_method 调用控制器 T 上名为 method_name 的方法。
//
// 这是一个顶层泛型函数（非闭包），因此 V 的 comptime 变量
// （T 和 $for method）在此函数体内可正常访问。
//
// 控制器方法签名就是 veb 的原生形态：
//
//	pub fn (mut c MyController) handler(mut ctx veb.Context) veb.Result
//
// 路由注解和签名都跟「直接写在 App 上」一模一样 —— 控制器只是换个文件放，
// 不用为了被挂载而改写方法形状。路径参数从 ctx 上取（ctx.path('id')），
// 由 RouteRegistry 在匹配成功后写入，见 RouterContext。
//
// 仅对返回类型为 veb.Result 的方法生成调用代码，避免对非路由方法
// （构造器、辅助方法）生成不匹配的调用。
pub fn dispatch_controller_method[T, X](controller_ptr voidptr, method_name string, ctx_ptr voidptr) veb.Result {
	mut ctrl := unsafe { &T(controller_ptr) }
	mut ctx := unsafe { &X(ctx_ptr) }
	// 这些控制器路由不在 veb 自己的路由表里，veb 会先留一个 404 状态。
	// 命中后兜成 200；处理器需要 401/403/503 等状态时自行覆盖。
	mut res_ctx := unsafe { &veb.Context(ctx_ptr) }
	res_ctx.res.set_status(unsafe { http.Status(200) })
	$for method in T.methods {
		$if method.return_type is veb.Result {
			if method_name == method.name {
				return ctrl.$method(mut ctx)
			}
		}
	}
	// 方法未找到，返回 404。
	// X 都嵌入 veb.Context，所以 ctx_ptr 也可以当作 &veb.Context 使用。
	mut veb_ctx := unsafe { &veb.Context(ctx_ptr) }
	veb_ctx.res.set_status(unsafe { http.Status(404) })
	veb_ctx.set_content_type('application/json')
	return veb_ctx.text('{"error":"method not found","code":404}')
}

// ═══════════════════════════════════════════════════════════
// 路径参数
// ═══════════════════════════════════════════════════════════

// extract_path_params 按路由定义把请求 URL 的路径段取成 `名字 → 值`。
//
// find_route 已经切过一遍了，这个函数是给「手里只有路径串、没有 RouteDef」
// 的场景用的（actuator /mappings、单测、自己 dispatch 的代码）。
pub fn extract_path_params(path string, route_path string) map[string]string {
	mut params := map[string]string{}
	url_words := split_url_words(path)
	route_words := split_url_words(route_path)
	if url_words.len != route_words.len {
		return params
	}
	for i, word in route_words {
		name := if word.starts_with(':') {
			word[1..]
		} else if word.starts_with('{') {
			word.trim('{}')
		} else {
			''
		}
		if name.len > 0 {
			params[name] = url_words[i]
		}
	}
	return params
}

// store_path_params 把匹配到的路径参数写到请求上下文上。
//
// 为什么要绕到 ctx 上：控制器方法签名保持 veb 原生形态（只收 ctx），
// 于是框架没有位置把 map 递进去；而让方法为了收 map 改写签名，等于
// Photon 自造了第二种方法形状。挂到 ctx 上之后，想取就取。
//
// 上下文必须是 web.RouterContext（用户项目里的 Context 嵌入它）。
// 传进来的如果只是裸 veb.Context（手写 dispatch 的老用法），这里不写 ——
// 写进去就越界了，宁可不给参数，也不能踩别人内存。
fn store_path_params(ctx_ptr voidptr, params map[string]string) {
	if ctx_ptr == unsafe { nil } {
		return
	}
	mut rctx := unsafe { &RouterContext(ctx_ptr) }
	rctx.path_params = params.clone()
}

// path_params_of 读回当前请求的路径参数（没有则空 map）。
pub fn path_params_of(ctx_ptr voidptr) map[string]string {
	if ctx_ptr == unsafe { nil } {
		return map[string]string{}
	}
	rctx := unsafe { &RouterContext(ctx_ptr) }
	return rctx.path_params
}

// ═══════════════════════════════════════════════════════════
// 控制器挂载（核心 API）
// ═══════════════════════════════════════════════════════════

// mount_controller 通过编译期扫描将控制器 T 的路由方法注册到 RouteRegistry。
//
// 这是 Photon Web 模块的核心能力：控制器在任意目录、任意包中定义，
// 通过 comptime $for 自动发现 @[get]、@[post] 等路由注解并注册。
//
// 参数：
//   controller: 控制器实例指针（依赖应已注入）
//   prefix:     路由前缀（如 '/api/v1'），会拼接到每条路由路径前
//
// 用法：
//   app.WebModule.mount_controller[UserController, Context](&UserController{...}, '/api/v1')
pub fn (mut rr RouteRegistry) mount_controller[T, X](controller &T, prefix string) {
	// 编译期扫描控制器的所有方法
	$for method in T.methods {
		// 仅处理返回 veb.Result 的方法
		$if method.return_type is veb.Result {
			// 跳过生命周期钩子
			if method.name != 'before_request' && method.name != 'after_request' {
				// 解析路由属性。V comptime 的 $for 里不能 continue，
				// 所以用 or 兜一个空 RouteAttr 表示「这条不是路由」。
				route_attr := parse_route_attrs(method.name, method.attrs) or { RouteAttr{} }

				if route_attr.method.len > 0 {
					full_path := join_route_path(prefix, route_attr.path)
					method_name := method.name
					ctrl_ptr := voidptr(controller)

					// 闭包内不能直接使用 $method，所以通过
					// dispatch_controller_method[T, X] 顶层函数分发。
					// X 泛型参数允许控制器方法使用任意嵌入 veb.Context 的 Context 类型。
					dispatcher := dispatch_controller_method[T, X]
					handler := fn [ctrl_ptr, method_name, dispatcher] (ctx_ptr voidptr, _ map[string]string) veb.Result {
						// 路径参数已经由 RouteRegistry 写进 ctx（见 store_path_params），
						// 控制器方法因此可以保持 veb 原生签名，需要参数时用 ctx.path('id') 取。
						// 闭包仍收第二个形参是因为 RouteHandler 的类型签名如此，
						// 这里用不上 —— 写成 `_` 让「没用到」这件事写在脸上。
						return dispatcher(ctrl_ptr, method_name, ctx_ptr)
					}

					rr.register(route_attr.method, full_path, handler)
				}
			}
		}
	}
}

// mount_controller_auto 自动从结构体注解中提取前缀并挂载控制器。
// 如果控制器有 @[prefix: '/api/v1'] 注解，则使用注解前缀；
// 否则使用传入的 default_prefix。
//
// 用法：
//   rr.mount_controller_auto[UserController, Context](&UserController{}, '')
pub fn (mut rr RouteRegistry) mount_controller_auto[T, X](controller &T, default_prefix string) {
	mut prefix := extract_controller_prefix[T]()
	if prefix.len == 0 {
		prefix = default_prefix
	}
	rr.mount_controller[T, X](controller, prefix)
}

// ═══════════════════════════════════════════════════════════
// WebModule 便捷方法
// ═══════════════════════════════════════════════════════════

// mount_controller 通过 WebModule 挂载控制器（委托给 RouteRegistry）。
// 用法：
//   app.WebModule.mount_controller[UserController, Context](&UserController{...}, '/api/v1')
pub fn (mut wm WebModule) mount_controller[T, X](controller &T, prefix string) {
	wm.router.mount_controller[T, X](controller, prefix)
}

// mount_controller_auto 通过 WebModule 自动挂载控制器（委托给 RouteRegistry）。
// 用法：
//   app.WebModule.mount_controller_auto[UserController, Context](&UserController{}, '')
pub fn (mut wm WebModule) mount_controller_auto[T, X](controller &T, default_prefix string) {
	wm.router.mount_controller_auto[T, X](controller, default_prefix)
}

// mount 挂载控制器并返回自身，支持一次性挂载多个。
//
// 这是「控制器自己带路由注解」最顺手的入口：前缀取自控制器上的
// @[prefix: '/api/v1']，取不到就用空串（路由注解里写的就是全路径）。
//
//	app.WebModule.mount[UserController, Context](&user_ctrl)
//	   .mount[AuthController, Context](&auth_ctrl)
//
// 返回 &WebModule 而不是 void，是为了让启动代码读起来像一句话；
// 中间件/静态资源那些配置方法本来就是链式的，没道理这里例外。
pub fn (mut wm WebModule) mount[T, X](controller &T) &WebModule {
	wm.router.mount_controller_auto[T, X](controller, '')
	return wm
}

// ═══════════════════════════════════════════════════════════
// DI + 挂载一体化（wire_and_mount_controller）
// ═══════════════════════════════════════════════════════════

// wire_and_mount_controller 一步完成「DI 创建+注入」和「路由挂载」。
//
// 这是 wire_controller[T]() + mount_controller[T, X]() 的便捷封装——
// 将两步操作合并为一次调用，消除 main.v 中的样板代码。
//
// 参数：
//   ctx:    ApplicationContext（DI 容器）
//   prefix: 路由前缀（如 '' 或 '/api/v1'），会自动拼接到每条路由路径前
//
// 返回：完全初始化的控制器实例指针（依赖已注入、路由已注册）
//
// Spring 等价：@Controller + @Autowired + @RequestMapping 一体化
//
// 用法：
//   ctrl := app.WebModule.wire_and_mount_controller[UserController, http.Context](mut app_ctx, '/api/v1')!
pub fn (mut wm WebModule) wire_and_mount_controller[T, X](mut ctx core.ApplicationContext, prefix string) !&T {
	ctrl := ctx.wire_controller[T]()!
	wm.mount_controller[T, X](ctrl, prefix)
	return ctrl
}

// wire_and_mount_controller_auto 一步完成「DI 创建+注入」和「路由挂载（自动前缀）」。
//
// 如果控制器有 @[prefix: '/api/v1'] 注解，则使用注解前缀；
// 否则使用传入的 default_prefix。
//
// 用法：
//   ctrl := app.WebModule.wire_and_mount_controller_auto[UserController, http.Context](mut app_ctx, '')!
pub fn (mut wm WebModule) wire_and_mount_controller_auto[T, X](mut ctx core.ApplicationContext, default_prefix string) !&T {
	ctrl := ctx.wire_controller[T]()!
	wm.mount_controller_auto[T, X](ctrl, default_prefix)
	return ctrl
}

// wire_and_mount 一步完成「DI 创建+注入」和「路由挂载（前缀取自注解）」。
//
//   app.WebModule.wire_and_mount[UserController, Context](mut app_ctx)!
//
// 前缀来源与 mount 一致：@[prefix: ...] 优先，没有就是空串。
pub fn (mut wm WebModule) wire_and_mount[T, X](mut ctx core.ApplicationContext) !&T {
	ctrl := ctx.wire_controller[T]()!
	wm.mount[T, X](ctrl)
	return ctrl
}

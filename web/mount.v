module web

// mount.v — 编译期控制器挂载（Spring @Controller + @RequestMapping 等价）
//
// 核心能力：
//   通过 comptime $for 扫描任意控制器类型 T 的方法，自动发现路由注解
//   （@[get]、@[post]、@[put]、@[delete]、@[patch]），并将匹配的方法
//   注册为 RouteHandler 闭包。
//
//   控制器可以在任意目录、任意包中定义，只要在挂载点 import 即可。
//   这解决了"控制器只能在单文件内编写"的限制。
//
// 设计灵感：
//   - Spring MVC 的 @Controller + @RequestMapping 自动扫描
//   - very 框架的 mount[T]() comptime 挂载模式
//
// 控制器方法签名约定：
//   pub fn (mut c MyController) handler(mut ctx veb.Context, params map[string]string) veb.Result
//
// 路由注解格式（支持两种写法）：
//   方式一（分离式，veb 风格）：
//     @[get]
//     @['/users']
//     pub fn (mut c UserController) list(mut ctx veb.Context, params map[string]string) veb.Result { ... }
//
//   方式二（合并式，Spring 风格）：
//     @[get: '/users']
//     pub fn (mut c UserController) list(mut ctx veb.Context, params map[string]string) veb.Result { ... }
//
// 控制器前缀注解：
//   @[prefix: '/api/v1']
//   pub struct UserController { ... }
//
// 依赖注入：
//   控制器字段标注 @[autowired] 后，可通过 core.ApplicationContext.autowire_controller[T]()
//   自动从 DI 容器注入依赖。
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
//   pub fn (mut c UserController) list(mut ctx veb.Context, params map[string]string) veb.Result {
//       return ctx.text('{"users":[]}')
//   }
//
//   // 2. 在 App 中挂载控制器
//   mut app := &App{
//       WebModule: web.init_web_module()
//   }
//   app.WebModule.mount_controller[UserController](&UserController{}, '/api/v1')
//
//   // 3. 在 before_request 中分发
//   pub fn (mut ctx Context) before_request() {
//       ctx.app.WebModule.handle_request(mut ctx)
//   }
import veb
import net.http

// ═══════════════════════════════════════════════════════════
// 路由属性解析
// ═══════════════════════════════════════════════════════════

// RouteAttr 解析后的路由属性
pub struct RouteAttr {
pub:
	method string // GET, POST, PUT, DELETE, PATCH
	path   string // 路由路径，如 /users/:id
}

// parse_route_attrs 从方法属性列表中解析 HTTP 方法和路径。
// 支持两种格式：
//   1. 分离式：@[get] + @['/users']  → attrs = ['get', '/users']
//   2. 合并式：@[get: '/users']      → attrs = ["get: '/users'"]
pub fn parse_route_attrs(method_name string, attrs []string) ?RouteAttr {
	mut http_method := ''
	mut path := ''

	for attr in attrs {
		// 分离式：检查 HTTP 方法
		if attr == 'get' || attr == 'post' || attr == 'put' || attr == 'delete' || attr == 'patch' {
			http_method = attr.to_upper()
			continue
		}

		// 分离式：检查路径
		if attr.starts_with('/') {
			path = attr
			continue
		}

		// 合并式：get: '/path' 或 get('/path')
		for prefix in ['get', 'post', 'put', 'delete', 'patch'] {
			if attr.starts_with('${prefix}:') || attr.starts_with('${prefix}(') {
				http_method = prefix.to_upper()
				extracted := extract_route_attr_arg(attr, prefix)
				if extracted.len > 0 {
					path = extracted
				}
				break
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

// extract_attr_arg 从属性字符串中提取参数值。
// 例如：get: '/users' → '/users'
//       get('/users') → '/users'
fn extract_route_attr_arg(attr string, prefix string) string {
	mut val := attr
	if val.starts_with('${prefix}:') {
		val = val['${prefix}:'.len..]
	} else if val.starts_with('${prefix}(') {
		val = val['${prefix}('.len..]
		if val.ends_with(')') {
			val = val[..val.len - 1]
		}
	}
	return val.trim_space().trim("'").trim('"').trim_space()
}

// extract_prefix 从结构体属性中解析 @[prefix: '/api/v1'] 前缀。
// 返回前缀字符串，如果没有则返回空字符串。
pub fn extract_controller_prefix[T]() string {
	mut prefix := ''
	$for attr in T.attributes {
		$if attr.name == 'prefix' {
			$if attr.has_arg {
				prefix = attr.arg.trim("'").trim('"').trim_space()
			}
		}
	}
	return prefix
}

// ═══════════════════════════════════════════════════════════
// 控制器方法分发（comptime 顶层函数）
// ═══════════════════════════════════════════════════════════

// dispatch_controller_method 调用控制器 T 上名为 method_name 的方法。
//
// 这是一个顶层泛型函数（非闭包），因此 V 0.5.1 的 comptime 变量
// （T 和 $for method）在此函数体内可正常访问。
//
// 仅对返回类型为 veb.Result 的方法生成调用代码，避免对非路由方法
// （如构造函数、辅助方法）生成不匹配的调用。
//
// V comptime 注意：
//   $if method.return_type is veb.Result 确保只对返回 veb.Result 的方法
//   生成 ctrl.$method(mut ctx, params) 调用。所有路由处理方法必须具有
//   签名 fn (mut ctx veb.Context, params map[string]string) veb.Result。
//   非路由方法（构造器等）返回 &T 或 void，不会被匹配。
pub fn dispatch_controller_method[T](controller_ptr voidptr, method_name string, mut ctx veb.Context, params map[string]string) veb.Result {
	mut ctrl := unsafe { &T(controller_ptr) }
	$for method in T.methods {
		$if method.return_type is veb.Result {
			if method_name == method.name {
				return ctrl.$method(mut ctx, params)
			}
		}
	}
	// 方法未找到，返回 404
	ctx.res.set_status(unsafe { http.Status(404) })
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"method not found","code":404}')
}

// ═══════════════════════════════════════════════════════════
// 控制器挂载（核心 API）
// ═══════════════════════════════════════════════════════════

// mount_controller 通过编译期扫描将控制器 T 的路由方法注册到 RouteRegistry。
//
// 这是 Photon Web 模块的核心能力：支持控制器在任意目录、任意包中定义，
// 通过 comptime $for 自动发现 @[get]、@[post] 等路由注解并注册为
// RouteHandler 闭包。
//
// 参数：
//   controller: 控制器实例指针（依赖应已注入）
//   prefix:     路由前缀（如 '/api/v1'），会自动拼接到每条路由路径前
//
// 控制器方法签名约定：
//   pub fn (mut c MyController) handler(mut ctx veb.Context, params map[string]string) veb.Result
//
// 路由注解支持两种格式：
//   @[get: '/users']           — Spring 风格（合并式）
//   @[get] @['/users']          — veb 风格（分离式）
//
// 用法：
//   rr.mount_controller[UserController](&UserController{...}, '/api/v1')
//   // 或通过 WebModule：
//   app.WebModule.mount_controller[UserController](&UserController{...}, '/api/v1')
pub fn (mut rr RouteRegistry) mount_controller[T](controller &T, prefix string) {
	// 编译期扫描控制器的所有方法
	$for method in T.methods {
		// 仅处理返回 veb.Result 的方法
		$if method.return_type is veb.Result {
			// 跳过生命周期钩子
			if method.name != 'before_request' && method.name != 'after_request' {
				// 解析路由属性
				route_attr := parse_route_attrs(method.name, method.attrs) or {
					// 非 HTTP 路由方法，跳过
					// 注意：V comptime $for 循环不允许 continue，
					// 所以用 if 嵌套代替 continue
					RouteAttr{}
				}

				// 只有成功解析到路由属性时才注册（route_attr.method 非空）
				if route_attr.method.len > 0 {
					// 拼接完整路径
					full_path := prefix + route_attr.path
					method_name := method.name
					ctrl_ptr := voidptr(controller)

					// 创建路由处理器闭包
					// 注意：V 0.5.1 comptime 限制下，闭包内不能直接使用 $method，
					// 所以通过 dispatch_controller_method[T] 顶层函数进行分发。
					dispatcher := dispatch_controller_method[T]
					handler := fn [ctrl_ptr, method_name, dispatcher] (mut ctx veb.Context, params map[string]string) veb.Result {
						return dispatcher(ctrl_ptr, method_name, mut ctx, params)
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
//   rr.mount_controller_auto[UserController](&UserController{})
//   // 如果 UserController 有 @[prefix: '/api/v1']，则自动使用 '/api/v1'
pub fn (mut rr RouteRegistry) mount_controller_auto[T](controller &T, default_prefix string) {
	mut prefix := extract_controller_prefix[T]()
	if prefix.len == 0 {
		prefix = default_prefix
	}
	rr.mount_controller[T](controller, prefix)
}

// ═══════════════════════════════════════════════════════════
// WebModule 便捷方法
// ═══════════════════════════════════════════════════════════

// mount_controller 通过 WebModule 挂载控制器（委托给 RouteRegistry）。
// 用法：
//   app.WebModule.mount_controller[UserController](&UserController{...}, '/api/v1')
pub fn (mut wm WebModule) mount_controller[T](controller &T, prefix string) {
	wm.router.mount_controller[T](controller, prefix)
}

// mount_controller_auto 通过 WebModule 自动挂载控制器（委托给 RouteRegistry）。
// 用法：
//   app.WebModule.mount_controller_auto[UserController](&UserController{})
pub fn (mut wm WebModule) mount_controller_auto[T](controller &T, default_prefix string) {
	wm.router.mount_controller_auto[T](controller, default_prefix)
}

// ═══════════════════════════════════════════════════════════
// 批量挂载
// ═══════════════════════════════════════════════════════════



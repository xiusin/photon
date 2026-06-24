module web

// dispatcher.v — 路由匹配引擎
//
// 支持静态路径和 :param 路径参数的匹配。
// 匹配优先级：静态路径 > 参数路径（按注册顺序）。
// 线程安全：DispatchedRequest 是请求级对象，无共享状态。
import veb

// RouteHandler — 路由处理器闭包
// 参数：mut ctx veb.Context, params map[string]string（路径参数）
pub type RouteHandler = fn (mut ctx veb.Context, params map[string]string) veb.Result

// RouteMiddleware — 路由级中间件函数
// 返回 true 表示继续执行（放行），false 表示中止请求（已自行写入响应）。
// 与 middleware.v 中的 MiddlewareFunc（基于 MiddlewareContext）不同，
// RouteMiddleware 直接操作 veb.Context，便于在路由分发阶段轻量执行。
pub type RouteMiddleware = fn (mut ctx veb.Context) bool

// MiddlewareRegistry — 命名路由中间件注册表
// 通过名称查找中间件函数，供 RouteDef.middlewares 引用。
// 线程安全：注册发生在启动阶段（单线程），查询发生在请求阶段（只读）。
pub struct MiddlewareRegistry {
pub mut:
	middlewares map[string]RouteMiddleware
}

// new_middleware_registry 创建中间件注册表
pub fn new_middleware_registry() &MiddlewareRegistry {
	return &MiddlewareRegistry{
		middlewares: map[string]RouteMiddleware{}
	}
}

// register 注册一个命名中间件
pub fn (mut mr MiddlewareRegistry) register(name string, mw RouteMiddleware) {
	mr.middlewares[name] = mw
}

// lookup 按名称查找中间件，未找到返回 none
pub fn (mr &MiddlewareRegistry) lookup(name string) ?RouteMiddleware {
	return mr.middlewares[name]
}

// RouteDef — 单条路由定义（@[heap] 确保指针安全返回）
@[heap]
pub struct RouteDef {
pub:
	method      string           // GET / POST / PUT / DELETE / PATCH
	path        string           // 原始路径，如 /api/v1/users/:id
	handler     RouteHandler = unsafe { nil } // 处理器闭包
	segments    []RouteSegment   // 编译后的路径段
	middlewares []string         // 处理器执行前应用的中间件名
}

// RouteSegment — 路径段（文本段、参数段 或 通配符段）
pub struct RouteSegment {
	is_param    bool   // true = :id 这种参数段
	is_wildcard bool   // true = *filepath 这种通配符段（匹配剩余所有路径）
	value       string // 文本段值；参数段为参数名；通配符段为参数名
}

// parse_path 将路径字符串编译为 RouteSegment 切片
// 支持三种段类型：
//   - 文本段：/users → {value: 'users'}
//   - 参数段：/:id   → {is_param: true, value: 'id'}
//   - 通配符段：/*filepath → {is_wildcard: true, value: 'filepath'}
pub fn parse_path(path string) []RouteSegment {
	mut segments := []RouteSegment{}
	for part in path.split('/') {
		if part.len == 0 {
			continue
		}
		if part.starts_with('*') {
			segments << RouteSegment{
				is_wildcard: true
				value:       part[1..] // 参数名（去掉 * 前缀）
			}
		} else if part.starts_with(':') {
			segments << RouteSegment{
				is_param: true
				value:    part[1..]
			}
		} else {
			segments << RouteSegment{
				value: part
			}
		}
	}
	return segments
}

// match_route 检查 URL 是否匹配路由定义，若匹配返回路径参数
// 通配符段（*filepath）匹配剩余所有路径段，捕获为单个路径字符串（如 '/css/app.css'）。
pub fn match_route(url_path string, route &RouteDef) ?map[string]string {
	url_parts := url_path.split('/')
	mut url_words := []string{}
	for part in url_parts {
		if part.len > 0 {
			url_words << part
		}
	}
	route_words := route.segments

	// 检测通配符段（约定通配符必须是最后一段）
	mut has_wildcard := false
	mut wildcard_idx := -1
	for i, seg in route_words {
		if seg.is_wildcard {
			has_wildcard = true
			wildcard_idx = i
			break
		}
	}

	if has_wildcard {
		// 通配符匹配：通配符之前的段必须精确匹配，
		// 通配符捕获剩余所有段并拼接为单个路径字符串
		if url_words.len < wildcard_idx {
			return none
		}
		mut params := map[string]string{}
		// 匹配通配符之前的段
		for i := 0; i < wildcard_idx; i++ {
			seg := route_words[i]
			if seg.is_param {
				params[seg.value] = url_words[i]
			} else if seg.value != url_words[i] {
				return none
			}
		}
		// 捕获剩余段作为通配符值（以 '/' 开头）
		mut remaining := []string{}
		for i := wildcard_idx; i < url_words.len; i++ {
			remaining << url_words[i]
		}
		params[route_words[wildcard_idx].value] = '/' + remaining.join('/')
		return params
	}

	// 非通配符：段数必须一致
	if url_words.len != route_words.len {
		return none
	}

	mut params := map[string]string{}
	for i, seg in route_words {
		if seg.is_param {
			params[seg.value] = url_words[i]
		} else if seg.value != url_words[i] {
			return none
		}
	}

	return params
}

// find_route 在路由列表中查找匹配的路由
// 优先匹配静态路径，再匹配参数/通配符路径。
// 返回 (路由定义, 路径参数字典) 或 none
pub fn find_route(routes []&RouteDef, method string, url_path string) ?(&RouteDef, map[string]string) {
	// 第一轮：精确静态匹配
	for route in routes {
		if route.method != method {
			continue
		}
		if route.segments.len == 0 && (url_path == '/' || url_path == '') {
			return route, map[string]string{}
		}
		mut has_dynamic := false
		for seg in route.segments {
			if seg.is_param || seg.is_wildcard {
				has_dynamic = true
				break
			}
		}
		if !has_dynamic {
			mut route_path := ''
			for seg in route.segments {
				route_path += '/' + seg.value
			}
			if route_path == '' {
				route_path = '/'
			}
			if route_path == url_path || route_path == url_path + '/' {
				return route, map[string]string{}
			}
		}
	}

	// 第二轮：参数/通配符路径匹配
	for route in routes {
		if route.method != method {
			continue
		}
		if params := match_route(url_path, route) {
			return route, params
		}
	}

	return none
}

// ============================================================
// DispatchedRequest — 调度器上下文（注入到 before_request）
// ============================================================

// DispatchedRequest 是请求调度结果，在 before_request 中填充
pub struct DispatchedRequest {
pub mut:
	matched      bool
	route        &RouteDef = unsafe { nil }
	params       map[string]string
}

// new_dispatched_request 创建 DispatchedRequest
pub fn new_dispatched_request() DispatchedRequest {
	return DispatchedRequest{
		params: map[string]string{}
	}
}

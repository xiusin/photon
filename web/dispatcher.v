module web

// dispatcher.v — 路由匹配引擎
//
// 支持静态路径和 :param 路径参数的匹配。
// 匹配优先级：静态路径 > 参数路径（按注册顺序）。
// 线程安全：DispatchedRequest 是请求级对象，无共享状态。
import veb

// RouteHandler — 路由处理器闭包
// 参数：ctx_ptr voidptr（上下文指针，支持任意嵌入 veb.Context 的类型）, params map[string]string（路径参数）
//
// 使用 voidptr 而非 veb.Context 是为了支持自定义 Context 类型
// （如 demo 中的 http.Context，嵌入 veb.Context 并扩展 request_id/user_id 等字段）
// dispatch_controller_method[T, Ctx] 会在编译期将 voidptr 安全转换为 &Ctx
pub type RouteHandler = fn (ctx_ptr voidptr, params map[string]string) veb.Result

// RouteDef — 单条路由定义（@[heap] 确保指针安全返回）
//
// middlewares: 路由级前置中间件，在 handler 之前执行
// after_middlewares: 路由级后置中间件，在 handler 之后执行
// host: 路由级 host 限制（空字符串 = 不限制），桥接 veb 的 host: 属性
//
// 路由级中间件与全局中间件（MiddlewareChain）叠加执行：
//   全局前置 → 路由前置 → handler → 路由后置 → 全局后置
//
// Host 级路由隔离：
//   当 host 非空时，只有请求的 Host 头匹配此值时路由才匹配。
//   用于多租户 / 多域名场景，桥接 veb.controller_host()。
@[heap]
pub struct RouteDef {
pub:
	method            string           // GET / POST / PUT / DELETE / PATCH
	path              string           // 原始路径，如 /api/v1/users/:id
	handler           RouteHandler = unsafe { nil } // 处理器闭包
	segments          []RouteSegment   // 编译后的路径段
	middlewares       []MiddlewareFunc // 路由级前置中间件
	after_middlewares []MiddlewareFunc // 路由级后置中间件
	host              string           // 路由级 host 限制（空 = 不限制）
}

// RouteSegment — 路径段（文本段 或 参数段）
pub struct RouteSegment {
	is_param bool   // true = :id 这种参数段
	value    string // 如果是文本段，值为段文本；如果是参数段，值为参数名
}

// parse_path 将路径字符串编译为 RouteSegment 切片
pub fn parse_path(path string) []RouteSegment {
	mut segments := []RouteSegment{}
	for part in path.split('/') {
		if part.len == 0 {
			continue
		}
		if part.starts_with(':') {
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
pub fn match_route(url_path string, route &RouteDef) ?map[string]string {
	url_parts := url_path.split('/')
	mut url_words := []string{}
	for part in url_parts {
		if part.len > 0 {
			url_words << part
		}
	}
	route_words := route.segments

	// 段数必须一致
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
// 优先匹配静态路径，再匹配参数路径。
// host 参数用于 host 级路由隔离（空字符串 = 不限制 host）。
// 返回 (路由定义, 路径参数字典) 或 none
//
// Host 匹配规则：
//   - route.host 为空 → 匹配任意 host
//   - route.host 非空 → 必须与请求 host 完全匹配（大小写不敏感）
//   - host 限制的路由优先于无限制路由
pub fn find_route(routes []&RouteDef, method string, url_path string, host string) ?(&RouteDef, map[string]string) {
	// 第一轮：精确静态匹配（host 限定的路由优先）
	for route in routes {
		if route.method != method {
			continue
		}
		// Host 检查：如果路由有 host 限制，必须匹配
		if route.host.len > 0 && route.host != host {
			continue
		}
		if route.segments.len == 0 && (url_path == '/' || url_path == '') {
			return route, map[string]string{}
		}
		mut has_params := false
		for seg in route.segments {
			if seg.is_param {
				has_params = true
				break
			}
		}
		if !has_params {
			mut route_path := ''
			for seg in route.segments {
				route_path += '/' + seg.value
			}
			if route_path == '' {
				route_path = '/'
			}
			// Match exact path, or either side having a trailing slash
			if route_path == url_path || route_path + '/' == url_path || route_path == url_path + '/' {
				return route, map[string]string{}
			}
		}
	}

	// 第二轮：参数路径匹配
	for route in routes {
		if route.method != method {
			continue
		}
		// Host 检查
		if route.host.len > 0 && route.host != host {
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

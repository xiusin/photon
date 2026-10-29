module web

// dispatcher.v — 路由匹配引擎
//
// 支持静态路径和 :param 路径参数的匹配。
// 匹配优先级：静态路径 > 参数路径（静态段多者优先，再按注册顺序）。
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
	method   string // GET / POST / PUT / DELETE / PATCH
	path     string // 原始路径，如 /api/v1/users/:id
	handler  RouteHandler = unsafe { nil } // 处理器闭包
	segments []RouteSegment // 编译后的路径段
	// static_count 是 segments 里静态段的数量，注册期算好。
	// 参数路由之间的「谁更具体」排序要用它，见 find_route()。
	static_count      int
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
	url_words := split_url_words(url_path)
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

// route_static_key 构造静态路由索引键：method:host:path
// host 为空表示无 host 限制（匹配任意 Host）。
fn route_static_key(method string, host string, path string) string {
	// 空路径归一化为 '/'（与 segments 为空时的根路由语义一致）
	key_path := if path.len == 0 { '/' } else { path }
	return method + ':' + host + ':' + key_path
}

// static_segment_score_of 数一段路由里「静态段」的个数。
// 只在注册期调用一次（见 RouteRegistry.add_route），结果存进
// RouteDef.static_count —— 匹配路径上不再重复遍历 segments。
fn static_segment_score_of(segments []RouteSegment) int {
	mut n := 0
	for seg in segments {
		if !seg.is_param {
			n++
		}
	}
	return n
}

// static_segment_score 读注册期算好的静态段数量 —— 参数路由之间的具体程度
// 排序依据。O(1)。
@[inline]
fn static_segment_score(route &RouteDef) int {
	return route.static_count
}

// split_url_words 按 '/' 切分 URL 并丢掉空段（'/a//b/' → ['a','b']）。
//
// 单次扫描：旧实现先 split 出一个容器再逐个 push 到第二个容器，每个请求
// 多一次分配 + 一次拷贝。
fn split_url_words(url_path string) []string {
	mut words := []string{cap: 4}
	mut start := 0
	for i in 0 .. url_path.len {
		if url_path[i] == `/` {
			if i > start {
				words << url_path[start..i]
			}
			start = i + 1
		}
	}
	if start < url_path.len {
		words << url_path[start..]
	}
	return words
}

// count_url_words 返回 URL 路径的有效段数（跳过空段）。
// 与 split_url_words().len 同语义，但不分配切片。
fn count_url_words(url_path string) int {
	mut count := 0
	mut in_word := false
	for i in 0 .. url_path.len {
		if url_path[i] == `/` {
			in_word = false
			continue
		}
		if !in_word {
			in_word = true
			count++
		}
	}
	return count
}

// find_static_route 在静态路由哈希表中做 O(1) 精确匹配。
// host 限定的路由优先于无限制路由；
// 候选路径包含尾斜杠容错（与旧线性扫描的匹配语义一致）。
fn find_static_route(rr &RouteRegistry, method string, url_path string, host string) ?&RouteDef {
	// Host 大小写不敏感（文档里承诺过，但注册时已 to_lower，查询侧没归一 →
	// `Host: Admin.Example.COM` 永远匹配不到 host 限定路由）。
	req_host := host.to_lower()
	mut candidates := [url_path]
	if url_path.len > 1 && url_path.ends_with('/') {
		candidates << url_path[..url_path.len - 1]
	} else if !url_path.ends_with('/') {
		candidates << url_path + '/'
	}

	for path in candidates {
		if req_host.len > 0 {
			key := route_static_key(method, req_host, path)
			if route := rr.static_routes[key] {
				return route
			}
		}
		key := route_static_key(method, '', path)
		if route := rr.static_routes[key] {
			return route
		}
	}
	return none
}

// find_route 在路由注册表中查找匹配的路由
// 匹配顺序：静态哈希表 O(1) → 参数路由按段数分桶 → 全量线性回退。
// host 参数用于 host 级路由隔离（空字符串 = 不限制 host）。
// 返回 (路由定义, 路径参数字典) 或 none
//
// Host 匹配规则：
//   - route.host 为空 → 匹配任意 host
//   - route.host 非空 → 必须与请求 host 完全匹配（大小写不敏感）
//   - host 限制的路由优先于无限制路由
pub fn find_route(rr &RouteRegistry, method string, url_path string, host string) ?(&RouteDef, map[string]string) {
	// 第一级：静态路由哈希表 O(1) 精确匹配
	if route := find_static_route(rr, method, url_path, host) {
		return route, map[string]string{}
	}

	// 第二级：参数路由按段数分桶匹配（仅比较段数相同的路由）
	//
	// 桶内不是简单「注册顺序优先」：同一段数下，静态段更多的路由更具体。
	// `/files/:id/download`（2 个静态段）必须赢过 `/files/:id/:action`
	// （1 个静态段），否则后者按注册顺序先落座，前者永远不可达 —— 不报错，
	// 只是请求走进了别的 handler。
	seg_count := count_url_words(url_path)
	req_host := host.to_lower()
	bucket := rr.param_routes[seg_count] or { []&RouteDef{} }
	mut best := unsafe { nil }
	mut best_params := map[string]string{}
	mut best_score := -1
	for route in bucket {
		if route.method != method {
			continue
		}
		// Host 检查：如果路由有 host 限制，必须匹配（大小写不敏感）
		mut host_bonus := 0
		if route.host.len > 0 {
			if route.host != req_host {
				continue
			}
			host_bonus = 1
		}
		params := match_route(url_path, route) or { continue }
		score := static_segment_score(route) * 2 + host_bonus
		if score > best_score {
			best = route
			best_params = params.clone()
			best_score = score
		}
	}
	if best_score >= 0 {
		return best, best_params
	}

	// 第三级：全量线性回退（兜底非规范 URL，如缺失前导斜杠、重复斜杠等）
	return find_route_linear(rr.routes, method, url_path, host)
}

// find_route_linear 旧版线性扫描匹配逻辑，作为 find_route 的最终兜底，
// 保证对任意非规范 URL 的行为与优化前完全一致。
fn find_route_linear(routes []&RouteDef, method string, url_path string, host string) ?(&RouteDef, map[string]string) {
	req_host := host.to_lower()
	// 第一轮：精确静态匹配（host 限定的路由优先）
	for route in routes {
		if route.method != method {
			continue
		}
		// Host 检查：如果路由有 host 限制，必须匹配
		if route.host.len > 0 && route.host != req_host {
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
			if route_path == url_path || route_path + '/' == url_path
				|| route_path == url_path + '/' {
				return route, map[string]string{}
			}
		}
	}

	// 第二轮：参数路径匹配（同等条件下静态段多的优先，理由同 find_route）
	mut best := unsafe { nil }
	mut best_params := map[string]string{}
	mut best_score := -1
	for route in routes {
		if route.method != method {
			continue
		}
		mut host_bonus := 0
		if route.host.len > 0 {
			if route.host != req_host {
				continue
			}
			host_bonus = 1
		}
		params := match_route(url_path, route) or { continue }
		score := static_segment_score(route) * 2 + host_bonus
		if score > best_score {
			best = route
			best_params = params.clone()
			best_score = score
		}
	}
	if best_score >= 0 {
		return best, best_params
	}

	return none
}

// ============================================================
// DispatchedRequest — 调度器上下文（注入到 before_request）
// ============================================================

// DispatchedRequest 是请求调度结果，在 before_request 中填充
pub struct DispatchedRequest {
pub mut:
	matched bool
	route   &RouteDef = unsafe { nil }
	params  map[string]string
}

// new_dispatched_request 创建 DispatchedRequest
pub fn new_dispatched_request() DispatchedRequest {
	return DispatchedRequest{
		params: map[string]string{}
	}
}

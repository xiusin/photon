module web

// route_group_regression_test.v — group() must not drop what it did not create.
//
// group() 曾经用 register(method, path, handler) 把子路由搬进父表，而
// register() 只认识这三样东西：子表上 register_with_middleware() 挂的路由级
// 中间件和 register_with_host() 的 host 限制被静默丢弃 —— 组里的鉴权中间件
// 就此失效，请求照常打进 handler，没有任何报错。
import veb

// noop_route 只用于注册，不实际调用。
fn noop_route(ctx_ptr voidptr, params map[string]string) veb.Result {
	mut ctx := unsafe { &veb.Context(ctx_ptr) }
	return ctx.text('')
}

fn group_marker_mw(mctx &MiddlewareContext) !bool {
	return true
}

fn group_after_mw(mctx &MiddlewareContext) !bool {
	return true
}

fn test_group_preserves_route_middlewares() {
	mut rr := new_route_registry()
	rr.group('/api/v1', fn (mut sub RouteRegistry) {
		sub.register_with_middleware('GET', '/admin', noop_route, [group_marker_mw], [
			group_after_mw,
		], '')
	})
	assert rr.routes.len == 1
	assert rr.routes[0].path == '/api/v1/admin'
	assert rr.routes[0].middlewares.len == 1
	assert rr.routes[0].after_middlewares.len == 1
}

fn test_group_preserves_host_restriction() {
	mut rr := new_route_registry()
	rr.group('/api', fn (mut sub RouteRegistry) {
		sub.register_with_host('GET', '/admin', noop_route, 'Admin.Example.com')
	})
	assert rr.routes.len == 1
	assert rr.routes[0].host == 'admin.example.com'
	// host 限定路由必须能匹配到（group 之前会丢掉 host，退化成匹配任意域名）
	found, _ := find_route(rr, 'GET', '/api/admin', 'admin.example.com') or {
		assert false, 'host-restricted route inside a group is unreachable'
		return
	}
	assert found.path == '/api/admin'
	_, _ := find_route(rr, 'GET', '/api/admin', 'other.example.com') or { return }
	assert false, 'host-restricted route matched a foreign host'
}

fn test_group_routes_are_dispatched_through_param_bucket() {
	mut rr := new_route_registry()
	rr.group('/api', fn (mut sub RouteRegistry) {
		sub.get('/users/:id', noop_route)
	})
	// group() 走 add_route，参数路由必须进分桶（'/api/users/:id' 是 3 段），
	// 否则只能靠线性兜底命中
	bucket := rr.param_routes[3] or { []&RouteDef{} }
	assert bucket.len == 1
	found, params := find_route(rr, 'GET', '/api/users/42', '') or {
		assert false, 'grouped param route not matched'
		return
	}
	assert params['id'] == '42'
	assert found.path == '/api/users/:id'
}

module web

// router_test.v - Tests for the closure-based RouteRegistry
import veb

// 测试用占位处理器（闭包），仅用于注册，不实际调用
fn noop_handler(ctx_ptr voidptr, params map[string]string) veb.Result {
	mut ctx := unsafe { &veb.Context(ctx_ptr) }
	return ctx.text('')
}

fn test_route_registry_new() {
	rr := new_route_registry()
	assert rr.routes.len == 0
	assert rr.route_count() == 0
}

fn test_route_registry_register() {
	mut rr := new_route_registry()
	rr.register('GET', '/users', noop_handler)
	rr.register('POST', '/users', noop_handler)
	assert rr.routes.len == 2
	assert rr.routes[0].method == 'GET'
	assert rr.routes[0].path == '/users'
	assert rr.routes[1].method == 'POST'
}

fn test_route_get() {
	mut rr := new_route_registry()
	rr.get('/api/users', noop_handler)
	assert rr.routes.len == 1
	assert rr.routes[0].method == 'GET'
	assert rr.routes[0].path == '/api/users'
}

fn test_route_post() {
	mut rr := new_route_registry()
	rr.post('/api/users', noop_handler)
	assert rr.routes[0].method == 'POST'
	assert rr.routes[0].path == '/api/users'
}

fn test_route_put() {
	mut rr := new_route_registry()
	rr.put('/api/users/:id', noop_handler)
	assert rr.routes[0].method == 'PUT'
	assert rr.routes[0].path == '/api/users/:id'
}

fn test_route_delete() {
	mut rr := new_route_registry()
	rr.delete('/api/users/:id', noop_handler)
	assert rr.routes[0].method == 'DELETE'
	assert rr.routes[0].path == '/api/users/:id'
}

fn test_route_patch() {
	mut rr := new_route_registry()
	rr.patch('/api/users/:id', noop_handler)
	assert rr.routes[0].method == 'PATCH'
}

fn test_route_group() {
	mut rr := new_route_registry()
	rr.group('/api/v1', fn (mut sub RouteRegistry) {
		sub.get('/users', noop_handler)
		sub.get('/users/:id', noop_handler)
		sub.post('/users', noop_handler)
	})
	assert rr.routes.len == 3
	assert rr.routes[0].path == '/api/v1/users'
	assert rr.routes[1].path == '/api/v1/users/:id'
	assert rr.routes[2].path == '/api/v1/users'
}

fn test_route_group_empty() {
	mut rr := new_route_registry()
	rr.group('/api', fn (mut sub RouteRegistry) {})
	assert rr.routes.len == 0
}

fn test_route_registry_multiple_register() {
	mut rr := new_route_registry()
	rr.register('GET', '/', noop_handler)
	rr.register('GET', '/health', noop_handler)
	rr.register('POST', '/login', noop_handler)
	assert rr.routes.len == 3
	assert rr.route_count() == 3
}

// 路径段编译验证（静态段 + :param 段）
fn test_route_segments_parsed() {
	mut rr := new_route_registry()
	rr.get('/api/users/:id', noop_handler)
	segs := rr.routes[0].segments
	assert segs.len == 3
	assert segs[0].value == 'api'
	assert segs[0].is_param == false
	assert segs[2].value == 'id'
	assert segs[2].is_param == true
}

// ═══════════════════════════════════════════════════════════
// 匹配优先级：静态段 > 注册顺序
// ═══════════════════════════════════════════════════════════

// 同一段数下，静态段更多的参数路由更具体，必须优先命中。
// 旧实现按注册顺序取桶内第一个匹配项，于是顺序一换，请求就静默走进
// 别的 handler —— 没有报错，只是结果不对。
fn test_param_route_more_static_segments_wins() {
	mut rr := new_route_registry()
	// 故意先注册更宽的那条
	rr.get('/files/:id/:action', noop_handler)
	rr.get('/files/:id/download', noop_handler)

	found, params := find_route(rr, 'GET', '/files/42/download', '') or {
		assert false, 'route not found'
		return
	}
	assert found.path == '/files/:id/download'
	assert params['id'] == '42'
}

fn test_param_route_static_segments_win_reverse_registration_order() {
	mut rr := new_route_registry()
	rr.get('/files/:id/download', noop_handler)
	rr.get('/files/:id/:action', noop_handler)

	found, _ := find_route(rr, 'GET', '/files/42/archive', '') or {
		assert false, 'route not found'
		return
	}
	assert found.path == '/files/:id/:action'
}

// Host 匹配大小写不敏感：注册时 to_lower，查询侧也必须归一。
fn test_static_route_host_match_is_case_insensitive() {
	mut rr := new_route_registry()
	rr.register_with_host('GET', '/admin', noop_handler, 'Admin.Example.COM')

	_, _ := find_route(rr, 'GET', '/admin', 'admin.example.com') or {
		assert false, 'lowercase host should match'
		return
	}
	_, _ = find_route(rr, 'GET', '/admin', 'ADMIN.EXAMPLE.COM') or {
		assert false, 'uppercase host should match'
		return
	}
}

fn test_param_route_host_match_is_case_insensitive() {
	mut rr := new_route_registry()
	rr.register_with_host('GET', '/t/:id', noop_handler, 'Tenant.Example.COM')

	_, params := find_route(rr, 'GET', '/t/abc', 'TENANT.EXAMPLE.COM') or {
		assert false, 'host-limited param route should match case-insensitively'
		return
	}
	assert params['id'] == 'abc'
}

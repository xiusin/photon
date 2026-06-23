module web

// router_test.v - Tests for the closure-based RouteRegistry
import veb

// 测试用占位处理器（闭包），仅用于注册，不实际调用
fn noop_handler(mut ctx veb.Context, params map[string]string) veb.Result {
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

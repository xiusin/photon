module web

// router_test.v - Tests for RouteRegistry and route helpers

fn test_route_registry_new() {
	rr := new_route_registry()
	assert rr.routes.len == 0
}

fn test_route_registry_register() {
	mut rr := new_route_registry()
	rr.register('GET', '/users', 'list_users')
	rr.register('POST', '/users', 'create_user')
	assert rr.routes.len == 2
	assert rr.routes[0].method == 'GET'
	assert rr.routes[0].path == '/users'
	assert rr.routes[0].handler_name == 'list_users'
}

fn test_route_get() {
	route := get('/api/users', 'get_users')
	assert route.method == 'GET'
	assert route.path == '/api/users'
	assert route.handler_name == 'get_users'
}

fn test_route_post() {
	route := post('/api/users', 'create_user')
	assert route.method == 'POST'
	assert route.path == '/api/users'
}

fn test_route_put() {
	route := put('/api/users/:id', 'update_user')
	assert route.method == 'PUT'
	assert route.path == '/api/users/:id'
}

fn test_route_delete() {
	route := del('/api/users/:id', 'delete_user')
	assert route.method == 'DELETE'
	assert route.path == '/api/users/:id'
}

fn test_route_patch() {
	route := patch('/api/users/:id', 'patch_user')
	assert route.method == 'PATCH'
}

fn test_route_group() {
	routes := [
		get('/users', 'list'),
		get('/users/:id', 'show'),
		post('/users', 'create'),
	]
	grouped := group('/api/v1', routes)
	assert grouped.len == 3
	assert grouped[0].path == '/api/v1/users'
	assert grouped[1].path == '/api/v1/users/:id'
	assert grouped[2].path == '/api/v1/users'
}

fn test_route_group_empty() {
	grouped := group('/api', [])
	assert grouped.len == 0
}

fn test_route_registry_multiple_register() {
	mut rr := new_route_registry()
	rr.register('GET', '/', 'index')
	rr.register('GET', '/health', 'health')
	rr.register('POST', '/login', 'login')
	assert rr.routes.len == 3
}

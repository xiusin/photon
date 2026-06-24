module web

// mount_test.v — mount_controller[T]() 单元测试
//
// 测试 comptime 控制器挂载功能：
//   1. 控制器路由自动扫描与注册
//   2. 分离式注解（@[get] + @['/path']）
//   3. 合并式注解（@[get: '/path']）
//   4. 路由前缀拼接
//   5. 路由匹配与分发
//   6. 控制器方法实际调用
import veb

// ═══════════════════════════════════════════════════════════
// 测试控制器定义
// ═══════════════════════════════════════════════════════════

// TestControllerA — 使用分离式注解的测试控制器
@[controller]
pub struct TestControllerA {
pub mut:
	called_name string
}

// 分离式注解：@[get] + @['/hello']
@[get]
@['/hello']
pub fn (mut c TestControllerA) hello(mut ctx veb.Context, params map[string]string) veb.Result {
	c.called_name = 'hello'
	return ctx.text('hello from A')
}

// 分离式注解：@[post] + @['/create']
@[post]
@['/create']
pub fn (mut c TestControllerA) create(mut ctx veb.Context, params map[string]string) veb.Result {
	c.called_name = 'create'
	return ctx.text('created')
}

// 带路径参数的路由
@[get]
@['/item/:id']
pub fn (mut c TestControllerA) show(mut ctx veb.Context, params map[string]string) veb.Result {
	id := params['id'] or { 'unknown' }
	c.called_name = 'show:${id}'
	return ctx.text('item:${id}')
}

// 无路径注解 → 默认使用方法名作为路径
@[get]
pub fn (mut c TestControllerA) ping(mut ctx veb.Context, params map[string]string) veb.Result {
	c.called_name = 'ping'
	return ctx.text('pong')
}

// TestControllerB — 使用合并式注解的测试控制器
@[controller]
@[prefix: '/api/v2']
pub struct TestControllerB {
pub mut:
	value int
}

// 合并式注解：@[get: '/users']
@[get: '/users']
pub fn (mut c TestControllerB) list(mut ctx veb.Context, params map[string]string) veb.Result {
	c.value = 42
	return ctx.text('users list')
}

// 合并式注解：@[post: '/users']
@[post: '/users']
pub fn (mut c TestControllerB) create(mut ctx veb.Context, params map[string]string) veb.Result {
	return ctx.text('user created')
}

// 合并式注解带参数
@[get: '/users/:id']
pub fn (mut c TestControllerB) show(mut ctx veb.Context, params map[string]string) veb.Result {
	id := params['id'] or { '0' }
	return ctx.text('user:${id}')
}

// TestControllerC — 带依赖的控制器（用于 DI 测试）
@[controller]
pub struct TestControllerC {
pub mut:
	service &TestService = unsafe { nil } @[autowired]
}

@[get: '/data']
pub fn (mut c TestControllerC) data(mut ctx veb.Context, params map[string]string) veb.Result {
	if !isnil(c.service) {
		return ctx.text('data:${c.service.value}')
	}
	return ctx.text('data:no-service')
}

// TestService — 用于 DI 注入测试的服务
pub struct TestService {
pub:
	value int
}

// ═══════════════════════════════════════════════════════════
// 路由注册测试
// ═══════════════════════════════════════════════════════════

fn test_mount_controller_separated_attrs() {
	mut rr := new_route_registry()
	ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	// 应该注册 4 条路由（hello, create, show, ping）
	assert rr.route_count() == 4, 'expected 4 routes, got ${rr.route_count()}'

	// 验证路由路径和方法
	mut found_hello := false
	mut found_create := false
	mut found_show := false
	mut found_ping := false

	for route in rr.routes {
		if route.path == '/api/hello' && route.method == 'GET' {
			found_hello = true
		}
		if route.path == '/api/create' && route.method == 'POST' {
			found_create = true
		}
		if route.path == '/api/item/:id' && route.method == 'GET' {
			found_show = true
		}
		if route.path == '/api/ping' && route.method == 'GET' {
			found_ping = true
		}
	}

	assert found_hello, 'route GET /api/hello not found'
	assert found_create, 'route POST /api/create not found'
	assert found_show, 'route GET /api/item/:id not found'
	assert found_ping, 'route GET /api/ping not found'
}

fn test_mount_controller_merged_attrs() {
	mut rr := new_route_registry()
	ctrl := &TestControllerB{}
	rr.mount_controller[TestControllerB](ctrl, '')

	// 应该注册 3 条路由
	assert rr.route_count() == 3, 'expected 3 routes, got ${rr.route_count()}'

	// 验证路由路径和方法
	mut found_list := false
	mut found_create := false
	mut found_show := false

	for route in rr.routes {
		if route.path == '/users' && route.method == 'GET' {
			found_list = true
		}
		if route.path == '/users' && route.method == 'POST' {
			found_create = true
		}
		if route.path == '/users/:id' && route.method == 'GET' {
			found_show = true
		}
	}

	assert found_list, 'route GET /users not found'
	assert found_create, 'route POST /users not found'
	assert found_show, 'route GET /users/:id not found'
}

fn test_mount_controller_with_prefix() {
	mut rr := new_route_registry()
	ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api/v1')

	// 验证前缀正确拼接
	mut found := false
	for route in rr.routes {
		if route.path == '/api/v1/hello' {
			found = true
		}
	}
	assert found, 'route with prefix /api/v1/hello not found'
}

fn test_mount_controller_auto_prefix() {
	mut rr := new_route_registry()
	ctrl := &TestControllerB{}
	// TestControllerB 有 @[prefix: '/api/v2'] 注解
	rr.mount_controller_auto[TestControllerB](ctrl, '/default')

	mut found := false
	for route in rr.routes {
		if route.path == '/api/v2/users' {
			found = true
		}
	}
	assert found, 'route with auto prefix /api/v2/users not found'
}

fn test_extract_controller_prefix() {
	prefix := extract_controller_prefix[TestControllerB]()
	assert prefix == '/api/v2', 'expected /api/v2, got "${prefix}"'

	prefix_a := extract_controller_prefix[TestControllerA]()
	assert prefix_a == '', 'expected empty prefix, got "${prefix_a}"'
}

fn test_parse_route_attrs_separated() {
	attr := parse_route_attrs('hello', ['get', '/hello']) or {
		assert false, 'should have found route'
		return
	}
	assert attr.method == 'GET'
	assert attr.path == '/hello'
}

fn test_parse_route_attrs_merged() {
	attr := parse_route_attrs('list', ["get: '/users'"]) or {
		assert false, 'should have found route'
		return
	}
	assert attr.method == 'GET'
	assert attr.path == '/users'
}

fn test_parse_route_attrs_default_path() {
	// 无路径 → 默认使用方法名
	attr := parse_route_attrs('index', ['get']) or {
		assert false, 'should have found route'
		return
	}
	assert attr.method == 'GET'
	assert attr.path == '/'
}

fn test_parse_route_attrs_no_method() {
	// 无 HTTP 方法 → 返回 none
	result := parse_route_attrs('helper', ['some_other_attr'])
	assert result == none, 'should return none for non-route method'
}

// ═══════════════════════════════════════════════════════════
// 路由分发测试
// ═══════════════════════════════════════════════════════════

fn test_dispatch_finds_route() {
	mut rr := new_route_registry()
	ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	mut ctx := &veb.Context{}
	ctx.req.url = '/api/hello'

	found := rr.dispatch('GET', '/api/hello', mut ctx)
	assert found, 'should have found and dispatched GET /api/hello'
}

fn test_dispatch_post_route() {
	mut rr := new_route_registry()
	ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	mut ctx := &veb.Context{}
	found := rr.dispatch('POST', '/api/create', mut ctx)
	assert found, 'should have found and dispatched POST /api/create'
}

fn test_dispatch_with_params() {
	mut rr := new_route_registry()
	ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	mut ctx := &veb.Context{}
	found := rr.dispatch('GET', '/api/item/42', mut ctx)
	assert found, 'should have found and dispatched GET /api/item/42'
}

fn test_dispatch_not_found() {
	mut rr := new_route_registry()
	ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	mut ctx := &veb.Context{}
	found := rr.dispatch('GET', '/api/nonexistent', mut ctx)
	assert !found, 'should not have found /api/nonexistent'
}

fn test_dispatch_wrong_method() {
	mut rr := new_route_registry()
	ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	mut ctx := &veb.Context{}
	// GET route should not match POST
	found := rr.dispatch('DELETE', '/api/hello', mut ctx)
	assert !found, 'should not have found DELETE /api/hello (only GET registered)'
}

// ═══════════════════════════════════════════════════════════
// 控制器方法调用验证
// ═══════════════════════════════════════════════════════════

fn test_controller_method_called() {
	mut rr := new_route_registry()
	mut ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	mut ctx := &veb.Context{}
	rr.dispatch('GET', '/api/hello', mut ctx)

	// 验证控制器方法被实际调用（called_name 被设置）
	assert ctrl.called_name == 'hello', 'controller method should have been called, called_name=${ctrl.called_name}'
}

fn test_controller_method_called_with_params() {
	mut rr := new_route_registry()
	mut ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	mut ctx := &veb.Context{}
	rr.dispatch('GET', '/api/item/99', mut ctx)

	// 验证路径参数被正确传递
	assert ctrl.called_name == 'show:99', 'controller should have received id=99, got ${ctrl.called_name}'
}

fn test_controller_method_ping_default_path() {
	mut rr := new_route_registry()
	mut ctrl := &TestControllerA{}
	rr.mount_controller[TestControllerA](ctrl, '/api')

	mut ctx := &veb.Context{}
	rr.dispatch('GET', '/api/ping', mut ctx)

	assert ctrl.called_name == 'ping', 'ping method should have been called'
}

// ═══════════════════════════════════════════════════════════
// 多控制器挂载测试
// ═══════════════════════════════════════════════════════════

fn test_mount_multiple_controllers() {
	mut rr := new_route_registry()
	ctrl_a := &TestControllerA{}
	ctrl_b := &TestControllerB{}

	rr.mount_controller[TestControllerA](ctrl_a, '/v1')
	rr.mount_controller[TestControllerB](ctrl_b, '/v2')

	// 总共 4 + 3 = 7 条路由
	assert rr.route_count() == 7, 'expected 7 routes, got ${rr.route_count()}'

	// 验证两个控制器的路由都能匹配
	mut ctx := &veb.Context{}
	assert rr.dispatch('GET', '/v1/hello', mut ctx)
	assert rr.dispatch('GET', '/v2/users', mut ctx)
}

// ═══════════════════════════════════════════════════════════
// WebModule 集成测试
// ═══════════════════════════════════════════════════════════

fn test_web_module_mount_controller() {
	mut wm := init_web_module()
	ctrl := &TestControllerA{}
	wm.mount_controller[TestControllerA](ctrl, '/api')

	assert wm.router.route_count() == 4, 'WebModule should have 4 routes'
}

fn test_web_module_mount_controller_auto() {
	mut wm := init_web_module()
	ctrl := &TestControllerB{}
	wm.mount_controller_auto[TestControllerB](ctrl, '/default')

	assert wm.router.route_count() == 3, 'WebModule should have 3 routes'

	// 验证使用了注解前缀
	mut found := false
	for route in wm.router.routes {
		if route.path == '/api/v2/users' {
			found = true
		}
	}
	assert found, 'should have route /api/v2/users from annotation prefix'
}

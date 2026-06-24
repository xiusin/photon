module web

// mount_test.v - Tests for mount[T] comptime controller mounting
//
// 验证 mount[T] 编译期控制器挂载功能：
//   1. 注册正确的路由数量
//   2. 路由路径正确（含 @[group] 前缀）
//   3. HTTP 方法正确
//   4. 请求能正确分发并调用控制器方法
//   5. @[autowired] 字段能从 ApplicationContext 注入
import veb
import core

// ============================================================
// 测试用服务
// ============================================================

// MountTestService — 用于测试 @[autowired] 注入的服务
pub struct MountTestService {
pub:
	value int
}

// ============================================================
// 测试控制器 1：带 @[group] 前缀，显式路径注解
// ============================================================

@[group: '/test']
pub struct MountTestController {
	veb.Context
}

// index GET /test/ — 列表
@['/'; get]
pub fn (mut c MountTestController) index() veb.Result {
	return c.text('index')
}

// show GET /test/:id — 详情
@['/:id'; get]
pub fn (mut c MountTestController) show() veb.Result {
	return c.text('show')
}

// create POST /test/create — 创建
@['/create'; post]
pub fn (mut c MountTestController) create() veb.Result {
	return c.text('created')
}

// update PUT /test/update — 更新
@['/update'; put]
pub fn (mut c MountTestController) update() veb.Result {
	return c.text('updated')
}

// destroy DELETE /test/destroy — 删除
@['/destroy'; delete]
pub fn (mut c MountTestController) destroy() veb.Result {
	return c.text('destroyed')
}

// not_a_route — 无路由注解，不应被注册
pub fn (mut c MountTestController) helper() int {
	return 42
}

// ============================================================
// 测试控制器 2：无 @[group] 前缀，约定式路由
// ============================================================

pub struct MountSimpleController {
	veb.Context
}

// index GET / — 约定式根路径
@[get]
pub fn (mut c MountSimpleController) index() veb.Result {
	return c.text('simple-index')
}

// list GET /list — 约定式路径
@[get]
pub fn (mut c MountSimpleController) list() veb.Result {
	return c.text('simple-list')
}

// ============================================================
// 测试控制器 3：带 @[autowired] 字段注入
// ============================================================

pub struct MountAutowireController {
	veb.Context
	svc &MountTestService = unsafe { nil } @[autowired]
}

@['/value'; get]
pub fn (mut c MountAutowireController) get_value() veb.Result {
	return c.text('value:${c.svc.value}')
}

// ============================================================
// 路由注册测试
// ============================================================

fn test_mount_registers_correct_route_count() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})
	// index, show, create, update, destroy = 5 条路由
	// helper() 无路由注解，不应注册
	assert rr.route_count() == 5
}

fn test_mount_with_group_prefix_paths() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})

	// 验证路径包含 /test 前缀
	mut paths := []string{}
	for route in rr.routes {
		paths << route.path
	}
	assert '/test/' in paths
	assert '/test/:id' in paths
	assert '/test/create' in paths
	assert '/test/update' in paths
	assert '/test/destroy' in paths
}

fn test_mount_http_methods() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})

	// 验证 HTTP 方法
	mut method_path_map := map[string]string{}
	for route in rr.routes {
		method_path_map['${route.method} ${route.path}'] = route.path
	}
	assert 'GET /test/' in method_path_map
	assert 'GET /test/:id' in method_path_map
	assert 'POST /test/create' in method_path_map
	assert 'PUT /test/update' in method_path_map
	assert 'DELETE /test/destroy' in method_path_map
}

fn test_mount_without_group_prefix() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountSimpleController](mut ctx, MountOptions{})

	// 无 @[group] 前缀，路径应为 / 和 /list
	mut paths := []string{}
	for route in rr.routes {
		paths << route.path
	}
	assert '/' in paths
	assert '/list' in paths
	assert rr.route_count() == 2
}

fn test_mount_with_options_prefix() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	// MountOptions.prefix 与 @[group] 前缀拼接
	rr.mount[MountTestController](mut ctx, MountOptions{ prefix: '/api/v1' })

	mut paths := []string{}
	for route in rr.routes {
		paths << route.path
	}
	// 前缀应为 /api/v1/test
	assert '/api/v1/test/' in paths
	assert '/api/v1/test/:id' in paths
	assert '/api/v1/test/create' in paths
}

// ============================================================
// 请求分发测试
// ============================================================

fn test_mount_dispatch_index() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	vctx.req.method = .get
	vctx.req.url = '/test/'
	dispatched := rr.dispatch('GET', '/test/', mut vctx)
	assert dispatched
	assert vctx.res.body == 'index'
}

fn test_mount_dispatch_show() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/test/42', mut vctx)
	assert dispatched
	assert vctx.res.body == 'show'
}

fn test_mount_dispatch_create() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('POST', '/test/create', mut vctx)
	assert dispatched
	assert vctx.res.body == 'created'
}

fn test_mount_dispatch_simple_index() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountSimpleController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/', mut vctx)
	assert dispatched
	assert vctx.res.body == 'simple-index'
}

fn test_mount_dispatch_simple_list() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountSimpleController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/list', mut vctx)
	assert dispatched
	assert vctx.res.body == 'simple-list'
}

// ============================================================
// @[autowired] 字段注入测试
// ============================================================

fn test_mount_autowired_injection() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()

	// 注册服务实例（bean 名为 'MountTestService'，去掉 & 前缀）
	svc := &MountTestService{
		value: 99
	}
	ctx.register_instance('MountTestService', voidptr(svc)) or { assert false }

	// 挂载控制器（挂载时预解析 @[autowired] 字段）
	rr.mount[MountAutowireController](mut ctx, MountOptions{})

	// 分发请求，验证服务已注入
	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/value', mut vctx)
	assert dispatched
	assert vctx.res.body == 'value:99'
}

// ============================================================
// WebModule.mount[T] 测试
// ============================================================

fn test_webmodule_mount_with_options() {
	mut wm := init_web_module()
	mut ctx := core.new_application_context()
	wm.mount[MountTestController](mut ctx, MountOptions{ prefix: '/api' })
	assert wm.router.route_count() == 5
}

fn test_webmodule_mount_without_options() {
	mut wm := init_web_module()
	mut ctx := core.new_application_context()
	wm.mount[MountSimpleController](mut ctx, MountOptions{})
	assert wm.router.route_count() == 2
}

// ============================================================
// 多控制器挂载测试
// ============================================================

fn test_mount_multiple_controllers() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})
	rr.mount[MountSimpleController](mut ctx, MountOptions{})

	// 5 + 2 = 7 条路由
	assert rr.route_count() == 7

	// 验证两个控制器的路由都能分发
	mut vctx1 := &veb.Context{}
	dispatched1 := rr.dispatch('GET', '/test/', mut vctx1)
	assert dispatched1
	assert vctx1.res.body == 'index'

	mut vctx2 := &veb.Context{}
	dispatched2 := rr.dispatch('GET', '/', mut vctx2)
	assert dispatched2
	assert vctx2.res.body == 'simple-index'
}

// ============================================================
// 未匹配路由测试
// ============================================================

fn test_mount_unmatched_route_returns_false() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	// 不存在的路径
	dispatched := rr.dispatch('GET', '/nonexistent', mut vctx)
	assert !dispatched
}

fn test_mount_wrong_method_returns_false() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MountTestController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	// POST 到 GET 路由
	dispatched := rr.dispatch('POST', '/test/', mut vctx)
	assert !dispatched
}

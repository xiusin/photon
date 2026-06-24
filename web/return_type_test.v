module web

// return_type_test.v - Task A5: 控制器方法返回值兼容性测试
//
// 验证 dispatch_route_method[T] 支持三种返回类型：
//   1. veb.Result      — 直接返回方法结果
//   2. !veb.Result     — 成功时使用方法写入的响应，失败时补写 500
//   3. !               — 同 !veb.Result
//
// 测试场景：
//   - veb.Result 方法：成功路径（已有行为，回归验证）
//   - !veb.Result 方法：成功路径（写入响应）、失败路径（补写 500）
//   - ! 方法：成功路径（写入响应）、失败路径（补写 500）
//   - ! 方法成功但不写响应：补写 500（约定：成功方法应写响应）
import veb
import core

// ============================================================
// 测试控制器：veb.Result 方法（回归验证）
// ============================================================

pub struct ReturnTypeResultController {
	veb.Context
}

@['/result/ok'; get]
pub fn (mut c ReturnTypeResultController) ok_handler() veb.Result {
	return c.text('result-ok')
}

// ============================================================
// 测试控制器：!veb.Result 方法
// ============================================================

pub struct ReturnTypeResultErrController {
	veb.Context
}

// 成功路径：写入 200 响应
@['/resulterr/success'; get]
pub fn (mut c ReturnTypeResultErrController) success_handler() !veb.Result {
	return c.text('resulterr-success')
}

// 失败路径：返回错误，应补写 500
@['/resulterr/fail'; get]
pub fn (mut c ReturnTypeResultErrController) fail_handler() !veb.Result {
	return error('resulterr-failure')
}

// ============================================================
// 测试控制器：! (void error) 方法
// ============================================================

pub struct ReturnTypeVoidErrController {
	veb.Context
}

// 成功路径：写入 200 响应
@['/voiderr/success'; get]
pub fn (mut c ReturnTypeVoidErrController) success_handler() ! {
	_ = c.text('voiderr-success')
}

// 失败路径：返回错误，应补写 500
@['/voiderr/fail'; get]
pub fn (mut c ReturnTypeVoidErrController) fail_handler() ! {
	return error('voiderr-failure')
}

// 成功但不写响应：约定上应补写 500（成功方法应显式写响应）
@['/voiderr/nowrite'; get]
pub fn (mut c ReturnTypeVoidErrController) nowrite_handler() ! {
	// 故意不写响应，验证 postwrite 补写 500
}

// ============================================================
// veb.Result 回归测试
// ============================================================

fn test_result_method_returns_response() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[ReturnTypeResultController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/result/ok', mut vctx)
	assert dispatched
	assert vctx.res.body == 'result-ok'
	assert vctx.res.status_code == 200
}

// ============================================================
// !veb.Result 测试
// ============================================================

fn test_resulterr_method_success_writes_response() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[ReturnTypeResultErrController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/resulterr/success', mut vctx)
	assert dispatched
	// 成功路径：方法写入的响应应被保留
	assert vctx.res.body == 'resulterr-success'
	assert vctx.res.status_code == 200
}

fn test_resulterr_method_failure_returns_500() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[ReturnTypeResultErrController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/resulterr/fail', mut vctx)
	assert dispatched
	// 失败路径：方法未写响应，应补写 500
	assert vctx.res.status_code == 500
	assert vctx.res.body == 'Internal Server Error'
}

// ============================================================
// ! (void error) 测试
// ============================================================

fn test_voiderr_method_success_writes_response() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[ReturnTypeVoidErrController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/voiderr/success', mut vctx)
	assert dispatched
	// 成功路径：方法写入的响应应被保留
	assert vctx.res.body == 'voiderr-success'
	assert vctx.res.status_code == 200
}

fn test_voiderr_method_failure_returns_500() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[ReturnTypeVoidErrController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/voiderr/fail', mut vctx)
	assert dispatched
	// 失败路径：方法未写响应，应补写 500
	assert vctx.res.status_code == 500
	assert vctx.res.body == 'Internal Server Error'
}

fn test_voiderr_method_success_nowrite_returns_500() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[ReturnTypeVoidErrController](mut ctx, MountOptions{})

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/voiderr/nowrite', mut vctx)
	assert dispatched
	// 成功但未写响应：约定上补写 500（成功方法应显式写响应）
	assert vctx.res.status_code == 500
}

// ============================================================
// 路由注册测试：验证 !veb.Result 和 ! 方法被正确注册
// ============================================================

fn test_resulterr_methods_registered() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[ReturnTypeResultErrController](mut ctx, MountOptions{})

	// success_handler 和 fail_handler 都应被注册
	assert rr.route_count() == 2

	mut paths := []string{}
	for route in rr.routes {
		paths << route.path
	}
	assert '/resulterr/success' in paths
	assert '/resulterr/fail' in paths
}

fn test_voiderr_methods_registered() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[ReturnTypeVoidErrController](mut ctx, MountOptions{})

	// success_handler, fail_handler, nowrite_handler 都应被注册
	assert rr.route_count() == 3

	mut paths := []string{}
	for route in rr.routes {
		paths << route.path
	}
	assert '/voiderr/success' in paths
	assert '/voiderr/fail' in paths
	assert '/voiderr/nowrite' in paths
}

// ============================================================
// 混合返回类型测试：同一控制器可包含不同返回类型的方法
// ============================================================

pub struct MixedReturnTypeController {
	veb.Context
}

@['/mixed/result'; get]
pub fn (mut c MixedReturnTypeController) result_handler() veb.Result {
	return c.text('mixed-result')
}

@['/mixed/resulterr'; get]
pub fn (mut c MixedReturnTypeController) resulterr_handler() !veb.Result {
	return c.text('mixed-resulterr')
}

@['/mixed/voiderr'; get]
pub fn (mut c MixedReturnTypeController) voiderr_handler() ! {
	_ = c.text('mixed-voiderr')
}

fn test_mixed_return_types_all_registered() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MixedReturnTypeController](mut ctx, MountOptions{})

	assert rr.route_count() == 3
}

fn test_mixed_return_types_all_dispatch_correctly() {
	mut rr := new_route_registry()
	mut ctx := core.new_application_context()
	rr.mount[MixedReturnTypeController](mut ctx, MountOptions{})

	// veb.Result 方法
	mut vctx1 := &veb.Context{}
	dispatched1 := rr.dispatch('GET', '/mixed/result', mut vctx1)
	assert dispatched1
	assert vctx1.res.body == 'mixed-result'
	assert vctx1.res.status_code == 200

	// !veb.Result 方法（成功）
	mut vctx2 := &veb.Context{}
	dispatched2 := rr.dispatch('GET', '/mixed/resulterr', mut vctx2)
	assert dispatched2
	assert vctx2.res.body == 'mixed-resulterr'
	assert vctx2.res.status_code == 200

	// ! 方法（成功）
	mut vctx3 := &veb.Context{}
	dispatched3 := rr.dispatch('GET', '/mixed/voiderr', mut vctx3)
	assert dispatched3
	assert vctx3.res.body == 'mixed-voiderr'
	assert vctx3.res.status_code == 200
}

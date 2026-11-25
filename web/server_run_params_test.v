module web

// server_run_params_test.v — run / run_with_routes 的参数、路由扫描与错误上抛
//
// 背景：run[A, X](port) 与 run_with_routes[A, X](port) 一直没有用例。
// 它们把端口写死在体内、一调用就独占端口永不返回，于是「这两个入口是否
// 正确」从未被验证 —— 这跟 run_with_graceful_shutdown 当年的处境一样：
// 没有用例的代码，全绿的测试报告里就没有它的声音。
//
// 这里靠 ServerRunParams + 注入启动器（run_by）在不起真服务的前提下把
// 三件事钉死：
//   1. 参数校验先于启动（端口非法时不碰启动器）
//   2. 监听地址与端口原样传给底层启动器
//   3. 启动器的错误原样回到调用方
// 外加 run_with_routes 的编译期路由扫描结果与 print_routes 的输出形状。
import veb

// ── 假应用/上下文：只为让泛型参数被实例化 ──

struct RunParamsProbeApp {}

struct RunParamsProbeCtx {
	veb.Context
}

// ── 带路由属性的控制器：验证 show_routes 走的扫描路径 ──

@[prefix: '/probe']
@[controller]
pub struct RunParamsProbeController {}

@[get: '/items']
pub fn (mut c RunParamsProbeController) list_items(mut ctx veb.Context) veb.Result {
	return ctx.text('items')
}

@[post: '/items']
pub fn (mut c RunParamsProbeController) create_item(mut ctx veb.Context) veb.Result {
	return ctx.text('created')
}

// 分离式 @[delete] + @['/items/:id'] —— 与合并式混用，验证两种写法都被认
@['/items/:id'; delete]
pub fn (mut c RunParamsProbeController) remove_item(mut ctx veb.Context) veb.Result {
	return ctx.text('removed')
}

// ── 启动器探针：记录收到的参数，不监听任何端口 ──

struct StarterProbe {
mut:
	called bool
	host   string
	port   int
}

fn probe_starter_ok(probe &StarterProbe) ServerStarter {
	return fn [probe] (app_ptr voidptr, params ServerRunParams) !string {
		unsafe {
			mut p := &StarterProbe(probe)
			p.called = true
			p.host = params.host
			p.port = params.port
		}
		_ := app_ptr
		return 'started on ${params.host}:${params.port}'
	}
}

fn probe_starter_failing(app_ptr voidptr, params ServerRunParams) !string {
	_ := app_ptr
	return error('bind failed on ${params.port}')
}

// ═══════════════════════════════════════════════════════════
// ServerRunParams 本身
// ═══════════════════════════════════════════════════════════

fn test_run_params_defaults() {
	p := new_server_run_params(8080)
	assert p.port == 8080
	assert p.host == '0.0.0.0'
	assert p.show_routes == false
}

fn test_run_params_with_host_returns_copy() {
	base := new_server_run_params(8080)
	other := base.with_host('127.0.0.1')
	assert other.host == '127.0.0.1'
	// 不可变链：改副本不能反噬原实例，否则并发下会互相踩
	assert base.host == '0.0.0.0'
}

fn test_run_params_with_routes_returns_copy() {
	base := new_server_run_params(8080)
	loud := base.with_routes(true)
	assert loud.show_routes == true
	assert base.show_routes == false
}

fn test_run_params_validate_accepts_boundary_ports() {
	new_server_run_params(1).validate() or { assert false, 'port 1 must be valid' }
	new_server_run_params(65535).validate() or { assert false, 'port 65535 must be valid' }
	new_server_run_params(8080).validate() or { assert false, 'port 8080 must be valid' }
}

fn test_run_params_validate_rejects_out_of_range() {
	for bad in [0, -1, 65536, 70000] {
		new_server_run_params(bad).validate() or {
			assert err.msg().contains('invalid port ${bad}')
			continue
		}
		assert false, 'port ${bad} should have been rejected'
	}
}

// ═══════════════════════════════════════════════════════════
// run_by —— 参数透传与错误上抛
// ═══════════════════════════════════════════════════════════

fn test_run_by_passes_host_and_port_to_starter() {
	probe := &StarterProbe{}
	note := run_by[RunParamsProbeApp, RunParamsProbeCtx](new_server_run_params(18081).with_host('127.0.0.1'),
		probe_starter_ok(probe)) or {
		assert false, 'unexpected: ${err}'
		return
	}
	assert probe.called
	assert probe.host == '127.0.0.1'
	assert probe.port == 18081
	assert note == 'started on 127.0.0.1:18081'
}

fn test_run_by_rejects_bad_port_without_calling_starter() {
	probe := &StarterProbe{}
	run_by[RunParamsProbeApp, RunParamsProbeCtx](new_server_run_params(0), probe_starter_ok(probe)) or {
		assert err.msg().contains('must be between 1 and 65535')
		// 校验必须发生在启动之前：端口不合法时不该去碰监听
		assert probe.called == false
		return
	}
	assert false, 'port 0 should have been rejected'
}

fn test_run_by_propagates_starter_error() {
	note := run_by[RunParamsProbeApp, RunParamsProbeCtx](new_server_run_params(18082),
		probe_starter_failing) or {
		assert err.msg().contains('bind failed on 18082')
		return
	}
	assert false, 'expected the starter error to surface, got ${note}'
}

fn test_run_by_scans_routes_when_show_routes() {
	// show_routes 只是「启动前打表」，不改变启动参数 —— 打表用的
	// scan_controller 是编译期扫描，不需要真实 app 实例
	probe := &StarterProbe{}
	routes := scan_controller[RunParamsProbeController]()
	assert routes.len == 3
	run_by[RunParamsProbeController, RunParamsProbeCtx](new_server_run_params(18083).with_routes(true),
		probe_starter_ok(probe)) or {
		assert false, 'unexpected: ${err}'
		return
	}
	assert probe.port == 18083
}

// ═══════════════════════════════════════════════════════════
// run_with_routes 依赖的扫描结果
// ═══════════════════════════════════════════════════════════

fn test_scan_controller_sees_prefixed_routes() {
	routes := scan_controller[RunParamsProbeController]()
	mut seen := map[string]bool{}
	for r in routes {
		seen['${r.method} ${r.path}'] = true
	}
	assert seen['GET /probe/items']
	assert seen['POST /probe/items']
}

fn test_scan_controller_sees_combined_and_separated_attrs() {
	// 合并式 @[get: '/items'] 曾经被 scan_controller 整条漏掉：它只比对
	// attr == 'get'（分离式），而 comptime 给出的是 "get: '/items'" 整串。
	// 于是 mount_controller（走 parse_route_attrs，认三种写法）把路由挂上，
	// print_routes / actuator /mappings 里却一条都没有。
	routes := scan_controller[RunParamsProbeController]()
	mut seen := map[string]bool{}
	for r in routes {
		seen['${r.method} ${r.path}'] = true
	}
	assert seen['GET /probe/items'], 'combined form @[get: ...] must be scanned'
	assert seen['POST /probe/items'], 'combined form @[post: ...] must be scanned'
	assert seen['DELETE /probe/items/:id'], 'separated form @[delete] + @[...] must be scanned'
	assert routes.len == 3
}

fn test_print_routes_output_shape() {
	// print_routes 会写入 stdout，这里只验证它对空表不乱打
	routes := scan_controller[RunParamsProbeApp]()
	assert routes.len == 0
	print_routes(routes)
}

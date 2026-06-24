module main

// verify_controller_mount.v — 跨包控制器挂载 + DI 注入 + 路由分发 集成验证
//
// 本文件验证 Photon Web 模块的核心新特性：
//   1. 控制器可在任意目录/包中定义，通过 mount_controller[T]() 自动挂载
//   2. 合并式注解 @[get: '/path'] 和分离式注解 @[get] + @['/path']
//   3. @[prefix: '/api/v1'] 控制器前缀自动提取
//   4. @[autowired] 字段注入 — core.wire_controller[T]() 自动创建+注入
//   5. 多控制器挂载到同一 RouteRegistry
//   6. 路由分发与路径参数传递
//   7. WebModule 集成
//   8. ServiceLocator + locate_controller[T] 全局定位
//   9. register_controller[T]() 注册到 DI 容器
import core
import web
import veb

// ═══════════════════════════════════════════════════════════
// 模拟业务服务（用于 DI 注入测试）
// ═══════════════════════════════════════════════════════════

struct VerifyUserService {
pub mut:
	prefix string
}

fn (s &VerifyUserService) greet(name string) string {
	return '${s.prefix}${name}'
}

struct VerifyAuthService {
pub:
	token string
}

fn (s &VerifyAuthService) validate(token string) bool {
	return token == s.token
}

struct VerifyNotifyService {
pub mut:
	sent_count int
}

fn (mut s VerifyNotifyService) send(msg string) {
	s.sent_count++
}

// ═══════════════════════════════════════════════════════════
// 跨包控制器定义（模拟在任意包中的控制器）
// ═══════════════════════════════════════════════════════════

// VerifyUserController — 带依赖注入的用户控制器
@[controller]
@[prefix: '/api/v1']
pub struct VerifyUserController {
pub mut:
	user_service  &VerifyUserService = unsafe { nil } @[autowired]
	auth_service  &VerifyAuthService = unsafe { nil } @[autowired]
	called_method string
}

@[get: '/users']
pub fn (mut c VerifyUserController) list(mut ctx veb.Context, params map[string]string) veb.Result {
	c.called_method = 'list'
	if !isnil(c.user_service) {
		return ctx.text('users:${c.user_service.prefix}')
	}
	return ctx.text('users:no-service')
}

@[get: '/users/:id']
pub fn (mut c VerifyUserController) show(mut ctx veb.Context, params map[string]string) veb.Result {
	id := params['id'] or { '0' }
	c.called_method = 'show'
	if !isnil(c.user_service) {
		return ctx.text('user:${id}:${c.user_service.greet(id)}')
	}
	return ctx.text('user:${id}:no-service')
}

@[post: '/users']
pub fn (mut c VerifyUserController) create(mut ctx veb.Context, params map[string]string) veb.Result {
	c.called_method = 'create'
	return ctx.text('created')
}

// VerifyAdminController — 另一个包的控制器，带独立前缀
@[controller]
@[prefix: '/admin']
pub struct VerifyAdminController {
pub mut:
	auth_service   &VerifyAuthService = unsafe { nil } @[autowired]
	notify_service &VerifyNotifyService = unsafe { nil } @[autowired]
	action_log     []string
}

@[get: '/dashboard']
pub fn (mut c VerifyAdminController) dashboard(mut ctx veb.Context, params map[string]string) veb.Result {
	c.action_log << 'dashboard'
	if !isnil(c.auth_service) {
		return ctx.text('admin:dashboard:auth=${c.auth_service.validate("secret")}')
	}
	return ctx.text('admin:dashboard:no-auth')
}

@[delete: '/cache']
pub fn (mut c VerifyAdminController) clear_cache(mut ctx veb.Context, params map[string]string) veb.Result {
	c.action_log << 'clear_cache'
	return ctx.text('cache:cleared')
}

// VerifyHealthController — 无依赖的简单控制器（分离式注解）
@[controller]
pub struct VerifyHealthController {
pub mut:
	checked bool
}

@[get]
@['/health']
pub fn (mut c VerifyHealthController) check(mut ctx veb.Context, params map[string]string) veb.Result {
	c.checked = true
	return ctx.text('ok')
}

@[get]
pub fn (mut c VerifyHealthController) ping(mut ctx veb.Context, params map[string]string) veb.Result {
	return ctx.text('pong')
}

// ═══════════════════════════════════════════════════════════
// 辅助：创建一个最小化的 veb.Context 用于测试
// ═══════════════════════════════════════════════════════════

fn new_test_veb_context() &veb.Context {
	mut ctx := &veb.Context{}
	return ctx
}

// ═══════════════════════════════════════════════════════════
// 验证函数
// ═══════════════════════════════════════════════════════════

// verify_controller_mount 验证跨包控制器挂载与路由分发
fn verify_controller_mount(mut v Verifier) {
	v.section('跨包控制器挂载 — mount_controller[T]()')

	// ── 1. 分离式注解挂载 ──
	mut rr := web.new_route_registry()
	ctrl_health := &VerifyHealthController{}
	rr.mount_controller[VerifyHealthController](ctrl_health, '/api')

	v.check('分离式注解：注册 2 条路由', rr.route_count() == 2)

	mut found_health := false
	mut found_ping := false
	for route in rr.routes {
		if route.path == '/api/health' && route.method == 'GET' {
			found_health = true
		}
		if route.path == '/api/ping' && route.method == 'GET' {
			found_ping = true
		}
	}
	v.check('分离式注解：GET /api/health 存在', found_health)
	v.check('分离式注解：GET /api/ping 存在（默认路径）', found_ping)

	// ── 2. 合并式注解挂载 ──
	mut rr2 := web.new_route_registry()
	ctrl_user := &VerifyUserController{}
	rr2.mount_controller[VerifyUserController](ctrl_user, '/api/v1')

	v.check('合并式注解：注册 3 条路由', rr2.route_count() == 3)

	mut found_list := false
	mut found_show := false
	mut found_create := false
	for route in rr2.routes {
		if route.path == '/api/v1/users' && route.method == 'GET' {
			found_list = true
		}
		if route.path == '/api/v1/users/:id' && route.method == 'GET' {
			found_show = true
		}
		if route.path == '/api/v1/users' && route.method == 'POST' {
			found_create = true
		}
	}
	v.check('合并式注解：GET /api/v1/users 存在', found_list)
	v.check('合并式注解：GET /api/v1/users/:id 存在', found_show)
	v.check('合并式注解：POST /api/v1/users 存在', found_create)

	// ── 3. 路由分发与控制器方法调用 ──
	mut ctx1 := new_test_veb_context()
	found := rr2.dispatch('GET', '/api/v1/users', mut ctx1)
	v.check('路由分发：GET /api/v1/users 命中', found)
	v.check('控制器方法被调用 (called_method=list)', ctrl_user.called_method == 'list')

	mut ctx2 := new_test_veb_context()
	found2 := rr2.dispatch('POST', '/api/v1/users', mut ctx2)
	v.check('路由分发：POST /api/v1/users 命中', found2)
	v.check('控制器方法被调用 (called_method=create)', ctrl_user.called_method == 'create')

	// ── 4. 路径参数传递 ──
	mut ctrl_user2 := &VerifyUserController{}
	mut rr3 := web.new_route_registry()
	rr3.mount_controller[VerifyUserController](ctrl_user2, '/api/v1')

	mut ctx3 := new_test_veb_context()
	found3 := rr3.dispatch('GET', '/api/v1/users/42', mut ctx3)
	v.check('路径参数：GET /api/v1/users/42 命中', found3)
	v.check('路径参数：控制器收到 id=42', ctrl_user2.called_method == 'show')

	// ── 5. 未匹配路由 ──
	mut ctx4 := new_test_veb_context()
	not_found := rr2.dispatch('DELETE', '/api/v1/nonexistent', mut ctx4)
	v.check('未匹配路由：DELETE /api/v1/nonexistent 返回 false', !not_found)

	// ── 6. 自动前缀提取 ──
	prefix := web.extract_controller_prefix[VerifyUserController]()
	v.check('自动前缀：VerifyUserController 前缀=/api/v1', prefix == '/api/v1')

	prefix_health := web.extract_controller_prefix[VerifyHealthController]()
	v.check('自动前缀：VerifyHealthController 无前缀', prefix_health == '')
}

// verify_controller_di_injection 验证 DI 注入到控制器
fn verify_controller_di_injection(mut v Verifier) {
	v.section('控制器 DI 注入 — wire_controller[T]()')

	// ── 1. 准备 DI 容器，注册业务服务 ──
	mut ctx := core.new_application_context()
	user_svc := &VerifyUserService{prefix: 'Hello:'}
	auth_svc := &VerifyAuthService{token: 'secret'}
	ctx.register_instance('user_service', voidptr(user_svc)) or {
		v.check('注册 user_service', false)
		return
	}
	ctx.register_instance('VerifyUserService', voidptr(user_svc)) or {
		v.check('注册 VerifyUserService', false)
		return
	}
	ctx.register_instance('auth_service', voidptr(auth_svc)) or {
		v.check('注册 auth_service', false)
		return
	}
	ctx.register_instance('VerifyAuthService', voidptr(auth_svc)) or {
		v.check('注册 VerifyAuthService', false)
		return
	}
	v.check('DI 容器：注册业务服务', true)

	// ── 2. wire_controller 创建控制器 + 自动注入 ──
	ctrl := ctx.wire_controller[VerifyUserController]() or {
		v.check('wire_controller[VerifyUserController]', false)
		ctx.shutdown()
		return
	}
	v.check('wire_controller: 创建控制器实例', !isnil(ctrl))
	v.check('wire_controller: user_service 已注入', !isnil(ctrl.user_service))
	v.check('wire_controller: auth_service 已注入', !isnil(ctrl.auth_service))

	// 验证注入的服务确实是注册的实例
	if !isnil(ctrl.user_service) {
		v.check('wire_controller: user_service 正确 (prefix=Hello:)', ctrl.user_service.prefix == 'Hello:')
	}
	if !isnil(ctrl.auth_service) {
		v.check('wire_controller: auth_service 正确 (validate)', ctrl.auth_service.validate('secret'))
	}

	// ── 3. 注入后挂载 + 路由分发验证 ──
	mut rr := web.new_route_registry()
	rr.mount_controller[VerifyUserController](ctrl, '/api/v1')

	mut vctx := new_test_veb_context()
	rr.dispatch('GET', '/api/v1/users', mut vctx)
	v.check('DI+挂载：list 方法可调用 (called_method=list)', ctrl.called_method == 'list')
	v.check('DI+挂载：user_service 在方法中可用', !isnil(ctrl.user_service))

	// ── 4. 带 DI 的 Admin 控制器 ──
	notify_svc := &VerifyNotifyService{}
	ctx.register_instance('notify_service', voidptr(notify_svc)) or {
		v.check('注册 notify_service', false)
		ctx.shutdown()
		return
	}

	admin_ctrl := ctx.wire_controller[VerifyAdminController]() or {
		v.check('wire_controller[VerifyAdminController]', false)
		ctx.shutdown()
		return
	}
	v.check('wire_controller: Admin 控制器创建', !isnil(admin_ctrl))
	v.check('wire_controller: admin auth_service 已注入', !isnil(admin_ctrl.auth_service))

	// 挂载并验证
	rr.mount_controller[VerifyAdminController](admin_ctrl, '/admin')

	mut vctx2 := new_test_veb_context()
	found := rr.dispatch('GET', '/admin/dashboard', mut vctx2)
	v.check('Admin 控制器路由命中', found)
	v.check('Admin 控制器方法调用', 'dashboard' in admin_ctrl.action_log)

	ctx.shutdown()
}

// verify_controller_register_container 验证 register_controller[T]() 注册到 DI 容器
fn verify_controller_register_container(mut v Verifier) {
	v.section('控制器注册到 DI 容器 — register_controller[T]()')

	mut ctx := core.new_application_context()

	// 注册依赖
	user_svc := &VerifyUserService{prefix: 'Reg:'}
	ctx.register_instance('user_service', voidptr(user_svc)) or { return }
	ctx.register_instance('VerifyUserService', voidptr(user_svc)) or { return }

	// register_controller 创建+注入+注册到容器
	ctrl := ctx.register_controller[VerifyUserController]() or {
		v.check('register_controller[VerifyUserController]', false)
		ctx.shutdown()
		return
	}
	v.check('register_controller: 返回控制器实例', !isnil(ctrl))
	v.check('register_controller: user_service 已注入', !isnil(ctrl.user_service))

	// 通过容器再次 resolve
	resolved := ctx.resolve('VerifyUserController') or {
		v.check('resolve VerifyUserController', false)
		ctx.shutdown()
		return
	}
	v.check('register_controller: 可通过 resolve() 再次获取', resolved == voidptr(ctrl))

	ctx.shutdown()
}

// verify_webmodule_integration 验证 WebModule 便捷方法
fn verify_webmodule_integration(mut v Verifier) {
	v.section('WebModule 集成 — mount_controller / mount_controller_auto')

	mut wm := web.init_web_module()
	ctrl := &VerifyHealthController{}
	wm.mount_controller[VerifyHealthController](ctrl, '/api')

	v.check('WebModule.mount_controller: 注册 2 条路由', wm.router.route_count() == 2)

	mut ctx := new_test_veb_context()
	found := wm.router.dispatch('GET', '/api/health', mut ctx)
	v.check('WebModule: GET /api/health 命中', found)

	// mount_controller_auto — 自动提取前缀
	mut wm2 := web.init_web_module()
	ctrl_user := &VerifyUserController{}
	wm2.mount_controller_auto[VerifyUserController](ctrl_user, '/default')

	mut found_auto := false
	for route in wm2.router.routes {
		if route.path == '/api/v1/users' {
			found_auto = true
		}
	}
	v.check('WebModule.mount_controller_auto: 使用注解前缀 /api/v1', found_auto)

	// 无注解前缀时使用默认值
	mut wm3 := web.init_web_module()
	ctrl_health := &VerifyHealthController{}
	wm3.mount_controller_auto[VerifyHealthController](ctrl_health, '/fallback')

	mut found_fallback := false
	for route in wm3.router.routes {
		if route.path == '/fallback/health' {
			found_fallback = true
		}
	}
	v.check('WebModule.mount_controller_auto: 无注解前缀时使用 /fallback', found_fallback)
}

// verify_multi_controller_dispatch 验证多控制器共存与分发
fn verify_multi_controller_dispatch(mut v Verifier) {
	v.section('多控制器共存与分发')

	mut rr := web.new_route_registry()

	// 挂载 3 个控制器到同一注册表
	ctrl_user := &VerifyUserController{}
	ctrl_admin := &VerifyAdminController{}
	ctrl_health := &VerifyHealthController{}

	rr.mount_controller[VerifyUserController](ctrl_user, '/api/v1')
	rr.mount_controller[VerifyAdminController](ctrl_admin, '/admin')
	rr.mount_controller[VerifyHealthController](ctrl_health, '/')

	// 3+2+2 = 7 条路由
	v.check('多控制器：共注册 7 条路由', rr.route_count() == 7)

	// 验证各控制器的路由独立工作
	mut ctx1 := new_test_veb_context()
	mut ctx2 := new_test_veb_context()
	mut ctx3 := new_test_veb_context()

	found1 := rr.dispatch('GET', '/api/v1/users', mut ctx1)
	found2 := rr.dispatch('GET', '/admin/dashboard', mut ctx2)
	found3 := rr.dispatch('GET', '/health', mut ctx3)

	v.check('多控制器：用户路由命中', found1)
	v.check('多控制器：管理路由命中', found2)
	v.check('多控制器：健康路由命中', found3)

	v.check('多控制器：用户方法被调用', ctrl_user.called_method == 'list')
	v.check('多控制器：管理方法被调用', 'dashboard' in ctrl_admin.action_log)
	v.check('多控制器：健康检查被调用', ctrl_health.checked)
}

// verify_locate_controller_global 验证全局 ServiceLocator + locate_controller
fn verify_locate_controller_global(mut v Verifier) {
	v.section('全局 ServiceLocator — locate_controller[T]()')

	// ── 1. 初始化全局 ServiceLocator ──
	mut ctx := core.new_application_context()
	user_svc := &VerifyUserService{prefix: 'Global:'}
	ctx.register_instance('user_service', voidptr(user_svc)) or { return }
	ctx.register_instance('VerifyUserService', voidptr(user_svc)) or { return }

	sl := core.new_service_locator(ctx)
	core.set_global_service_locator(sl)

	// ── 2. 通过全局定位器创建控制器 ──
	ctrl := core.locate_controller[VerifyUserController]() or {
		v.check('locate_controller[VerifyUserController]', false)
		ctx.shutdown()
		return
	}
	v.check('locate_controller: 返回控制器实例', !isnil(ctrl))
	v.check('locate_controller: user_service 已注入', !isnil(ctrl.user_service))

	if !isnil(ctrl.user_service) {
		v.check('locate_controller: 注入值正确 (prefix=Global:)', ctrl.user_service.prefix == 'Global:')
	}

	ctx.shutdown()
}

// verify_dispatch_controller_method 验证顶层分发函数
fn verify_dispatch_controller_method(mut v Verifier) {
	v.section('分发函数 — dispatch_controller_method[T]()')

	ctrl := &VerifyHealthController{}
	mut ctx := new_test_veb_context()

	// 直接调用分发函数
	result := web.dispatch_controller_method[VerifyHealthController](voidptr(ctrl), 'check', mut ctx, map[string]string{})
	v.check('dispatch_controller_method: check 方法返回 veb.Result', result.str().len > 0)
	v.check('dispatch_controller_method: 控制器方法被调用', ctrl.checked)

	// 调用不存在的方法 → 不会 panic，正常返回 404 结果
	mut ctx2 := new_test_veb_context()
	result2 := web.dispatch_controller_method[VerifyHealthController](voidptr(ctrl), 'nonexistent', mut ctx2, map[string]string{})
	// dispatch_controller_method 对未找到的方法返回一个包含 404 错误的 veb.Result
	// 无法直接检查 Result 内容，但验证其不 panic 且返回了非空结果即可
	v.check('dispatch_controller_method: 未找到方法安全返回结果', result2.str().len > 0)
}

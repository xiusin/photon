module main

// verify_core.v — 依赖注入容器、生命周期、可用注解的验证

import core
import web
import orm
import ticker

// ── 用于 DI 验证的示例 Bean ──
struct GreetService {
mut:
	greeting string
}

fn (g &GreetService) greet(name string) string {
	return '${g.greeting}, ${name}!'
}

// Product 由 FactoryBean 构造，用于验证 singleton/prototype 作用域
struct Product {
mut:
	serial int
}

// SingletonFactory 实现 core.FactoryBean（is_singleton=true → 容器缓存实例）
struct SingletonFactory {}

fn (f &SingletonFactory) create() !voidptr {
	return voidptr(&Product{serial: 1})
}

fn (f &SingletonFactory) bean_type() string {
	return 'SingletonProduct'
}

fn (f &SingletonFactory) is_singleton() bool {
	return true
}

// PrototypeFactory（is_singleton=false → 每次 resolve 新建实例）
struct PrototypeFactory {}

fn (f &PrototypeFactory) create() !voidptr {
	return voidptr(&Product{serial: 2})
}

fn (f &PrototypeFactory) bean_type() string {
	return 'PrototypeProduct'
}

fn (f &PrototypeFactory) is_singleton() bool {
	return false
}

// verify_di 验证 ApplicationContext 的属性、profile、Bean 注册与解析、作用域
fn verify_di(mut v Verifier) {
	v.section('依赖注入 / DI 容器 (core.ApplicationContext)')

	mut ctx := core.new_application_context()

	// 1) Environment 属性 + profile
	ctx.set_profiles(['dev', 'test'])
	ctx.set_property('app.name', 'PhotonVerify')
	v.check('set/get property', ctx.get_property_or('app.name', '') == 'PhotonVerify')
	v.check('get_property_or 默认值', ctx.get_property_or('missing.key', 'fallback') == 'fallback')
	v.check('has_profile(dev)', ctx.has_profile('dev'))
	v.check('has_profile(prod)=false', !ctx.has_profile('prod'))

	// 2) register_instance + resolve_typed（预构建单例）
	svc := &GreetService{
		greeting: 'Hello'
	}
	ctx.register_instance('GreetService', svc) or {
		v.check('register_instance', false)
		return
	}
	v.check('register_instance 成功', true)
	v.check('has(GreetService)', ctx.has('GreetService'))

	// 3) register_factory — singleton 作用域：两次 resolve 返回同一实例
	ctx.register_factory('SingletonProduct', &SingletonFactory{}) or {
		v.check('register_factory(singleton)', false)
		return
	}
	// 4) register_factory — prototype 作用域：两次 resolve 返回不同实例
	ctx.register_factory('PrototypeProduct', &PrototypeFactory{}) or {
		v.check('register_factory(prototype)', false)
		return
	}

	ctx.refresh() or {
		v.check('refresh()', false)
		return
	}
	v.check('refresh() 成功', true)

	// resolve_typed 取回强类型 Bean
	got := ctx.resolve_typed[GreetService]('GreetService') or {
		v.check('resolve_typed[GreetService]', false)
		return
	}
	v.check('resolve_typed 返回正确实例', got.greet('V') == 'Hello, V!')

	// 单例工厂：两次 resolve 指针相同
	s1 := ctx.resolve('SingletonProduct') or { unsafe { nil } }
	s2 := ctx.resolve('SingletonProduct') or { unsafe { nil } }
	v.check('singleton 作用域：两次解析同一实例', voidptr_eq(s1, s2) && !isnil(s1))

	// 原型工厂：两次 resolve 指针不同
	p1 := ctx.resolve('PrototypeProduct') or { unsafe { nil } }
	p2 := ctx.resolve('PrototypeProduct') or { unsafe { nil } }
	v.check('prototype 作用域：两次解析不同实例', !voidptr_eq(p1, p2) && !isnil(p1) && !isnil(p2))

	// bean 统计
	v.check('bean_count > 0', ctx.bean_count() > 0)

	ctx.shutdown()
	v.check('shutdown() 完成', true)
}

fn voidptr_eq(a voidptr, b voidptr) bool {
	return u64(a) == u64(b)
}

// ── 生命周期验证用 Bean + 追踪器 ──
struct LifecycleBean {
mut:
	name string
}

// EventTracker 用引用捕获记录回调触发顺序（闭包捕获值类型会复制，故用指针）
struct EventTracker {
mut:
	events []string
}

fn (mut t EventTracker) record(e string) {
	t.events << e
}

// verify_lifecycle 验证 @[post_construct]/@[pre_destroy]、InitializingBean/DisposableBean
// 回调的触发顺序（手动注册回调以模拟 comptime 自动扫描尚未实现的部分）
fn verify_lifecycle(mut v Verifier) {
	v.section('Bean 生命周期 (post_construct/pre_destroy/init/destroy)')

	mut tracker := &EventTracker{}
	mut ctx := core.new_application_context()

	// 注册 Bean 定义 + 预构建实例（生命周期需要定义才会被容器处理）
	ctx.register(core.new_bean_definition('LifecycleBean')) or {
		v.check('注册 Bean 定义', false)
		return
	}
	bean := &LifecycleBean{
		name: 'LB'
	}
	ctx.register_instance('LifecycleBean', bean) or {
		v.check('注册生命周期 Bean', false)
		return
	}

	// 注册生命周期回调（容器在 refresh/shutdown 时按序触发）
	ctx.lifecycle.register_post_construct('LifecycleBean', fn [mut tracker] () ! {
		tracker.record('post_construct')
	})
	ctx.container.register_init_callback('LifecycleBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('after_properties_set')
	})
	ctx.lifecycle.register_pre_destroy('LifecycleBean', fn [mut tracker] () ! {
		tracker.record('pre_destroy')
	})
	ctx.container.register_destroy_callback('LifecycleBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy')
	})

	ctx.refresh() or {
		v.check('refresh() 触发初始化回调', false)
		return
	}
	v.check('refresh 后触发 post_construct', 'post_construct' in tracker.events)
	v.check('refresh 后触发 after_properties_set (InitializingBean)', 'after_properties_set' in tracker.events)
	v.check('初始化顺序: post_construct 先于 after_properties_set', index_of(tracker.events,
		'post_construct') < index_of(tracker.events, 'after_properties_set'))

	ctx.shutdown()
	v.check('shutdown 后触发 pre_destroy', 'pre_destroy' in tracker.events)
	v.check('shutdown 后触发 destroy (DisposableBean)', 'destroy' in tracker.events)
}

fn index_of(arr []string, s string) int {
	for i, e in arr {
		if e == s {
			return i
		}
	}
	return -1
}

// ── 注解验证：@[scheduled] / @[transactional] / @[controller]+@[get] ──

// MockTxManager 实现 begin/commit/rollback 供 core.transactional_wrap 使用
struct MockTxManager {
mut:
	began      bool
	committed  bool
	rolledback bool
}

pub fn (mut m MockTxManager) begin() ! {
	m.began = true
}

pub fn (mut m MockTxManager) commit() ! {
	m.committed = true
}

pub fn (mut m MockTxManager) rollback() ! {
	m.rolledback = true
}

// SchedJobService 带 @[scheduled] 注解的方法（comptime 自动注册路径，真实可用）
struct SchedJobService {
mut:
	runs int
}

@[scheduled: '* * * * *']
fn (mut s SchedJobService) heartbeat() {
	s.runs++
}

// VerifyController 演示路由注解（@['/path'; verb] 组合形式）
@[controller]
struct VerifyController {
}

@['/hello'; get]
fn (c &VerifyController) hello() string {
	return 'hi'
}

@['/users/:id'; post]
fn (c &VerifyController) create_user() string {
	return 'created'
}

fn verify_annotations(mut v Verifier) {
	v.section('注解 (@[transactional] / @[scheduled] / @[controller]+路由)')

	// 1) @[transactional] — core.transactional_wrap 成功路径 → commit
	mut tm_ok := MockTxManager{}
	core.transactional_wrap(mut tm_ok, fn () ! {
		// 业务逻辑成功
	}) or {}
	v.check('@[transactional] 成功 → begin', tm_ok.began)
	v.check('@[transactional] 成功 → commit', tm_ok.committed)
	v.check('@[transactional] 成功 → 不 rollback', !tm_ok.rolledback)

	// 2) @[transactional] — 失败路径 → rollback
	mut tm_err := MockTxManager{}
	core.transactional_wrap(mut tm_err, fn () ! {
		return error('boom')
	}) or {}
	v.check('@[transactional] 失败 → rollback', tm_err.rolledback)
	v.check('@[transactional] 失败 → 不 commit', !tm_err.committed)

	// 3) @[scheduled] — comptime 扫描并注册到 Scheduler（真实可用注解路径）
	mut ctx := core.new_application_context()
	sched_svc := &SchedJobService{}
	ctx.register_instance('SchedJobService', sched_svc) or {}
	mut scheduler := ticker.new_task_scheduler()
	ctx.register_scheduled[SchedJobService](mut scheduler) or {
		v.check('register_scheduled[@[scheduled]]', false)
		return
	}
	v.check('@[scheduled] 被 comptime 扫描并注册任务', scheduler.task_count() > 0)
	ctx.shutdown()

	// 4) @[controller] + 路由注解 — web.scan_controller 编译期扫描
	routes := web.scan_controller[VerifyController]()
	v.check('scan_controller 扫描到路由', routes.len >= 2)
	mut has_get_hello := false
	mut has_post_user := false
	for r in routes {
		if r.method == 'GET' && r.path == '/hello' {
			has_get_hello = true
		}
		if r.method == 'POST' && r.path == '/users/:id' {
			has_post_user = true
		}
	}
	v.check('路由注解 @[\'/hello\'; get] 解析正确', has_get_hello)
	v.check('路由注解 @[\'/users/:id\'; post] 解析正确', has_post_user)

	// 5) @[table]/@[primary_key] — 实体元数据（BaseEntity）
	mut ent := orm.BaseEntity{}
	v.check('BaseEntity.is_new() (id=0)', ent.is_new())
	ent.id = 5
	v.check('BaseEntity.id() 取主键', ent.id() == 5)
	v.check('BaseEntity.is_new()=false (id!=0)', !ent.is_new())
}

// verify_cycle_detection 验证 bean 依赖图的循环检测（DFS，报出准确环路径）。
// 依赖边来自 @[autowired] 字段与 @[depends_on]（编译期注解扫描提取），
// 在容器装配（refresh）前检查，禁止循环依赖。
fn verify_cycle_detection(mut v Verifier) {
	v.section('依赖循环检测 (bean 依赖图 DFS)')

	// 无环：线性链 A → B → C
	mut ok_ctx := core.new_application_context()
	ok_ctx.register_bean('SvcA', core.BeanRegistrationOptions{ depends_on: ['SvcB'] }) or {}
	ok_ctx.register_bean('SvcB', core.BeanRegistrationOptions{ depends_on: ['SvcC'] }) or {}
	ok_ctx.register_bean('SvcC', core.BeanRegistrationOptions{}) or {}
	v.check('无环图：find_dependency_cycle 为空', ok_ctx.container.find_dependency_cycle().len == 0)
	mut ok_pass := true
	ok_ctx.container.check_circular_dependencies() or { ok_pass = false }
	v.check('无环图：check_circular_dependencies 通过', ok_pass)
	ok_ctx.shutdown()

	// 有环：A → B → A
	mut bad_ctx := core.new_application_context()
	bad_ctx.register_bean('SvcA', core.BeanRegistrationOptions{ depends_on: ['SvcB'] }) or {}
	bad_ctx.register_bean('SvcB', core.BeanRegistrationOptions{ depends_on: ['SvcA'] }) or {}
	cyc := bad_ctx.container.find_dependency_cycle()
	v.check('有环图：检出循环', cyc.len > 0)
	v.check('有环图：环路径闭合(首尾相接)', cyc.len >= 2 && cyc.first() == cyc.last())
	v.check('有环图：路径含 SvcA 与 SvcB', 'SvcA' in cyc && 'SvcB' in cyc)
	mut bad_errored := false
	bad_ctx.container.check_circular_dependencies() or {
		bad_errored = true
		v.check('有环图：错误信息含 circular dependency', err.msg().contains('circular dependency'))
	}
	v.check('有环图：check_circular_dependencies 报错', bad_errored)
	mut refresh_errored := false
	bad_ctx.refresh() or { refresh_errored = true }
	v.check('有环图：refresh 因循环依赖被拒绝', refresh_errored)
	bad_ctx.shutdown()

	// 三节点环：A → B → C → A
	mut tri := core.new_application_context()
	tri.register_bean('SvcA', core.BeanRegistrationOptions{ depends_on: ['SvcB'] }) or {}
	tri.register_bean('SvcB', core.BeanRegistrationOptions{ depends_on: ['SvcC'] }) or {}
	tri.register_bean('SvcC', core.BeanRegistrationOptions{ depends_on: ['SvcA'] }) or {}
	tcyc := tri.container.find_dependency_cycle()
	v.check('三节点环：检出且含 A/B/C', tcyc.len > 0 && 'SvcA' in tcyc && 'SvcB' in tcyc
		&& 'SvcC' in tcyc)
	tri.shutdown()
}

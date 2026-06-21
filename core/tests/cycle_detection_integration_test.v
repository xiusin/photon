module tests

import core

// cycle_detection_integration_test.v — 依赖循环检测的端到端集成测试
//
// 与 cycle_detection_test.v（纯算法单元测试）不同，这里注册真实的 bean
// 定义 + 实例 + 生命周期回调，跑完整 refresh() 流程，验证：
//   1. 无环图：refresh 成功、按依赖序实例化、@[post_construct] 触发、可解析；
//   2. 多层环：refresh 在实例化(step 5)之前的循环检查(step 4)就被拒绝，
//      报出准确环路径，且没有任何 bean 被实例化（无 post_construct 触发）；
//   3. @[autowired] 依赖 + @[depends_on] 混合成环也能检出。

// ── 集成测试用 bean ──
pub struct IntLogger {
mut:
	tag string
}

pub struct IntRepo {
mut:
	name string
}

pub struct IntService {
mut:
	name string
}

// IntTracker 引用捕获记录生命周期触发顺序
struct IntTracker {
mut:
	events []string
}

fn (mut t IntTracker) record(e string) {
	t.events << e
}

// 1) 无环图：完整 refresh 成功、依赖序、生命周期、解析
fn test_integration_acyclic_full_refresh() {
	mut tracker := &IntTracker{}
	mut ctx := core.new_application_context()

	// Logger（无依赖）
	ctx.register(core.new_bean_definition('IntLogger')) or { assert false }
	ctx.register_instance('IntLogger', &IntLogger{
		tag: 'log'
	}) or { assert false }
	ctx.lifecycle.register_post_construct('IntLogger', fn [mut tracker] () ! {
		tracker.record('IntLogger')
	})

	// Repo 依赖 Logger
	mut def_repo := core.new_bean_definition('IntRepo')
	def_repo.depends_on = ['IntLogger']
	ctx.register(def_repo) or { assert false }
	ctx.register_instance('IntRepo', &IntRepo{
		name: 'repo'
	}) or { assert false }
	ctx.lifecycle.register_post_construct('IntRepo', fn [mut tracker] () ! {
		tracker.record('IntRepo')
	})

	// Service 依赖 Repo
	mut def_svc := core.new_bean_definition('IntService')
	def_svc.depends_on = ['IntRepo']
	ctx.register(def_svc) or { assert false }
	ctx.register_instance('IntService', &IntService{
		name: 'svc'
	}) or { assert false }
	ctx.lifecycle.register_post_construct('IntService', fn [mut tracker] () ! {
		tracker.record('IntService')
	})

	// 无环
	assert ctx.container.find_dependency_cycle().len == 0

	// 完整装配
	ctx.refresh() or { assert false }

	// 全部可解析
	assert ctx.has('IntLogger')
	assert ctx.has('IntRepo')
	assert ctx.has('IntService')
	svc := ctx.resolve_typed[IntService]('IntService') or { panic(err) }
	assert svc.name == 'svc'

	// @[post_construct] 按依赖序触发：Logger → Repo → Service
	assert tracker.events.len == 3
	assert tracker.events.index('IntLogger') < tracker.events.index('IntRepo')
	assert tracker.events.index('IntRepo') < tracker.events.index('IntService')

	ctx.shutdown()
}

// 2) 多层环：refresh 在实例化前被拒绝，无 bean 被实例化
fn test_integration_multilayer_cycle_rejected_before_instantiation() {
	mut tracker := &IntTracker{}
	mut ctx := core.new_application_context()

	// BeanA → BeanB → BeanC → BeanA
	mut def_a := core.new_bean_definition('BeanA')
	def_a.depends_on = ['BeanB']
	ctx.register(def_a) or { assert false }
	ctx.register_instance('BeanA', &IntService{
		name: 'a'
	}) or { assert false }
	ctx.lifecycle.register_post_construct('BeanA', fn [mut tracker] () ! {
		tracker.record('BeanA')
	})

	mut def_b := core.new_bean_definition('BeanB')
	def_b.depends_on = ['BeanC']
	ctx.register(def_b) or { assert false }
	ctx.register_instance('BeanB', &IntService{
		name: 'b'
	}) or { assert false }
	ctx.lifecycle.register_post_construct('BeanB', fn [mut tracker] () ! {
		tracker.record('BeanB')
	})

	mut def_c := core.new_bean_definition('BeanC')
	def_c.depends_on = ['BeanA']
	ctx.register(def_c) or { assert false }
	ctx.register_instance('BeanC', &IntService{
		name: 'c'
	}) or { assert false }
	ctx.lifecycle.register_post_construct('BeanC', fn [mut tracker] () ! {
		tracker.record('BeanC')
	})

	// 环检出且路径闭合、含三节点
	cycle := ctx.container.find_dependency_cycle()
	assert cycle.len > 0
	assert cycle.first() == cycle.last()
	assert 'BeanA' in cycle
	assert 'BeanB' in cycle
	assert 'BeanC' in cycle

	// refresh 被拒绝
	mut errored := false
	ctx.refresh() or {
		errored = true
		assert err.msg().contains('circular dependency')
	}
	assert errored

	// 关键：循环检查(step 4)在实例化(step 5)之前 → 没有任何 bean 被实例化
	assert tracker.events.len == 0

	ctx.shutdown()
}

// 3) @[autowired] 依赖 + @[depends_on] 混合成环
fn test_integration_mixed_autowired_and_depends_on_cycle() {
	mut ctx := core.new_application_context()

	// MixA --(@[autowired])--> MixB --(@[depends_on])--> MixC --(@[depends_on])--> MixA
	ctx.register_bean('MixA', core.BeanRegistrationOptions{
		dependencies: [core.Dependency{
			type_name: 'MixB'
		}]
	}) or { assert false }
	ctx.register_bean('MixB', core.BeanRegistrationOptions{
		depends_on: ['MixC']
	}) or { assert false }
	ctx.register_bean('MixC', core.BeanRegistrationOptions{
		depends_on: ['MixA']
	}) or { assert false }

	cycle := ctx.container.find_dependency_cycle()
	assert cycle.len > 0
	assert cycle.first() == cycle.last()
	assert 'MixA' in cycle
	assert 'MixB' in cycle
	assert 'MixC' in cycle

	mut errored := false
	ctx.container.check_circular_dependencies() or {
		errored = true
		assert err.msg().contains('circular dependency')
	}
	assert errored
}

// 4) 给无环图新增一条回边即成环 —— 验证检测对增量边敏感
fn test_integration_adding_back_edge_creates_cycle() {
	mut ctx := core.new_application_context()

	// 先是无环 X → Y → Z
	ctx.register_bean('NodeX', core.BeanRegistrationOptions{
		depends_on: ['NodeY']
	}) or { assert false }
	ctx.register_bean('NodeY', core.BeanRegistrationOptions{
		depends_on: ['NodeZ']
	}) or { assert false }
	mut def_z := core.new_bean_definition('NodeZ')
	ctx.register(def_z) or { assert false }
	assert ctx.container.find_dependency_cycle().len == 0

	// 给 Z 加一条回到 X 的边 → 成环
	def_z.depends_on = ['NodeX']
	ctx.container.replace_definition(def_z) or { assert false }
	cycle := ctx.container.find_dependency_cycle()
	assert cycle.len > 0
	assert 'NodeX' in cycle
	assert 'NodeY' in cycle
	assert 'NodeZ' in cycle
}

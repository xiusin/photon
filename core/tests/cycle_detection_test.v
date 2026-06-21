module tests

import core

// cycle_detection_test.v — bean 依赖循环检测 (DFS, 报出准确环路径)

// is_closed 判断返回的环路径是否首尾相接（闭合）
fn is_closed(cycle []string) bool {
	return cycle.len >= 2 && cycle.first() == cycle.last()
}

fn contains_all(cycle []string, nodes []string) bool {
	for n in nodes {
		if n !in cycle {
			return false
		}
	}
	return true
}

fn test_no_cycle_linear_chain_passes() {
	mut ctx := core.new_application_context()
	// A → B → C （线性，无环）
	ctx.register_bean('A', core.BeanRegistrationOptions{ depends_on: ['B'] }) or { assert false }
	ctx.register_bean('B', core.BeanRegistrationOptions{ depends_on: ['C'] }) or { assert false }
	ctx.register_bean('C', core.BeanRegistrationOptions{}) or { assert false }

	cycle := ctx.container.find_dependency_cycle()
	assert cycle.len == 0
	ctx.container.check_circular_dependencies() or { assert false }
}

fn test_two_node_cycle_detected_with_path() {
	mut ctx := core.new_application_context()
	// A ↔ B
	ctx.register_bean('A', core.BeanRegistrationOptions{ depends_on: ['B'] }) or { assert false }
	ctx.register_bean('B', core.BeanRegistrationOptions{ depends_on: ['A'] }) or { assert false }

	cycle := ctx.container.find_dependency_cycle()
	assert cycle.len > 0
	assert is_closed(cycle)
	assert contains_all(cycle, ['A', 'B'])

	mut errored := false
	ctx.container.check_circular_dependencies() or {
		errored = true
		assert err.msg().contains('circular dependency')
		assert err.msg().contains('A')
		assert err.msg().contains('B')
	}
	assert errored
}

fn test_three_node_cycle_detected() {
	mut ctx := core.new_application_context()
	// A → B → C → A
	ctx.register_bean('A', core.BeanRegistrationOptions{ depends_on: ['B'] }) or { assert false }
	ctx.register_bean('B', core.BeanRegistrationOptions{ depends_on: ['C'] }) or { assert false }
	ctx.register_bean('C', core.BeanRegistrationOptions{ depends_on: ['A'] }) or { assert false }

	cycle := ctx.container.find_dependency_cycle()
	assert cycle.len > 0
	assert is_closed(cycle)
	assert contains_all(cycle, ['A', 'B', 'C'])
}

fn test_self_cycle_detected() {
	mut ctx := core.new_application_context()
	// A → A
	ctx.register_bean('A', core.BeanRegistrationOptions{ depends_on: ['A'] }) or { assert false }

	cycle := ctx.container.find_dependency_cycle()
	assert cycle.len > 0
	assert is_closed(cycle)
	assert 'A' in cycle
}

fn test_cycle_via_autowired_dependencies() {
	mut ctx := core.new_application_context()
	// 通过 @[autowired] 依赖（Dependency）形成 A ↔ B
	ctx.register_bean('A', core.BeanRegistrationOptions{
		dependencies: [core.Dependency{
			type_name: 'B'
		}]
	}) or { assert false }
	ctx.register_bean('B', core.BeanRegistrationOptions{
		dependencies: [core.Dependency{
			type_name: 'A'
		}]
	}) or { assert false }

	cycle := ctx.container.find_dependency_cycle()
	assert cycle.len > 0
	assert is_closed(cycle)
	assert contains_all(cycle, ['A', 'B'])
}

fn test_refresh_fails_on_cycle() {
	mut ctx := core.new_application_context()
	ctx.register_bean('A', core.BeanRegistrationOptions{ depends_on: ['B'] }) or { assert false }
	ctx.register_bean('B', core.BeanRegistrationOptions{ depends_on: ['A'] }) or { assert false }

	mut errored := false
	ctx.refresh() or {
		errored = true
		assert err.msg().contains('circular dependency')
	}
	assert errored
	ctx.shutdown()
}

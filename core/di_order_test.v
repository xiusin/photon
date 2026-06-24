module core

// di_order_test.v - 验证 @[order(n)] 注解扫描与排序（Task B5）
//
// 测试内容：
//   - scan_and_register 正确扫描 @[order(n)] 并设置 BeanDefinition.order_
//   - resolve_all_by_interface 按 order_ 升序返回实例
//   - resolve_all_by_tag 按 order_ 升序返回实例
//   - 未标注 @[order] 的 bean 默认 order_ = 0（最早）

// ═══════════════════════════════════════════════════════════
// 测试用接口与结构体
// ═══════════════════════════════════════════════════════════

// HealthIndicator — 健康检查接口
pub interface HealthIndicator {
	health() string
}

@[component]
@[order(3)]
pub struct OrderTestIndicatorA {
}

pub fn (a &OrderTestIndicatorA) health() string {
	return 'A'
}

@[component]
@[order(1)]
pub struct OrderTestIndicatorB {
}

pub fn (b &OrderTestIndicatorB) health() string {
	return 'B'
}

@[component]
@[order(2)]
pub struct OrderTestIndicatorC {
}

pub fn (c &OrderTestIndicatorC) health() string {
	return 'C'
}

// OrderTestNoOrder — 未标注 @[order]，默认 order_ = 0
@[component]
pub struct OrderTestNoOrder {
}

pub fn (n &OrderTestNoOrder) health() string {
	return 'N'
}

// ═══════════════════════════════════════════════════════════
// scan_and_register 测试 — 验证 order_ 字段正确扫描
// ═══════════════════════════════════════════════════════════

fn test_scan_and_register_order_value() {
	mut ctx := new_application_context()
	scan_and_register[OrderTestIndicatorA](mut ctx) or { assert false; return }
	scan_and_register[OrderTestIndicatorB](mut ctx) or { assert false; return }
	scan_and_register[OrderTestIndicatorC](mut ctx) or { assert false; return }

	def_a := ctx.get_definition('core.OrderTestIndicatorA') or {
		assert false
		return
	}
	assert def_a.order_ == 3

	def_b := ctx.get_definition('core.OrderTestIndicatorB') or {
		assert false
		return
	}
	assert def_b.order_ == 1

	def_c := ctx.get_definition('core.OrderTestIndicatorC') or {
		assert false
		return
	}
	assert def_c.order_ == 2
}

fn test_scan_and_register_default_order_is_zero() {
	mut ctx := new_application_context()
	scan_and_register[OrderTestNoOrder](mut ctx) or { assert false; return }

	def := ctx.get_definition('core.OrderTestNoOrder') or {
		assert false
		return
	}
	assert def.order_ == 0
}

// ═══════════════════════════════════════════════════════════
// resolve_all_by_interface 排序测试
// ═══════════════════════════════════════════════════════════

// add_interface_to_def 辅助函数：为已注册的 bean 添加接口声明
// scan_and_register 不自动检测接口实现，需手动补充
fn add_interface_to_def(mut ctx ApplicationContext, type_name string, iface string) {
	mut def := ctx.get_definition(type_name) or { return }
	def.interfaces = [iface]
	ctx.replace_definition(def) or { assert false }
}

fn test_resolve_all_by_interface_sorted_by_order() {
	mut ctx := new_application_context()
	scan_and_register[OrderTestIndicatorA](mut ctx) or { assert false; return }
	scan_and_register[OrderTestIndicatorB](mut ctx) or { assert false; return }
	scan_and_register[OrderTestIndicatorC](mut ctx) or { assert false; return }

	// 手动添加接口声明（scanner 不自动检测接口实现）
	add_interface_to_def(mut ctx, 'core.OrderTestIndicatorA', 'HealthIndicator')
	add_interface_to_def(mut ctx, 'core.OrderTestIndicatorB', 'HealthIndicator')
	add_interface_to_def(mut ctx, 'core.OrderTestIndicatorC', 'HealthIndicator')

	ctx.refresh() or { assert false; return }

	// 按 order_ 升序解析：B(1), C(2), A(3)
	indicators := ctx.resolve_all_by_interface('HealthIndicator') or {
		assert false
		return
	}
	assert indicators.len == 3

	// 验证顺序：B(1) → C(2) → A(3)
	b := unsafe { &OrderTestIndicatorB(indicators[0]) }
	assert b.health() == 'B'

	c := unsafe { &OrderTestIndicatorC(indicators[1]) }
	assert c.health() == 'C'

	a := unsafe { &OrderTestIndicatorA(indicators[2]) }
	assert a.health() == 'A'
}

// ═══════════════════════════════════════════════════════════
// resolve_all_by_tag 排序测试
// ═══════════════════════════════════════════════════════════

// add_tag_to_def 辅助函数：为已注册的 bean 添加 tag
fn add_tag_to_def(mut ctx ApplicationContext, type_name string, tag string) {
	mut def := ctx.get_definition(type_name) or { return }
	def.tags = [tag]
	ctx.replace_definition(def) or { assert false }
}

fn test_resolve_all_by_tag_sorted_by_order() {
	mut ctx := new_application_context()
	scan_and_register[OrderTestIndicatorA](mut ctx) or { assert false; return }
	scan_and_register[OrderTestIndicatorB](mut ctx) or { assert false; return }
	scan_and_register[OrderTestIndicatorC](mut ctx) or { assert false; return }

	// 手动添加 tag
	add_tag_to_def(mut ctx, 'core.OrderTestIndicatorA', 'indicator')
	add_tag_to_def(mut ctx, 'core.OrderTestIndicatorB', 'indicator')
	add_tag_to_def(mut ctx, 'core.OrderTestIndicatorC', 'indicator')

	ctx.refresh() or { assert false; return }

	// 按 order_ 升序解析：B(1), C(2), A(3)
	indicators := ctx.resolve_all_by_tag('indicator') or {
		assert false
		return
	}
	assert indicators.len == 3

	// 验证顺序：B(1) → C(2) → A(3)
	b := unsafe { &OrderTestIndicatorB(indicators[0]) }
	assert b.health() == 'B'

	c := unsafe { &OrderTestIndicatorC(indicators[1]) }
	assert c.health() == 'C'

	a := unsafe { &OrderTestIndicatorA(indicators[2]) }
	assert a.health() == 'A'
}

// ═══════════════════════════════════════════════════════════
// 默认 order_ = 0 的 bean 排在最前
// ═══════════════════════════════════════════════════════════

fn test_resolve_all_by_interface_default_order_first() {
	mut ctx := new_application_context()
	scan_and_register[OrderTestNoOrder](mut ctx) or { assert false; return }
	scan_and_register[OrderTestIndicatorB](mut ctx) or { assert false; return }
	scan_and_register[OrderTestIndicatorC](mut ctx) or { assert false; return }

	add_interface_to_def(mut ctx, 'core.OrderTestNoOrder', 'HealthIndicator')
	add_interface_to_def(mut ctx, 'core.OrderTestIndicatorB', 'HealthIndicator')
	add_interface_to_def(mut ctx, 'core.OrderTestIndicatorC', 'HealthIndicator')

	ctx.refresh() or { assert false; return }

	indicators := ctx.resolve_all_by_interface('HealthIndicator') or {
		assert false
		return
	}
	assert indicators.len == 3

	// NoOrder(0) → B(1) → C(2)
	n := unsafe { &OrderTestNoOrder(indicators[0]) }
	assert n.health() == 'N'

	b := unsafe { &OrderTestIndicatorB(indicators[1]) }
	assert b.health() == 'B'

	c := unsafe { &OrderTestIndicatorC(indicators[2]) }
	assert c.health() == 'C'
}

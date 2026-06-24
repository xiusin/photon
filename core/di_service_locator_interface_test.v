module core

// di_service_locator_interface_test.v - 验证 ServiceLocator 接口解析（Task B7）
//
// 测试内容：
//   - locate_service_name[T] 当 T 是接口时，按接口查找所有实现
//   - 多个实现时返回 @[primary] 标记的 bean 名称
//   - 单个实现时直接返回
//   - 无接口实现时回退到按类型名解析
//   - locate_service[T] 对结构体类型正常工作
//   - scan_and_register 扫描 @[primary] 标志
//
// V 0.5.1 限制说明：
//   当 T 是接口类型时，`unsafe { &T(instance) }` 无法正确设置接口的 vtable
//   （接口引用是胖指针 = 对象指针 + vtable 指针）。因此对接口类型，使用
//   locate_service_name[T]() 获取选中的 bean 名称，再通过 locate_service_by_name()
//   获取 voidptr 实例，最后用具体类型进行 unsafe 转换。
//   对结构体类型，locate_service[T]() 完全可用。

// ═══════════════════════════════════════════════════════════
// 测试用接口与结构体
// ═══════════════════════════════════════════════════════════

// TestCache — 缓存接口
pub interface TestCache {
	get(key string) ?string
}

// PrimaryCache — 主缓存实现（标记 @[primary]）
@[service]
@[primary]
pub struct PrimaryCache {
}

pub fn (c &PrimaryCache) get(key string) ?string {
	return 'primary:' + key
}

// SecondaryCache — 备用缓存实现
@[service]
pub struct SecondaryCache {
}

pub fn (c &SecondaryCache) get(key string) ?string {
	return 'secondary:' + key
}

// SingleCache — 单一实现（无 primary 标记）
@[service]
pub struct SingleCache {
}

pub fn (c &SingleCache) get(key string) ?string {
	return 'single:' + key
}

// ═══════════════════════════════════════════════════════════
// 辅助函数：注册带接口和实例的 bean
// ═══════════════════════════════════════════════════════════

// register_bean_with_interface 注册 bean 定义（含接口声明）和实例
fn register_bean_with_interface(mut ctx ApplicationContext, type_name string, instance voidptr, interfaces []string, is_primary bool) {
	mut def := new_bean_definition(type_name)
	def.interfaces = interfaces
	def.is_primary = is_primary
	ctx.register(def) or { assert false; return }
	ctx.register_instance(type_name, instance) or { assert false; return }
}

// ═══════════════════════════════════════════════════════════
// locate_service_name 接口解析测试 — 多实现时返回 @[primary] 名称
// ═══════════════════════════════════════════════════════════

fn test_locate_service_name_interface_returns_primary() {
	mut ctx := new_application_context()

	// 注册两个 TestCache 实现，PrimaryCache 标记 @[primary]
	primary := &PrimaryCache{}
	secondary := &SecondaryCache{}
	register_bean_with_interface(mut ctx, 'core.PrimaryCache', primary, ['core.TestCache'], true)
	register_bean_with_interface(mut ctx, 'core.SecondaryCache', secondary, ['core.TestCache'], false)

	// 设置全局 ServiceLocator
	locator := new_service_locator(ctx)
	set_global_service_locator(locator)

	// 按接口定位，应返回 @[primary] 标记的 PrimaryCache 名称
	name := locate_service_name[TestCache]() or {
		assert false
		return
	}
	assert name == 'core.PrimaryCache'

	// 通过名称获取实例，用具体类型转换后调用方法
	ptr := locate_service_by_name(name) or {
		assert false
		return
	}
	cache := unsafe { &PrimaryCache(ptr) }
	result := cache.get('test') or {
		assert false
		return
	}
	assert result == 'primary:test'
}

// ═══════════════════════════════════════════════════════════
// locate_service_name 接口解析测试 — 单实现时直接返回
// ═══════════════════════════════════════════════════════════

fn test_locate_service_name_interface_single_implementation() {
	mut ctx := new_application_context()

	single := &SingleCache{}
	register_bean_with_interface(mut ctx, 'core.SingleCache', single, ['core.TestCache'], false)

	locator := new_service_locator(ctx)
	set_global_service_locator(locator)

	// 单一实现，直接返回
	name := locate_service_name[TestCache]() or {
		assert false
		return
	}
	assert name == 'core.SingleCache'

	// 通过名称获取实例并调用方法
	ptr := locate_service_by_name(name) or {
		assert false
		return
	}
	cache := unsafe { &SingleCache(ptr) }
	result := cache.get('key') or {
		assert false
		return
	}
	assert result == 'single:key'
}

// ═══════════════════════════════════════════════════════════
// locate_service_name 回退测试 — 无接口实现时按类型名查找
// ═══════════════════════════════════════════════════════════

fn test_locate_service_name_falls_back_to_type_name() {
	mut ctx := new_application_context()

	// 注册 PrimaryCache 但不设置接口声明
	primary := &PrimaryCache{}
	ctx.register_instance('core.PrimaryCache', primary) or { assert false; return }

	locator := new_service_locator(ctx)
	set_global_service_locator(locator)

	// TestCache 无接口实现，回退到按类型名查找
	// 'core.TestCache' 不是注册的 bean，所以应失败
	_ := locate_service_name[TestCache]() or {
		// 预期失败 — 无 TestCache 接口实现，也无 'core.TestCache' bean
		assert true
		return
	}
	assert false // 不应到达
}

// ═══════════════════════════════════════════════════════════
// locate_service 结构体类型测试 — 直接按类型名解析并调用方法
// ═══════════════════════════════════════════════════════════

fn test_locate_service_struct_type() {
	mut ctx := new_application_context()

	primary := &PrimaryCache{}
	ctx.register_instance('core.PrimaryCache', primary) or { assert false; return }

	locator := new_service_locator(ctx)
	set_global_service_locator(locator)

	// 按结构体类型定位 — 结构体类型完全支持
	cache := locate_service[PrimaryCache]() or {
		assert false
		return
	}
	result := cache.get('x') or {
		assert false
		return
	}
	assert result == 'primary:x'
}

// ═══════════════════════════════════════════════════════════
// locate_service_name 结构体类型回退测试
// ═══════════════════════════════════════════════════════════

fn test_locate_service_name_struct_type() {
	mut ctx := new_application_context()

	primary := &PrimaryCache{}
	ctx.register_instance('core.PrimaryCache', primary) or { assert false; return }

	locator := new_service_locator(ctx)
	set_global_service_locator(locator)

	// 按结构体类型定位名称
	name := locate_service_name[PrimaryCache]() or {
		assert false
		return
	}
	assert name == 'core.PrimaryCache'
}

// ═══════════════════════════════════════════════════════════
// scan_and_register + @[primary] 扫描测试
// ═══════════════════════════════════════════════════════════

fn test_scan_and_register_primary_flag() {
	mut ctx := new_application_context()
	scan_and_register[PrimaryCache](mut ctx) or { assert false; return }
	scan_and_register[SecondaryCache](mut ctx) or { assert false; return }

	def_primary := ctx.get_definition('core.PrimaryCache') or {
		assert false
		return
	}
	assert def_primary.is_primary == true

	def_secondary := ctx.get_definition('core.SecondaryCache') or {
		assert false
		return
	}
	assert def_secondary.is_primary == false
}

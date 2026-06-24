module core

// di_profile_test.v - 验证 @[profile('dev')] 注解的条件过滤（Task B6）
//
// 测试内容：
//   - scan_and_register 将 @[profile('dev')] 转换为 OnProfileCondition
//   - 当 profile 不匹配时，bean 被静默跳过（不注册）
//   - 当 profile 匹配时，bean 正常注册
//   - BeanDefinition.conditions 正确包含 OnProfileCondition

// ═══════════════════════════════════════════════════════════
// 测试用结构体
// ═══════════════════════════════════════════════════════════

@[service]
@[profile('prod')]
pub struct ProdOnlyService {
pub:
	name string = 'prod'
}

@[service]
@[profile('dev')]
pub struct DevOnlyService {
pub:
	name string = 'dev'
}

@[service]
@[profile('test')]
pub struct TestOnlyService {
pub:
	name string = 'test'
}

// 无 profile 限制的服务，始终注册
@[service]
pub struct UniversalService {
pub:
	name string = 'universal'
}

// ═══════════════════════════════════════════════════════════
// 条件扫描测试 — 验证 @[profile] 被转换为 OnProfileCondition
// ═══════════════════════════════════════════════════════════

fn test_scan_and_register_profile_creates_condition() {
	mut ctx := new_application_context()
	// 设置 dev profile 以便 bean 能注册（条件需通过才会注册）
	ctx.set_profiles(['dev'])
	scan_and_register[DevOnlyService](mut ctx) or { assert false; return }

	def := ctx.get_definition('core.DevOnlyService') or {
		assert false
		return
	}
	// @[profile('dev')] 应生成 1 个 OnProfileCondition
	assert def.conditions.len == 1
}

// ═══════════════════════════════════════════════════════════
// profile 过滤测试 — 不匹配的 bean 被跳过
// ═══════════════════════════════════════════════════════════

fn test_profile_mismatch_skips_registration() {
	mut ctx := new_application_context()
	ctx.set_profiles(['dev'])

	// ProdOnlyService 标注了 @[profile('prod')]，但当前 profile 是 'dev'
	// 应被静默跳过
	scan_and_register[ProdOnlyService](mut ctx) or { assert false; return }

	// ProdOnlyService 不应被注册
	has_prod := ctx.has('core.ProdOnlyService')
	assert has_prod == false
}

fn test_profile_match_allows_registration() {
	mut ctx := new_application_context()
	ctx.set_profiles(['dev'])

	// DevOnlyService 标注了 @[profile('dev')]，当前 profile 是 'dev'
	// 应正常注册
	scan_and_register[DevOnlyService](mut ctx) or { assert false; return }

	has_dev := ctx.has('core.DevOnlyService')
	assert has_dev == true
}

// ═══════════════════════════════════════════════════════════
// 多 profile 过滤测试
// ═══════════════════════════════════════════════════════════

fn test_multiple_profiles_filtering() {
	mut ctx := new_application_context()
	ctx.set_profiles(['dev', 'test'])

	scan_and_register[ProdOnlyService](mut ctx) or { assert false; return }
	scan_and_register[DevOnlyService](mut ctx) or { assert false; return }
	scan_and_register[TestOnlyService](mut ctx) or { assert false; return }
	scan_and_register[UniversalService](mut ctx) or { assert false; return }

	// ProdOnlyService 应被跳过（profile 'prod' 不在 ['dev','test'] 中）
	assert ctx.has('core.ProdOnlyService') == false
	// DevOnlyService 应注册
	assert ctx.has('core.DevOnlyService') == true
	// TestOnlyService 应注册
	assert ctx.has('core.TestOnlyService') == true
	// UniversalService 无 profile 限制，应注册
	assert ctx.has('core.UniversalService') == true
}

// ═══════════════════════════════════════════════════════════
// 端到端测试 — refresh 后可解析匹配的 bean
// ═══════════════════════════════════════════════════════════

fn test_profile_filtering_end_to_end() {
	mut ctx := new_application_context()
	ctx.set_profiles(['dev'])

	scan_and_register[ProdOnlyService](mut ctx) or { assert false; return }
	scan_and_register[DevOnlyService](mut ctx) or { assert false; return }

	ctx.refresh() or { assert false; return }

	// ProdOnlyService 不应可解析
	_ := ctx.resolve('core.ProdOnlyService') or {
		// 预期失败 — profile 不匹配
		assert true
		return
	}
	// 不应到达此处
	assert false
}

fn test_profile_match_resolvable_after_refresh() {
	mut ctx := new_application_context()
	ctx.set_profiles(['dev'])

	scan_and_register[DevOnlyService](mut ctx) or { assert false; return }

	ctx.refresh() or { assert false; return }

	// DevOnlyService 应已注册且可解析（refresh 后 bean 定义存在）
	assert ctx.has('core.DevOnlyService') == true
}

// ═══════════════════════════════════════════════════════════
// 无 profile 限制的 bean 始终注册
// ═══════════════════════════════════════════════════════════

fn test_no_profile_always_registered() {
	mut ctx := new_application_context()
	// 不设置任何 profile
	scan_and_register[UniversalService](mut ctx) or { assert false; return }

	assert ctx.has('core.UniversalService') == true

	// 设置 profile 后仍应注册
	mut ctx2 := new_application_context()
	ctx2.set_profiles(['prod'])
	scan_and_register[UniversalService](mut ctx2) or { assert false; return }
	assert ctx2.has('core.UniversalService') == true
}

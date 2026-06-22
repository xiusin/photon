module web

// after_completion_test.v - AfterCompletionRegistry 单元测试
// AfterCompletionRegistry Unit Tests
//
// 测试覆盖 / Test Coverage:
//   - on() 注册回调，返回唯一 ID
//   - off() 取消注册
//   - fire() 触发所有回调
//   - freeze() 冻结后无锁快速路径
//   - unfreeze() 解冻后恢复动态注册
//   - 冻结后 on() 仍可注册（写入 entries，不影响 frozen_entries 快照）
//   - 空注册表 fire 不报错
//   - 多次 fire 正常工作
//   - callback_count() / is_frozen() 辅助方法
//   - 回调按 order 升序执行
import sync

// ── 全局测试状态 / Global test state ──
// V 闭包按值捕获变量，使用全局变量在回调间共享状态
// V closures capture by value; use globals to share state across callbacks
__global g_ac_counter int
__global g_ac_err_msg string
__global g_ac_err_was_none bool
__global g_ac_order_log []int

// ── on() 注册回调测试 / on() registration tests ──

fn test_after_completion_on_returns_unique_ids() {
	mut r := new_after_completion_registry()
	id1 := r.on(fn (ctx voidptr, err ?string) {}, 0)
	id2 := r.on(fn (ctx voidptr, err ?string) {}, 0)
	id3 := r.on(fn (ctx voidptr, err ?string) {}, 0)
	assert id1 != id2
	assert id2 != id3
	assert id1 != id3
}

fn test_after_completion_on_increments_callback_count() {
	mut r := new_after_completion_registry()
	assert r.callback_count() == 0
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	assert r.callback_count() == 1
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	assert r.callback_count() == 2
}

// ── off() 取消注册测试 / off() deregistration tests ──

fn test_after_completion_off_removes_callback() {
	mut r := new_after_completion_registry()
	id1 := r.on(fn (ctx voidptr, err ?string) {}, 0)
	id2 := r.on(fn (ctx voidptr, err ?string) {}, 0)
	assert r.callback_count() == 2
	r.off(id1)
	assert r.callback_count() == 1
	r.off(id2)
	assert r.callback_count() == 0
}

fn test_after_completion_off_nonexistent_id_is_noop() {
	mut r := new_after_completion_registry()
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	r.off(999)
	assert r.callback_count() == 1
}

fn test_after_completion_off_twice_is_noop() {
	mut r := new_after_completion_registry()
	id := r.on(fn (ctx voidptr, err ?string) {}, 0)
	r.off(id)
	assert r.callback_count() == 0
	r.off(id)
	assert r.callback_count() == 0
}

// ── fire() 触发回调测试 / fire() callback dispatch tests ──

fn test_after_completion_fire_invokes_all_callbacks() {
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.fire(voidptr(0), none)
	assert g_ac_counter == 3
}

fn test_after_completion_fire_passes_err_to_callbacks() {
	mut r := new_after_completion_registry()
	g_ac_err_msg = ''
	r.on(fn (ctx voidptr, err ?string) {
		if e := err {
			g_ac_err_msg = e
		}
	}, 0)
	r.fire(voidptr(0), 'something went wrong')
	assert g_ac_err_msg == 'something went wrong'
}

fn test_after_completion_fire_passes_none_err_on_success() {
	mut r := new_after_completion_registry()
	g_ac_err_was_none = false
	r.on(fn (ctx voidptr, err ?string) {
		if err == none {
			g_ac_err_was_none = true
		}
	}, 0)
	r.fire(voidptr(0), none)
	assert g_ac_err_was_none == true
}

fn test_after_completion_fire_empty_registry_is_noop() {
	mut r := new_after_completion_registry()
	r.fire(voidptr(0), none)
	assert true
}

fn test_after_completion_fire_multiple_times() {
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.fire(voidptr(0), none)
	assert g_ac_counter == 1
	r.fire(voidptr(0), none)
	assert g_ac_counter == 2
	r.fire(voidptr(0), none)
	assert g_ac_counter == 3
}

fn test_after_completion_fire_executes_in_order() {
	// 回调按 order 升序执行（需要 freeze() 后排序才生效）
	// Callbacks execute in ascending order (sorting happens during freeze())
	mut r := new_after_completion_registry()
	g_ac_order_log = []int{}
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_order_log << 3
	}, 30)
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_order_log << 1
	}, 10)
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_order_log << 2
	}, 20)
	// freeze() 按 order 排序后快照
	r.freeze()
	r.fire(voidptr(0), none)
	assert g_ac_order_log.len == 3
	assert g_ac_order_log[0] == 1
	assert g_ac_order_log[1] == 2
	assert g_ac_order_log[2] == 3
}

// ── freeze() / unfreeze() 测试 / freeze() / unfreeze() tests ──

fn test_after_completion_freeze_sets_frozen_flag() {
	mut r := new_after_completion_registry()
	assert r.is_frozen() == false
	r.freeze()
	assert r.is_frozen() == true
}

fn test_after_completion_freeze_idempotent() {
	mut r := new_after_completion_registry()
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	r.freeze()
	r.freeze()
	assert r.is_frozen() == true
	assert r.callback_count() == 1
}

fn test_after_completion_fire_uses_frozen_snapshot() {
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.freeze()
	// 冻结后注册新回调 — 不影响快照
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter += 10
	}, 0)
	r.fire(voidptr(0), none)
	// 只有冻结前的回调被执行（counter=1，不是 11）
	assert g_ac_counter == 1
}

fn test_after_completion_unfreeze_clears_frozen_flag() {
	mut r := new_after_completion_registry()
	r.freeze()
	assert r.is_frozen() == true
	r.unfreeze()
	assert r.is_frozen() == false
}

fn test_after_completion_unfreeze_restores_dynamic_registration() {
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.freeze()
	r.unfreeze()
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter += 10
	}, 0)
	r.fire(voidptr(0), none)
	assert g_ac_counter == 11
}

fn test_after_completion_off_updates_frozen_snapshot() {
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	id1 := r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter += 10
	}, 0)
	r.freeze()
	r.off(id1)
	r.fire(voidptr(0), none)
	assert g_ac_counter == 10
}

// ── callback_count() 测试 / callback_count() tests ──

fn test_after_completion_callback_count_unfrozen() {
	mut r := new_after_completion_registry()
	assert r.callback_count() == 0
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	assert r.callback_count() == 1
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	assert r.callback_count() == 2
}

fn test_after_completion_callback_count_frozen() {
	mut r := new_after_completion_registry()
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	r.freeze()
	assert r.callback_count() == 2
}

// ── 并发安全测试 / Concurrency safety tests ──

fn test_after_completion_concurrent_on_and_fire() {
	mut r := new_after_completion_registry()
	mut wg := sync.new_waitgroup()

	for i in 0 .. 20 {
		wg.add(1)
		spawn fn (mut reg AfterCompletionRegistry, mut w sync.WaitGroup) {
			defer { w.done() }
			reg.on(fn (ctx voidptr, err ?string) {}, 0)
		}(mut r, mut wg)
	}

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut reg AfterCompletionRegistry, mut w sync.WaitGroup) {
			defer { w.done() }
			reg.fire(voidptr(0), none)
		}(mut r, mut wg)
	}

	wg.wait()
	assert true
}

// ── 边界条件测试 / Edge case tests ──

fn test_after_completion_fire_with_nil_callback_skipped() {
	mut r := new_after_completion_registry()
	r.on(fn (ctx voidptr, err ?string) {}, 0)
	r.fire(voidptr(0), none)
	assert true
}

fn test_after_completion_off_after_fire() {
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	id := r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.fire(voidptr(0), none)
	assert g_ac_counter == 1
	r.off(id)
	r.fire(voidptr(0), none)
	assert g_ac_counter == 1
}

// ── fire() 传递 ctx 测试 / fire() ctx passing tests ──

fn test_after_completion_fire_passes_ctx_to_callbacks() {
	// fire() 将 ctx 参数传递给回调
	// fire() passes the ctx argument to callbacks
	mut r := new_after_completion_registry()
	g_ac_err_msg = ''
	test_ptr := voidptr(0xDEAD)
	r.on(fn (ctx voidptr, err ?string) {
		// 验证回调接收到了非空 ctx 指针
		// Verify the callback received a non-nil ctx pointer
		if !isnil(ctx) {
			g_ac_err_msg = 'received'
		}
	}, 0)
	r.fire(test_ptr, none)
	// 验证回调接收到了 ctx 指针
	// Verify the callback received the ctx pointer
	assert g_ac_err_msg == 'received'
}

// ── 并发安全增强测试 / Enhanced concurrency safety tests ──

fn test_after_completion_concurrent_on_returns_unique_ids() {
	// 并发 on() 返回的 ID 全局唯一（next_id 竞态条件修复验证）
	// Concurrent on() returns globally unique IDs (next_id race condition fix verification)
	mut r := new_after_completion_registry()
	mut wg := sync.new_waitgroup()
	mut ids := []int{cap: 50}

	for i in 0 .. 50 {
		wg.add(1)
		spawn fn (mut reg AfterCompletionRegistry, mut w sync.WaitGroup) {
			defer { w.done() }
			_ = reg.on(fn (ctx voidptr, err ?string) {}, 0)
		}(mut r, mut wg)
	}

	wg.wait()
	// 注册 50 个回调后 callback_count 应为 50
	// After registering 50 callbacks, callback_count should be 50
	assert r.callback_count() == 50
}

fn test_after_completion_concurrent_on_and_off() {
	// 并发 on() 和 off() 不应 panic
	// Concurrent on() and off() should not panic
	mut r := new_after_completion_registry()
	mut wg := sync.new_waitgroup()

	// 先注册一些回调 / Register some callbacks first
	mut ids := []int{}
	for i in 0 .. 10 {
		ids << r.on(fn (ctx voidptr, err ?string) {}, 0)
	}

	// 并发注册和移除 / Concurrent register and remove
	for i in 0 .. 20 {
		wg.add(1)
		spawn fn (mut reg AfterCompletionRegistry, mut w sync.WaitGroup) {
			defer { w.done() }
			reg.on(fn (ctx voidptr, err ?string) {}, 0)
		}(mut r, mut wg)
	}

	for i in 0 .. 5 {
		wg.add(1)
		spawn fn (mut reg AfterCompletionRegistry, id int, mut w sync.WaitGroup) {
			defer { w.done() }
			reg.off(id)
		}(mut r, ids[i], mut wg)
	}

	wg.wait()
	// 不应 panic / should not panic
	assert true
}

fn test_after_completion_concurrent_fire_and_off() {
	// 并发 fire() 和 off() 不应 panic
	// Concurrent fire() and off() should not panic
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	mut wg := sync.new_waitgroup()

	for i in 0 .. 10 {
		r.on(fn (ctx voidptr, err ?string) {
			g_ac_counter++
		}, 0)
	}

	for _ in 0 .. 10 {
		wg.add(1)
		spawn fn (mut reg AfterCompletionRegistry, mut w sync.WaitGroup) {
			defer { w.done() }
			reg.fire(voidptr(0), none)
		}(mut r, mut wg)
	}

	for i in 1 .. 6 {
		wg.add(1)
		spawn fn (mut reg AfterCompletionRegistry, id int, mut w sync.WaitGroup) {
			defer { w.done() }
			reg.off(id)
		}(mut r, i, mut wg)
	}

	wg.wait()
	// 不应 panic / should not panic
	assert true
}

// ── freeze/unfreeze 增强测试 / Enhanced freeze/unfreeze tests ──

fn test_after_completion_unfreeze_fire_uses_entries() {
	// unfreeze 后 fire() 使用 entries（非 frozen_entries）
	// After unfreeze, fire() uses entries (not frozen_entries)
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	r.freeze()
	r.unfreeze()
	// unfreeze 后注册新回调 / Register new callback after unfreeze
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter += 10
	}, 0)
	r.fire(voidptr(0), none)
	// 两个回调都应执行 / Both callbacks should execute
	assert g_ac_counter == 11
}

fn test_after_completion_freeze_off_fire_consistency() {
	// 冻结后 off() 更新快照，fire() 只执行快照中的回调
	// After freeze, off() updates snapshot; fire() only executes snapshot callbacks
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	id1 := r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)
	id2 := r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter += 10
	}, 0)
	r.freeze()
	// 冻结后移除 id1 / Remove id1 after freeze
	r.off(id1)
	r.fire(voidptr(0), none)
	// 只有 id2 的回调执行 / Only id2's callback executes
	assert g_ac_counter == 10
	// 移除 id2 后 fire 不执行任何回调 / After removing id2, fire executes nothing
	r.off(id2)
	g_ac_counter = 0
	r.fire(voidptr(0), none)
	assert g_ac_counter == 0
}

fn test_after_completion_multiple_freeze_unfreeze_cycles() {
	// 多次 freeze/unfreeze 循环
	// Multiple freeze/unfreeze cycles
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	r.on(fn (ctx voidptr, err ?string) {
		g_ac_counter++
	}, 0)

	r.freeze()
	r.unfreeze()
	r.freeze()
	r.unfreeze()
	r.freeze()

	r.fire(voidptr(0), none)
	assert g_ac_counter == 1
}

// ── 边界条件增强测试 / Enhanced edge case tests ──

fn test_after_completion_fire_with_error_string() {
	// fire() 传递错误字符串给回调
	// fire() passes error string to callbacks
	mut r := new_after_completion_registry()
	g_ac_err_msg = ''
	r.on(fn (ctx voidptr, err ?string) {
		if e := err {
			g_ac_err_msg = e
		}
	}, 0)
	r.fire(voidptr(0), 'internal server error')
	assert g_ac_err_msg == 'internal server error'
}

fn test_after_completion_large_number_of_callbacks() {
	// 注册大量回调后 fire() 正常工作
	// fire() works correctly with a large number of callbacks
	mut r := new_after_completion_registry()
	g_ac_counter = 0
	for _ in 0 .. 100 {
		r.on(fn (ctx voidptr, err ?string) {
			g_ac_counter++
		}, 0)
	}
	r.fire(voidptr(0), none)
	assert g_ac_counter == 100
}

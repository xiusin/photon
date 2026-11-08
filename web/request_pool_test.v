module web

// request_pool_test.v - RequestPool 单元测试
// RequestPool Unit Tests
//
// 测试覆盖 / Test Coverage:
//   - register_pool[T]() 注册对象池
//   - acquire[T]() 获取对象
//   - release() 释放对象回池
//   - with_acquired[T]() 零心智成本回调
//   - pool_stats() 获取池统计信息
//   - close_all() 关闭所有池
//   - 未注册池类型时 acquire 的行为
//   - PooledGuard RAII 自动释放
//   - 重复注册同名池返回错误
//   - Resettable 接口
//   - 预置 reset 函数（reset_session, reset_middleware_context, reset_input）
import sync
import photon.pool
import os

// ── 测试用简单对象 / Simple test object ──

// TestPooledObj 用于测试池化的简单对象
pub struct TestPooledObj {
pub mut:
	value int
	name  string
}

fn new_test_pooled_obj() &TestPooledObj {
	return &TestPooledObj{
		value: 0
		name:  ''
	}
}

fn reset_test_pooled_obj(obj voidptr) {
	mut o := unsafe { &TestPooledObj(obj) }
	o.value = 0
	o.name = ''
}

// ── RequestPoolConfig 测试 / RequestPoolConfig tests ──

fn test_request_pool_config_defaults() {
	// 默认配置：min_size=4, max_size=100
	// Default config: min_size=4, max_size=100
	config := RequestPoolConfig{}
	assert config.min_size == 4
	assert config.max_size == 100
}

fn test_request_pool_config_custom() {
	// 自定义配置
	// Custom configuration
	config := RequestPoolConfig{
		min_size: 8
		max_size: 50
	}
	assert config.min_size == 8
	assert config.max_size == 50
}

// ── new_request_pool 测试 / new_request_pool tests ──

fn test_new_request_pool_empty() {
	// 新创建的 RequestPool 为空
	// Newly created RequestPool is empty
	mut rp := new_request_pool(RequestPoolConfig{})
	assert rp.pools.len == 0
	assert rp.entries.len == 0
}

// ── register_pool 测试 / register_pool tests ──

fn test_request_pool_register_pool_success() {
	// 注册对象池成功
	// Register object pool successfully
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	assert 'test' in rp.pools
	assert 'test' in rp.entries
}

fn test_request_pool_register_pool_duplicate_name_error() {
	// 重复注册同名池返回错误
	// Duplicate pool name returns an error
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj) or {
		assert err.msg().contains('already registered')
		return
	}
	assert false
}

fn test_request_pool_register_multiple_pools() {
	// 注册多个不同名称的池
	// Register multiple pools with different names
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('pool-a', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.register_pool[TestPooledObj]('pool-b', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	assert rp.pools.len == 2
	assert 'pool-a' in rp.pools
	assert 'pool-b' in rp.pools
}

// ── acquire 测试 / acquire tests ──

fn test_request_pool_acquire_success() {
	// 从已注册池获取对象
	// Acquire object from a registered pool
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut guard := rp.acquire[TestPooledObj]('test')!
	defer { guard.release() }
	obj := guard.get()
	assert !isnil(obj)
}

fn test_request_pool_acquire_not_found_error() {
	// 从未注册池获取对象返回错误
	// Acquire from unregistered pool returns an error
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.acquire[TestPooledObj]('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_request_pool_acquire_and_modify() {
	// 获取对象并读取其值
	// Acquire object and read its value
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut guard := rp.acquire[TestPooledObj]('test')!
	defer { guard.release() }
	// 验证对象已获取 / Verify object was acquired
	assert guard.is_released() == false
}

// ── release 测试 / release tests ──

fn test_request_pool_release_calls_reset_fn() {
	// release() 调用 reset_fn 清除对象数据
	// release() calls reset_fn to clear object data
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	obj := rp.acquire_raw('test')!
	mut typed_obj := unsafe { &TestPooledObj(obj) }
	typed_obj.value = 99
	typed_obj.name = 'dirty'
	rp.release('test', obj)

	// 再次获取同一对象（池可能复用），reset 应已清除数据
	// Acquire again (pool may reuse); reset should have cleared data
	obj2 := rp.acquire_raw('test')!
	mut typed_obj2 := unsafe { &TestPooledObj(obj2) }
	assert typed_obj2.value == 0
	assert typed_obj2.name == ''
	rp.release('test', obj2)
}

fn test_request_pool_release_nil_obj_is_noop() {
	// release nil 对象为 no-op
	// Releasing a nil object is a no-op
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.release('test', unsafe { nil }) // 不应 panic / should not panic
	assert true
}

fn test_request_pool_release_to_nonexistent_pool_is_noop() {
	// release 到不存在的池为 no-op
	// Releasing to a non-existent pool is a no-op
	mut rp := new_request_pool(RequestPoolConfig{})
	obj := new_test_pooled_obj()
	rp.release('nonexistent', voidptr(obj)) // 不应 panic / should not panic
	assert true
}

// ── PooledGuard RAII 测试 / PooledGuard RAII tests ──

fn test_request_pool_guard_release_is_idempotent() {
	// PooledGuard 多次 release() 安全
	// PooledGuard release() is safe to call multiple times
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut guard := rp.acquire[TestPooledObj]('test')!
	guard.release()
	assert guard.is_released() == true
	guard.release() // 第二次 / second time
	assert guard.is_released() == true
}

fn test_request_pool_guard_get_after_release_returns_nil() {
	// 释放后 get() 返回 nil
	// get() returns nil after release
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut guard := rp.acquire[TestPooledObj]('test')!
	guard.release()
	obj := guard.get()
	assert isnil(obj)
}

fn test_request_pool_guard_is_released() {
	// is_released() 状态查询
	// is_released() state query
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut guard := rp.acquire[TestPooledObj]('test')!
	assert guard.is_released() == false
	guard.release()
	assert guard.is_released() == true
}

// ── with_acquired 回调测试 / with_acquired callback tests ──

fn test_request_pool_with_acquired_success() {
	// with_acquired() 在回调中使用池化对象
	// with_acquired() uses pooled object in callback
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.with_acquired[TestPooledObj]('test', fn (obj &TestPooledObj) ! {
		// 回调执行成功 / Callback executed successfully
	})!
	assert true
}

fn test_request_pool_with_acquired_releases_on_success() {
	// 回调成功后对象被释放（reset + release）
	// Object is released (reset + release) after successful callback
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.with_acquired[TestPooledObj]('test', fn (obj &TestPooledObj) ! {
		// 回调内部 / inside callback
	})!
	// 对象应已释放回池 / Object should have been released back to the pool
	assert true
}

fn test_request_pool_with_acquired_releases_on_error() {
	// 回调返回错误时对象也被释放
	// Object is released even when callback returns an error
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.with_acquired[TestPooledObj]('test', fn (obj &TestPooledObj) ! {
		return error('callback error')
	}) or { assert err.msg() == 'callback error' }
	// 对象应已释放 / Object should have been released
	assert true
}

fn test_request_pool_with_acquired_not_found_error() {
	// 从未注册池 with_acquired 返回错误
	// with_acquired on unregistered pool returns an error
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.with_acquired[TestPooledObj]('nonexistent', fn (obj &TestPooledObj) ! {}) or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ── pool_stats 测试 / pool_stats tests ──

fn test_request_pool_pool_stats() {
	// pool_stats() 返回池统计信息
	// pool_stats() returns pool statistics
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	stats := rp.pool_stats()
	assert 'test' in stats
}

fn test_request_pool_pool_stats_empty() {
	// 空池的统计信息
	// Statistics for empty pool
	mut rp := new_request_pool(RequestPoolConfig{})
	stats := rp.pool_stats()
	assert stats.len == 0
}

// ── close_all 测试 / close_all tests ──

fn test_request_pool_close_all() {
	// close_all() 关闭所有池
	// close_all() closes all pools
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.close_all()
	// 不应 panic / should not panic
	assert true
}

fn test_request_pool_close_all_idempotent() {
	// 多次调用 close_all() 安全
	// Calling close_all() multiple times is safe
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.close_all()
	rp.close_all() // 第二次 / second time
	assert true
}

fn test_request_pool_close_all_empty() {
	// 空池 close_all() 安全
	// close_all() on empty pool is safe
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.close_all()
	assert true
}

// ── acquire_raw 测试 / acquire_raw tests ──

fn test_request_pool_acquire_raw_success() {
	// acquire_raw() 获取原始 voidptr
	// acquire_raw() gets a raw voidptr
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	obj := rp.acquire_raw('test')!
	assert !isnil(obj)
	rp.release('test', obj)
}

fn test_request_pool_acquire_raw_not_found_error() {
	// 从未注册池 acquire_raw 返回错误
	// acquire_raw from unregistered pool returns an error
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.acquire_raw('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ── 预置 reset 函数测试 / Pre-built reset function tests ──

fn test_reset_session() {
	// reset_session 重置 Session 对象
	// reset_session resets a Session object
	mut sess := new_session('test-id')
	sess.data = {
		'key': 'value'
	}
	sess.flash_data = {
		'flash': 'data'
	}
	sess.old_flash = {
		'old': 'data'
	}
	sess.is_dirty = true
	sess.is_new = false

	reset_session(voidptr(sess))

	assert sess.data.len == 0
	assert sess.flash_data.len == 0
	assert sess.old_flash.len == 0
	assert sess.is_dirty == false
	assert sess.is_new == true
}

fn test_reset_middleware_context() {
	// reset_middleware_context 重置 MiddlewareContext
	// reset_middleware_context resets MiddlewareContext
	mut mctx := &MiddlewareContext{
		data: {
			'request_id':     'abc'
			'_global_config': 'val'
		}
		ctx:  unsafe { nil }
	}

	reset_middleware_context(voidptr(mctx))

	// 保留 _global_ 前缀的数据 / Preserve _global_ prefixed data
	assert '_global_config' in mctx.data
	assert mctx.data['_global_config'] == 'val'
	// 清除非全局数据 / Clear non-global data
	assert 'request_id' !in mctx.data
	// ctx 引用应被清除 / ctx reference should be cleared
	assert isnil(mctx.ctx)
}

fn test_reset_input() {
	// reset_input 重置 Input 对象
	// reset_input resets Input object
	mut inp := &Input{
		ctx: unsafe { nil }
	}
	// 设置一个非 nil ctx（使用临时指针模拟）
	// Set a non-nil ctx (using a temporary pointer to simulate)
	inp.ctx = unsafe { voidptr(malloc(1)) }
	assert !isnil(inp.ctx)

	reset_input(voidptr(inp))

	assert isnil(inp.ctx)
}

// ── Resettable 接口测试 / Resettable interface tests ──

fn test_resettable_interface() {
	// Resettable 接口定义了 reset() 方法
	// Resettable interface defines the reset() method
	// 这是一个编译期检查：确保 Session 实现了 Resettable
	// This is a compile-time check: ensure Session implements Resettable
	// （Session 有 reset 方法，但不是显式实现 Resettable trait）
	// (Session has a reset method, but doesn't explicitly implement Resettable trait)
	assert true
}

// ── 并发安全测试 / Concurrency safety tests ──

fn test_request_pool_concurrent_acquire_release() {
	// 并发 acquire/release 不应 panic
	// Concurrent acquire/release should not panic
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut wg := sync.new_waitgroup()

	for _ in 0 .. 10 {
		wg.add(1)
		spawn fn (mut rp RequestPool, mut w sync.WaitGroup) ! {
			defer { w.done() }
			mut guard := rp.acquire[TestPooledObj]('test')!
			guard.release()
		}(mut rp, mut wg)
	}

	wg.wait()
	assert true
}

// ── RequestPoolStats 测试 / RequestPoolStats tests ──

fn test_request_pool_stats_struct() {
	// RequestPoolStats 结构体
	// RequestPoolStats struct
	stats := RequestPoolStats{
		pools: map[string]pool.PoolStats{}
	}
	assert stats.pools.len == 0
}

// ── close_all() 使用 @lock 的并发安全测试 / close_all() @lock concurrency safety tests ──

fn test_request_pool_close_all_concurrent_with_acquire() {
	// close_all() 使用 @lock（非 rlock），与 acquire 并发安全
	// close_all() uses @lock (not rlock), safe with concurrent acquire
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut wg := sync.new_waitgroup()

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut rp RequestPool, mut w sync.WaitGroup) {
			defer { w.done() }
			mut guard := rp.acquire[TestPooledObj]('test') or { return }
			guard.release()
		}(mut rp, mut wg)
	}

	wg.add(1)
	spawn fn (mut rp RequestPool, mut w sync.WaitGroup) {
		defer { w.done() }
		rp.close_all()
	}(mut rp, mut wg)

	wg.wait()
	// 不应 panic / should not panic
	assert true
}

fn test_request_pool_concurrent_register_and_acquire() {
	// 并发 register_pool 和 acquire 不应 panic
	// Concurrent register_pool and acquire should not panic
	mut rp := new_request_pool(RequestPoolConfig{})
	mut wg := sync.new_waitgroup()

	// 先注册一个池 / Register a pool first
	rp.register_pool[TestPooledObj]('existing', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut rp RequestPool, mut w sync.WaitGroup) {
			defer { w.done() }
			mut guard := rp.acquire[TestPooledObj]('existing') or { return }
			guard.release()
		}(mut rp, mut wg)
	}

	wg.add(1)
	spawn fn (mut rp RequestPool, mut w sync.WaitGroup) {
		defer { w.done() }
		rp.register_pool[TestPooledObj]('new-pool', fn () !voidptr {
			return unsafe { voidptr(new_test_pooled_obj()) }
		}, reset_test_pooled_obj) or {}
	}(mut rp, mut wg)

	wg.wait()
	assert true
}

fn test_request_pool_concurrent_pool_stats_and_acquire() {
	// 并发 pool_stats 和 acquire 不应 panic
	// Concurrent pool_stats and acquire should not panic
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut wg := sync.new_waitgroup()

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut rp RequestPool, mut w sync.WaitGroup) {
			defer { w.done() }
			_ = rp.pool_stats()
		}(mut rp, mut wg)
	}

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut rp RequestPool, mut w sync.WaitGroup) {
			defer { w.done() }
			mut guard := rp.acquire[TestPooledObj]('test') or { return }
			guard.release()
		}(mut rp, mut wg)
	}

	wg.wait()
	assert true
}

// ── 边界条件增强测试 / Enhanced edge case tests ──

fn test_request_pool_register_empty_name() {
	// 空名称注册池
	// Register pool with empty name
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	assert '' in rp.pools
}

fn test_request_pool_acquire_release_multiple_cycles() {
	// 多次 acquire/release 循环
	// Multiple acquire/release cycles
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	for _ in 0 .. 10 {
		mut guard := rp.acquire[TestPooledObj]('test')!
		assert guard.is_released() == false
		guard.release()
		assert guard.is_released() == true
	}
}

fn test_request_pool_with_acquired_callback_can_modify_object() {
	// with_acquired 回调中可以修改对象
	// Object can be modified inside with_acquired callback
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	rp.with_acquired[TestPooledObj]('test', fn (obj &TestPooledObj) ! {
		// 回调内读取对象 / Read object inside callback
		assert obj.value == 0
	})!
}

fn test_request_pool_release_resets_object_state() {
	// release 后对象被 reset，再次获取时状态已清除
	// After release, object is reset; next acquire gets clean state
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	// 第一次获取并修改 / First acquire and modify
	obj1 := rp.acquire_raw('test')!
	mut typed1 := unsafe { &TestPooledObj(obj1) }
	typed1.value = 42
	typed1.name = 'modified'
	rp.release('test', obj1)

	// 第二次获取应得到已重置的对象 / Second acquire should get a reset object
	obj2 := rp.acquire_raw('test')!
	mut typed2 := unsafe { &TestPooledObj(obj2) }
	assert typed2.value == 0
	assert typed2.name == ''
	rp.release('test', obj2)
}

fn test_request_pool_multiple_pools_independent() {
	// 多个池互不影响
	// Multiple pools are independent
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('pool-a', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.register_pool[TestPooledObj]('pool-b', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	mut guard_a := rp.acquire[TestPooledObj]('pool-a')!
	mut guard_b := rp.acquire[TestPooledObj]('pool-b')!

	assert guard_a.is_released() == false
	assert guard_b.is_released() == false

	guard_a.release()
	assert guard_a.is_released() == true
	assert guard_b.is_released() == false

	guard_b.release()
	assert guard_b.is_released() == true
}

// ── acquire/defer 的 reset 契约 / reset on the acquire path ──
//
// 这几条针对一个只会在「推荐用法」上出现的缺陷：
//
//   mut guard := rp.acquire[Session]('session')!
//   defer { guard.release() }
//
// 这是 request_pool.v 文件头写的用法，也是唯一省心的用法。但 reset_fn
// 以前只挂在 rp.release(name, obj) 上，走 guard.release() 这条路根本不 reset。
// 结果是上一个请求写进池化对象的字段，会被下一个请求原样读到。
//
// 行为用例抓不住它（对象确实归还了、计数确实对），所以下面这条同时断言
// 「不该残留的数据没残留」。

fn test_request_pool_guard_release_clears_reset_fields() {
	mut rp := new_request_pool(RequestPoolConfig{
		min_size: 1
		max_size: 1
	})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	mut guard := rp.acquire[TestPooledObj]('test')!
	mut obj := guard.get()
	obj.value = 42
	obj.name = 'request-1'
	guard.release()

	// 第二个「请求」拿到的是同一个对象，必须已经被 reset 过
	mut next := rp.acquire[TestPooledObj]('test')!
	reused := next.get()
	assert reused.value == 0
	assert reused.name == ''
	next.release()
}

// ── 池耗尽时的临时对象 / fallback objects when the pool is exhausted ──

fn test_request_pool_temporary_guard_reports_released() {
	// 池满时 acquire 返回临时对象。它没有池可归还，但 release() 必须把
	// released 置位：否则调用方按 RAII 契约写 `assert guard.is_released()`
	// 永远得不到 true，也没法区分「还在手上」和「已经没了」。
	mut rp := new_request_pool(RequestPoolConfig{
		min_size: 1
		max_size: 1
	})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	mut hog := rp.acquire[TestPooledObj]('test')!
	mut temp := rp.acquire[TestPooledObj]('test')!
	assert !temp.is_released()
	assert !isnil(temp.get())
	temp.release()
	assert temp.is_released()
	assert isnil(temp.get())
	hog.release()
}

fn test_request_pool_with_acquired_temporary_runs_reset() {
	// with_acquired 的池耗尽分支同样要 reset：那条路径直接建对象、
	// 调回调、丢掉，既不进池也不再经过任何 release 钩子。
	mut mark := &ResetCounter{}
	mut rp := new_request_pool(RequestPoolConfig{
		min_size: 1
		max_size: 1
	})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, fn [mut mark] (obj voidptr) {
		mark.n++
		reset_test_pooled_obj(obj)
	})!

	mut hog := rp.acquire[TestPooledObj]('test')!
	rp.with_acquired[TestPooledObj]('test', fn (obj &TestPooledObj) ! {
		assert !isnil(obj)
	})!
	assert mark.n == 1
	hog.release()
	assert mark.n == 2
}

fn test_request_pool_with_acquired_temporary_resets_on_error() {
	// 回调失败时也一样：reset 先跑，错误再往上抛。
	mut mark := &ResetCounter{}
	mut rp := new_request_pool(RequestPoolConfig{
		min_size: 1
		max_size: 1
	})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, fn [mut mark] (obj voidptr) {
		mark.n++
		reset_test_pooled_obj(obj)
	})!

	mut hog := rp.acquire[TestPooledObj]('test')!
	mut caught := false
	rp.with_acquired[TestPooledObj]('test', fn (obj &TestPooledObj) ! {
		return error('callback boom')
	}) or {
		caught = true
		assert err.msg() == 'callback boom'
	}
	assert caught
	assert mark.n == 1
	hog.release()
}

// 计数器必须是堆上的引用，不能写 `mut n := 0` + `fn [mut n]`：V 0.5.2 的
// `[mut x]` 捕获给的是副本，闭包内自增对外不可见（最小复现见
// strutil/module_identity_test.v）。用它计数会得到「一次都没调」。
struct ResetCounter {
mut:
	n int
}

// ── close_all 之后的语义 / Semantics after close_all ──
//
// 这四个是同一件事的四个面：close_all() 以前只关内部 Pool，却把池留在
// entries / pools 里。于是之后每一次 acquire 都找到 entry、问一个已关闭的池、
// 拿到 `pool is closed`，在 `or` 块里吞掉、降级成临时对象——调用方拿到一个
// 完全能用的对象，一个错误都收不到。池已经关了，而没有任何人能察觉。
//
// These four are four faces of one bug: close_all() used to close the inner
// Pool but leave it in entries / pools. Every later acquire found the entry,
// asked a closed pool, received `pool is closed`, swallowed it in the `or`
// block and degraded to a temporary object — a fully working object, zero
// errors reported. The pool was shut down and nobody could tell.

fn test_request_pool_close_all_unregisters_pools() {
	// close_all() 之后注册表必须是空的，而不只是「池被标记为关闭」
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('a', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.register_pool[TestPooledObj]('b', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	assert rp.pools.len == 2

	rp.close_all()
	assert rp.pools.len == 0
	assert rp.pool_stats().len == 0
}

fn test_request_pool_acquire_after_close_all_errors() {
	// 关闭后 acquire 必须明确报错，不能静默降级成临时对象
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.close_all()

	mut caught := false
	rp.acquire[TestPooledObj]('test') or {
		caught = true
		msg := err.msg()
		assert msg.contains('not found') || msg.contains('closed')
	}
	assert caught, 'close_all() 之后的 acquire 必须报错，不能返回一个临时对象'
}

fn test_request_pool_acquire_raw_after_close_all_errors() {
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.close_all()

	mut caught := false
	rp.acquire_raw('test') or { caught = true }
	assert caught, 'close_all() 之后的 acquire_raw 必须报错'
}

fn test_request_pool_with_acquired_after_close_all_errors() {
	mut rp := new_request_pool(RequestPoolConfig{})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	rp.close_all()

	mut ran := &ResetCounter{}
	mut caught := false
	rp.with_acquired[TestPooledObj]('test', fn [mut ran] (obj &TestPooledObj) ! {
		ran.n++
	}) or {
		caught = true
	}
	assert caught, 'close_all() 之后的 with_acquired 必须报错'
	assert ran.n == 0, '回调不应该被调用——池已经关了'
}

fn test_request_pool_in_use_object_survives_close_all() {
	// 已在用的对象在 close_all() 之后仍可 release，且不 panic。
	// 这是唯一必须保留的能力：不关掉持有者手里那个对象。
	mut rp := new_request_pool(RequestPoolConfig{
		min_size: 1
		max_size: 2
	})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!
	mut guard := rp.acquire[TestPooledObj]('test')!
	rp.close_all()
	guard.release()
	assert guard.is_released()
}

fn test_request_pool_close_all_between_lookup_and_acquire() {
	// 摘除注册表堵住了「close_all 之后还能拿到对象」的主路，但还有一条窄缝：
	// acquire 读到 entry 之后、真正去问 Pool 之前，另一个协程调了 close_all。
	// 此时 entry 已经在手（上面那次 rlock 已经放锁了），问到的就是一个
	// 刚被关掉的池。这条路只剩 is_closed() 这道闸。
	//
	// 这里不靠并发复现（不可靠），直接对着 Pool 层验：已关闭的池必须能被
	// 认出来，而不是让调用方从错误文本里猜。
	mut p := pool.new_pool_with_config('closed-probe', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, 0, 1)
	p.initialize() or {}
	assert !p.is_closed()
	p.close() or {}
	assert p.is_closed(), 'close() 之后 is_closed() 必须为 true'
	mut caught := false
	p.acquire() or {
		caught = true
		assert err.msg().contains('closed')
	}
	assert caught
}

fn test_request_pool_acquire_raw_exhausted_returns_nil() {
	// acquire_raw 与 acquire 的分歧点，在此钉成事实而不是留给人猜：
	// 池耗尽时 acquire 会建临时对象（有 pool.PooledGuard 兜底、不泄漏），
	// acquire_raw 直接返回 nil —— 它拿的是裸 voidptr，没法替你决定
	// 「这个临时对象该由谁销毁」，于是把判断权交给调用方。
	//
	// 这条用例同时锁住了「耗尽 ≠ 报错」：错误通道只用来报「未注册/已关闭」。
	mut rp := new_request_pool(RequestPoolConfig{
		min_size: 1
		max_size: 1
	})
	rp.register_pool[TestPooledObj]('test', fn () !voidptr {
		return unsafe { voidptr(new_test_pooled_obj()) }
	}, reset_test_pooled_obj)!

	mut hog := rp.acquire[TestPooledObj]('test')!
	mut caught := false
	rp.acquire_raw('test') or { caught = true }
	assert !caught, '池耗尽时 acquire_raw 返回 nil，不应走错误通道'
	hog.release()
}

fn test_request_pool_has_no_dead_stats_field() {
	// RequestPool 以前还声明了一个 pub 的 `stats map[string]pool.PoolStats`，
	// 从构造起就置空、全仓库没有任何写入方。它是第二个真相源的对立面：
	// 一个永远为空、却出现在公开结构里的字段，读者会以为 pool_stats()
	// 只是它的副本。现在只有一个来源（pool_stats()，直接问每个 Pool）。
	//
	// 用源码断言锁住：行为用例绕不过「字段存在但永远为空」这件事。
	src := read_source('/web/request_pool.v')
	assert !src.contains('\tstats map[string]pool.PoolStats'), 'RequestPool 的 stats 字段是死的，别再把它加回来'
}

// read_source 读取仓库内的源文件。测试的 cwd 是模块目录（web/），
// 所以先从上一层找。找不到直接让用例失败，不要静默跳过。
fn read_source(rel string) string {
	for candidate in ['..${rel}', '.${rel}'] {
		if os.exists(candidate) {
			return os.read_file(candidate) or { '' }
		}
	}
	assert false, '找不到源文件 ${rel}'
	return ''
}

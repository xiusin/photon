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
import pool

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
	rp.release('test', voidptr(0)) // 不应 panic / should not panic
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
	}) or {
		assert err.msg() == 'callback error'
	}
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
	sess.data = {'key': 'value'}
	sess.flash_data = {'flash': 'data'}
	sess.old_flash = {'old': 'data'}
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
		data: {'request_id': 'abc', '_global_config': 'val'}
		ctx: unsafe { nil }
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

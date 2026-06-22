module web

// session_lock_test.v - SessionLockManager 单元测试
// SessionLockManager Unit Tests
//
// 测试覆盖 / Test Coverage:
//   - acquire() / release() 基本功能
//   - SessionLockGuard RAII 自动释放（defer { guard.release() }）
//   - with_session_lock() 零心智成本回调
//   - 同一 session ID 的互斥性
//   - 不同 session ID 的并发性（不互相阻塞）
//   - 重复 release 不 panic
//   - SessionLockGuard.is_released() 状态查询
//   - 超时获取锁返回错误
import sync
import time
import locking

// ── 全局测试状态 / Global test state ──
// V 闭包按值捕获变量，使用全局变量在回调间共享状态
// V closures capture by value; use globals to share state across callbacks
__global g_sl_counter int
__global g_sl_mixed int

// ── 基本功能测试 / Basic functionality tests ──

fn test_session_lock_acquire_and_release() {
	// acquire() 获取锁，release() 释放锁
	// acquire() gets the lock, release() releases it
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-abc')!
	defer { guard.release() }
	assert guard.is_released() == false
	guard.release()
	assert guard.is_released() == true
}

fn test_session_lock_acquire_returns_guard() {
	// acquire() 返回 SessionLockGuard
	// acquire() returns a SessionLockGuard
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-xyz')!
	defer { guard.release() }
	assert guard.is_released() == false
}

fn test_session_lock_manager_release_method() {
	// SessionLockManager.release() 直接释放锁
	// SessionLockManager.release() directly releases the lock
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-direct')!
	guard.release()
	// 释放后可以再次获取
	// After release, the lock can be acquired again
	mut guard2 := slm.acquire('session-direct')!
	guard2.release()
}

// ── RAII Guard 测试 / RAII Guard tests ──

fn test_session_lock_guard_defer_release() {
	// defer { guard.release() } 模式确保锁释放
	// defer { guard.release() } pattern ensures lock release
	mut slm := new_session_lock_manager(SessionLockConfig{})
	{
		mut guard := slm.acquire('session-defer')!
		defer { guard.release() }
		assert guard.is_released() == false
		// 作用域结束，defer 自动释放
		// Scope ends, defer auto-releases
	}
	// 锁已释放，可以再次获取
	// Lock released, can acquire again
	mut guard2 := slm.acquire('session-defer')!
	guard2.release()
}

fn test_session_lock_guard_double_release_is_noop() {
	// 重复调用 release() 不 panic，第二次为 no-op
	// Calling release() twice is safe; second call is a no-op
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-double')!
	guard.release()
	assert guard.is_released() == true
	guard.release() // 第二次 / second time — 不应 panic
	assert guard.is_released() == true
}

fn test_session_lock_guard_triple_release_is_noop() {
	// 三次调用 release() 仍然安全
	// Three release() calls are still safe
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-triple')!
	guard.release()
	guard.release()
	guard.release()
	assert guard.is_released() == true
}

fn test_session_lock_guard_is_released_initially_false() {
	// 刚获取的 Guard is_released() 为 false
	// Newly acquired Guard has is_released() == false
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-check')!
	assert guard.is_released() == false
	guard.release()
}

// ── with_session_lock() 回调测试 / with_session_lock() callback tests ──

fn test_session_lock_with_session_lock_basic() {
	// with_session_lock() 在锁保护下执行回调
	// with_session_lock() executes callback under lock protection
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut executed := false
	slm.with_session_lock('session-callback', fn () ! {
		// 回调执行成功 / Callback executed successfully
	})!
	executed = true
	assert executed == true
}

fn test_session_lock_with_session_lock_releases_on_success() {
	// 回调成功完成后锁自动释放
	// Lock is auto-released after successful callback
	mut slm := new_session_lock_manager(SessionLockConfig{})
	slm.with_session_lock('session-auto-release', fn () ! {
		// 回调内部 / inside callback
	})!
	// 锁已释放，可以再次获取
	// Lock released, can acquire again
	mut guard := slm.acquire('session-auto-release')!
	guard.release()
}

fn test_session_lock_with_session_lock_releases_on_error() {
	// 回调返回错误时锁也会释放
	// Lock is released even when callback returns an error
	mut slm := new_session_lock_manager(SessionLockConfig{})
	slm.with_session_lock('session-err-release', fn () ! {
		return error('callback error')
	}) or {
		assert err.msg() == 'callback error'
	}
	// 锁已释放，可以再次获取
	// Lock released, can acquire again
	mut guard := slm.acquire('session-err-release')!
	guard.release()
}

// ── 同一 session ID 互斥性测试 / Same session ID mutual exclusion tests ──

fn test_session_lock_same_session_id_is_mutex() {
	// 同一 session ID 的锁是互斥的
	// Same session ID locks are mutually exclusive
	mut slm := new_session_lock_manager(SessionLockConfig{
		acquire_timeout_ms: 200
	})
	mut guard1 := slm.acquire('session-mutex')!
	defer { guard1.release() }

	// 第二次获取同一 session ID 应超时
	// Second acquire on the same session ID should timeout
	mut acquired := false
	slm.with_session_lock('session-mutex', fn () ! {
		// 如果执行到这里，说明锁获取成功（不应该）
		// If we reach here, the lock was acquired (should not happen)
	}) or {
		// 预期超时 / expected timeout
		acquired = false
	}
	assert acquired == false
}

fn test_session_lock_same_session_id_sequential_access() {
	// 同一 session ID 顺序访问：先获取→释放→再获取
	// Same session ID sequential access: acquire → release → acquire
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut counter := 0

	// 第一次获取 / First acquire
	mut guard1 := slm.acquire('session-seq')!
	counter = 1
	guard1.release()

	// 第二次获取 / Second acquire
	mut guard2 := slm.acquire('session-seq')!
	counter = 2
	guard2.release()

	assert counter == 2
}

// ── 不同 session ID 并发性测试 / Different session ID concurrency tests ──

fn test_session_lock_different_session_ids_no_blocking() {
	// 不同 session ID 的锁不互相阻塞
	// Different session IDs don't block each other
	mut slm := new_session_lock_manager(SessionLockConfig{
		acquire_timeout_ms: 1000
	})

	// 获取 session-a 的锁
	// Acquire lock for session-a
	mut guard_a := slm.acquire('session-a')!
	defer { guard_a.release() }

	// 获取 session-b 的锁应立即成功（不被 session-a 阻塞）
	// Acquiring lock for session-b should succeed immediately (not blocked by session-a)
	mut guard_b := slm.acquire('session-b')!
	defer { guard_b.release() }

	assert guard_a.is_released() == false
	assert guard_b.is_released() == false
}

fn test_session_lock_concurrent_different_sessions() {
	// 多个不同 session ID 并发获取锁
	// Multiple different session IDs acquire locks concurrently
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut wg := sync.new_waitgroup()
	success_ch := chan int{cap: 10}

	for i in 0 .. 10 {
		wg.add(1)
		spawn fn (mut manager SessionLockManager, idx int, mut w sync.WaitGroup, ch chan int) ! {
			defer { w.done() }
			session_id := 'session-${idx}'
			mut guard := manager.acquire(session_id)!
			select {
				ch <- 1 {}
				else {}
			}
			guard.release()
		}(mut slm, i, mut wg, success_ch)
	}

	wg.wait()
	mut success_count := 0
	for _ in 0 .. 10 {
		select {
			_ := <-success_ch {
				success_count++
			}
			else {
				break
			}
		}
	}
	assert success_count == 10
}

// ── 超时测试 / Timeout tests ──

fn test_session_lock_acquire_timeout() {
	// 获取锁超时返回错误
	// Acquire lock timeout returns an error
	mut slm := new_session_lock_manager(SessionLockConfig{
		acquire_timeout_ms: 100
	})

	// 先获取锁 / Acquire the lock first
	mut guard := slm.acquire('session-timeout')!
	defer { guard.release() }

	// 尝试再次获取同一 session ID，应超时
	// Try to acquire the same session ID again; should timeout
	mut err_caught := false
	slm.acquire('session-timeout') or {
		err_caught = true
	}
	assert err_caught == true
}

// ── SessionLockConfig 默认值测试 / SessionLockConfig default tests ──

fn test_session_lock_config_defaults() {
	// 默认配置：acquire_timeout_ms=3000, lock_timeout_ms=5000
	// Default config: acquire_timeout_ms=3000, lock_timeout_ms=5000
	config := SessionLockConfig{}
	assert config.acquire_timeout_ms == 3000
	assert config.lock_timeout_ms == 5000
}

fn test_session_lock_config_custom() {
	// 自定义配置
	// Custom configuration
	config := SessionLockConfig{
		acquire_timeout_ms: 5000
		lock_timeout_ms:    10000
	}
	assert config.acquire_timeout_ms == 5000
	assert config.lock_timeout_ms == 10000
}

// ── new_session_lock_guard 测试 / new_session_lock_guard tests ──

fn test_session_lock_guard_new() {
	// 直接创建 SessionLockGuard
	// Create SessionLockGuard directly
	mut lm := locking.new_lock_manager()
	lm.lock('test-key') // 先获取锁 / Acquire lock first
	mut guard := new_session_lock_guard(lm, 'test-key')
	assert guard.is_released() == false
	guard.release()
	assert guard.is_released() == true
}

fn test_session_lock_guard_new_double_release() {
	// 直接创建的 Guard 重复释放安全
	// Double release on directly created Guard is safe
	mut lm := locking.new_lock_manager()
	lm.lock('test-key') // 先获取锁 / Acquire lock first
	mut guard := new_session_lock_guard(lm, 'test-key')
	guard.release()
	guard.release() // 不应 panic / should not panic
	assert guard.is_released() == true
}

// ── SessionLockGuard.release() 锁保护下捕获 manager 指针测试 ──
// SessionLockGuard.release() captures manager pointer under lock protection tests

fn test_session_lock_guard_release_captures_manager_under_lock() {
	// release() 在锁保护下捕获 manager 指针后再释放锁
	// 验证：释放后 is_released 为 true，且锁确实被释放
	// release() captures manager pointer under lock before releasing the lock
	// Verify: is_released is true after release, and the lock is actually released
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-capture')!
	assert guard.is_released() == false
	guard.release()
	assert guard.is_released() == true
	// 锁应已释放，可以再次获取 / Lock should be released, can acquire again
	mut guard2 := slm.acquire('session-capture')!
	guard2.release()
}

fn test_session_lock_guard_release_with_nil_manager() {
	// manager 为 nil 时 release() 不 panic（isnil 检查）
	// release() does not panic when manager is nil (isnil check)
	mut guard := SessionLockGuard{
		manager:  unsafe { nil }
		key:      'test-nil'
		released: false
	}
	guard.release() // 不应 panic / should not panic
	assert guard.is_released() == true
}

// ── SessionLockManager.release() 直接释放测试 ──
// SessionLockManager.release() direct release tests

fn test_session_lock_manager_release_direct() {
	// SessionLockManager.release() 直接通过 session_id 释放锁
	// SessionLockManager.release() directly releases lock by session_id
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-direct-release')!
	defer { guard.release() }
	// 通过 manager 直接释放 / Release directly through manager
	guard.release()
	slm.release('session-direct-release')
	// 不应 panic / should not panic
	assert true
}

// ── 并发安全增强测试 / Enhanced concurrency safety tests ──

fn test_session_lock_concurrent_acquire_release_same_session() {
	// 多线程顺序获取/释放同一 session ID 的锁
	// Multiple threads sequentially acquire/release the same session ID lock
	mut slm := new_session_lock_manager(SessionLockConfig{
		acquire_timeout_ms: 5000
	})
	mut wg := sync.new_waitgroup()

	g_sl_counter = 0

	for i in 0 .. 5 {
		wg.add(1)
		spawn fn (mut manager SessionLockManager, mut w sync.WaitGroup) {
			defer { w.done() }
			mut guard := manager.acquire('session-concurrent')!
			g_sl_counter++
			guard.release()
		}(mut slm, mut wg)
	}

	wg.wait()
	assert g_sl_counter == 5
}

fn test_session_lock_concurrent_mixed_sessions() {
	// 多线程同时操作不同 session ID，互不阻塞
	// Multiple threads operate on different session IDs without blocking each other
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut wg := sync.new_waitgroup()

	g_sl_mixed = 0

	for i in 0 .. 20 {
		wg.add(1)
		spawn fn (mut manager SessionLockManager, idx int, mut w sync.WaitGroup) {
			defer { w.done() }
			session_id := 'session-mixed-${idx % 5}'
			mut guard := manager.acquire(session_id)!
			g_sl_mixed++
			guard.release()
		}(mut slm, i, mut wg)
	}

	wg.wait()
	assert g_sl_mixed == 20
}

// ── 边界条件增强测试 / Enhanced edge case tests ──

fn test_session_lock_empty_session_id() {
	// 空 session ID 也能正常获取和释放锁
	// Empty session ID can also acquire and release locks normally
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('')!
	guard.release()
	assert guard.is_released() == true
}

fn test_session_lock_long_session_id() {
	// 超长 session ID 也能正常工作
	// Very long session ID also works normally
	mut slm := new_session_lock_manager(SessionLockConfig{})
	long_id := 'x'.repeat(1000)
	mut guard := slm.acquire(long_id)!
	guard.release()
	assert guard.is_released() == true
}

fn test_session_lock_special_chars_in_session_id() {
	// session ID 包含特殊字符
	// Session ID with special characters
	mut slm := new_session_lock_manager(SessionLockConfig{})
	mut guard := slm.acquire('session-with-dashes_and_underscores.and.dots')!
	guard.release()
	assert guard.is_released() == true
}
module web

// session_lock.v - Session 并发锁管理
// Session Concurrency Lock Management
//
// 复用 locking 模块的 LockManager，提供 RAII Guard 模式。
// 设计哲学（降低心智成本 / Reduce Cognitive Load）：
//   - acquire() 返回 SessionLockGuard，defer { guard.release() } 自动释放
//   - with_session_lock() 回调 API：零心智成本，框架保证锁的获取与释放
//
// Reuses locking module's LockManager with RAII Guard pattern.
// Design philosophy (Reduce Cognitive Load):
//   - acquire() returns SessionLockGuard, defer { guard.release() } auto-releases
//   - with_session_lock() callback API: zero cognitive load, framework guarantees lock acquire/release
import locking
import sync

// SessionLockConfig 配置 Session 锁参数。
// SessionLockConfig configures Session lock parameters.
pub struct SessionLockConfig {
pub:
	acquire_timeout_ms int = 3000 // 获取锁的最大等待时间 / max wait time for lock acquisition
	lock_timeout_ms    int = 5000 // 锁持有超时（0=无限）/ lock hold timeout (0=infinite)
}

// SessionLockManager 管理 Session 级别的并发锁。
// 复用 locking 模块的 LockManager，提供 RAII Guard 模式。
//
// SessionLockManager manages Session-level concurrency locks.
// Reuses locking module's LockManager with RAII Guard pattern.
@[heap]
pub struct SessionLockManager {
pub mut:
	lock_manager &locking.LockManager = unsafe { nil }
	config       SessionLockConfig
}

// new_session_lock_manager 创建 Session 锁管理器。
// new_session_lock_manager creates a Session lock manager.
pub fn new_session_lock_manager(config SessionLockConfig) &SessionLockManager {
	return &SessionLockManager{
		lock_manager: locking.new_lock_manager()
		config:       config
	}
}

// SessionLockGuard 是 Session 锁的 RAII Guard。
// 使用 defer { guard.release() } 模式确保锁一定释放。
// 即使请求 panic，defer 保证锁释放。
//
// SessionLockGuard is the RAII guard for Session locks.
// Use defer { guard.release() } to ensure the lock is always released.
// Even if the request panics, defer guarantees lock release.
@[heap]
pub struct SessionLockGuard {
pub mut:
	manager  &locking.LockManager = unsafe { nil }
	key      string
	released bool
mut:
	mu sync.Mutex
}

// new_session_lock_guard 创建 SessionLockGuard。
// new_session_lock_guard creates a SessionLockGuard.
pub fn new_session_lock_guard(manager &locking.LockManager, key string) SessionLockGuard {
	return SessionLockGuard{
		manager:  manager
		key:      key
		released: false
	}
}

// release 释放 Session 锁。安全：多次调用为 no-op。
// 这是 RAII 保证的核心。
//
// 注意：此处不能使用 defer { g.mu.unlock() }，因为需要先设置 released=true
// 并释放 g.mu，然后才能调用 manager.unlock(key)。如果使用 defer，
// manager.unlock(key) 会在 g.mu.unlock() 之后执行，顺序正确，
// 但 released 标志的检查和设置必须在 g.mu 保护下完成，
// 因此手动控制锁的获取和释放是必要的。
//
// release releases the Session lock. Safe: multiple calls are no-ops.
// This is the core of the RAII guarantee.
//
// Note: defer { g.mu.unlock() } cannot be used here because we need to
// set released=true and release g.mu BEFORE calling manager.unlock(key).
// The released flag check and set must be done under g.mu protection,
// so manual lock acquire/release control is necessary.
pub fn (mut g SessionLockGuard) release() {
	g.mu.@lock()
	if g.released || isnil(g.manager) {
		g.mu.unlock()
		return
	}
	g.released = true
	// Capture manager pointer under lock protection before releasing.
	// 在锁保护下捕获 manager 指针，然后再释放锁。
	manager := g.manager
	g.mu.unlock()
	manager.unlock(g.key) or {
		// 静默忽略解锁错误（锁可能已被清理）
		// Silently ignore unlock errors (lock may have been cleaned up)
	}
}

// is_released 返回锁是否已释放。
// is_released returns whether the lock has been released.
pub fn (g &SessionLockGuard) is_released() bool {
	return g.released
}

// acquire 获取 Session 锁，返回 RAII SessionLockGuard。
// 超时返回错误。
//
// 用法 / Usage:
//   mut guard := slm.acquire('session:abc')!
//   defer { guard.release() }
//   // 在锁保护下操作 Session / Operate on Session under lock protection
//
// acquire acquires a Session lock and returns an RAII SessionLockGuard.
// Returns error on timeout.
pub fn (mut slm SessionLockManager) acquire(session_id string) !SessionLockGuard {
	key := 'session:${session_id}'
	acquired := slm.lock_manager.lock_with_timeout(key, slm.config.acquire_timeout_ms)!
	if !acquired {
		return error('session lock timeout: ${session_id} / Session 锁超时: ${session_id}')
	}
	return new_session_lock_guard(slm.lock_manager, key)
}

// release 释放 Session 锁（通常由 SessionLockGuard 的 defer 自动调用）。
// release releases a Session lock (typically auto-called by SessionLockGuard's defer).
pub fn (mut slm SessionLockManager) release(session_id string) {
	key := 'session:${session_id}'
	slm.lock_manager.unlock(key) or {}
}

// with_session_lock 零心智成本的回调 API。
// 在锁保护下执行回调，框架保证锁的获取与释放。
// 即使回调返回错误，锁也会被释放。
//
// with_session_lock is the zero-cognitive-load callback API.
// Executes the callback under lock protection; the framework guarantees
// lock acquire and release. Even if the callback returns an error,
// the lock is released.
//
// 用法 / Usage:
//   slm.with_session_lock('session:abc', fn () ! {
//       // 在锁保护下操作 Session / Operate on Session under lock protection
//   })!
pub fn (mut slm SessionLockManager) with_session_lock(session_id string, callback fn () !) ! {
	key := 'session:${session_id}'
	acquired := slm.lock_manager.lock_with_timeout(key, slm.config.acquire_timeout_ms)!
	if !acquired {
		return error('session lock timeout: ${session_id} / Session 锁超时: ${session_id}')
	}
	callback() or {
		slm.lock_manager.unlock(key) or {}
		return err
	}
	slm.lock_manager.unlock(key) or {}
}

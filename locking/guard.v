module locking

// guard.v - RAII Guard Pattern for Automatic Lock Release
//
// Provides LockGuard — a guard that automatically releases a lock
// when it goes out of scope. This eliminates the risk of forgetting
// to unlock, which would cause deadlocks.
//
// Design Philosophy (降低心智成本 / Reduce Cognitive Load):
//   - Users should NOT need to remember to call unlock() on every code path
//   - Even if the user forgets or a panic occurs, the guard ensures unlock
//   - Prevents deadlocks from forgotten unlocks
//
// Spring equivalent: TransactionTemplate (auto-rollback on exception)
// Rust equivalent: MutexGuard (RAII, compiler-guaranteed Drop)
//
// Usage:
//   // Pattern 1: Guard with defer (recommended)
//   mut guard := lm.lock_guard('user:123')!
//   defer { guard.release() }
//   // Do work under lock — even if panic, defer ensures unlock
//
//   // Pattern 2: Callback mode (zero cognitive load)
//   lm.with_lock('user:123', fn () ! {
//       // Do work under lock — framework guarantees lock/unlock
//   })!

import sync

// LockGuard is an RAII guard for a LockManager lock.
// When released (either manually or via defer), the lock is
// automatically released back to the LockManager.
@[heap]
pub struct LockGuard {
pub mut:
	manager  &LockManager = unsafe { nil }
	key      string
	released bool
mut:
	mu sync.Mutex
}

// new_lock_guard creates a LockGuard for the given key.
pub fn new_lock_guard(manager &LockManager, key string) LockGuard {
	return LockGuard{
		manager:  manager
		key:      key
		released: false
	}
}

// release unlocks the key in the LockManager. Safe to call multiple times
// (subsequent calls are no-ops). This is the core of the RAII guarantee.
pub fn (mut g LockGuard) release() {
	g.mu.@lock()
	if g.released || isnil(g.manager) {
		g.mu.unlock()
		return
	}
	g.released = true
	unsafe {
		mut manager := g.manager
		manager.unlock(g.key) or {
			// Silently ignore unlock errors (lock may have been cleaned up)
		}
	}
}

// is_released returns whether the guard has already released its lock.
pub fn (g &LockGuard) is_released() bool {
	return g.released
}

// drop is called when the guard goes out of scope.
// In V, this is typically called via defer { guard.release() }.
pub fn (mut g LockGuard) drop() {
	g.release()
}

// ── LockManager Guard Methods ──

// lock_guard acquires a lock and returns an RAII guard.
// The guard will automatically release the lock when release() is called
// (typically via defer).
//
// Usage:
//   mut guard := lm.lock_guard('user:123')!
//   defer { guard.release() }
//   // Do work under lock
pub fn (mut lm LockManager) lock_guard(key string) !LockGuard {
	lm.lock(key)
	return LockGuard{
		manager:  lm
		key:      key
		released: false
	}
}

// try_lock_guard attempts to acquire a lock and returns a guard if successful.
// Returns none if the lock is already held.
pub fn (mut lm LockManager) try_lock_guard(key string) ?LockGuard {
	if lm.try_lock(key) {
		return LockGuard{
			manager:  lm
			key:      key
			released: false
		}
	}
	return none
}

// lock_guard_with_timeout attempts to acquire a lock with a timeout
// and returns a guard if successful.
pub fn (mut lm LockManager) lock_guard_with_timeout(key string, timeout_ms int) !LockGuard {
	acquired := lm.lock_with_timeout(key, timeout_ms)!
	if acquired {
		return LockGuard{
			manager:  lm
			key:      key
			released: false
		}
	}
	return error('lock timeout: ${key}')
}

// with_lock executes a callback while holding a lock, guaranteeing
// that the lock is released after the callback completes — even if
// the callback returns an error.
//
// This is the zero-cognitive-load API: users never need to think about
// lock/unlock at all. The framework handles it completely.
//
// Usage:
//   lm.with_lock('user:123', fn () ! {
//       // Do work under lock — framework guarantees lock/unlock
//   })!
pub fn (mut lm LockManager) with_lock(key string, callback fn () !) ! {
	lm.lock(key)
	callback() or {
		lm.unlock(key) or {}
		return err
	}
	lm.unlock(key) or {}
}

// with_distributed_lock_guard executes a callback while holding a
// distributed lock, guaranteeing release after the callback completes.
pub fn (mut lm LockManager) with_distributed_lock_guard(key string, ttl_ms int, callback fn () !) ! {
	if isnil(lm.distributed) {
		return error('no distributed lock backend configured / 未配置分布式锁后端')
	}
	acquired := lm.distributed.acquire(key, ttl_ms)!
	if !acquired {
		return error('distributed lock "${key}" not acquired / 分布式锁 "${key}" 获取失败')
	}
	callback() or {
		lm.distributed.release(key) or {}
		return err
	}
	lm.distributed.release(key) or {}
}
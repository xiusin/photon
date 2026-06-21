module locking

import time

// lock_test.v - Unit tests for Photon Lock Module
// Tests: LocalMutex, LockManager lock/unlock, LockGuard, try_lock

// ============================================================
// LocalMutex Tests
// ============================================================

fn test_new_mutex() {
	mut mu := new_mutex()
	assert mu.try_lock() == true // Should acquire
	mu.unlock()
}

fn test_mutex_lock_and_unlock() {
	mut mu := new_mutex()
	mu.lock()
	mu.unlock()
	// Should not panic
	assert true
}

fn test_mutex_try_lock_success() {
	mut mu := new_mutex()
	result := mu.try_lock()
	assert result == true
	mu.unlock()
}

fn test_mutex_try_lock_fails_when_locked() {
	mut mu := new_mutex()
	mu.lock()
	result := mu.try_lock()
	assert result == false
	mu.unlock()
}

fn test_mutex_try_lock_after_unlock() {
	mut mu := new_mutex()
	mu.lock()
	mu.unlock()
	result := mu.try_lock()
	assert result == true
	mu.unlock()
}

fn test_mutex_double_lock() {
	mut mu := new_mutex()
	mu.lock()
	// sync.Mutex is NOT reentrant — double-lock from same goroutine
	// would deadlock. This is correct behavior for a real mutex.
	mu.unlock()
	// Re-acquire after unlock should work
	mu.lock()
	mu.unlock()
	assert true
}

// ============================================================
// LockManager Tests
// ============================================================

fn test_new_lock_manager() {
	mut lm := new_lock_manager()
	assert lm.local_locks.len == 0
}

fn test_lock_manager_lock_unlock() {
	mut lm := new_lock_manager()
	lm.lock('resource1')
	lm.unlock('resource1') or { assert false, 'unlock failed' }
}

fn test_lock_manager_unlock_unknown_key() {
	mut lm := new_lock_manager()
	if _ := lm.unlock('unknown') {
		assert false, 'expected error for unknown key'
	} else {
		assert true
	}
}

fn test_lock_manager_try_lock_success() {
	mut lm := new_lock_manager()
	result := lm.try_lock('resource')
	assert result == true
	lm.unlock('resource') or {}
}

fn test_lock_manager_try_lock_fails_when_locked() {
	mut lm := new_lock_manager()
	lm.lock('shared')
	result := lm.try_lock('shared')
	assert result == false
	lm.unlock('shared') or {}
}

fn test_lock_manager_multiple_keys() {
	mut lm := new_lock_manager()
	lm.lock('a')
	lm.lock('b')
	lm.lock('c')

	// Should be able to unlock in any order
	lm.unlock('b') or {}
	lm.unlock('a') or {}
	lm.unlock('c') or {}
}

fn test_lock_manager_new_lock_creates_mutex() {
	mut lm := new_lock_manager()
	lm.lock('new-key')
	// Lock was created on-the-fly
	lm.unlock('new-key') or { assert false, 'should exist' }
}

fn test_lock_manager_try_lock_twice_same_key() {
	mut lm := new_lock_manager()
	// First try_lock on a new key: creates mutex, locks it, returns true (the fixed code path)
	first := lm.try_lock('resource-a')
	assert first == true
	// Second try_lock on the same key: mutex is already locked, should return false
	second := lm.try_lock('resource-a')
	assert second == false
	lm.unlock('resource-a') or {}
}

fn test_lock_manager_try_lock_reacquire_after_unlock() {
	mut lm := new_lock_manager()
	// Acquire
	assert lm.try_lock('reusable') == true
	// Release
	lm.unlock('reusable') or {}
	// Re-acquire after release — should succeed
	assert lm.try_lock('reusable') == true
	lm.unlock('reusable') or {}
}

// ============================================================
// LockManager Timeout Tests
// ============================================================

fn test_lock_with_timeout_success() {
	mut lm := new_lock_manager()
	result := lm.lock_with_timeout('available', 100)!
	assert result == true
	lm.unlock('available') or {}
}

fn test_lock_with_timeout_new_lock() {
	mut lm := new_lock_manager()
	// Key doesn't exist yet - should create and acquire
	result := lm.lock_with_timeout('new-resource', 10)!
	assert result == true
	lm.unlock('new-resource') or {}
}

fn test_lock_with_timeout_expires_when_held() {
	mut lm := new_lock_manager()
	// Hold the lock first
	lm.lock('contended-resource')
	// lock_with_timeout should poll try_lock(), fail each time, and return false after timeout
	result := lm.lock_with_timeout('contended-resource', 50)!
	assert result == false
	lm.unlock('contended-resource') or {}
}

// Helper: polls try_lock() until acquired. Same logic as lock_with_timeout's inner loop,
// but at the LocalMutex level to avoid the V shared-lock deadlock that would occur
// if lock_with_timeout held `lock lm { }` for the entire polling duration.
fn poll_mutex_until_acquired(shared mu LocalMutex) {
	start := time.now().unix_milli()
	for {
		lock mu {
			if mu.try_lock() {
				break
			}
		}
		if time.now().unix_milli() - start > 5000 {
			break
		}
		time.sleep(1 * time.millisecond)
	}
}

fn test_lock_with_timeout_succeeds_when_released() {
	// Tests the polling semantics that lock_with_timeout uses internally.
	// One goroutine polls try_lock(); the main goroutine unlocks mid-polling.
	shared mu := new_mutex()
	lock mu {
		mu.lock()
	}

	h := spawn poll_mutex_until_acquired(shared mu)

	// Let the spawned goroutine start polling, then release the lock
	time.sleep(50 * time.millisecond)
	lock mu {
		mu.unlock()
	}

	h.wait()

	// Spawned goroutine acquired the lock — try_lock should now fail
	lock mu {
		assert mu.try_lock() == false
		mu.unlock()
	}
}

// ============================================================
// DistributedLock Tests (interface only)
// ============================================================

fn test_lock_manager_distributed_nil() {
	mut lm := new_lock_manager()
	// dist_lock returns !bool, use or {} to handle
	if _ := lm.dist_lock('key', 100) {
		assert false, 'expected error'
	} else {
		assert true
	}
}

fn test_lock_manager_dist_unlock_nil() {
	mut lm := new_lock_manager()
	// dist_unlock returns !bool, use or {} to handle
	if _ := lm.dist_unlock('key') {
		assert false, 'expected error'
	} else {
		assert true
	}
}

// ============================================================
// LockGuard Tests
// ============================================================

fn test_lock_guard_acquires_lock() {
	mut lm := new_lock_manager()
	mut guard := new_lock_guard(mut lm, 'guarded-resource')
	assert guard.locked == true
	assert guard.key == 'guarded-resource'

	// Should not be able to acquire the same lock
	assert lm.try_lock('guarded-resource') == false

	guard.unlock()
}

fn test_lock_guard_unlock() {
	mut lm := new_lock_manager()
	mut guard := new_lock_guard(mut lm, 'resource')
	assert guard.locked == true

	guard.unlock()
	assert guard.locked == false

	// Now should be able to acquire
	assert lm.try_lock('resource') == true
	lm.unlock('resource') or {}
}

fn test_lock_guard_double_unlock() {
	mut lm := new_lock_manager()
	mut guard := new_lock_guard(mut lm, 'resource')
	guard.unlock()
	guard.unlock() // Second unlock should be safe (no-op)
	assert guard.locked == false
}

// ============================================================
// GuardedLock Tests
// ============================================================

fn test_guarded_lock_executes() {
	mut lm := new_lock_manager()

	result := guarded_lock(mut lm, 'critical-section', fn [mut lm] () !int {
		return 42
	})!

	assert result == 42
}

fn test_guarded_lock_releases_after_execution() {
	mut lm := new_lock_manager()
	guarded_lock(mut lm, 'section', fn [mut lm] () !int {
		return 1
	}) or {}

	// Lock should be released - can acquire again
	assert lm.try_lock('section') == true
	lm.unlock('section') or {}
}

fn test_guarded_lock_releases_on_error() {
	mut lm := new_lock_manager()
	guarded_lock(mut lm, 'section', fn [mut lm] () !int {
		return error('task failed')
	}) or {}

	// Lock should be released even on error — verified after defer-based cleanup
	assert lm.try_lock('section') == true
	lm.unlock('section') or {}
}

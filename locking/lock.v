module locking

// lock.v - Photon Lock Module
//
// Provides synchronization primitives using V's sync primitives.
// Supports local mutex locks and a distributed lock interface
// with pluggable backends (Redis, etc.).
import time
import sync

// DistributedLock is the trait for distributed lock implementations
pub interface DistributedLock {
	acquire(key string, ttl_ms int) !bool
	release(key string) !bool
	renew(key string, ttl_ms int) !bool
	is_locked(key string) bool
}

// LocalMutex provides a real mutual exclusion lock.
// V 0.5.1's sync.Mutex.try_lock() is broken (always returns false),
// so we use sync.Mutex as a short-lived spin-guard protecting a boolean flag.
pub struct LocalMutex {
mut:
	guard  sync.Mutex
	locked bool
}

// new_mutex creates a new LocalMutex
pub fn new_mutex() &LocalMutex {
	return &LocalMutex{}
}

// lock acquires the mutex (blocking, spin-waits with backoff)
pub fn (mut m LocalMutex) lock() {
	for {
		m.guard.@lock()
		if !m.locked {
			m.locked = true
			m.guard.unlock()
			return
		}
		m.guard.unlock()
		time.sleep(100 * time.microsecond)
	}
}

// unlock releases the mutex
pub fn (mut m LocalMutex) unlock() {
	m.guard.@lock()
	m.locked = false
	m.guard.unlock()
}

// try_lock attempts to acquire without blocking
pub fn (mut m LocalMutex) try_lock() bool {
	m.guard.@lock()
	if m.locked {
		m.guard.unlock()
		return false
	}
	m.locked = true
	m.guard.unlock()
	return true
}

// LockManager provides unified lock operations (local + distributed)
// Uses a sharded approach with sync.RwMutex for the map itself to prevent
// races when multiple goroutines create/access locks concurrently.
pub struct LockManager {
mut:
	map_mu sync.RwMutex
pub mut:
	local_locks map[string]&LocalMutex
	distributed &DistributedLock = unsafe { nil }
}

// new_lock_manager creates a new LockManager
pub fn new_lock_manager() &LockManager {
	return &LockManager{
		local_locks: map[string]&LocalMutex{}
	}
}

// with_distributed_lock sets a distributed lock backend
@[unsafe]
pub fn (mut lm LockManager) with_distributed_lock(dl &DistributedLock) {
	lm.distributed = dl
}

// lock acquires a local lock by key.
// Uses RwLock for map access to prevent races on lock creation.
pub fn (mut lm LockManager) lock(key string) {
	mut mu := lm.get_or_create_mutex(key)
	mu.lock()
}

// unlock releases a local lock by key
pub fn (mut lm LockManager) unlock(key string) ! {
	lm.map_mu.@rlock()
	mut mu := lm.local_locks[key] or {
		lm.map_mu.unlock()
		return error('lock "${key}" not found')
	}
	lm.map_mu.unlock()
	mu.unlock()
}

// try_lock attempts to acquire a local lock without blocking
pub fn (mut lm LockManager) try_lock(key string) bool {
	mut mu := lm.get_or_create_mutex(key)
	return mu.try_lock()
}

// lock_with_timeout acquires a lock with a timeout (blocking)
pub fn (mut lm LockManager) lock_with_timeout(key string, timeout_ms int) !bool {
	// Get or create the mutex first
	mut mu := lm.get_or_create_mutex(key)

	start := time.now().unix_milli()
	for {
		if mu.try_lock() {
			return true
		}
		if time.now().unix_milli() - start > timeout_ms {
			return false
		}
		time.sleep(1 * time.millisecond)
	}

	return false
}

// get_or_create_mutex returns an existing mutex or creates a new one.
// The returned mutex is NOT locked — caller must acquire it.
fn (mut lm LockManager) get_or_create_mutex(key string) &LocalMutex {
	// Fast path: try read lock first
	lm.map_mu.@rlock()
	if existing := lm.local_locks[key] {
		result := existing
		lm.map_mu.unlock()
		return result
	}
	lm.map_mu.unlock()

	// Slow path: create
	lm.map_mu.@lock()
	if existing := lm.local_locks[key] {
		result := existing
		lm.map_mu.unlock()
		return result
	}
	new_mu := new_mutex()
	lm.local_locks[key] = new_mu
	lm.map_mu.unlock()
	return new_mu
}

// dist_lock acquires a distributed lock
pub fn (mut lm LockManager) dist_lock(key string, ttl_ms int) !bool {
	if isnil(lm.distributed) {
		return error('no distributed lock backend configured')
	}
	return lm.distributed.acquire(key, ttl_ms)
}

// dist_unlock releases a distributed lock
pub fn (mut lm LockManager) dist_unlock(key string) !bool {
	if isnil(lm.distributed) {
		return error('no distributed lock backend configured')
	}
	return lm.distributed.release(key)
}

// LockGuard provides RAII-style automatic lock release
pub struct LockGuard {
	key string
mut:
	manager &LockManager
	locked  bool
}

// new_lock_guard creates a new lock guard and acquires the lock
pub fn new_lock_guard(mut manager LockManager, key string) &LockGuard {
	manager.lock(key)
	return &LockGuard{
		key:     key
		manager: manager
		locked:  true
	}
}

// unlock manually releases the lock
pub fn (mut lg LockGuard) unlock() {
	if lg.locked {
		lg.manager.unlock(lg.key) or {}
		lg.locked = false
	}
}

// guarded_lock runs a function under a named lock.
// Uses `defer` to guarantee the lock is released even if `f()` panics.
pub fn guarded_lock[T](mut manager LockManager, key string, f fn () !T) !T {
	manager.lock(key)
	defer {
		manager.unlock(key) or {}
	}
	return f()
}

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

// lock acquires the mutex (blocking, with exponential backoff).
// Starts at 100us backoff and doubles each iteration up to 50ms cap,
// balancing low latency for short waits with reduced CPU waste for long waits.
pub fn (mut m LocalMutex) lock() {
	mut backoff_us := i64(100)

	for {
		m.guard.@lock()
		if !m.locked {
			m.locked = true
			m.guard.unlock()
			return
		}
		m.guard.unlock()

		// Exponential backoff: 100us → 200us → 400us → ... → cap 50ms
		time.sleep(backoff_us * time.microsecond)
		if backoff_us < 50_000 {
			backoff_us *= 2
		}
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

// lock_with_timeout acquires a lock with a timeout (blocking).
// Uses sub-millisecond polling with exponential backoff for
// responsive acquisition on short timeouts.
pub fn (mut lm LockManager) lock_with_timeout(key string, timeout_ms int) !bool {
	mut mu := lm.get_or_create_mutex(key)

	start := time.now().unix_milli()
	mut poll_us := i64(100) // start at 100us

	for {
		if mu.try_lock() {
			return true
		}
		if time.now().unix_milli() - start > timeout_ms {
			return false
		}

		// Exponential backoff poll: 100us → 200us → 400us → ... → cap 1ms
		time.sleep(poll_us * time.microsecond)
		if poll_us < 1000 {
			poll_us *= 2
		}
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

// ── Lock Cleanup (Prevent Memory Leaks) ──

// unlock_and_cleanup unlocks a local lock and removes it from the map
// if no other goroutines are likely waiting for it.
// This prevents memory leaks from accumulating unused lock entries.
//
// Usage pattern:
//   lm.lock('temp-key')
//   // ... critical section ...
//   lm.unlock_and_cleanup('temp-key') or {}
//
// Note: Only use this for one-time or rarely-used keys.
// For frequently-used keys, regular unlock() is preferred.
pub fn (mut lm LockManager) unlock_and_cleanup(key string) ! {
	lm.map_mu.@rlock()
	mut mu := lm.local_locks[key] or {
		lm.map_mu.unlock()
		return error('lock "${key}" not found')
	}
	lm.map_mu.unlock()
	mu.unlock()

	// Remove the lock entry to free memory
	// Only safe if no other goroutine is waiting — use with caution
	lm.map_mu.@lock()
	lm.local_locks.delete(key)
	lm.map_mu.unlock()
}

// cleanup_unused_locks removes all lock entries that are not currently held.
// This is safe to call periodically (e.g., during low-traffic periods)
// to prevent memory leaks from accumulating unused lock entries.
//
// Returns the number of entries removed.
pub fn (mut lm LockManager) cleanup_unused_locks() int {
	lm.map_mu.@lock()
	defer { lm.map_mu.unlock() }

	mut removed := 0
	mut keys_to_remove := []string{}
	for key, mut mu in lm.local_locks {
		// Try to acquire — if we can, nobody else holds it
		if mu.try_lock() {
			// We acquired it, which means nobody was holding it
			mu.unlock()
			keys_to_remove << key
		}
		// If we can't acquire it, someone is using it — skip
	}
	for key in keys_to_remove {
		lm.local_locks.delete(key)
		removed++
	}
	return removed
}

// lock_count returns the total number of lock entries in the manager.
// Useful for monitoring potential memory leaks.
pub fn (mut lm LockManager) lock_count() int {
	lm.map_mu.rlock()
	defer { lm.map_mu.runlock() }
	return lm.local_locks.len
}

// LockGuard provides RAII-style automatic lock release.
//
// V does not have destructors, so the guard must be released explicitly
// via unlock() or implicitly via defer:
//
//   mut guard := new_lock_guard(mut manager, 'my-key')
//   defer { guard.unlock() }
//   // ... critical section ...
//
// Alternatively, use guarded_lock[T] which handles defer automatically.
pub struct LockGuard {
pub:
	key string
mut:
	manager &LockManager
	locked  bool
}

// new_lock_guard creates a new lock guard and acquires the lock.
// Remember to call unlock() when done (typically via defer).
pub fn new_lock_guard(mut manager LockManager, key string) &LockGuard {
	manager.lock(key)
	return &LockGuard{
		key:     key
		manager: manager
		locked:  true
	}
}

// unlock releases the lock. Safe to call multiple times.
pub fn (mut lg LockGuard) unlock() {
	if lg.locked {
		lg.manager.unlock(lg.key) or {}
		lg.locked = false
	}
}

// relock re-acquires the lock after unlock().
// Useful for temporarily releasing a lock in the middle of a critical section.
pub fn (mut lg LockGuard) relock() {
	if !lg.locked {
		lg.manager.lock(lg.key)
		lg.locked = true
	}
}

// is_locked returns whether the guard currently holds the lock.
pub fn (lg &LockGuard) is_locked() bool {
	return lg.locked
}

// guarded_lock runs a function under a named lock.
// Uses `defer` to guarantee the lock is released even if `f()` panics.
// This is the recommended way to use locks — it prevents forgetting to unlock.
pub fn guarded_lock[T](mut manager LockManager, key string, f fn () !T) !T {
	manager.lock(key)
	defer {
		manager.unlock(key) or {}
	}
	return f()
}

// scoped_lock acquires a lock, runs a function, and releases the lock.
// Simpler than guarded_lock when you don't need the generic return type.
// Spring equivalent: TransactionTemplate.execute()
pub fn scoped_lock(mut manager LockManager, key string, f fn ()) {
	manager.lock(key)
	defer {
		manager.unlock(key) or {}
	}
	f()
}

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
//
// Backed by sync.Mutex, not a channel. The previous implementation used a
// buffered chan bool as a binary semaphore, which meant every lock() was a
// channel send — a heap-allocated structure plus a scheduler round-trip even
// when completely uncontended. A local mutex is the hottest primitive in the
// framework; it has no business paying for a channel.
//
// `try_lock()` is kept because `LockManager.try_lock()` and
// `lock_with_timeout()` depend on a non-blocking acquire.
//
// unlock() stays idempotent-by-contract: the RAII guards in guard.v all call
// it unconditionally, so callers must not unlock a mutex they do not own.
pub struct LocalMutex {
mut:
	mu sync.Mutex
}

// new_mutex creates a new LocalMutex
pub fn new_mutex() &LocalMutex {
	mut m := &LocalMutex{}
	// Initialise eagerly: V's sync.Mutex lazy-initialises on first use, and
	// that path is racy when two goroutines contend on a brand-new mutex —
	// which is precisely what a lock manager produces.
	unsafe { m.mu.init() }
	return m
}

// lock acquires the mutex (blocking).
pub fn (mut m LocalMutex) lock() {
	m.mu.@lock()
}

// unlock releases the mutex.
pub fn (mut m LocalMutex) unlock() {
	m.mu.unlock()
}

// try_lock attempts to acquire without blocking.
// Returns true if acquired, false if the mutex is already held.
pub fn (mut m LocalMutex) try_lock() bool {
	return m.mu.try_lock()
}

// LockManager provides unified lock operations (local + distributed)
// Uses a sharded approach with sync.RwMutex for the map itself to prevent
// races when multiple goroutines create/access locks concurrently.
//
// ref_counts tracks how many goroutines hold a reference to each lock
// (via lock/try_lock/lock_with_timeout). unlock_and_cleanup() only deletes
// a lock entry when ref_count reaches 0, preventing the race where another
// goroutine acquires the lock between unlock and map deletion.
pub struct LockManager {
mut:
	map_mu sync.RwMutex
pub mut:
	local_locks map[string]&LocalMutex
	ref_counts  map[string]int
	distributed &DistributedLock = unsafe { nil }
	stop_gc     chan bool        = chan bool{cap: 1}
	gc_started  bool
	wg          sync.WaitGroup
}

// new_lock_manager creates a new LockManager
pub fn new_lock_manager() &LockManager {
	mut lm := &LockManager{
		local_locks: map[string]&LocalMutex{}
		ref_counts:  map[string]int{}
	}
	// Initialise eagerly: V's RwMutex initialises lazily on first use and
	// that path is racy when several goroutines lock a fresh manager at
	// once — which is the whole point of a lock manager.
	unsafe { lm.map_mu.init() }
	return lm
}

// with_distributed_lock sets a distributed lock backend
@[unsafe]
pub fn (mut lm LockManager) with_distributed_lock(dl &DistributedLock) {
	lm.distributed = dl
}

// lock acquires a local lock by key.
// Uses RwLock for map access to prevent races on lock creation.
// Increments ref_count atomically with mutex lookup so that
// unlock_and_cleanup() can safely detect concurrent users.
pub fn (mut lm LockManager) lock(key string) {
	mut mu := lm.get_or_create_mutex(key)
	mu.lock()
}

// unlock releases a local lock by key and decrements ref_count.
// Does NOT delete the lock entry — use unlock_and_cleanup() for that,
// or rely on the background GC to remove entries with ref_count == 0.
pub fn (mut lm LockManager) unlock(key string) ! {
	lm.map_mu.@lock()
	mut mu := lm.local_locks[key] or {
		lm.map_mu.unlock()
		return error('lock "${key}" not found')
	}
	count := lm.ref_counts[key] or { 0 }
	if count > 0 {
		lm.ref_counts[key] = count - 1
	}
	lm.map_mu.unlock()
	mu.unlock()
}

// try_lock attempts to acquire a local lock without blocking.
// On failure, decrements ref_count (incremented by get_or_create_mutex).
pub fn (mut lm LockManager) try_lock(key string) bool {
	mut mu := lm.get_or_create_mutex(key)
	if mu.try_lock() {
		return true
	}
	// Failed to acquire — release the reference taken in get_or_create_mutex
	lm.decrement_ref(key)
	return false
}

// lock_with_timeout acquires a lock with a timeout (blocking).
// Uses sub-millisecond polling with exponential backoff for
// responsive acquisition on short timeouts.
// On timeout, decrements ref_count (incremented by get_or_create_mutex).
pub fn (mut lm LockManager) lock_with_timeout(key string, timeout_ms int) !bool {
	mut mu := lm.get_or_create_mutex(key)

	start := time.now().unix_milli()
	mut poll_us := i64(100) // start at 100us

	for time.now().unix_milli() - start <= timeout_ms {
		if mu.try_lock() {
			return true
		}

		// Exponential backoff poll: 100us → 200us → 400us → ... → cap 1ms
		time.sleep(poll_us * time.microsecond)
		if poll_us < 1000 {
			poll_us *= 2
		}
	}

	// Timeout — release the reference taken in get_or_create_mutex
	lm.decrement_ref(key)
	return false
}

// get_or_create_mutex returns an existing mutex or creates a new one.
// The returned mutex is NOT locked — caller must acquire it.
// Atomically increments ref_count under the map write lock so that
// unlock_and_cleanup() can safely detect concurrent users.
fn (mut lm LockManager) get_or_create_mutex(key string) &LocalMutex {
	lm.map_mu.@lock()
	if existing := lm.local_locks[key] {
		result := existing
		lm.ref_counts[key] = (lm.ref_counts[key] or { 0 }) + 1
		lm.map_mu.unlock()
		return result
	}
	new_mu := new_mutex()
	lm.local_locks[key] = new_mu
	lm.ref_counts[key] = 1
	lm.map_mu.unlock()
	return new_mu
}

// decrement_ref decrements the ref_count for a key (used on try_lock/timeout failure).
fn (mut lm LockManager) decrement_ref(key string) {
	lm.map_mu.@lock()
	count := lm.ref_counts[key] or { 0 }
	if count > 0 {
		lm.ref_counts[key] = count - 1
	}
	lm.map_mu.unlock()
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
// if no other goroutines hold a reference to it (ref_count == 0).
//
// This is thread-safe: ref_count is decremented under the map write lock,
// and the entry is only deleted when ref_count reaches 0. If another
// goroutine has a pending reference (via lock/try_lock/lock_with_timeout),
// the entry is retained.
//
// Usage pattern:
//   lm.lock('temp-key')
//   // ... critical section ...
//   lm.unlock_and_cleanup('temp-key') or {}
//
// Note: Only use this for one-time or rarely-used keys.
// For frequently-used keys, regular unlock() is preferred.
pub fn (mut lm LockManager) unlock_and_cleanup(key string) ! {
	lm.map_mu.@lock()
	mut mu := lm.local_locks[key] or {
		lm.map_mu.unlock()
		return error('lock "${key}" not found')
	}
	count := lm.ref_counts[key] or { 0 }
	if count > 0 {
		lm.ref_counts[key] = count - 1
	}
	// Only delete if no other goroutine holds a reference
	if (lm.ref_counts[key] or { 0 }) <= 0 {
		lm.ref_counts.delete(key)
		lm.local_locks.delete(key)
	}
	lm.map_mu.unlock()
	mu.unlock()
}

// cleanup_unused_locks removes all lock entries with ref_count == 0.
// This is safe to call periodically (e.g., by the background GC)
// to prevent memory leaks from accumulating unused lock entries.
//
// Returns the number of entries removed.
pub fn (mut lm LockManager) cleanup_unused_locks() int {
	lm.map_mu.@lock()
	defer { lm.map_mu.unlock() }

	mut removed := 0
	mut keys_to_remove := []string{}
	for key, _ in lm.local_locks {
		count := lm.ref_counts[key] or { 0 }
		if count <= 0 {
			keys_to_remove << key
		}
	}
	for key in keys_to_remove {
		lm.local_locks.delete(key)
		lm.ref_counts.delete(key)
		removed++
	}
	return removed
}

// start_gc launches the background GC goroutine that periodically removes
// lock entries with ref_count == 0. Safe to call multiple times; only the
// first call starts the goroutine.
pub fn (mut lm LockManager) start_gc() {
	lm.map_mu.@lock()
	if lm.gc_started {
		lm.map_mu.unlock()
		return
	}
	lm.gc_started = true
	lm.stop_gc = chan bool{cap: 1}
	sig := lm.stop_gc
	lm.map_mu.unlock()

	lm.wg.add(1)
	spawn fn (glm &LockManager, stop_sig chan bool) {
		defer {
			unsafe { glm.wg.done() }
		}
		mut elapsed := 0
		for {
			// Sleep in 100ms increments so close() can stop us promptly.
			time.sleep(100 * time.millisecond)
			elapsed += 100

			// Non-blocking check for stop signal.
			mut should_stop := false
			select {
				_ := <-stop_sig {
					should_stop = true
				}
				else {}
			}
			if should_stop {
				break
			}

			// Sweep every 60 seconds
			if elapsed >= 60000 {
				elapsed = 0
				unsafe {
					mut m := glm
					m.cleanup_unused_locks()
				}
			}
		}
	}(lm, sig)
}

// close stops the background GC goroutine and waits for it to exit.
// Safe to call multiple times.
pub fn (mut lm LockManager) close() {
	lm.map_mu.@lock()
	if !lm.gc_started {
		lm.map_mu.unlock()
		return
	}
	lm.gc_started = false
	sig := lm.stop_gc
	lm.map_mu.unlock()

	select {
		sig <- true {}
		else {}
	}
	lm.wg.wait()
}

// lock_count returns the total number of lock entries in the manager.
// Useful for monitoring potential memory leaks.
pub fn (mut lm LockManager) lock_count() int {
	lm.map_mu.rlock()
	defer { lm.map_mu.runlock() }
	return lm.local_locks.len
}

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

// LockManager provides unified lock operations (local + distributed).
//
// Hot-path design: one map read, one lock, zero allocation.
//
//   - The key space is split into `lock_shard_count` shards. The shard is a
//     pure function of the key, so every operation touches exactly one shard
//     and one mutex — two keys on different shards never contend.
//     (Same shape as the cache shards.)
//
//   - The previous version took the map's write lock twice per lock() —
//     once to bump the ref count, once more inside get_or_create_mutex — and
//     lock_guard() took it a third time through lock(). That is three
//     exclusive acquisitions on the hottest primitive in the framework, and
//     they serialised *unrelated* keys. Now: one.
//
//   - The shard's mutex is held only for the map lookup/insert and the ref
//     count bump. The user-visible LocalMutex is locked *after* the shard
//     mutex is released, so holding a user lock never holds a shard lock.
//
//   - `distributed` is read without a lock. It is configured once by
//     with_distributed_lock() during startup and never mutated afterwards,
//     exactly like a Spring bean reference.
//
// Lock ordering (mandatory): shard.mu may be held while locking shard.mu of
// the *same* shard only; a user LocalMutex is never held together with a
// shard mutex. There is no global lock in this file.
pub struct LockManager {
mut:
	shards []LockShard
	// gc state — start/stop only ever happens once, guaranteed by sync.Once.
	gc_once sync.Once
	stop_gc chan bool
	started bool
	wg      sync.WaitGroup
pub mut:
	distributed &DistributedLock = unsafe { nil }
}

// lock_shard_count is the number of map shards. Power of two so the index is
// a mask instead of a modulo.
pub const lock_shard_count = 16

// LockShard is one lock domain of the manager's key table.
@[heap]
struct LockShard {
mut:
	mu sync.RwMutex
	// local_locks / ref_counts are only touched with mu held.
	local_locks map[string]&LocalMutex
	ref_counts  map[string]int
}

// new_lock_manager creates a new LockManager.
pub fn new_lock_manager() &LockManager {
	mut lm := &LockManager{
		shards:  new_lock_shards()
		stop_gc: chan bool{cap: 1}
	}
	return lm
}

// new_lock_shards allocates the shard table with every mutex initialised up
// front. V's sync primitives initialise lazily, and that path is racy when the
// goroutine that loses the CAS proceeds to use an uninitialised pthread mutex —
// which is the normal case for a lock manager.
fn new_lock_shards() []LockShard {
	mut shards := []LockShard{len: lock_shard_count}
	for i in 0 .. shards.len {
		shards[i].local_locks = map[string]&LocalMutex{}
		shards[i].ref_counts = map[string]int{}
		unsafe { shards[i].mu.init() }
	}
	return shards
}

// shard_ptr returns the shard owning `key`.
@[direct_array_access; inline]
fn (lm &LockManager) shard_ptr(key string) &LockShard {
	return unsafe { &lm.shards[lock_shard_index(key)] }
}

// lock_shard_index maps a key to its shard slot: FNV-1a masked to the
// (power-of-two) shard count. Allocation-free.
@[direct_array_access; inline]
fn lock_shard_index(key string) int {
	mut h := u64(0xcbf29ce484222325)
	for i in 0 .. key.len {
		h = (h ^ u64(unsafe { key.str[i] })) * 0x100000001b3
	}
	return int(h & u64(lock_shard_count - 1))
}

// with_distributed_lock sets a distributed lock backend.
// Configure once, at startup: the field is read lock-free afterwards.
@[unsafe]
pub fn (mut lm LockManager) with_distributed_lock(dl &DistributedLock) {
	lm.distributed = dl
}

// lock acquires a local lock by key. Blocking.
pub fn (mut lm LockManager) lock(key string) {
	mut mu := lm.acquire_mutex(key)
	// The user lock is taken after the shard mutex is already released, so a
	// contended key never blocks holders of unrelated keys.
	mu.lock()
}

// unlock releases a local lock by key and decrements ref_count.
// Does NOT delete the entry — use unlock_and_cleanup() for that, or rely on
// the background GC to remove entries with ref_count == 0.
pub fn (mut lm LockManager) unlock(key string) ! {
	mut sh := lm.shard_ptr(key)
	sh.mu.@lock()
	mut mu := sh.local_locks[key] or {
		sh.mu.unlock()
		return error('lock "${key}" not found')
	}
	count := sh.ref_counts[key] or { 0 }
	if count > 0 {
		sh.ref_counts[key] = count - 1
	}
	sh.mu.unlock()
	mu.unlock()
}

// try_lock attempts to acquire a local lock without blocking.
// On failure, the reference taken by acquire_mutex is released again.
pub fn (mut lm LockManager) try_lock(key string) bool {
	mut mu := lm.acquire_mutex(key)
	if mu.try_lock() {
		return true
	}
	lm.decrement_ref(key)
	return false
}

// lock_with_timeout acquires a lock with a timeout (blocking).
//
// The first attempt is immediate, which is the only case that matters for an
// uncontended key: one try_lock, no timing syscall. Only a contended key pays
// for the clock and the backoff sleep.
pub fn (mut lm LockManager) lock_with_timeout(key string, timeout_ms int) !bool {
	mut mu := lm.acquire_mutex(key)

	// Fast path: uncontended.
	if mu.try_lock() {
		return true
	}

	start := time.now().unix_milli()
	mut poll_us := i64(100) // 100us → 200us → … → 1ms

	// Contract: `false` means the caller does NOT hold the lock, so failing
	// only decrements the ref count. The loop therefore never leaves an
	// acquisition pending at the deadline: on success it returns immediately
	// with the mutex held, and once the deadline has passed it stops trying.
	// (A separate "maybe held" probe at the end is unsound — under contention
	// the probing try_lock/failed-unlock pair itself can drop another
	// goroutine's lock.)
	for {
		remaining := i64(timeout_ms) - (time.now().unix_milli() - start)
		if remaining < 0 {
			break
		}
		if mu.try_lock() {
			return true
		}
		sleep_us := if poll_us < remaining * 1000 { poll_us } else { remaining * 1000 }
		if sleep_us > 0 {
			time.sleep(sleep_us * time.microsecond)
		}
		if poll_us < 1000 {
			poll_us *= 2
		}
	}

	lm.decrement_ref(key)
	return false
}

// acquire_mutex returns the existing mutex for `key` or creates one, bumping
// its ref_count. The returned mutex is NOT locked — caller must acquire it.
//
// One shard write lock, one map lookup, one insert on the miss path.
fn (mut lm LockManager) acquire_mutex(key string) &LocalMutex {
	mut sh := lm.shard_ptr(key)
	sh.mu.@lock()
	if existing := sh.local_locks[key] {
		sh.ref_counts[key] = (sh.ref_counts[key] or { 0 }) + 1
		sh.mu.unlock()
		return existing
	}
	new_mu := new_mutex()
	sh.local_locks[key] = new_mu
	sh.ref_counts[key] = 1
	sh.mu.unlock()
	return new_mu
}

// decrement_ref decrements the ref_count for a key (used when an acquisition
// attempt failed after the reference had already been taken).
fn (mut lm LockManager) decrement_ref(key string) {
	mut sh := lm.shard_ptr(key)
	sh.mu.@lock()
	count := sh.ref_counts[key] or { 0 }
	if count > 0 {
		sh.ref_counts[key] = count - 1
	}
	sh.mu.unlock()
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

// unlock_and_cleanup unlocks a local lock and removes it from the map when no
// other goroutine holds a reference (ref_count == 0).
//
// The ref count is decremented and the entry deleted under a single shard lock,
// so a concurrent reference taken by another goroutine keeps the entry alive.
pub fn (mut lm LockManager) unlock_and_cleanup(key string) ! {
	mut sh := lm.shard_ptr(key)
	sh.mu.@lock()
	mut mu := sh.local_locks[key] or {
		sh.mu.unlock()
		return error('lock "${key}" not found')
	}
	count := sh.ref_counts[key] or { 0 }
	if count > 0 {
		sh.ref_counts[key] = count - 1
	}
	if (sh.ref_counts[key] or { 0 }) <= 0 {
		sh.ref_counts.delete(key)
		sh.local_locks.delete(key)
	}
	sh.mu.unlock()
	mu.unlock()
}

// cleanup_unused_locks removes all lock entries with ref_count == 0.
// Safe to call periodically (the background GC does exactly that).
//
// Each shard is swept under its own write lock: a sweep of one shard never
// blocks lock acquisition on another.
//
// Returns the number of entries removed.
pub fn (mut lm LockManager) cleanup_unused_locks() int {
	mut removed := 0
	for i in 0 .. lm.shards.len {
		mut sh := unsafe { &lm.shards[i] }
		sh.mu.@lock()
		mut dead := []string{cap: sh.local_locks.len}
		for key, _ in sh.local_locks {
			if (sh.ref_counts[key] or { 0 }) <= 0 {
				dead << key
			}
		}
		for key in dead {
			sh.local_locks.delete(key)
			sh.ref_counts.delete(key)
		}
		removed += dead.len
		sh.mu.unlock()
	}
	return removed
}

// gc_interval_ms is how often the background sweeper runs.
const gc_interval_ms = 60000

// start_gc launches the background GC goroutine that removes lock entries with
// ref_count == 0. Idempotent and cheap after the first call: the "already
// started" check is a plain boolean read guarded by sync.Once, not a lock.
pub fn (mut lm LockManager) start_gc() {
	if lm.started {
		return
	}
	lm.gc_once.do(fn [mut lm] () {
		lm.started = true
		lm.wg.add(1)
		spawn fn (glm &LockManager, stop_sig chan bool) {
			defer {
				unsafe { glm.wg.done() }
			}
			mut elapsed := 0
			for {
				time.sleep(100 * time.millisecond)
				elapsed += 100

				mut should_stop := false
				select {
					_ := <-stop_sig {
						should_stop = true
					}
					else {
					}
				}
				if should_stop {
					return
				}

				if elapsed >= gc_interval_ms {
					elapsed = 0
					unsafe {
						mut m := glm
						m.cleanup_unused_locks()
					}
				}
			}
		}(lm, lm.stop_gc)
	})
}

// close stops the background GC goroutine and waits for it to exit.
// Safe to call multiple times.
pub fn (mut lm LockManager) close() {
	if !lm.started {
		return
	}
	sig := lm.stop_gc
	select {
		sig <- true {
		}
		else {
		}
	}
	lm.wg.wait()
}

// lock_count returns the total number of live lock entries.
// Monitoring helper; walks the shards one at a time.
pub fn (mut lm LockManager) lock_count() int {
	mut n := 0
	for i in 0 .. lm.shards.len {
		mut sh := unsafe { &lm.shards[i] }
		sh.mu.rlock()
		n += sh.local_locks.len
		sh.mu.runlock()
	}
	return n
}

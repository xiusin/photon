module pool

// pool.v - Photon Connection/Object Pool Module
//
// Provides a generic object pool with configurable min/max size,
// health checking, connection validation, idle timeout, max lifetime,
// background GC, and thread safety.
import time
import sync

// PooledObject is the trait for objects managed by the pool.
// Implementations provide their own close() and is_valid() methods.
// For pools that manage voidptr resources, use a Factory implementation
// whose destroy() handles resource cleanup.
pub interface PooledObject {
	close() !
	is_valid() bool
}

// Factory creates and manages the lifecycle of pooled objects.
// Implementations are responsible for:
//   - create():    constructing a new resource
//   - is_valid():  health-checking an existing resource (e.g. ping)
//   - destroy():   releasing/closing a resource
//
// All methods use immutable receivers so that factories may be shared
// safely across goroutines via the Pool's &Factory reference. Factories
// that need to track mutable state should do so through pointers or
// module-level globals guarded by their own synchronization.
pub interface Factory {
	create() !voidptr
	is_valid(obj voidptr) bool
	destroy(obj voidptr)
}

// FuncFactory wraps a simple creation function into a Factory.
// is_valid always returns true and destroy is a no-op, making it
// suitable for simple pools that don't need validation or explicit
// teardown (e.g. pools of plain integers/structs in tests).
struct FuncFactory {
	create_fn fn () !voidptr = unsafe { nil }
}

pub fn (f &FuncFactory) create() !voidptr {
	return f.create_fn()
}

pub fn (f &FuncFactory) is_valid(obj voidptr) bool {
	return true
}

pub fn (f &FuncFactory) destroy(obj voidptr) {
	// no-op for function-based factories
}

// Pool manages a pool of reusable objects (thread-safe).
//
// active_count tracks the number of objects currently checked out
// (in use) plus any slots reserved for in-flight creation. The total
// number of live objects is objects.len. max_size is enforced against
// active_count so that reserved slots count toward the cap.
@[heap]
pub struct Pool {
pub mut:
	min_size             int = 2
	max_size             int = 10
	idle_timeout_seconds int = 300 // 0 = disable idle eviction
	max_lifetime_seconds int // 0 = disable lifetime eviction
	gc_interval_seconds  int = 10 // how often the GC goroutine sweeps
pub:
	name string
mut:
	mu           sync.Mutex
	objects      []PoolEntry
	// obj_index maps an object pointer to its ledger slot. Maintained only when
	// the ledger is rebuilt (initialize / gc_sweep / close), so no operation pays
	// an O(n) rebuild: appends just record the new slot.
	obj_index    map[voidptr]int
	free_stack   []voidptr // stack of free object pointers (O(1) pop/push)
	active_count int             // in-use + reserved slots
	wait_count   int
	closed       bool
	factory      &Factory = unsafe { nil }
	stop_gc      chan bool
	wg           sync.WaitGroup
	gc_started   bool
	// avail is a broadcast channel for waiters blocked in
	// acquire_with_timeout(): release()/close() close it to wake every waiter
	// at once, which replaces the previous 10ms polling loop. It is recreated
	// (empty) by the woken waiter, so waiters never miss a wakeup.
	avail chan bool
}

// PoolEntry wraps a pooled object with metadata
struct PoolEntry {
pub mut:
	object       voidptr
	in_use       bool
	created_at   i64
	last_used_at i64
}

// init_locks initialises the pool's sync primitives up front.
//
// V's sync.RwMutex/Mutex initialise lazily on first use, and that lazy path
// is racy: a goroutine that loses the CAS proceeds to lock a
// pthread_rwlock_t that may not be initialised yet. A pool is handed to
// several goroutines immediately after construction, so the first lock is
// very likely concurrent. Doing it here removes the window entirely.
fn (mut p Pool) init_locks() {
	p.avail = chan bool{}
	p.obj_index = map[voidptr]int{}
	unsafe {
		p.mu.init()
	}
}

// new_pool creates a new Pool with a function factory.
// The function is wrapped in a FuncFactory whose is_valid() always
// returns true and whose destroy() is a no-op.
pub fn new_pool(name string, factory fn () !voidptr) &Pool {
	mut p := &Pool{
		name:    name
		factory: &FuncFactory{
			create_fn: factory
		}
	}
	p.init_locks()
	return p
}

// new_pool_with_config creates a Pool with custom sizes and a function factory.
pub fn new_pool_with_config(name string, factory fn () !voidptr, min_size int, max_size int) &Pool {
	mut p := &Pool{
		name:     name
		factory:  &FuncFactory{
			create_fn: factory
		}
		min_size: min_size
		max_size: max_size
	}
	p.init_locks()
	return p
}

// new_pool_with_factory creates a Pool with a Factory trait implementation.
// Use this constructor when you need is_valid() validation and destroy()
// cleanup (e.g. for real database connections).
pub fn new_pool_with_factory(name string, factory &Factory, min_size int, max_size int) &Pool {
	mut p := &Pool{
		name:     name
		factory:  factory
		min_size: min_size
		max_size: max_size
	}
	p.init_locks()
	return p
}

// initialize pre-creates min_size objects. The objects are created in
// the idle state; active_count is not incremented because they are not
// in use.
pub fn (mut p Pool) initialize() ! {
	p.mu.@lock()
	defer { p.mu.unlock() }
	if p.closed {
		return error('pool "${p.name}" is closed')
	}
	for _ in 0 .. p.min_size {
		obj := p.factory.create()!
		p.obj_index[obj] = p.objects.len
		p.objects << PoolEntry{
			object:       obj
			created_at:   time.now().unix()
			last_used_at: time.now().unix()
		}
		p.free_stack << obj
	}
}

// is_closed reports whether the pool has been closed. A closed pool refuses
// acquire() and initialize(), but `release()` still works so holders of
// in-use objects can finish — it destroys them instead of pooling them.
//
// Why this is a method and not a public field: callers used to tell "closed"
// apart from "exhausted" by string-matching the error text, because
// acquire() reports both as !voidptr errors and the two need very different
// handling — an exhausted pool is a capacity signal and degrades gracefully,
// a closed pool is a lifecycle bug and must not be papered over.
//
// is_closed 报告池是否已关闭。已关闭的池拒绝 acquire() 与 initialize()，
// 但 release() 仍可用，好让持有在用对象的一方收尾——它会销毁对象而不是归还。
//
// 为什么是方法而不是公开字段：调用方以前靠匹配错误文本区分「已关闭」和「已耗尽」，
// 因为 acquire() 两者都报 !voidptr 错误，而它们需要完全不同的处理——
// 耗尽只是容量信号、可以优雅降级；已关闭是生命周期错误、不能被糊过去。
pub fn (p &Pool) is_closed() bool {
	mut pm := unsafe { &Pool(p) }
	pm.mu.@lock()
	defer { pm.mu.unlock() }
	return p.closed
}

// start_gc launches the background GC goroutine that evicts idle objects
// whose idle_timeout_seconds or max_lifetime_seconds have elapsed.
// Safe to call multiple times; only the first call starts the goroutine.
pub fn (mut p Pool) start_gc() {
	p.mu.@lock()
	if p.gc_started || p.closed {
		p.mu.unlock()
		return
	}
	p.gc_started = true
	p.stop_gc = chan bool{cap: 1}
	sig := p.stop_gc
	interval_ms := p.gc_interval_seconds * 1000
	p.mu.unlock()

	p.wg.add(1)
	spawn fn (gp &Pool, stop_sig chan bool, interval_ms int) {
		defer {
			unsafe { gp.wg.done() }
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

			// Bail out if the pool was closed.
			unsafe { gp.mu.@lock() }
			closed := gp.closed
			unsafe { gp.mu.unlock() }
			if closed {
				break
			}

			// Sweep when the configured interval has elapsed.
			if elapsed >= interval_ms {
				elapsed = 0
				unsafe { gp.gc_sweep() }
			}
		}
	}(p, sig, interval_ms)
}

// gc_sweep removes idle objects whose idle timeout or max lifetime has
// expired, and destroys them via the factory. In-use objects are always
// retained. Called periodically by the GC goroutine.
fn (mut p Pool) gc_sweep() {
	mut to_destroy := []voidptr{}
	p.mu.@lock()
	if p.closed {
		p.mu.unlock()
		return
	}
	now := time.now().unix()
	mut kept := []PoolEntry{}
	for entry in p.objects {
		if entry.in_use {
			kept << entry
			continue
		}
		idle_expired := p.idle_timeout_seconds > 0
			&& (now - entry.last_used_at) > p.idle_timeout_seconds
		lifetime_expired := p.max_lifetime_seconds > 0
			&& (now - entry.created_at) > p.max_lifetime_seconds
		if idle_expired || lifetime_expired {
			to_destroy << entry.object
		} else {
			kept << entry
		}
	}
	// Swap in the compacted ledger: this sweep is already O(n), so it is the
	// natural place to drop tombstones and rebuild the free stack in one pass.
	// Swap in the compacted ledger and rebuild the reverse index + free stack
	// in the same O(n) pass. This sweep already walks the ledger, so the index
	// costs nothing extra and no other operation has to maintain it.
	p.objects = kept
	p.obj_index = map[voidptr]int{}
	p.free_stack = []
	for i, entry in kept {
		if entry.object != unsafe { nil } {
			p.obj_index[entry.object] = i
		}
		if !entry.in_use {
			p.free_stack << entry.object
		}
	}
	p.mu.unlock()

	// Destroy evicted objects outside the lock to avoid blocking
	// other pool operations during teardown.
	for obj in to_destroy {
		p.factory.destroy(obj)
	}
}

// wake_waiters_unsafe wakes every goroutine parked in acquire_with_timeout()
// and arms a fresh channel for the next round. Closing the channel broadcasts
// to all waiters at once; a single buffered send would only wake one.
// Caller must hold `mu`.
fn (mut p Pool) wake_waiters_unsafe() {
	old := p.avail
	p.avail = chan bool{}
	old.close()
}

// entry_unsafe finds the ledger entry for `obj`. Caller must hold `mu`.
//
// O(1) through the reverse index, which is only rebuilt by the passes that
// already walk the whole ledger (initialize / gc_sweep / close). The previous
// version scanned the ledger backwards on every acquire and release; with the
// index maintained at rebuild time there is nothing to pay per operation.
fn (mut p Pool) entry_unsafe(obj voidptr) ?PoolEntry {
	idx := p.obj_index[obj] or { return none }
	if idx < 0 || idx >= p.objects.len {
		return none
	}
	entry := p.objects[idx]
	if entry.object != obj {
		return none
	}
	return entry
}

// mark_in_use_unsafe flips the ledger flag for `obj`. Caller must hold `mu`.
fn (mut p Pool) mark_in_use_unsafe(obj voidptr) {
	if obj !in p.obj_index {
		return
	}
	idx := p.obj_index[obj]
	if idx < 0 || idx >= p.objects.len {
		return
	}
	p.objects[idx].in_use = true
	p.objects[idx].last_used_at = time.now().unix()
}

// tombstone_unsafe clears a dead entry's object pointer and drops it from the
// reverse index. Caller must hold `mu`. The slot stays as a hole until the next
// GC sweep compacts the ledger, which keeps every live object's slot stable.
fn (mut p Pool) tombstone_unsafe(obj voidptr) {
	if obj !in p.obj_index {
		return
	}
	idx := p.obj_index[obj]
	p.obj_index.delete(obj)
	if idx >= 0 && idx < p.objects.len {
		unsafe { p.objects[idx].object = nil }
		p.objects[idx].in_use = false
	}
}

// acquire gets an object from the pool.
//
// It first looks for a valid idle object from the free stack (O(1) pop),
// validating via factory.is_valid. Invalid idle objects are destroyed and
// removed. If no valid idle object is available and the pool is under
// max_size, a new object is created.
// Returns an error if the pool is closed or exhausted.
pub fn (mut p Pool) acquire() !voidptr {
	for {
		p.mu.@lock()

		if p.closed {
			p.mu.unlock()
			return error('pool "${p.name}" is closed')
		}

		// Pop from the free stack (O(1)) until a valid idle object is found.
		//
		// `objects` is an append-only ledger: dead entries are tombstoned by
		// clearing their pointer, never removed by index, so every live object
		// keeps a stable slot and the reverse index stays valid between GC
		// sweeps.
		mut candidate := unsafe { nil }
		mut found := false
		for p.free_stack.len > 0 {
			obj_ptr := p.free_stack[p.free_stack.len - 1]
			p.free_stack.delete(p.free_stack.len - 1)

			entry := p.entry_unsafe(obj_ptr) or { continue }
			if entry.in_use || entry.object == unsafe { nil } {
				continue
			}
			candidate = entry.object
			found = true
			break
		}

		if found {
			// Health-check OUTSIDE the pool lock: is_valid() may ping a database
			// or open a socket, and doing that while holding the pool mutex
			// stalls every other goroutine in the pool for the duration of a
			// network round-trip.
			p.mu.unlock()
			if p.factory.is_valid(candidate) {
				p.mu.@lock()
				// Re-check under the lock: a concurrent release may have already
				// handed this object out, or the pool may have been closed.
				if p.closed {
					p.mu.unlock()
					p.factory.destroy(candidate)
					return error('pool "${p.name}" is closed')
				}
				entry := p.entry_unsafe(candidate) or {
					p.mu.unlock()
					continue
				}
				if entry.in_use {
					// Lost the race, put it back and retry.
					p.free_stack << candidate
					p.mu.unlock()
					continue
				}
				p.mark_in_use_unsafe(candidate)
				p.active_count++
				p.mu.unlock()
				return candidate
			}

			// Invalid object: destroy it (outside the lock) and drop it from the
			// kernel-visible ledger so the slot can be compacted by GC.
			p.factory.destroy(candidate)
			p.mu.@lock()
			p.tombstone_unsafe(candidate)
			p.mu.unlock()
			continue
		}

		// No idle object; create a new one if under the cap.
		if p.active_count < p.max_size {
			// Reserve the slot under the lock, create outside it (the factory may
			// do network I/O), then register the object.
			p.active_count++
			p.mu.unlock()
			obj := p.factory.create() or {
				p.mu.@lock()
				p.active_count--
				p.mu.unlock()
				return err
			}
			p.mu.@lock()
			if p.closed {
				p.active_count--
				p.mu.unlock()
				p.factory.destroy(obj)
				return error('pool "${p.name}" is closed')
			}
			p.obj_index[obj] = p.objects.len
			p.objects << PoolEntry{
				object:       obj
				created_at:   time.now().unix()
				last_used_at: time.now().unix()
				in_use:       true
			}
			p.mu.unlock()
			return obj
		}

		p.mu.unlock()
		return error('pool "${p.name}" exhausted (max=${p.max_size}, active=${p.active_count})')
	}
	return error('pool "${p.name}" acquire: unreachable')
}

// acquire_with_timeout blocks until an object is available or the timeout expires.
//
// Unlike acquire() which returns immediately with an error when the pool is
// exhausted, this method polls the pool periodically until an object becomes
// available (e.g. another goroutine calls release()). If the timeout is
// reached, it returns an error.
//
// timeout_seconds must be >= 1. The caller should always release the object.
//
// Usage:
//   obj := pool.acquire_with_timeout(30)! // wait up to 30 seconds
//   defer { pool.release(obj) }
pub fn (mut p Pool) acquire_with_timeout(timeout_seconds int) !voidptr {
	deadline := time.now().unix() + i64(timeout_seconds)
	for {
		obj := p.acquire() or {
			if !err.msg().contains('exhausted') {
				return err
			}
			remaining := deadline - time.now().unix()
			if remaining <= 0 {
				return error('pool "${p.name}" acquire timed out after ${timeout_seconds}s')
			}
			// Park on the broadcast channel instead of polling every 10ms:
			// release() closes it the moment an object becomes free, so a waiter
			// wakes immediately and an idle waiter costs no CPU at all.
			p.mu.@lock()
			if p.closed {
				p.mu.unlock()
				return error('pool "${p.name}" is closed')
			}
			signal := p.avail
			p.avail = chan bool{}
			p.mu.unlock()

			// `time.after` does not exist in V, so the timeout is a timer
			// goroutine that fires the same broadcast channel the pool uses.
			timer := spawn fn (sig chan bool, wait_s int) {
				time.sleep(wait_s * time.second)
				select {
					sig <- true {}
					else {}
				}
			}(signal, int(remaining))
			_ := <-signal
			timer.wait()
			continue
		}
		return obj
	}
	return error('unreachable')
}

// acquire_guard_with_timeout acquires a typed RAII guard, blocking up to
// the specified timeout. See acquire_with_timeout for blocking semantics.
pub fn (mut p Pool) acquire_guard_with_timeout[T](timeout_seconds int) !PooledGuard[T] {
	obj := p.acquire_with_timeout(timeout_seconds) or {
		return error('acquire_guard_with_timeout: ${err}')
	}
	return new_pooled_guard[T](p, obj)
}

// release returns an object to the pool.
//
// If the pool is closed, the object is destroyed directly via the factory
// (it cannot be returned to a closed pool). Otherwise the object is marked
// idle via O(1) reverse-mapping lookup, active_count is decremented, and
// last_used_at is updated so the GC can evict it after idle_timeout_seconds.
pub fn (mut p Pool) release(obj voidptr) {
	p.mu.@lock()
	if p.closed {
		// Pool is closed: destroy the object directly to avoid a leak.
		//
		// Only objects this pool still owns may be destroyed. A pool that is
		// closed while an object is checked out keeps that object in `objects`
		// (so it can still be found here); an object that is *not* in `objects`
		// was never handed out by this pool — or was already released — and the
		// caller has nothing to give back. Destroying it anyway calls
		// factory.destroy() twice for one object: the double free deletes the
		// heap pointer under an API that still points at it, which is exactly
		// how a pool turns into a use-after-free.
		if !p.owns(obj) {
			p.mu.unlock()
			return
		}
		p.forget(obj)
		p.mu.unlock()
		p.factory.destroy(obj)
		return
	}
	// O(1) via the reverse index. Unknown / tombstoned / already-idle objects
	// are silently ignored (backward compat), and a double release cannot
	// inflate active_count or push the same pointer twice onto the free stack.
	entry := p.entry_unsafe(obj) or {
		p.mu.unlock()
		return
	}
	if entry.in_use {
		idx := p.obj_index[obj]
		p.objects[idx].in_use = false
		p.objects[idx].last_used_at = time.now().unix()
		p.active_count--
		p.free_stack << obj
		p.wake_waiters_unsafe()
	}
	p.mu.unlock()
}

// owns reports whether `obj` is still tracked by this pool's ledger.
// Caller must hold `mu`.
fn (p &Pool) owns(obj voidptr) bool {
	if obj in p.obj_index {
		return true
	}
	// The index is only rebuilt by initialize / gc_sweep / close, and the
	// ledger is compacted there too — so a miss means "not ours".
	return false
}

// forget drops `obj` from the ledger without destroying it. Caller must hold
// `mu`. Used on the closed-pool path so a second release() of the same
// pointer cannot reach destroy() again.
fn (mut p Pool) forget(obj voidptr) {
	if obj !in p.obj_index {
		return
	}
	idx := p.obj_index[obj]
	p.obj_index.delete(obj)
	if idx >= 0 && idx < p.objects.len {
		p.objects[idx].object = unsafe { nil }
		p.objects[idx].in_use = false
	}
}

// close drains and closes all idle pooled objects.
//
// Sets the closed flag, destroys every IDLE object via the factory,
// removes them from the pool, and resets active_count. In-use objects
// are retained so their holders can release() them; release() on a
// closed pool destroys the object directly (avoiding double-destroy).
// The GC goroutine is stopped if running. Safe to call multiple times.
pub fn (mut p Pool) close() ! {
	p.mu.@lock()
	if p.closed {
		p.mu.unlock()
		return
	}
	p.closed = true
	mut to_destroy := []voidptr{}
	mut kept := []PoolEntry{}
	for entry in p.objects {
		if entry.in_use {
			// Keep in-use objects; the holder will release() them,
			// and release() on a closed pool destroys them directly.
			kept << entry
		} else {
			// Destroy idle objects now.
			to_destroy << entry.object
		}
	}
	p.objects = kept
	p.active_count = 0
	p.free_stack = [] // all idle objects destroyed
	p.obj_index = map[voidptr]int{}
	for i, entry in kept {
		if entry.object != unsafe { nil } {
			p.obj_index[entry.object] = i
		}
	}
	p.wake_waiters_unsafe()
	gc_was_started := p.gc_started
	p.mu.unlock()

	// Stop the GC goroutine and wait for it to fully exit.
	if gc_was_started {
		select {
			p.stop_gc <- true {}
			else {}
		}
		p.wg.wait()
	}

	// Destroy idle objects outside the lock to avoid blocking pool
	// operations during teardown.
	for obj in to_destroy {
		p.factory.destroy(obj)
	}
}

// stats returns a consistent snapshot of pool statistics.
//
// The mutex is acquired (via an unsafe mutable cast of the immutable
// receiver) so that the total/active/idle fields are read atomically
// rather than torn across concurrent mutations.
pub fn (p &Pool) stats() PoolStats {
	mut pm := unsafe { &Pool(p) }
	pm.mu.@lock()
	defer { pm.mu.unlock() }
	mut in_use_count := 0
	for entry in p.objects {
		if entry.in_use {
			in_use_count++
		}
	}
	return PoolStats{
		name:   p.name
		total:  p.objects.len
		active: in_use_count
		idle:   p.objects.len - in_use_count
		max:    p.max_size
	}
}

// PoolStats holds pool statistics
pub struct PoolStats {
pub:
	name   string
	total  int
	active int
	idle   int
	max    int
}

// ── RAII Guard Methods (降低心智成本 / Reduce Cognitive Load) ──
//
// These methods provide automatic resource management so users
// don't need to remember to call release() on every code path.
// This prevents memory leaks from forgotten releases.

// acquire_guard acquires a pooled object wrapped in a type-safe RAII guard.
// The guard automatically releases the object when release() is called
// (typically via defer).
//
// Usage:
//   mut guard := pool.acquire_guard[DbConn]()!
//   defer { guard.release() }
//   conn := guard.get()
//   conn.query('SELECT ...')
//   // Even if query panics, defer ensures release
pub fn (mut p Pool) acquire_guard[T]() !PooledGuard[T] {
	obj := p.acquire() or { return error('acquire_guard: ${err}') }
	return new_pooled_guard[T](p, obj)
}

// with_acquired executes a callback with a pooled object, guaranteeing
// that the object is acquired before the callback and released after —
// even if the callback returns an error.
//
// This is the zero-cognitive-load API: users never need to think about
// acquire/release at all. The framework handles it completely.
//
// Spring equivalent: JdbcTemplate.execute(ConnectionCallback)
//   (Spring manages connection lifecycle; users just use the connection)
//
// Usage:
//   pool.with_acquired[DbConn](fn (conn &DbConn) ! {
//       conn.query('SELECT ...')
//   })!
pub fn (mut p Pool) with_acquired[T](callback fn (&T) !) ! {
	obj := p.acquire() or { return error('with_acquired: ${err}') }
	typed_obj := unsafe { &T(obj) }

	// Execute callback; release object regardless of success/failure
	callback(typed_obj) or {
		p.release(obj)
		return err
	}
	p.release(obj)
}

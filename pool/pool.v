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
	active_count int // in-use + reserved slots
	wait_count   int
	closed       bool
	factory      &Factory = unsafe { nil }
	stop_gc      chan bool
	wg           sync.WaitGroup
	gc_started   bool
}

// PoolEntry wraps a pooled object with metadata
struct PoolEntry {
pub mut:
	object       voidptr
	in_use       bool
	created_at   i64
	last_used_at i64
}

// new_pool creates a new Pool with a function factory.
// The function is wrapped in a FuncFactory whose is_valid() always
// returns true and whose destroy() is a no-op.
pub fn new_pool(name string, factory fn () !voidptr) &Pool {
	return &Pool{
		name:    name
		factory: &FuncFactory{
			create_fn: factory
		}
	}
}

// new_pool_with_config creates a Pool with custom sizes and a function factory.
pub fn new_pool_with_config(name string, factory fn () !voidptr, min_size int, max_size int) &Pool {
	return &Pool{
		name:     name
		factory:  &FuncFactory{
			create_fn: factory
		}
		min_size: min_size
		max_size: max_size
	}
}

// new_pool_with_factory creates a Pool with a Factory trait implementation.
// Use this constructor when you need is_valid() validation and destroy()
// cleanup (e.g. for real database connections).
pub fn new_pool_with_factory(name string, factory &Factory, min_size int, max_size int) &Pool {
	return &Pool{
		name:     name
		factory:  factory
		min_size: min_size
		max_size: max_size
	}
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
		p.objects << PoolEntry{
			object:       obj
			created_at:   time.now().unix()
			last_used_at: time.now().unix()
		}
	}
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
	p.objects = kept
	p.mu.unlock()

	// Destroy evicted objects outside the lock to avoid blocking
	// other pool operations during teardown.
	for obj in to_destroy {
		p.factory.destroy(obj)
	}
}

// acquire gets an object from the pool.
//
// It first looks for a valid idle object (validating via factory.is_valid).
// Invalid idle objects are destroyed and removed. If no valid idle object
// is available and the pool is under max_size, a new object is created.
// Returns an error if the pool is closed or exhausted.
pub fn (mut p Pool) acquire() !voidptr {
	p.mu.@lock()

	if p.closed {
		p.mu.unlock()
		return error('pool "${p.name}" is closed')
	}

	// Find a valid idle object; destroy invalid ones as we go.
	mut found_obj := unsafe { nil }
	mut i := 0
	for i < p.objects.len {
		entry := p.objects[i]
		if entry.in_use {
			i++
			continue
		}
		if p.factory.is_valid(entry.object) {
			p.objects[i].in_use = true
			p.objects[i].last_used_at = time.now().unix()
			p.active_count++
			found_obj = entry.object
			break
		}
		// Invalid: destroy and remove it, then re-check the same index
		// because the next element shifted into place.
		p.factory.destroy(entry.object)
		p.objects.delete(i)
	}

	if found_obj != unsafe { nil } {
		p.mu.unlock()
		return found_obj
	}

	// No valid idle object; create a new one if under the cap.
	if p.active_count < p.max_size {
		// Reserve a slot under the lock, then release it so the factory
		// call (which may do network I/O) runs without holding the lock.
		p.active_count++
		p.mu.unlock()
		obj := p.factory.create() or {
			// Factory failed: release the reserved slot under the lock.
			p.mu.@lock()
			p.active_count--
			p.mu.unlock()
			return err
		}
		p.mu.@lock()
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

// release returns an object to the pool.
//
// If the pool is closed, the object is destroyed directly via the factory
// (it cannot be returned to a closed pool). Otherwise the object is marked
// idle, active_count is decremented, and last_used_at is updated so the
// GC can evict it after idle_timeout_seconds.
pub fn (mut p Pool) release(obj voidptr) {
	p.mu.@lock()
	defer { p.mu.unlock() }
	if p.closed {
		// Pool is closed: destroy the object directly to avoid a leak.
		p.factory.destroy(obj)
		return
	}
	for i, entry in p.objects {
		if entry.object == obj && entry.in_use {
			p.objects[i].in_use = false
			p.objects[i].last_used_at = time.now().unix()
			p.active_count--
			return
		}
	}
	// Object not found in the pool: silently ignore (backward compat).
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

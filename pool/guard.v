module pool

// guard.v - RAII Guard Pattern for Pool Object Auto-Release
//
// Provides PooledGuard[T] — a type-safe guard that automatically releases
// pooled objects back to the pool when it goes out of scope.
//
// Design Philosophy (降低心智成本 / Reduce Cognitive Load):
//   - Users should NOT need to remember to call release() on every code path
//   - Even if the user forgets, the guard ensures the object is returned
//   - Prevents memory leaks and resource exhaustion from forgotten releases
//
// Spring equivalent: JdbcTemplate + DataSourceUtils.releaseConnection()
//   (Spring manages connection release internally — users never call close())
//
// Rust equivalent: RAII guard pattern (MutexGuard, RefCellRef)
//   (Compiler guarantees cleanup via Drop trait)
//
// Usage:
//   // Pattern 1: Guard with defer (recommended)
//   mut guard := pool.acquire_guard[DbConn]()!
//   defer { guard.release() }
//   conn := guard.get()
//   conn.query('SELECT ...')
//   // Even if query panics, defer ensures release
//
//   // Pattern 2: Callback mode (zero cognitive load)
//   pool.with_acquired[DbConn](fn (conn &DbConn) ! {
//       conn.query('SELECT ...')
//   })!
//   // Framework guarantees acquire/release — user never thinks about it

import sync

// PooledGuard is a type-safe RAII guard for pooled objects.
// When released (either manually or via defer), the object is
// returned to the pool automatically.
//
// Thread-safety: the released flag is protected by a mutex to
// prevent double-release in concurrent scenarios.
@[heap]
pub struct PooledGuard[T] {
pub mut:
	pool     &Pool = unsafe { nil }
	obj      voidptr = unsafe { nil }
	released bool
mut:
	mu sync.Mutex
}

// new_pooled_guard creates a PooledGuard wrapping a pool object.
pub fn new_pooled_guard[T](p &Pool, obj voidptr) PooledGuard[T] {
	return PooledGuard[T]{
		pool:     p
		obj:      obj
		released: false
	}
}

// get returns a typed reference to the pooled object.
// Returns unsafe { nil } if the guard has been released.
//
// Usage:
//   conn := guard.get()
//   conn.query('SELECT ...')
pub fn (g &PooledGuard[T]) get() &T {
	if g.released || isnil(g.obj) {
		return unsafe { nil }
	}
	return unsafe { &T(g.obj) }
}

// is_released returns whether the guard has already released its object.
pub fn (g &PooledGuard[T]) is_released() bool {
	return g.released
}

// release returns the object to the pool. Safe to call multiple times
// (subsequent calls are no-ops). This is the core of the RAII guarantee.
//
// Spring equivalent: DataSourceUtils.releaseConnection()
pub fn (mut g PooledGuard[T]) release() {
	g.mu.@lock()
	if g.released || isnil(g.pool) || isnil(g.obj) {
		g.mu.unlock()
		return
	}
	g.released = true
	obj := g.obj
	p := g.pool
	g.obj = unsafe { nil }
	g.mu.unlock()

	// Release outside the lock to avoid blocking other guard operations
	unsafe {
		mut pp := p
		pp.release(obj)
	}
}

// drop is called when the guard goes out of scope.
// In V, this is typically called via defer { guard.release() }.
// This method exists as a named cleanup entry point.
pub fn (mut g PooledGuard[T]) drop() {
	g.release()
}

// ── PoolAutoManager — Container-Level Pool Lifecycle Management ──
//
// Tracks all pools created within the application and ensures they
// are all properly closed when the application shuts down.
// This prevents pool leaks — users don't need to remember to close
// each pool individually.
//
// Spring equivalent: DisposableBean + @PreDestroy on DataSource beans
// Laravel equivalent: ServiceProvider::boot() cleanup

// PoolAutoManager manages the lifecycle of all pools in the application.
// Register pools here, and they will be automatically closed on shutdown.
@[heap]
pub struct PoolAutoManager {
pub mut:
	pools map[string]&Pool
mut:
	mu sync.RwMutex
}

// new_pool_auto_manager creates an empty PoolAutoManager.
pub fn new_pool_auto_manager() &PoolAutoManager {
	return &PoolAutoManager{
		pools: map[string]&Pool{}
	}
}

// register adds a pool to the auto-manager. The pool will be closed
// when close_all() is called (typically during application shutdown).
pub fn (mut m PoolAutoManager) register(name string, p &Pool) {
	m.mu.@lock()
	defer { m.mu.unlock() }
	m.pools[name] = p
}

// unregister removes a pool from the auto-manager.
pub fn (mut m PoolAutoManager) unregister(name string) {
	m.mu.@lock()
	defer { m.mu.unlock() }
	m.pools.delete(name)
}

// get retrieves a pool by name.
pub fn (mut m PoolAutoManager) get(name string) ?&Pool {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return m.pools[name] or { none }
}

// close_all closes all registered pools. This should be called during
// application shutdown to prevent resource leaks.
//
// Spring equivalent: ApplicationContext.close() → DisposableBean.destroy()
pub fn (mut m PoolAutoManager) close_all() {
	m.mu.@lock()
	pools_copy := m.pools.clone()
	m.pools.clear()
	m.mu.unlock()

	for name, p in pools_copy {
		unsafe {
			mut pp := p
			pp.close() or {
				eprintln('PoolAutoManager: failed to close pool "${name}": ${err}')
			}
		}
	}
}

// pool_count returns the number of registered pools.
pub fn (mut m PoolAutoManager) pool_count() int {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return m.pools.len
}

// pool_names returns the names of all registered pools.
pub fn (mut m PoolAutoManager) pool_names() []string {
	m.mu.rlock()
	defer { m.mu.runlock() }
	mut names := []string{}
	for name in m.pools.keys() {
		names << name
	}
	return names
}

// pool_stats returns statistics for all registered pools.
pub fn (mut m PoolAutoManager) pool_stats() map[string]PoolStats {
	m.mu.rlock()
	defer { m.mu.runlock() }
	mut stats_map := map[string]PoolStats{}
	for name, pool in m.pools {
		stats_map[name] = pool.stats()
	}
	return stats_map
}
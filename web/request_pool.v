module web

// request_pool.v - Request-Level Object Pooling / 请求级对象池化复用
//
// Provides a centralized pool manager for request-scoped objects (Session,
// Input, MiddlewareContext, etc.), reducing GC pressure under high concurrency
// by reusing objects across requests instead of allocating new ones each time.
//
// 提供请求级对象的集中池化管理（Session、Input、MiddlewareContext 等），
// 通过跨请求复用对象而非每次新建，降低高并发下的 GC 压力。
//
// Design Philosophy (设计哲学):
//   - Reuse pool module: leverage photon.pool.Pool + PooledGuard[T]
//   - Resettable interface: pooled objects must implement reset() to clear
//     request-specific data before returning to the pool
//   - RAII safety: PooledGuard[T] ensures objects are always returned
//   - Graceful degradation: when pool is exhausted, create temporary objects
//     (not pooled) instead of blocking requests
//
// Spring equivalent: @Scope("request") + ObjectPool
//   (Spring manages request-scoped bean lifecycle)
import photon.pool
import sync

// ── Resettable Interface / 可重置接口 ──

// Resettable defines the reset behavior for pooled objects.
// Pooled objects MUST call reset() before returning to the pool
// to clear request-specific data and prevent cross-request leakage.
//
// Resettable 定义池化对象的重置行为。
// 池化对象在归还前必须调用 reset() 清除请求特定数据，防止跨请求泄漏。
pub interface Resettable {
	reset()
}

// ── RequestPoolConfig / 请求池配置 ──

// RequestPoolConfig configures the request object pool parameters.
// All pools created through RequestPool share these defaults unless
// overridden in register_pool[T]().
//
// RequestPoolConfig 配置请求对象池参数。
// 通过 RequestPool 创建的所有池共享这些默认值，除非在 register_pool[T]() 中覆盖。
pub struct RequestPoolConfig {
pub:
	min_size int = 4   // Minimum pre-created objects / 最小预创建对象数
	max_size int = 100 // Maximum pooled objects / 最大池化对象数
}

// ── RequestPoolStats / 请求池统计 ──

// RequestPoolStats holds aggregated statistics across all managed pools.
// Useful for monitoring pool health and tuning configuration.
//
// RequestPoolStats 保存所有管理池的聚合统计信息。
// 用于监控池健康状态和调优配置。
pub struct RequestPoolStats {
pub:
	pools map[string]pool.PoolStats
}

// ── PoolEntry / 池条目 ──

// PoolEntry wraps a pool.Pool with its associated reset function.
// The reset_fn is called on objects before they are returned to the pool,
// ensuring request-specific data is cleared.
//
// PoolEntry 将 pool.Pool 与其关联的 reset 函数包装在一起。
// reset_fn 在对象归还到池之前调用，确保请求特定数据被清除。
struct PoolEntry {
pub:
	pool     &pool.Pool
	reset_fn fn (voidptr) = unsafe { nil } // Reset function for pooled objects / 池化对象的重置函数
}

// ── RequestPool / 请求对象池 ──

// RequestPool manages the pooling and reuse of request-level objects.
// It wraps photon.pool.Pool instances in a type-safe, thread-safe container
// with automatic reset() on release.
//
// RequestPool 管理请求级对象的池化复用。
// 将 photon.pool.Pool 实例包装在类型安全、线程安全的容器中，
// 并在归还时自动调用 reset()。
//
// Usage / 用法:
//   rp := new_request_pool(RequestPoolConfig{min_size: 4, max_size: 100})
//   rp.register_pool[Session]('session', fn () !voidptr {
//       return unsafe { voidptr(new_session('')) }
//   }, fn (obj voidptr) {
//       mut sess := unsafe { &Session(obj) }
//       sess.data = map[string]string{}
//       sess.flash_data = map[string]string{}
//       sess.old_flash = map[string]string{}
//       sess.is_dirty = false
//       sess.is_new = true
//   })!
//
//   // RAII guard pattern / RAII Guard 模式
//   mut guard := rp.acquire[Session]('session')!
//   defer { guard.release() }
//   sess := guard.get()
//   sess.set('user_id', '42')
//
//   // Callback pattern (zero cognitive load) / 回调模式（零心智成本）
//   rp.with_acquired[Session]('session', fn (sess &Session) ! {
//       sess.set('user_id', '42')
//   })!
@[heap]
pub struct RequestPool {
pub mut:
	pools map[string]&pool.Pool
mut:
	mu      sync.RwMutex
	config  RequestPoolConfig
	entries map[string]PoolEntry // name → PoolEntry with reset_fn
}

// ── Constructor / 构造函数 ──

// new_request_pool creates a new RequestPool with the given configuration.
// The pool is initially empty; call register_pool[T]() to add typed sub-pools.
//
// new_request_pool 使用给定配置创建新的 RequestPool。
// 池初始为空；调用 register_pool[T]() 添加类型化子池。
pub fn new_request_pool(config RequestPoolConfig) &RequestPool {
	return &RequestPool{
		pools:   map[string]&pool.Pool{}
		config:  config
		entries: map[string]PoolEntry{}
	}
}

// ── Pool Registration / 池注册 ──

// register_pool registers a typed object pool with the given name, factory,
// and reset function. The factory creates new instances; the reset_fn clears
// request-specific data before objects are returned to the pool.
// If a pool with the same name already exists, it returns an error.
//
// register_pool 注册一个类型化对象池，使用给定的名称、工厂函数和重置函数。
// 工厂函数创建新实例；reset_fn 在对象归还到池之前清除请求特定数据。
// 如果同名池已存在，返回错误。
//
// Example / 示例:
//   rp.register_pool[Session]('session', fn () !voidptr {
//       return unsafe { voidptr(new_session('')) }
//   }, fn (obj voidptr) {
//       mut sess := unsafe { &Session(obj) }
//       sess.data = map[string]string{}
//       sess.is_dirty = false
//       sess.is_new = true
//   })!
pub fn (mut rp RequestPool) register_pool[T](name string, factory fn () !voidptr, reset_fn fn (voidptr)) ! {
	rp.mu.@lock()
	defer { rp.mu.unlock() }

	if name in rp.pools {
		return error('request pool "${name}" already registered / 请求池 "${name}" 已注册')
	}

	p := pool.new_pool_with_config(name, factory, rp.config.min_size, rp.config.max_size)
	rp.pools[name] = p
	rp.entries[name] = PoolEntry{
		pool:     p
		reset_fn: reset_fn
	}
}

// ── Acquire / 获取对象 ──

// acquire gets a pooled object wrapped in a type-safe RAII guard.
// The guard automatically releases the object (with reset) when release()
// is called, typically via defer.
//
// When the pool is exhausted (all objects in use and max_size reached),
// a temporary object is created outside the pool. This temporary object
// will NOT be returned to the pool on release — it will be destroyed instead.
// This ensures requests are never blocked waiting for a pool slot.
//
// 锁策略：rlock 仅保护 entries map 的读取，获取 entry 后立即释放锁。
// 后续的 pool.acquire_guard[T]() 由 pool.Pool 自身的锁保护。
// 这种分层锁策略避免了 RequestPool.mu 与 Pool 内部锁的嵌套。
//
// acquire 获取一个池化对象，包装在类型安全的 RAII Guard 中。
// Guard 在调用 release() 时自动释放对象（带 reset），
// 通常通过 defer 调用。
//
// 当池耗尽时（所有对象都在使用中且已达 max_size），
// 会在池外创建临时对象。该临时对象在释放时不会归还到池中，
// 而是直接销毁。这确保请求永远不会因等待池槽位而阻塞。
//
// Lock strategy: rlock only protects entries map reads; the lock is released
// immediately after getting the entry. Subsequent pool.acquire_guard[T]() is
// protected by pool.Pool's own lock. This layered lock strategy avoids nesting
// RequestPool.mu with Pool's internal lock.
//
// Example / 示例:
//   mut guard := rp.acquire[Session]('session')!
//   defer { guard.release() }
//   sess := guard.get()
pub fn (mut rp RequestPool) acquire[T](name string) !pool.PooledGuard[T] {
	rp.mu.rlock()
	entry := rp.entries[name] or {
		rp.mu.runlock()
		return error('request pool "${name}" not found or already closed / 请求池 "${name}" 未找到或已关闭')
	}
	rp.mu.runlock()

	mut pg := unsafe { entry.pool }
	mut guard := pg.acquire_guard[T]() or {
		// Only "exhausted" can reach here: an inner pool that was closed by
		// close_all() is gone from entries, so the `or` block above already
		// returned `not found or already closed`. Degrading is therefore
		// correct here — it is the documented capacity behaviour.
		//
		// 只有「耗尽」能走到这里：被 close_all() 关闭的池已经从 entries 摘除，
		// 上面的 or 块早就返回了「未找到或已关闭」。所以这里的降级是正确的，
		// 它正是文档承诺的容量行为。
		// new_temporary_guard (not new_pooled_guard(nil, ...)) so that
		// guard.release() actually destroys the fallback object and flips
		// is_released() — the plain constructor treated a nil pool as a no-op
		// and left the guard permanently unreleased.
		eprintln('[RequestPool] pool "${name}" exhausted, creating temporary object / 池 "${name}" 耗尽，创建临时对象')
		obj := factory_create_temp[T]() or {
			return error('request pool "${name}" exhausted and temp creation failed: ${err} / 请求池 "${name}" 耗尽且临时创建失败: ${err}')
		}
		mut temp := pool.new_temporary_guard[T](obj)
		temp.reset_on_release = entry.reset_fn
		return temp
	}

	// Reset is attached to the guard so `defer { guard.release() }` — the
	// documented usage — clears request-scoped data on the way back to the
	// pool. Before this, reset only ran through rp.release(name, obj), so the
	// recommended path leaked data across requests: the user_id written by
	// request N was still there when request N+1 acquired the same object.
	guard.reset_on_release = entry.reset_fn
	return guard
}

// acquire_raw gets a raw voidptr from the named pool.
// The caller is responsible for calling release() to return the object.
// Prefer acquire[T]() for RAII safety.
//
// acquire_raw 从命名池获取原始 voidptr。
// 调用者负责调用 release() 归还对象。
// 推荐使用 acquire[T]() 以获得 RAII 安全性。
pub fn (mut rp RequestPool) acquire_raw(name string) !voidptr {
	rp.mu.rlock()
	entry := rp.entries[name] or {
		rp.mu.runlock()
		return error('request pool "${name}" not found or already closed / 请求池 "${name}" 未找到或已关闭')
	}
	rp.mu.runlock()

	mut pg := unsafe { entry.pool }
	obj := pg.acquire() or {
		// Exhausted is a capacity signal, not an error: report nil and let the
		// caller decide. There is no guard here to own a fallback object, so
		// this entry point cannot create one behind the caller's back.
		//
		// No is_closed() check is needed below: close_all() unregisters the
		// pool, so a closed pool can never be reached through entries. The
		// `not found or already closed` error above covers that case.
		//
		// 耗尽只是容量信号，不是错误：返回 nil 由调用方决定。
		// 这里没有 guard 接管回退对象，不能背着调用方建一个。
		//
		// 下面不需要 is_closed() 判断：close_all() 会注销池，已关闭的池
		// 不可能从 entries 里查到，上面那条「未找到或已关闭」已覆盖该情形。
		eprintln('[RequestPool] pool "${name}" exhausted, creating temporary object / 池 "${name}" 耗尽，创建临时对象')
		return unsafe { nil }
	}
	return obj
}

// ── Release / 归还对象 ──

// release returns an object to the named pool.
// Before returning, it calls the registered reset_fn on the object
// to clear request-specific data and prevent cross-request leakage.
// If the pool is not found or the object is nil, it's a no-op.
//
// release 将对象归还到命名池。
// 归还前，调用已注册的 reset_fn 清除请求特定数据，防止跨请求泄漏。
// 如果池未找到或对象为 nil，则不做任何操作。
pub fn (mut rp RequestPool) release(name string, obj voidptr) {
	if isnil(obj) {
		return
	}

	rp.mu.rlock()
	entry := rp.entries[name] or {
		PoolEntry{
			pool: unsafe { nil }
		}
	}
	rp.mu.runlock()

	// Call the registered reset_fn to clear request-specific data
	// 调用已注册的 reset_fn 清除请求特定数据
	if !isnil(entry.pool) && entry.reset_fn != unsafe { nil } {
		entry.reset_fn(obj)
	}

	if isnil(entry.pool) {
		// Pool not found — object was likely a temporary creation,
		// silently ignore since there's nowhere to return it.
		// 池未找到 — 对象可能是临时创建的，
		// 静默忽略，因为没有归还的地方。
		return
	}

	mut pg := unsafe { entry.pool }
	pg.release(obj)
}

// ── Callback Pattern / 回调模式 ──

// with_acquired executes a callback with a pooled object, guaranteeing
// that the object is acquired before the callback and released (with reset)
// after — even if the callback returns an error.
//
// This is the zero-cognitive-load API: users never need to think about
// acquire/release at all. The framework handles it completely.
//
// with_acquired 使用池化对象执行回调，保证回调前获取对象、
// 回调后释放对象（带 reset）——即使回调返回错误。
//
// 这是零心智成本 API：用户完全不需要考虑 acquire/release，
// 框架自动处理。
//
// Example / 示例:
//   rp.with_acquired[Session]('session', fn (sess &Session) ! {
//       sess.set('user_id', '42')
//   })!
pub fn (mut rp RequestPool) with_acquired[T](name string, callback fn (&T) !) ! {
	rp.mu.rlock()
	entry := rp.entries[name] or {
		rp.mu.runlock()
		return error('request pool "${name}" not found or already closed / 请求池 "${name}" 未找到或已关闭')
	}
	rp.mu.runlock()

	mut pg := unsafe { entry.pool }
	obj := pg.acquire() or {
		// Pool exhausted: create temporary object
		// 池耗尽：创建临时对象
		//
		// The fallback object leaves the pool's hands immediately, so this is
		// the only place that can destroy it — and the only place that can
		// reset it. Skipping either leaks the object and leaves the previous
		// request's data in it.
		eprintln('[RequestPool] pool "${name}" exhausted, creating temporary object / 池 "${name}" 耗尽，创建临时对象')
		temp_obj := factory_create_temp[T]() or {
			return error('request pool "${name}" exhausted and temp creation failed: ${err} / 请求池 "${name}" 耗尽且临时创建失败: ${err}')
		}
		typed_obj := unsafe { &T(temp_obj) }
		callback(typed_obj) or {
			// Reset even on error, then propagate
			// 即使出错也执行 reset，然后传播错误
			if entry.reset_fn != unsafe { nil } {
				entry.reset_fn(temp_obj)
			}
			unsafe { free(temp_obj) }
			return err
		}
		if entry.reset_fn != unsafe { nil } {
			entry.reset_fn(temp_obj)
		}
		unsafe { free(temp_obj) }
		return
	}

	typed_obj := unsafe { &T(obj) }

	// Execute callback; reset and release object regardless of success/failure
	// 执行回调；无论成功或失败都 reset 并释放对象
	callback(typed_obj) or {
		if entry.reset_fn != unsafe { nil } {
			entry.reset_fn(obj)
		}
		pg.release(obj)
		return err
	}
	if entry.reset_fn != unsafe { nil } {
		entry.reset_fn(obj)
	}
	pg.release(obj)
}

// ── Statistics / 统计信息 ──

// pool_stats returns a snapshot of statistics for all managed pools.
// The returned map is keyed by pool name.
//
// pool_stats 返回所有管理池的统计快照。
// 返回的 map 以池名称为键。
pub fn (mut rp RequestPool) pool_stats() map[string]pool.PoolStats {
	rp.mu.rlock()
	defer { rp.mu.runlock() }

	mut result := map[string]pool.PoolStats{}
	for name, entry in rp.entries {
		mut pg := unsafe { entry.pool }
		result[name] = pg.stats()
	}
	return result
}

// ── Lifecycle / 生命周期 ──

// close_all closes all managed pools, destroying idle objects, and then
// unregisters them. In-use objects are retained until their holders release
// them (release on a closed pool destroys the object directly).
// Safe to call multiple times.
// Uses @lock (not rlock) since closing pools modifies state.
//
// Why the pools are unregistered and not merely closed:
// closing the inner Pool left it in `rp.entries` / `rp.pools`, so every later
// acquire() found the entry, asked a closed pool, got `pool is closed`,
// swallowed it in the `or` block and fell back to a *temporary* object. The
// caller saw a working object and no error — the pool had been shut down and
// nobody downstream could tell. After close_all() the pool is gone from the
// registry, so acquire() reports `not found` / `already closed` instead of
// silently degrading forever.
//
// close_all 关闭所有管理池、销毁空闲对象，然后注销它们。
// 使用中的对象保留到持有者释放它们（在已关闭的池上 release 会直接销毁对象）。
// 可安全多次调用。
// 使用 @lock（非 rlock），因为关闭池会修改状态。
//
// 为什么要注销而不只是关闭：只关内部 Pool 的话，它仍然留在 entries / pools 里，
// 之后的 acquire() 能找到 entry、问一个已关闭的池、拿到 `pool is closed`，
// 然后在 `or` 块里把错误吞掉、降级成临时对象。调用方看到的是一个能用的对象和
// 一个错误都没有——池早就关了，下游没有任何人能察觉。注销之后 acquire() 会明确
// 报「未找到 / 已关闭」，而不是永远静默降级。
pub fn (mut rp RequestPool) close_all() {
	rp.mu.@lock()
	entries_copy := rp.entries.clone()
	// Unregister under the same lock that guards the maps, before releasing it:
	// a window between "closed" and "removed" is exactly where a concurrent
	// acquire would silently land on a dead pool.
	rp.entries.clear()
	rp.pools.clear()
	rp.mu.unlock()

	for name, entry in entries_copy {
		mut pg := unsafe { entry.pool }
		pg.close() or {
			eprintln('[RequestPool] failed to close pool "${name}": ${err} / 关闭池 "${name}" 失败: ${err}')
		}
	}
}

// ── Internal Helpers / 内部辅助函数 ──

// factory_create_temp creates a temporary object of type T when the pool
// is exhausted. This is a fallback mechanism — the created object will
// NOT be returned to the pool.
//
// factory_create_temp 在池耗尽时创建类型 T 的临时对象。
// 这是回退机制 — 创建的对象不会归还到池中。
fn factory_create_temp[T]() !voidptr {
	// Use comptime type checks for known web module types.
	// 使用编译期类型检查处理已知的 web 模块类型。
	$if T is Session {
		sess := new_session('')
		return unsafe { voidptr(sess) }
	} $else $if T is MiddlewareContext {
		mctx := &MiddlewareContext{
			data: map[string]string{}
		}
		return unsafe { voidptr(mctx) }
	} $else $if T is Input {
		inp := &Input{
			ctx: unsafe { nil }
		}
		return unsafe { voidptr(inp) }
	}
	// Generic fallback: zero-initialize / 通用回退：零初始化
	return unsafe { voidptr(malloc(int(sizeof(T)))) }
}

// ── Pre-built Reset Functions / 预置 Reset 函数 ──

// reset_session resets a Session object for pool reuse.
// Clears all data maps, resets dirty/new flags.
// The veb.Context reference is not stored in Session, so no ctx_ref cleanup needed.
//
// reset_session 重置 Session 对象以供池复用。
// 清除所有数据 map，重置 dirty/new 标志。
// Session 不存储 veb.Context 引用，因此无需清除 ctx_ref。
pub fn reset_session(obj voidptr) {
	mut sess := unsafe { &Session(obj) }
	sess.data = map[string]string{}
	sess.flash_data = map[string]string{}
	sess.old_flash = map[string]string{}
	sess.is_dirty = false
	sess.is_new = true
}

// reset_middleware_context resets a MiddlewareContext object for pool reuse.
// Clears request-scoped data (preserving _global_ prefixed entries)
// and nullifies the veb.Context reference to prevent cross-request leakage.
//
// reset_middleware_context 重置 MiddlewareContext 对象以供池复用。
// 清除请求级数据（保留 _global_ 前缀的条目），
// 并将 veb.Context 引用置空以防止跨请求泄漏。
pub fn reset_middleware_context(obj voidptr) {
	mut mctx := unsafe { &MiddlewareContext(obj) }
	// Preserve global data (prefixed with _global_)
	// 保留全局数据（_global_ 前缀）
	mut preserved := map[string]string{}
	for key, val in mctx.data {
		if key.starts_with('_global_') {
			preserved[key] = val
		}
	}
	// preserved is already a new map, no need to clone
	// preserved 已经是新 map，无需 clone
	mctx.data = preserved.move()
	// Clear veb.Context reference — critical for preventing cross-request leakage
	// 清除 veb.Context 引用 — 对防止跨请求泄漏至关重要
	mctx.ctx = unsafe { nil }
}

// reset_input resets an Input object for pool reuse.
// Nullifies the veb.Context reference to prevent cross-request leakage.
//
// reset_input 重置 Input 对象以供池复用。
// 将 veb.Context 引用置空以防止跨请求泄漏。
pub fn reset_input(obj voidptr) {
	mut inp := unsafe { &Input(obj) }
	// Clear veb.Context reference — critical for preventing cross-request leakage
	// 清除 veb.Context 引用 — 对防止跨请求泄漏至关重要
	inp.ctx = unsafe { nil }
}

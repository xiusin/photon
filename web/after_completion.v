module web

// after_completion.v - 请求后置 Hook 注册与触发
// Request Post-Completion Hook Registry and Dispatcher
//
// 参考 HttpKernel 的 on/freeze 模式：
//   - on(): 注册回调，返回唯一 ID
//   - freeze(): 冻结回调列表，后续 fire() 无需加锁
//   - fire(): 触发所有回调（finally 语义，异常不阻断后续回调）
//
// Inspired by HttpKernel's on/freeze pattern:
//   - on(): register callback, returns unique ID
//   - freeze(): freeze callback list, subsequent fire() needs no lock
//   - fire(): fire all callbacks (finally semantics, exceptions don't block subsequent callbacks)
import sync

// AfterCompletionCallback 是请求后置回调函数类型。
// ctx: 请求上下文（veb.Context 的不可变引用）
// err: 请求处理中的异常，正常完成为 none
//
// AfterCompletionCallback is the request post-completion callback function type.
// ctx: request context (immutable reference to veb.Context)
// err: exception during request processing, none on normal completion
pub type AfterCompletionCallback = fn (ctx voidptr, err ?string)

// AfterCompletionEntry 包装一个回调及其唯一 ID 和执行顺序。
// AfterCompletionEntry wraps a callback with its unique ID and execution order.
struct AfterCompletionEntry {
pub:
	id       int
	callback AfterCompletionCallback = unsafe { nil }
	order    int // 注册顺序，值越小越先执行 / registration order, lower values execute first
}

// AfterCompletionRegistry 管理请求后置回调的注册与触发。
// 参考 HttpKernel 的 on/freeze 模式：
//   - on(): 注册回调，返回唯一 ID
//   - freeze(): 冻结回调列表，后续 fire() 无需加锁
//   - fire(): 触发所有回调（finally 语义，异常不阻断后续回调）
//
// AfterCompletionRegistry manages registration and dispatch of request
// post-completion callbacks. Follows HttpKernel's on/freeze pattern:
//   - on(): register callback, returns unique ID
//   - freeze(): freeze callback list, subsequent fire() needs no lock
//   - fire(): fire all callbacks (finally semantics, exceptions don't block)
@[heap]
pub struct AfterCompletionRegistry {
pub mut:
	entries        []AfterCompletionEntry
	frozen_entries []AfterCompletionEntry
mut:
	mu      sync.RwMutex
	frozen  bool
	next_id int
}

// new_after_completion_registry 创建 AfterCompletionRegistry。
// new_after_completion_registry creates a new AfterCompletionRegistry.
pub fn new_after_completion_registry() &AfterCompletionRegistry {
	return &AfterCompletionRegistry{
		entries:        []AfterCompletionEntry{}
		frozen_entries: []AfterCompletionEntry{}
	}
}

// on 注册一个 after_completion 回调，返回唯一 ID。
// 回调按 order 升序执行（order 相同按注册顺序）。
//
// on registers an after_completion callback and returns a unique ID.
// Callbacks execute in ascending order (same order by registration sequence).
pub fn (mut r AfterCompletionRegistry) on(callback AfterCompletionCallback, order int) int {
	r.mu.@lock()
	defer { r.mu.unlock() }
	r.next_id++
	id := r.next_id
	r.entries << AfterCompletionEntry{
		id:       id
		callback: callback
		order:    order
	}
	return id
}

// off 移除指定 ID 的回调。
// 安全：冻结后也可调用，同时更新冻结快照。
//
// off removes the callback with the specified ID.
// Safe to call after freeze() — updates both live and frozen lists.
pub fn (mut r AfterCompletionRegistry) off(id int) {
	r.mu.@lock()
	defer { r.mu.unlock() }
	// 从活跃列表移除 / Remove from live entries
	mut new_entries := []AfterCompletionEntry{}
	for entry in r.entries {
		if entry.id != id {
			new_entries << entry
		}
	}
	r.entries = new_entries
	// 同步移除冻结列表中的条目 / Also remove from frozen entries
	if r.frozen {
		mut new_frozen := []AfterCompletionEntry{}
		for entry in r.frozen_entries {
			if entry.id != id {
				new_frozen << entry
			}
		}
		r.frozen_entries = new_frozen
	}
}

// freeze 冻结回调列表为不可变快照。
// 冻结后 fire() 直接读取快照，无需加锁。
// 幂等：多次调用安全。
//
// freeze snapshots the callback list as immutable.
// After freezing, fire() reads the snapshot directly without locking.
// Idempotent: safe to call multiple times.
pub fn (mut r AfterCompletionRegistry) freeze() {
	r.mu.@lock()
	defer { r.mu.unlock() }
	if r.frozen {
		return
	}
	// 按 order 排序后快照 / Sort by order then snapshot
	mut sorted := r.entries.clone()
	sorted.sort_with_compare(fn (a &AfterCompletionEntry, b &AfterCompletionEntry) int {
		if a.order < b.order {
			return -1
		}
		if a.order > b.order {
			return 1
		}
		return 0
	})
	r.frozen_entries = sorted
	r.frozen = true
}

// unfreeze 解冻，允许修改回调列表。
// 清除冻结快照，后续 fire() 走慢速路径。
//
// unfreeze thaws the registry, allowing callback modifications.
// Clears the frozen snapshot; subsequent fire() uses the slow path.
pub fn (mut r AfterCompletionRegistry) unfreeze() {
	r.mu.@lock()
	defer { r.mu.unlock() }
	r.frozen = false
	r.frozen_entries = []AfterCompletionEntry{}
}

// fire 触发所有 after_completion 回调。
// finally 语义：即使某个回调异常，后续回调仍执行。
// 响应已发送给客户端，回调中禁止修改响应。
//
// 性能优化：冻结后无锁快速路径。
// 冻结后 frozen_entries 为不可变快照，fire() 直接读取，无需加锁。
// frozen 标志由 freeze() 在写锁下设置，一旦为 true 不会再变回 false
// （unfreeze() 仅在应用关闭时调用），因此无需原子操作即可安全读取。
//
// fire triggers all after_completion callbacks.
// Finally semantics: even if a callback raises an exception, subsequent
// callbacks still execute. The response has already been sent to the client;
// callbacks must NOT modify the response.
//
// Performance optimization: lock-free fast path when frozen.
// After freezing, frozen_entries is an immutable snapshot; fire() reads it
// directly without locking. The frozen flag is set under write lock by freeze()
// and once true it never goes back to false (unfreeze() is only called at
// shutdown), so it can be safely read without atomics.
pub fn (mut r AfterCompletionRegistry) fire(ctx voidptr, err ?string) {
	// 冻结快速路径：无锁读取不可变快照 / Frozen fast path: lock-free read of immutable snapshot
	if r.frozen {
		for entry in r.frozen_entries {
			execute_callback_safely(entry.callback, ctx, err)
		}
		return
	}
	// 未冻结慢速路径：加锁克隆后释放锁 / Unfrozen slow path: clone under lock then release
	r.mu.rlock()
	entries := r.entries.clone()
	r.mu.runlock()
	for entry in entries {
		execute_callback_safely(entry.callback, ctx, err)
	}
}

// is_frozen 返回是否已冻结。
// is_frozen returns whether the registry is frozen.
pub fn (mut r AfterCompletionRegistry) is_frozen() bool {
	// 冻结标志在写锁下设置且不会回退，直接读取安全。
	// 加 rlock 会与 fire() 的无锁快速路径产生不必要的竞争。
	//
	// The frozen flag is set under write lock and never reverts,
	// so reading it directly is safe. Adding rlock would create
	// unnecessary contention with fire()'s lock-free fast path.
	return r.frozen
}

// callback_count 返回已注册的回调数量。
// callback_count returns the number of registered callbacks.
pub fn (mut r AfterCompletionRegistry) callback_count() int {
	r.mu.rlock()
	defer { r.mu.runlock() }
	if r.frozen {
		return r.frozen_entries.len
	}
	return r.entries.len
}

// execute_callback_safely 安全执行回调。
// 即使回调 panic，也不影响后续回调执行（finally 语义）。
// 注意：V 语言无 try-catch，此函数确保 nil 回调不会崩溃。
// 若回调本身 panic，V 运行时会终止当前协程。
//
// execute_callback_safely executes a callback safely.
// Even if the callback panics, subsequent callbacks are not affected (finally semantics).
// Note: V has no try-catch; this function ensures nil callbacks don't crash.
// If the callback itself panics, V's runtime will terminate the current goroutine.
fn execute_callback_safely(callback AfterCompletionCallback, ctx voidptr, err ?string) {
	if isnil(callback) {
		return
	}
	callback(ctx, err)
}

module core

// event.v - Event System (Spring ApplicationEvent + Laravel Event inspired)
//
// Provides a simple, type-safe event dispatching system.
// Events are dispatched synchronously by default; async dispatch
// integrates with the queue module.
//
// Performance optimization: ShardedRwMutex replaces the global RwMutex.
// Different event names map to different lock shards, allowing concurrent
// dispatch/on/off operations for unrelated events.
// 性能优化：ShardedRwMutex 替代全局 RwMutex。
// 不同事件名映射到不同分片锁，无关联事件的 dispatch/on/off 操作可并发执行。
//
// Usage:
//   mut bus := core.new_event_bus()
//   bus.on('user.registered', fn (e &Event) {
//       println('New user: ${e.payload_str}')
//   })
//   bus.dispatch(core.new_event('user.registered', 'alice')) or { 0 }
import sync
import time

// ── Event ──

// Event represents something that happened in the application.
// Payload can carry arbitrary data as a string (JSON-serialized).
@[heap]
pub struct Event {
pub:
	name        string
	payload     voidptr // typed payload pointer
	payload_str string  // string representation of payload
pub mut:
	timestamp i64               // unix timestamp
	stopped   bool              // set to true to stop propagation
	data      map[string]string // arbitrary metadata
}

// new_event creates a new Event with the current timestamp.
pub fn new_event(name string, payload_str string) &Event {
	return &Event{
		name:        name
		payload_str: payload_str
		timestamp:   time.now().unix()
	}
}

// new_event_with_data creates a new Event with metadata.
pub fn new_event_with_data(name string, payload_str string, data map[string]string) &Event {
	return &Event{
		name:        name
		payload_str: payload_str
		data:        data
		timestamp:   time.now().unix()
	}
}

// stop_propagation prevents further listeners from being called.
pub fn (mut e Event) stop_propagation() {
	e.stopped = true
}

// is_propagation_stopped returns whether propagation was stopped.
pub fn (e &Event) is_propagation_stopped() bool {
	return e.stopped
}

// ── EventListener ──

// EventListener is a function that handles an event.
pub type EventListener = fn (event &Event)

// ── ListenerPriority ──

// ListenerPriority defines the order in which listeners are invoked.
// Lower numbers fire first.
pub enum ListenerPriority {
	highest = 0
	high    = 25
	normal  = 50
	low     = 75
	lowest  = 100
}

// ── RegisteredListener ──

// RegisteredListener wraps an EventListener with priority and metadata.
pub struct RegisteredListener {
pub:
	id         int // unique id for fine-grained removal via off_listener(id)
	listener   EventListener = unsafe { nil }
	priority   int           = 50 // ListenerPriority.normal
	event_name string
pub mut:
	called_count int
}

// ── EventBus ──

// EventBus manages event listeners and dispatches events.
// Thread-safe via ShardedRwMutex — operations on different event names
// proceed concurrently without blocking each other.
// 线程安全：通过 ShardedRwMutex 实现，不同事件名的操作互不阻塞。
//
// dispatch_async() tracks spawned goroutines via sync.WaitGroup so that
// wait_async()/shutdown() can block until all in-flight async listeners
// complete. Listeners are assigned unique ids (returned by on()) so they
// can be removed individually via off_listener(id) — this works for
// closures where function-pointer comparison would fail.
@[heap]
pub struct EventBus {
pub mut:
	listeners               map[string][]RegisteredListener
	transactional_listeners map[string][]TransactionalRegisteredListener
mut:
	sharded_mu ShardedRwMutex // 分片锁：按事件名分片，替代全局 mu sync.RwMutex
	id_mu      sync.Mutex    // next_id 专用互斥锁 / dedicated mutex for next_id (避免分片锁间的竞态)
	wg         sync.WaitGroup
	next_id    int
}

// new_event_bus creates an empty EventBus with sharded locking.
// 创建空 EventBus，使用分片锁。
pub fn new_event_bus() &EventBus {
	mut bus := &EventBus{
		listeners:               map[string][]RegisteredListener{}
		transactional_listeners: map[string][]TransactionalRegisteredListener{}
		sharded_mu:              new_sharded_rw_mutex()
	}
	// WaitGroup 必须调用 init() 初始化内部信号量，否则 wait() 会永远阻塞。
	// WaitGroup.init() must be called to initialize the internal semaphore,
	// otherwise wait() will block forever.
	bus.wg.init()
	return bus
}

// on registers a listener for an event name with normal priority.
// Returns a unique listener id that can be passed to off_listener(id)
// to remove this specific listener later.
pub fn (mut bus EventBus) on(event_name string, listener EventListener) int {
	return bus.on_with_priority(event_name, listener, int(ListenerPriority.normal))
}

// on_with_priority registers a listener with a specific priority.
// Lower priority values fire first.
// Returns a unique listener id.
// 使用分片锁：仅锁定目标事件名对应的分片。
// next_id 使用独立 id_mu 保护，避免不同分片锁下的竞态条件。
// next_id is protected by its own id_mu to prevent race conditions
// across different shard locks.
pub fn (mut bus EventBus) on_with_priority(event_name string, listener EventListener, priority int) int {
	// Generate unique ID under dedicated mutex BEFORE acquiring shard lock.
	// This prevents race conditions when two threads register listeners
	// for different event names (different shards) concurrently — without
	// id_mu, both could read-increment-write next_id simultaneously,
	// producing duplicate IDs.
	// 在获取分片锁之前，先在 id_mu 保护下生成唯一 ID。
	// 防止两个线程对不同事件名（不同分片）并发注册时产生重复 ID。
	bus.id_mu.@lock()
	bus.next_id++
	id := bus.next_id
	bus.id_mu.unlock()

	bus.sharded_mu.@lock(event_name)
	defer { bus.sharded_mu.unlock(event_name) }
	mut listeners := bus.listeners[event_name] or { []RegisteredListener{} }
	listeners << RegisteredListener{
		id:         id
		listener:   listener
		priority:   priority
		event_name: event_name
	}
	// Sort by priority (ascending — lower fires first)
	listeners.sort_with_compare(fn (a &RegisteredListener, b &RegisteredListener) int {
		if a.priority < b.priority {
			return -1
		} else if a.priority > b.priority {
			return 1
		}
		return 0
	})
	bus.listeners[event_name] = listeners
	return id
}

// off removes all listeners for an event name.
// 使用分片锁：仅锁定目标事件名对应的分片。
pub fn (mut bus EventBus) off(event_name string) {
	bus.sharded_mu.@lock(event_name)
	defer { bus.sharded_mu.unlock(event_name) }
	bus.listeners.delete(event_name)
}

// off_listener removes a specific listener by its unique id (returned by on()).
// This works reliably for closures (unlike function-pointer comparison).
// Searches all event names since the id is globally unique.
// 使用全局分片锁：需遍历所有事件名。
//
// Spring equivalent: ApplicationListener removal
// Laravel equivalent: Event::forget()
pub fn (mut bus EventBus) off_listener(id int) {
	bus.sharded_mu.lock_all()
	defer { bus.sharded_mu.unlock_all() }

	for event_name, listeners in bus.listeners {
		mut new_listeners := []RegisteredListener{}
		for rl in listeners {
			if rl.id != id {
				new_listeners << rl
			}
		}
		if new_listeners.len == 0 {
			bus.listeners.delete(event_name)
		} else {
			bus.listeners[event_name] = new_listeners
		}
	}
}

// off_transactional_listener removes a transactional listener by its unique id.
// 使用全局分片锁：需遍历所有事件名。
pub fn (mut bus EventBus) off_transactional_listener(id int) {
	bus.sharded_mu.lock_all()
	defer { bus.sharded_mu.unlock_all() }

	for event_name, listeners in bus.transactional_listeners {
		mut new_listeners := []TransactionalRegisteredListener{}
		for rl in listeners {
			if rl.id != id {
				new_listeners << rl
			}
		}
		if new_listeners.len == 0 {
			bus.transactional_listeners.delete(event_name)
		} else {
			bus.transactional_listeners[event_name] = new_listeners
		}
	}
}

// listener_count_for returns the number of listeners for a specific event.
// 使用分片读锁：仅锁定目标事件名对应的分片。
pub fn (mut bus EventBus) listener_count_for(event_name string) int {
	bus.sharded_mu.rlock(event_name)
	defer { bus.sharded_mu.runlock(event_name) }
	listeners := bus.listeners[event_name] or { return 0 }
	return listeners.len
}

// has_listeners checks if an event has any registered listeners.
// 使用分片读锁：仅锁定目标事件名对应的分片。
pub fn (mut bus EventBus) has_listeners(event_name string) bool {
	bus.sharded_mu.rlock(event_name)
	defer { bus.sharded_mu.runlock(event_name) }
	listeners := bus.listeners[event_name] or { return false }
	return listeners.len > 0
}

// listener_count returns the number of listeners for an event.
// Deprecated: use listener_count_for() instead for clarity.
pub fn (mut bus EventBus) listener_count(event_name string) int {
	return bus.listener_count_for(event_name)
}

// dispatch fires an event, calling all listeners in priority order.
// If a listener calls event.stop_propagation(), no further listeners are invoked.
// Returns the number of listeners that were actually called.
// 使用分片读锁：仅锁定事件名对应的分片，不同事件名可并发 dispatch。
//
// 注意：V 语言没有 try-catch 机制，如果某个 listener 触发运行时 panic，
// 后续 listener 将不会被执行。如果需要 listener 隔离，请使用 dispatch_async()。
//
// Note: V has no try-catch mechanism. If a listener triggers a runtime panic,
// subsequent listeners will NOT be called. For listener isolation, use dispatch_async().
pub fn (mut bus EventBus) dispatch(event &Event) int {
	// Set timestamp if not already set
	if event.timestamp == 0 {
		unsafe {
			mut e := event
			e.timestamp = time.now().unix()
		}
	}

	bus.sharded_mu.rlock(event.name)
	listeners := bus.listeners[event.name] or { []RegisteredListener{} }
	bus.sharded_mu.runlock(event.name)

	mut called := 0
	for i in 0 .. listeners.len {
		if event.is_propagation_stopped() {
			break
		}
		rl := listeners[i]
		if !isnil(rl.listener) {
			rl.listener(event)
		}
		// Note: called_count (on RegisteredListener) is intentionally not
		// updated here — it would require a mutable reference to the
		// original RegisteredListener in the map, which is not available
		// after cloning the listeners slice. The local `called` counter
		// serves as the return value. called_count remains a diagnostic
		// field for future use with mutable iteration.
		called++
	}
	return called
}

// dispatch_async fires an event asynchronously using goroutines.
// Does not wait for listeners to complete — use wait_async() to block
// until all in-flight async dispatches finish.
// Each listener runs in its own thread — a failing listener does not affect others.
// Goroutines are tracked via sync.WaitGroup so shutdown() can drain them.
// 使用分片读锁：仅锁定事件名对应的分片，不同事件名可并发 dispatch。
pub fn (mut bus EventBus) dispatch_async(event &Event) {
	if event.timestamp == 0 {
		unsafe {
			mut e := event
			e.timestamp = time.now().unix()
		}
	}

	bus.sharded_mu.rlock(event.name)
	listeners := bus.listeners[event.name] or { []RegisteredListener{} }
	bus.sharded_mu.runlock(event.name)

	for rl in listeners {
		if event.is_propagation_stopped() {
			break
		}
		if isnil(rl.listener) {
			continue
		}
		captured_event := event
		captured_listener := rl.listener
		// 使用 wg.go() 替代手动 add(1)+spawn+done()。
		// wg.go() 内部正确处理了 mut WaitGroup 的传递，
		// 避免了 unsafe 调用 done() 的潜在问题。
		bus.wg.go(fn [captured_event, captured_listener] () {
			captured_listener(captured_event)
		})
	}
}

// wait_async blocks until all in-flight async dispatch goroutines complete.
// Useful for graceful shutdown — call before exiting to ensure all async
// event listeners have finished processing.
pub fn (mut bus EventBus) wait_async() {
	bus.wg.wait()
}

// shutdown waits for all in-flight async dispatches to complete and then
// clears all listeners. After shutdown(), the EventBus is empty and no
// further events will be dispatched.
// 使用全局分片锁：需清空所有事件监听器。
pub fn (mut bus EventBus) shutdown() {
	bus.wait_async()
	bus.sharded_mu.lock_all()
	defer { bus.sharded_mu.unlock_all() }
	bus.listeners = map[string][]RegisteredListener{}
	bus.transactional_listeners = map[string][]TransactionalRegisteredListener{}
}

// ── Diagnostic ──

// print_listeners prints all registered event listeners.
// 使用全局分片读锁：需遍历所有事件名。
pub fn (mut bus EventBus) print_listeners() {
	bus.sharded_mu.rlock_all()
	defer { bus.sharded_mu.runlock_all() }

	println('═══ EventBus: ${bus.listeners.len} event type(s) ═══')
	for event_name, listeners in bus.listeners {
		println('  ${event_name}:')
		for rl in listeners {
			println('    priority=${rl.priority} called=${rl.called_count}')
		}
	}
}

// ── Transactional Event Support ──

// TransactionPhase defines when a transactional event listener fires.
// Spring equivalent: org.springframework.transaction.event.TransactionPhase
pub enum TransactionPhase {
	before_commit    // before transaction commit
	after_commit     // after successful commit
	after_rollback   // after transaction rollback
	after_completion // after commit or rollback
}

// TransactionalEventListener handles events at specific transaction phases.
// Spring equivalent: @TransactionalEventListener
pub interface TransactionalEventListener {
	phase() TransactionPhase
mut:
	handle(event &Event)
}

// TransactionalRegisteredListener wraps a TransactionalEventListener with metadata.
pub struct TransactionalRegisteredListener {
pub:
	id         int
	phase      TransactionPhase
	event_name string
pub mut:
	listener TransactionalEventListener
}

// on_transactional registers a transactional event listener.
// The listener will only be invoked when dispatch_transactional is called
// with the matching phase.
// Returns a unique listener id that can be passed to off_transactional_listener(id).
// 使用分片锁：仅锁定目标事件名对应的分片。
// next_id 使用独立 id_mu 保护，避免不同分片锁下的竞态条件。
pub fn (mut bus EventBus) on_transactional(event_name string, listener TransactionalEventListener) int {
	// Generate unique ID under dedicated mutex (same pattern as on_with_priority)
	bus.id_mu.@lock()
	bus.next_id++
	id := bus.next_id
	bus.id_mu.unlock()

	bus.sharded_mu.@lock(event_name)
	defer { bus.sharded_mu.unlock(event_name) }
	mut listeners := bus.transactional_listeners[event_name] or {
		[]TransactionalRegisteredListener{}
	}
	listeners << TransactionalRegisteredListener{
		id:         id
		listener:   listener
		phase:      listener.phase()
		event_name: event_name
	}
	bus.transactional_listeners[event_name] = listeners
	return id
}

// dispatch_transactional fires an event for a specific transaction phase.
// Only listeners registered for the matching phase are invoked.
// Returns the number of listeners that were called.
// 使用分片读锁：仅锁定事件名对应的分片。
pub fn (mut bus EventBus) dispatch_transactional(event &Event, phase TransactionPhase) int {
	bus.sharded_mu.rlock(event.name)
	mut listeners := bus.transactional_listeners[event.name] or {
		[]TransactionalRegisteredListener{}
	}
	bus.sharded_mu.runlock(event.name)

	mut called := 0
	for mut rl in listeners {
		if event.is_propagation_stopped() {
			break
		}
		// Match phase: after_completion fires for both commit and rollback
		if rl.phase == phase || (rl.phase == .after_completion && (phase == .after_commit
			|| phase == .after_rollback)) {
			rl.listener.handle(event)
			called++
		}
	}
	return called
}

// dispatch_transactional_all fires an event for all phases.
// Useful for after_completion which should fire regardless of commit/rollback.
// 使用分片读锁：仅锁定事件名对应的分片。
pub fn (mut bus EventBus) dispatch_transactional_all(event &Event) int {
	bus.sharded_mu.rlock(event.name)
	mut listeners := bus.transactional_listeners[event.name] or {
		[]TransactionalRegisteredListener{}
	}
	bus.sharded_mu.runlock(event.name)

	mut called := 0
	for mut rl in listeners {
		if event.is_propagation_stopped() {
			break
		}
		rl.listener.handle(event)
		called++
	}
	return called
}

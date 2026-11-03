module core

// event_lifecycle_test.v - Lifecycle tests for EventBus
//
// Verifies fixes for:
//   - HIGH #7: dispatch_background() tracks goroutines so wait_background()/shutdown()
//              drain them before returning
//   - HIGH #8: off_listener(id) removes listeners by id (closure-safe)
//   - M23:     off_listener supports closure removal (id-based, not function-pointer)
//
// 注意：后台 listener 必须写 __global 计数器，不能靠闭包捕获。
// 背景：V 0.5.2 的 cgen 在 `spawn fn [mut x] ()` 里对 `x++` 生成的是
// `_V_closure_ctx->x++` —— 上下文是让新线程**独占**的，对局部变量的写入
// 永远不会回到 spawn 方。所以「闭包捕获计数器」这种写法只会永远读到 0，
// 断言 0/1/2 都失去意义（见 core/event.v 的 dispatch_background 注释）。
import time

// Global counter to track async listener completion.
// V closures cannot mutate captured variables unless captured by `mut`,
// and EventListener is a function type (not an interface), so we use
// a __global counter (compiled with -enable-globals, matching CI).
__global event_async_call_count int
__global event_sync_call_count int

fn event_async_test_listener(e &Event) {
	// Simulate work so wait_background() has something to wait for
	time.sleep(10 * time.millisecond)
	unsafe {
		event_async_call_count++
	}
}

fn event_sync_test_listener(e &Event) {
	unsafe {
		event_sync_call_count++
	}
}

// ============================================================
// dispatch_background() + wait_background() — goroutine tracking (HIGH #7)
// ============================================================

fn test_event_lifecycle_dispatch_background_drained() {
	mut bus := new_event_bus()
	unsafe {
		event_async_call_count = 0
	}
	bus.on('async.test', event_async_test_listener)
	bus.on('async.test', event_async_test_listener)

	event := new_event('async.test', 'payload')
	bus.dispatch_background(event)

	// wait_background() must block until both background listeners complete
	bus.wait_background()

	// Both listeners should have completed
	assert unsafe { event_async_call_count } == 2
}

fn test_event_lifecycle_wait_background_no_pending() {
	mut bus := new_event_bus()
	// wait_background() with no pending dispatches must return immediately
	start := time.ticks()
	bus.wait_background()
	// Not a time assertion: just proves it does not hang (file-level timeout).
	assert bus.listener_count_for('nothing') == 0
	assert time.ticks() - start < 5000
}

fn test_event_lifecycle_dispatch_background_multiple_events() {
	mut bus := new_event_bus()
	unsafe {
		event_async_call_count = 0
	}
	bus.on('event.a', event_async_test_listener)
	bus.on('event.b', event_async_test_listener)

	bus.dispatch_background(new_event('event.a', 'a'))
	bus.dispatch_background(new_event('event.b', 'b'))

	bus.wait_background()
	assert unsafe { event_async_call_count } == 2
}

// ============================================================
// off_listener(id) — closure-safe removal (HIGH #8, M23)
// ============================================================

fn test_event_lifecycle_off_listener_removes_closure() {
	mut bus := new_event_bus()
	unsafe {
		event_sync_call_count = 0
	}
	// Register a closure — function-pointer comparison would fail for
	// closures, but id-based removal works reliably.
	id := bus.on('closure.test', fn (e &Event) {
		unsafe {
			event_sync_call_count++
		}
	})
	assert bus.listener_count_for('closure.test') == 1

	// Remove by id
	bus.off_listener(id)
	assert bus.listener_count_for('closure.test') == 0

	// Dispatch — the removed closure should NOT be called
	bus.dispatch(new_event('closure.test', 'x'))
	assert unsafe { event_sync_call_count } == 0
}

fn test_event_lifecycle_off_listener_keeps_others() {
	mut bus := new_event_bus()
	unsafe {
		event_sync_call_count = 0
	}
	id1 := bus.on('multi.test', event_sync_test_listener)
	id2 := bus.on('multi.test', event_sync_test_listener)
	assert bus.listener_count_for('multi.test') == 2

	// Remove only the first listener
	bus.off_listener(id1)
	assert bus.listener_count_for('multi.test') == 1

	// The second listener should still be called
	bus.dispatch(new_event('multi.test', 'x'))
	assert unsafe { event_sync_call_count } == 1

	// Clean up
	bus.off_listener(id2)
}

fn test_event_lifecycle_off_listener_unknown_id() {
	mut bus := new_event_bus()
	bus.on('test', event_sync_test_listener)
	// Removing a non-existent id should be a safe no-op
	bus.off_listener(99999)
	assert bus.listener_count_for('test') == 1
}

fn test_event_lifecycle_off_listener_across_events() {
	mut bus := new_event_bus()
	unsafe {
		event_sync_call_count = 0
	}
	id1 := bus.on('event.one', event_sync_test_listener)
	id2 := bus.on('event.two', event_sync_test_listener)

	// off_listener searches all event names (id is globally unique)
	bus.off_listener(id1)
	assert bus.listener_count_for('event.one') == 0
	assert bus.listener_count_for('event.two') == 1

	// event.one should not trigger any calls
	bus.dispatch(new_event('event.one', 'x'))
	assert unsafe { event_sync_call_count } == 0

	// event.two should still trigger
	bus.dispatch(new_event('event.two', 'x'))
	assert unsafe { event_sync_call_count } == 1

	bus.off_listener(id2)
}

// ============================================================
// shutdown() — drains async + clears listeners (HIGH #7)
// ============================================================

fn test_event_lifecycle_shutdown_drains_background() {
	mut bus := new_event_bus()
	unsafe {
		event_async_call_count = 0
	}
	bus.on('shutdown.test', event_async_test_listener)
	bus.dispatch_background(new_event('shutdown.test', 'x'))

	// shutdown() calls wait_background() then clears all listeners
	bus.shutdown()

	// The background listener must have completed before shutdown returned
	assert unsafe { event_async_call_count } == 1
	// Listeners should be cleared
	assert bus.listener_count_for('shutdown.test') == 0
}

fn test_event_lifecycle_shutdown_clears_all_listeners() {
	mut bus := new_event_bus()
	bus.on('a', event_sync_test_listener)
	bus.on('b', event_sync_test_listener)
	bus.on('c', event_sync_test_listener)

	bus.shutdown()

	assert bus.listener_count_for('a') == 0
	assert bus.listener_count_for('b') == 0
	assert bus.listener_count_for('c') == 0
}

fn test_event_lifecycle_shutdown_idempotent() {
	mut bus := new_event_bus()
	bus.on('test', event_sync_test_listener)
	bus.shutdown()
	// Second shutdown should not panic
	bus.shutdown()
	assert bus.listener_count_for('test') == 0
}

// ============================================================
// on() returns unique ids — id-based removal foundation
// ============================================================

fn test_event_lifecycle_on_returns_unique_ids() {
	mut bus := new_event_bus()
	id1 := bus.on('test', event_sync_test_listener)
	id2 := bus.on('test', event_sync_test_listener)
	id3 := bus.on('other', event_sync_test_listener)

	assert id1 != id2
	assert id2 != id3
	assert id1 != id3
}

fn test_event_lifecycle_on_with_priority_returns_id() {
	mut bus := new_event_bus()
	id := bus.on_with_priority('priority.test', event_sync_test_listener,
		int(ListenerPriority.high))
	assert id > 0
	bus.off_listener(id)
}

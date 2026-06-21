module core

// event_lifecycle_test.v - Lifecycle tests for EventBus
//
// Verifies fixes for:
//   - HIGH #7: dispatch_async() tracks goroutines via WaitGroup (wait_async/shutdown)
//   - HIGH #8: off_listener(id) removes listeners by id (closure-safe)
//   - M23:     off_listener supports closure removal (id-based, not function-pointer)
import time

// Global counter to track async listener completion.
// V closures cannot mutate captured variables unless captured by `mut`,
// and EventListener is a function type (not an interface), so we use
// a __global counter (compiled with -enable-globals, matching CI).
__global event_async_call_count int
__global event_sync_call_count int

fn event_async_test_listener(e &Event) {
	// Simulate work so wait_async() has something to wait for
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
// dispatch_async() + wait_async() — goroutine tracking (HIGH #7)
// ============================================================

fn test_event_lifecycle_dispatch_async_tracked_by_waitgroup() {
	mut bus := new_event_bus()
	unsafe {
		event_async_call_count = 0
	}
	bus.on('async.test', event_async_test_listener)
	bus.on('async.test', event_async_test_listener)

	event := new_event('async.test', 'payload')
	bus.dispatch_async(event)

	// wait_async() should block until both async listeners complete
	bus.wait_async()

	// Both listeners should have completed
	assert unsafe { event_async_call_count } == 2
}

fn test_event_lifecycle_wait_async_no_pending() {
	mut bus := new_event_bus()
	// wait_async() with no pending goroutines should return immediately
	bus.wait_async()
	assert true // no hang
}

fn test_event_lifecycle_dispatch_async_multiple_events() {
	mut bus := new_event_bus()
	unsafe {
		event_async_call_count = 0
	}
	bus.on('event.a', event_async_test_listener)
	bus.on('event.b', event_async_test_listener)

	bus.dispatch_async(new_event('event.a', 'a'))
	bus.dispatch_async(new_event('event.b', 'b'))

	bus.wait_async()
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

fn test_event_lifecycle_shutdown_drains_async() {
	mut bus := new_event_bus()
	unsafe {
		event_async_call_count = 0
	}
	bus.on('shutdown.test', event_async_test_listener)
	bus.dispatch_async(new_event('shutdown.test', 'x'))

	// shutdown() calls wait_async() then clears all listeners
	bus.shutdown()

	// The async listener should have completed before shutdown returned
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

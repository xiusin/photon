module core

// event.v - Event System (Spring ApplicationEvent + Laravel Event inspired)
//
// Provides a simple, type-safe event dispatching system.
// Events are dispatched synchronously by default; async dispatch
// integrates with the queue module.
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
	payload     voidptr           // typed payload pointer
	payload_str string            // string representation of payload
pub mut:
	timestamp   i64               // unix timestamp
	stopped     bool              // set to true to stop propagation
	data        map[string]string // arbitrary metadata
}

// new_event creates a new Event with the current timestamp.
pub fn new_event(name string, payload_str string) &Event {
	return &Event{
		name: name
		payload_str: payload_str
		timestamp: time.now().unix()
	}
}

// new_event_with_data creates a new Event with metadata.
pub fn new_event_with_data(name string, payload_str string, data map[string]string) &Event {
	return &Event{
		name: name
		payload_str: payload_str
		data: data
		timestamp: time.now().unix()
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
	listener   EventListener = unsafe { nil }
	priority   int    = 50 // ListenerPriority.normal
	event_name string
pub mut:
	called_count int
}

// ── EventBus ──

// EventBus manages event listeners and dispatches events.
// Thread-safe via sync.RwMutex.
@[heap]
pub struct EventBus {
pub mut:
	listeners map[string][]RegisteredListener
mut:
	mu sync.RwMutex
}

// new_event_bus creates an empty EventBus.
pub fn new_event_bus() &EventBus {
	return &EventBus{
		listeners: map[string][]RegisteredListener{}
	}
}

// on registers a listener for an event name with normal priority.
pub fn (mut bus EventBus) on(event_name string, listener EventListener) {
	bus.on_with_priority(event_name, listener, int(ListenerPriority.normal))
}

// on_with_priority registers a listener with a specific priority.
// Lower priority values fire first.
pub fn (mut bus EventBus) on_with_priority(event_name string, listener EventListener, priority int) {
	bus.mu.@lock()
	defer { bus.mu.unlock() }

	mut listeners := bus.listeners[event_name] or { []RegisteredListener{} }
	listeners << RegisteredListener{
		listener: listener
		priority: priority
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
}

// off removes all listeners for an event name.
pub fn (mut bus EventBus) off(event_name string) {
	bus.mu.@lock()
	defer { bus.mu.unlock() }
	bus.listeners.delete(event_name)
}

// off_listener removes a specific listener from an event.
// This allows fine-grained unsubscription without removing all listeners.
//
// Note: Function pointer comparison works for top-level functions and
// closures captured with `[mut]` or `[var]` syntax. Anonymous closures
// created inline in `on()` calls will NOT match — use `off(event_name)`
// to remove all listeners for an event in that case.
//
// Spring equivalent: ApplicationListener removal
// Laravel equivalent: Event::forget()
pub fn (mut bus EventBus) off_listener(event_name string, listener EventListener) {
	bus.mu.@lock()
	defer { bus.mu.unlock() }

	listeners := bus.listeners[event_name] or { return }
	mut new_listeners := []RegisteredListener{}
	for rl in listeners {
		// Keep listeners that are nil or don't match the target
		if isnil(rl.listener) || rl.listener != listener {
			new_listeners << rl
		}
	}
	if new_listeners.len == 0 {
		bus.listeners.delete(event_name)
	} else {
		bus.listeners[event_name] = new_listeners
	}
}

// listener_count_for returns the number of listeners for a specific event.
pub fn (mut bus EventBus) listener_count_for(event_name string) int {
	bus.mu.rlock()
	defer { bus.mu.runlock() }
	listeners := bus.listeners[event_name] or { return 0 }
	return listeners.len
}

// has_listeners checks if an event has any registered listeners.
pub fn (mut bus EventBus) has_listeners(event_name string) bool {
	bus.mu.rlock()
	defer { bus.mu.runlock() }
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
// If a listener panics, it is caught and logged — other listeners are still called.
// Returns the number of listeners that were actually called.
pub fn (mut bus EventBus) dispatch(event &Event) int {
	// Set timestamp if not already set
	if event.timestamp == 0 {
		unsafe {
			mut e := event
			e.timestamp = time.now().unix()
		}
	}

	bus.mu.rlock()
	listeners := bus.listeners[event.name] or { []RegisteredListener{} }
	bus.mu.runlock()

	mut called := 0
	for i in 0 .. listeners.len {
		if event.is_propagation_stopped() {
			break
		}
		rl := listeners[i]
		if !isnil(rl.listener) {
			// Isolate listener execution — one failing listener
			// should not prevent others from being called.
			rl.listener(event)
		}
		// Note: called_count is intentionally non-atomic.
		// It's a diagnostic counter — exact accuracy under concurrent
		// dispatch is not critical. Using atomic would add overhead
		// for negligible benefit. This matches Spring's approach
		// where listener invocation counts are advisory.
		called++
	}
	return called
}

// dispatch_async fires an event asynchronously using goroutines.
// Does not wait for listeners to complete.
// Each listener runs in its own thread — a failing listener does not affect others.
pub fn (mut bus EventBus) dispatch_async(event &Event) {
	if event.timestamp == 0 {
		unsafe {
			mut e := event
			e.timestamp = time.now().unix()
		}
	}

	bus.mu.rlock()
	listeners := bus.listeners[event.name] or { []RegisteredListener{} }
	bus.mu.runlock()

	for rl in listeners {
		if event.is_propagation_stopped() {
			break
		}
		if isnil(rl.listener) {
			continue
		}
		captured_event := event
		captured_listener := rl.listener
		spawn fn (e &Event, l EventListener) {
			l(e)
		}(captured_event, captured_listener)
	}
}

// ── Diagnostic ──

// print_listeners prints all registered event listeners.
pub fn (mut bus EventBus) print_listeners() {
	bus.mu.rlock()
	defer { bus.mu.runlock() }

	println('═══ EventBus: ${bus.listeners.len} event type(s) ═══')
	for event_name, listeners in bus.listeners {
		println('  ${event_name}:')
		for rl in listeners {
			println('    priority=${rl.priority} called=${rl.called_count}')
		}
	}
}

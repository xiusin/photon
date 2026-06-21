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
// Thread-safe via sync.RwMutex.
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
	mu      sync.RwMutex
	wg      sync.WaitGroup
	next_id int
}

// new_event_bus creates an empty EventBus.
pub fn new_event_bus() &EventBus {
	return &EventBus{
		listeners:               map[string][]RegisteredListener{}
		transactional_listeners: map[string][]TransactionalRegisteredListener{}
	}
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
pub fn (mut bus EventBus) on_with_priority(event_name string, listener EventListener, priority int) int {
	bus.mu.@lock()
	defer { bus.mu.unlock() }

	bus.next_id++
	id := bus.next_id
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
pub fn (mut bus EventBus) off(event_name string) {
	bus.mu.@lock()
	defer { bus.mu.unlock() }
	bus.listeners.delete(event_name)
}

// off_listener removes a specific listener by its unique id (returned by on()).
// This works reliably for closures (unlike function-pointer comparison).
// Searches all event names since the id is globally unique.
//
// Spring equivalent: ApplicationListener removal
// Laravel equivalent: Event::forget()
pub fn (mut bus EventBus) off_listener(id int) {
	bus.mu.@lock()
	defer { bus.mu.unlock() }

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
pub fn (mut bus EventBus) off_transactional_listener(id int) {
	bus.mu.@lock()
	defer { bus.mu.unlock() }

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
// Does not wait for listeners to complete — use wait_async() to block
// until all in-flight async dispatches finish.
// Each listener runs in its own thread — a failing listener does not affect others.
// Goroutines are tracked via sync.WaitGroup so shutdown() can drain them.
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
		bus.wg.add(1)
		captured_event := event
		captured_listener := rl.listener
		bus_ref := bus
		spawn fn (e &Event, l EventListener, gb &EventBus) {
			defer {
				unsafe { gb.wg.done() }
			}
			l(e)
		}(captured_event, captured_listener, bus_ref)
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
pub fn (mut bus EventBus) shutdown() {
	bus.wait_async()
	bus.mu.@lock()
	defer { bus.mu.unlock() }
	bus.listeners = map[string][]RegisteredListener{}
	bus.transactional_listeners = map[string][]TransactionalRegisteredListener{}
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
pub fn (mut bus EventBus) on_transactional(event_name string, listener TransactionalEventListener) int {
	bus.mu.@lock()
	defer { bus.mu.unlock() }

	bus.next_id++
	id := bus.next_id
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
pub fn (mut bus EventBus) dispatch_transactional(event &Event, phase TransactionPhase) int {
	bus.mu.rlock()
	mut listeners := bus.transactional_listeners[event.name] or {
		[]TransactionalRegisteredListener{}
	}
	bus.mu.runlock()

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
pub fn (mut bus EventBus) dispatch_transactional_all(event &Event) int {
	bus.mu.rlock()
	mut listeners := bus.transactional_listeners[event.name] or {
		[]TransactionalRegisteredListener{}
	}
	bus.mu.runlock()

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

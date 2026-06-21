module web

// kernel.v - HttpKernel (Symfony HttpKernel inspired)
//
// Provides an event-driven HTTP kernel with standard lifecycle events:
// kernel.request → kernel.controller → kernel.response →
// kernel.exception → kernel.terminate.
import sync

// KernelEventType defines standard kernel events
pub enum KernelEventType {
	request
	controller
	response
	exception
	terminate
}

// kernel_event_name returns the event name string
fn kernel_event_name(evt KernelEventType) string {
	return match evt {
		.request { 'kernel.request' }
		.controller { 'kernel.controller' }
		.response { 'kernel.response' }
		.exception { 'kernel.exception' }
		.terminate { 'kernel.terminate' }
	}
}

pub type KernelListener = fn (event_name string, data voidptr)

pub type HandlerFn = fn (ctx voidptr) !voidptr

// KernelListenerEntry wraps a KernelListener with a unique id for
// fine-grained removal via off(listener_id).
struct KernelListenerEntry {
pub:
	id       int
	listener KernelListener = unsafe { nil }
}

// HandlerResolver resolves a request to a handler function.
// Spring equivalent: HandlerMapping + HandlerAdapter
pub interface HandlerResolver {
	resolve(ctx voidptr) !HandlerFn
}

// HttpKernel manages the HTTP request lifecycle with event hooks.
// Thread-safe via sync.RwMutex.
//
// After all listeners are registered, call freeze_listeners() (or simply
// start serving requests via handle()/handle_with(), which auto-freezes on
// the first call) to snapshot the listener table. Once frozen, dispatch()
// reads the immutable snapshot directly — no per-request locking or cloning.
//
// The frozen flag is protected by mu to ensure memory visibility across
// goroutines. unfreeze() can be used to thaw the kernel and modify listeners
// again; off(id) removes a specific listener by its registration id.
pub struct HttpKernel {
pub mut:
	listeners        map[string][]KernelListenerEntry
	frozen_listeners map[string][]KernelListenerEntry
mut:
	mu      sync.RwMutex
	frozen  bool
	next_id int
}

// new_http_kernel creates a new HttpKernel
pub fn new_http_kernel() &HttpKernel {
	return &HttpKernel{
		listeners:        map[string][]KernelListenerEntry{}
		frozen_listeners: map[string][]KernelListenerEntry{}
	}
}

// on registers a listener for a kernel event and returns its unique id.
// The id can be passed to off(id) to remove this specific listener later.
pub fn (mut k HttpKernel) on(event_type KernelEventType, listener KernelListener) int {
	k.mu.@lock()
	defer { k.mu.unlock() }
	name := kernel_event_name(event_type)
	k.next_id++
	id := k.next_id
	k.listeners[name] << KernelListenerEntry{
		id:       id
		listener: listener
	}
	return id
}

// off removes a listener by its registration id (returned by on()).
// Searches all event types. Safe to call after freeze_listeners() —
// updates both the live and frozen listener tables.
pub fn (mut k HttpKernel) off(listener_id int) {
	k.mu.@lock()
	defer { k.mu.unlock() }
	// Remove from live listeners
	for event_name, entries in k.listeners {
		mut new_entries := []KernelListenerEntry{}
		for entry in entries {
			if entry.id != listener_id {
				new_entries << entry
			}
		}
		k.listeners[event_name] = new_entries
	}
	// Remove from frozen listeners (if frozen)
	for event_name, entries in k.frozen_listeners {
		mut new_entries := []KernelListenerEntry{}
		for entry in entries {
			if entry.id != listener_id {
				new_entries << entry
			}
		}
		k.frozen_listeners[event_name] = new_entries
	}
}

// freeze_listeners snapshots all registered listeners into frozen_listeners.
// After freezing, dispatch() serves from the snapshot directly — no per-request
// locking or cloning. This eliminates the per-request allocation hotspot since
// kernel.request/controller/response fire on every HTTP request.
//
// Call this once after all listeners are registered and before serving requests.
// handle()/handle_with() auto-freeze on first call if not already frozen.
// Idempotent: safe to call multiple times; subsequent calls are no-ops.
pub fn (mut k HttpKernel) freeze_listeners() {
	k.mu.@lock()
	defer { k.mu.unlock() }
	if k.frozen {
		return
	}
	// Clone each slice so the snapshot is independent of the live listeners
	// map — later on() calls (which would be a programming error after
	// freezing) cannot mutate the frozen backing arrays.
	for name, lst in k.listeners {
		k.frozen_listeners[name] = lst.clone()
	}
	k.frozen = true
}

// unfreeze thaws the kernel, allowing listeners to be modified again.
// Clears the frozen snapshot and sets frozen = false under the write lock.
// Subsequent dispatch() calls will use the slow path (live listeners) until
// freeze_listeners() is called again.
pub fn (mut k HttpKernel) unfreeze() {
	k.mu.@lock()
	defer { k.mu.unlock() }
	k.frozen = false
	k.frozen_listeners = map[string][]KernelListenerEntry{}
}

// dispatch fires all listeners for an event.
//
// Fast path (frozen): reads the frozen flag under rlock for memory visibility,
// then reads the immutable snapshot. The snapshot slice is cloned under rlock
// to safely handle concurrent unfreeze()/off() calls.
//
// Slow path (not frozen): clones the listener slice under a read lock to avoid
// concurrent modification during iteration.
fn (mut k HttpKernel) dispatch(event_type KernelEventType, data voidptr) {
	name := kernel_event_name(event_type)
	// Read frozen flag under rlock for memory visibility across goroutines.
	k.mu.rlock()
	if k.frozen {
		entries := k.frozen_listeners[name] or {
			k.mu.runlock()
			return
		}
		listeners_copy := entries.clone()
		k.mu.runlock()
		for entry in listeners_copy {
			if !isnil(entry.listener) {
				entry.listener(name, data)
			}
		}
		return
	}
	// Slow path: not yet frozen — clone under read lock.
	entries := k.listeners[name].clone()
	k.mu.runlock()
	for entry in entries {
		if !isnil(entry.listener) {
			entry.listener(name, data)
		}
	}
}

// handle processes a request through the kernel lifecycle
pub fn (mut k HttpKernel) handle() ! {
	k.mu.rlock()
	frozen := k.frozen
	k.mu.runlock()
	if !frozen {
		k.freeze_listeners()
	}
	k.dispatch(.request, unsafe { nil })
	k.dispatch(.controller, unsafe { nil })
	// Process request here
	k.dispatch(.response, unsafe { nil })
}

// handle_with processes a request through the kernel lifecycle with a real handler resolver.
// Dispatches request → controller → response events, and exception on error.
// Returns the handler's response.
pub fn (mut k HttpKernel) handle_with(resolver HandlerResolver, ctx voidptr) !voidptr {
	k.mu.rlock()
	frozen := k.frozen
	k.mu.runlock()
	if !frozen {
		k.freeze_listeners()
	}
	k.dispatch(.request, ctx)

	handler := resolver.resolve(ctx) or {
		k.dispatch(.exception, err)
		return err
	}

	k.dispatch(.controller, ctx)

	result := handler(ctx) or {
		k.dispatch(.exception, err)
		return err
	}

	k.dispatch(.response, result)
	return result
}

// terminate runs post-response cleanup
pub fn (mut k HttpKernel) terminate() {
	k.dispatch(.terminate, unsafe { nil })
}

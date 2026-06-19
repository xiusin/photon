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
pub struct HttpKernel {
pub mut:
	listeners        map[string][]KernelListener
	frozen_listeners map[string][]KernelListener
mut:
	mu     sync.RwMutex
	frozen bool
}

// new_http_kernel creates a new HttpKernel
pub fn new_http_kernel() &HttpKernel {
	return &HttpKernel{
		listeners:        map[string][]KernelListener{}
		frozen_listeners: map[string][]KernelListener{}
	}
}

// on registers a listener for a kernel event
pub fn (mut k HttpKernel) on(event_type KernelEventType, listener KernelListener) {
	k.mu.@lock()
	defer { k.mu.unlock() }
	name := kernel_event_name(event_type)
	k.listeners[name] << listener
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

// dispatch fires all listeners for an event.
//
// Fast path (frozen): reads the immutable snapshot directly — no lock, no clone.
// The slice header is immutable after freezing, so concurrent reads are safe.
//
// Slow path (not frozen): clones the listener slice under a read lock to avoid
// concurrent modification during iteration.
fn (mut k HttpKernel) dispatch(event_type KernelEventType, data voidptr) {
	name := kernel_event_name(event_type)
	// Fast path: frozen snapshot is read-only after freezing.
	if k.frozen {
		listeners := k.frozen_listeners[name] or { return }
		for listener in listeners {
			listener(name, data)
		}
		return
	}
	// Slow path: not yet frozen — clone under read lock.
	k.mu.rlock()
	listeners := k.listeners[name].clone()
	k.mu.runlock()
	for listener in listeners {
		listener(name, data)
	}
}

// handle processes a request through the kernel lifecycle
pub fn (mut k HttpKernel) handle() ! {
	if !k.frozen {
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
	if !k.frozen {
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

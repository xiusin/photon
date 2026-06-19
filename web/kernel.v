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
pub struct HttpKernel {
pub mut:
	listeners map[string][]KernelListener
mut:
	mu sync.RwMutex
}

// new_http_kernel creates a new HttpKernel
pub fn new_http_kernel() &HttpKernel {
	return &HttpKernel{
		listeners: map[string][]KernelListener{}
	}
}

// on registers a listener for a kernel event
pub fn (mut k HttpKernel) on(event_type KernelEventType, listener KernelListener) {
	k.mu.@lock()
	defer { k.mu.unlock() }
	name := kernel_event_name(event_type)
	k.listeners[name] << listener
}

// dispatch fires all listeners for an event
fn (mut k HttpKernel) dispatch(event_type KernelEventType, data voidptr) {
	k.mu.rlock()
	name := kernel_event_name(event_type)
	listeners := k.listeners[name].clone()
	k.mu.runlock()
	for listener in listeners {
		listener(name, data)
	}
}

// handle processes a request through the kernel lifecycle
pub fn (mut k HttpKernel) handle() ! {
	k.dispatch(.request, unsafe { nil })
	k.dispatch(.controller, unsafe { nil })
	// Process request here
	k.dispatch(.response, unsafe { nil })
}

// handle_with processes a request through the kernel lifecycle with a real handler resolver.
// Dispatches request → controller → response events, and exception on error.
// Returns the handler's response.
pub fn (mut k HttpKernel) handle_with(resolver HandlerResolver, ctx voidptr) !voidptr {
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

module web

// web_ext_test.v - Tests for pipeline, ratelimit, kernel

// ============================================================
// Pipeline Tests
// ============================================================

@[heap]
struct PipelineTracker {
mut:
	order []string
	called bool
}

fn test_pipeline_construction() {
	p := new_pipeline()
	assert p != unsafe { nil }
}

fn test_pipeline_through_then() {
	mut p := new_pipeline()
	mut tracker := &PipelineTracker{}

	pipe1 := fn [mut tracker](passable voidptr, next fn (voidptr) voidptr) voidptr {
		tracker.order << 'pipe1_before'
		result := next(passable)
		tracker.order << 'pipe1_after'
		return result
	}

	pipe2 := fn [mut tracker](passable voidptr, next fn (voidptr) voidptr) voidptr {
		tracker.order << 'pipe2_before'
		result := next(passable)
		tracker.order << 'pipe2_after'
		return result
	}

	destination := fn [mut tracker](passable voidptr) voidptr {
		tracker.order << 'destination'
		return unsafe { nil }
	}

	p.send(unsafe { nil })
	p.through([pipe1, pipe2])
	_ = p.then(destination)

	assert tracker.order.len == 5
	assert tracker.order[0] == 'pipe1_before'
	assert tracker.order[1] == 'pipe2_before'
	assert tracker.order[2] == 'destination'
	assert tracker.order[3] == 'pipe2_after'
	assert tracker.order[4] == 'pipe1_after'
}

fn test_pipeline_empty_through() {
	mut p := new_pipeline()
	mut tracker := &PipelineTracker{}
	dest := fn [mut tracker](passable voidptr) voidptr {
		tracker.called = true
		return unsafe { nil }
	}
	p.send(unsafe { nil })
	p.through([])
	_ = p.then(dest)
	assert tracker.called == true
}

fn test_pipeline_single_pipe() {
	mut p := new_pipeline()
	mut tracker := &PipelineTracker{}
	pipe := fn [mut tracker](passable voidptr, next fn (voidptr) voidptr) voidptr {
		tracker.called = true
		return next(passable)
	}
	dest := fn (passable voidptr) voidptr {
		return unsafe { nil }
	}
	p.send(unsafe { nil })
	p.through([pipe])
	_ = p.then(dest)
	assert tracker.called == true
}

// ============================================================
// Rate Limiter Tests
// ============================================================

fn test_ratelimiter_new() {
	mut r := new_rate_limiter()
	assert r.key_count() == 0
}

fn test_ratelimiter_hit_and_check() {
	mut r := new_rate_limiter()
	assert r.too_many_attempts('key1', 3, 60) == false
	r.hit('key1')
	r.hit('key1')
	r.hit('key1')
	assert r.too_many_attempts('key1', 3, 60) == true
}

fn test_ratelimiter_remaining() {
	mut r := new_rate_limiter()
	assert r.remaining('key1', 5) == 5
	r.hit('key1')
	assert r.remaining('key1', 5) == 4
}

fn test_ratelimiter_remaining_capped() {
	mut r := new_rate_limiter()
	r.hit('k')
	r.hit('k')
	assert r.remaining('k', 1) == 0
}

fn test_ratelimiter_clear() {
	mut r := new_rate_limiter()
	r.hit('key1')
	assert r.too_many_attempts('key1', 1, 60) == true
	r.clear('key1')
	assert r.too_many_attempts('key1', 1, 60) == false
}

fn test_ratelimiter_multiple_keys() {
	mut r := new_rate_limiter()
	r.hit('user1')
	r.hit('user1')
	r.hit('user2')
	assert r.too_many_attempts('user1', 2, 60) == true
	assert r.too_many_attempts('user2', 2, 60) == false
}

fn test_ratelimiter_retry_without_hits() {
	mut r := new_rate_limiter()
	assert r.retry_after('nonexistent', 60) == 0
}

fn test_ratelimiter_clear_expired() {
	mut r := new_rate_limiter()
	r.hit('k')
	r.clear_expired(0)
	assert r.key_count() == 0
}

// ============================================================
// Kernel Tests
// ============================================================

@[heap]
struct KernelTracker {
mut:
	events []string
	count  int
	terminated bool
}

fn test_kernel_new() {
	k := new_http_kernel()
	assert k.listeners.len == 0
}

fn test_kernel_on() {
	mut k := new_http_kernel()
	k.on(.request, fn (name string, data voidptr) {})
	assert k.listeners.len == 1
}

fn test_kernel_handle() {
	mut k := new_http_kernel()
	mut tracker := &KernelTracker{}

	k.on(.request, fn [mut tracker](name string, data voidptr) {
		tracker.events << 'request'
	})
	k.on(.controller, fn [mut tracker](name string, data voidptr) {
		tracker.events << 'controller'
	})
	k.on(.response, fn [mut tracker](name string, data voidptr) {
		tracker.events << 'response'
	})

	k.handle() or { assert false }

	assert tracker.events.len == 3
	assert tracker.events[0] == 'request'
	assert tracker.events[1] == 'controller'
	assert tracker.events[2] == 'response'
}

fn test_kernel_terminate() {
	mut k := new_http_kernel()
	mut tracker := &KernelTracker{}
	k.on(.terminate, fn [mut tracker](name string, data voidptr) {
		tracker.terminated = true
	})

	k.terminate()
	assert tracker.terminated == true
}

fn test_kernel_event_names() {
	assert kernel_event_name(.request) == 'kernel.request'
	assert kernel_event_name(.controller) == 'kernel.controller'
	assert kernel_event_name(.response) == 'kernel.response'
	assert kernel_event_name(.exception) == 'kernel.exception'
	assert kernel_event_name(.terminate) == 'kernel.terminate'
}

fn test_kernel_multiple_listeners() {
	mut k := new_http_kernel()
	mut tracker := &KernelTracker{}

	k.on(.request, fn [mut tracker](name string, data voidptr) { tracker.count++ })
	k.on(.request, fn [mut tracker](name string, data voidptr) { tracker.count++ })
	k.on(.request, fn [mut tracker](name string, data voidptr) { tracker.count++ })

	k.handle() or { assert false }
	assert tracker.count == 3
}

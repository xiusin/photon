module web

// web_ext_test.v - Tests for pipeline, ratelimit, form, kernel

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
	assert r.attempts.len == 0
}

fn test_ratelimiter_hit_and_check() {
	mut r := new_rate_limiter()
	assert r.too_many_attempts('key1', 3) == false
	r.hit('key1')
	r.hit('key1')
	r.hit('key1')
	assert r.too_many_attempts('key1', 3) == true
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
	assert r.too_many_attempts('key1', 1)
	r.clear('key1')
	assert r.too_many_attempts('key1', 1) == false
}

fn test_ratelimiter_multiple_keys() {
	mut r := new_rate_limiter()
	r.hit('user1')
	r.hit('user1')
	r.hit('user2')
	assert r.too_many_attempts('user1', 2)
	assert r.too_many_attempts('user2', 2) == false
}

fn test_ratelimiter_retry_without_hits() {
	mut r := new_rate_limiter()
	assert r.retry_after('nonexistent', 60) == 0
}

fn test_ratelimiter_clear_expired() {
	mut r := new_rate_limiter()
	r.hit('k')
	r.clear_expired(0)
	assert r.attempts.len == 0
}

// ============================================================
// Form Builder Tests
// ============================================================

fn test_form_builder_new() {
	f := form()
	assert f.fields.len == 0
}

fn test_form_add_field() {
	mut f := form()
	f.add('name', .text)
	f.add('email', .email)
	assert f.fields.len == 2
}

fn test_form_add_label() {
	mut f := form()
	f.add('name', .text)
	f.add_label('name', 'Your Name')
	field := f.get_field('name')
	assert field.label == 'Your Name'
}

fn test_form_add_rule() {
	mut f := form()
	f.add('email', .email)
	f.add_rule('email', 'required')
	field := f.get_field('email')
	assert field.rules.len == 1
	assert field.rules[0] == 'required'
}

fn test_form_add_rules() {
	mut f := form()
	f.add('password', .password)
	f.add_rules('password', ['required', 'min:8'])
	field := f.get_field('password')
	assert field.rules.len == 2
}

fn test_form_set_required() {
	mut f := form()
	f.add('email', .email)
	f.set_required('email', true)
	field := f.get_field('email')
	assert field.required == true
}

fn test_form_get_fields() {
	mut f := form()
	f.add('a', .text)
	f.add('b', .number)
	fields := f.get_fields()
	assert fields.len == 2
}

fn test_form_get_field_missing() {
	f := form()
	field := f.get_field('nonexistent')
	assert field.name == 'nonexistent'
}

fn test_form_field_types() {
	mut f := form()
	f.add('t1', .text)
	f.add('t2', .email)
	f.add('t3', .password)
	f.add('t4', .number)
	f.add('t5', .textarea)
	f.add('t6', .select_)
	f.add('t7', .checkbox)
	f.add('t8', .file)
	f.add('t9', .hidden)
	assert f.fields.len == 9
}

fn test_form_builder_methods() {
	mut f := form()
	f.add('email', .email)
	f.add_label('email', 'Email Address')
	f.add_rule('email', 'required')
	f.add_rule('email', 'email')
	f.set_required('email', true)

	field := f.get_field('email')
	assert field.label == 'Email Address'
	assert field.rules.len == 2
	assert field.required
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

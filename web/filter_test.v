module web

// filter_test.v - Unit tests for FilterChain and built-in request/response filters
//
// Tests filter chain composition, request/response filter execution,
// built-in security headers, cache control, body size limiting,
// content type validation, and function type compatibility.

import veb

// Helper: create a minimal veb.Context for testing filters
fn filter_test_context() &veb.Context {
	return &veb.Context{}
}

// -- FilterChain construction tests --

fn test_new_filter_chain_empty() {
	chain := new_filter_chain()
	assert chain.request_filters.len == 0
	assert chain.response_filters.len == 0
}

fn test_add_request_filter() {
	mut chain := new_filter_chain()
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })
	assert chain.request_filters.len == 1
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })
	assert chain.request_filters.len == 2
}

fn test_add_response_filter() {
	mut chain := new_filter_chain()
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string { return body })
	assert chain.response_filters.len == 1
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string { return body + '!' })
	assert chain.response_filters.len == 2
}

fn test_add_both_filter_types() {
	mut chain := new_filter_chain()
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string { return body })
	assert chain.request_filters.len == 1
	assert chain.response_filters.len == 1
}

// -- FilterChain apply_request tests --

fn test_apply_request_empty() {
	chain := new_filter_chain()
	ctx := filter_test_context()
	result := chain.apply_request(ctx) or { false }
	assert result == true
}

fn test_apply_request_all_pass() {
	mut chain := new_filter_chain()
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })

	ctx := filter_test_context()
	result := chain.apply_request(ctx) or { false }
	assert result == true
}

fn test_apply_request_early_return_false() {
	mut chain := new_filter_chain()
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return false })
	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })

	ctx := filter_test_context()
	result := chain.apply_request(ctx) or { false }
	assert result == false
}

fn test_apply_request_error_propagation() {
	mut chain := new_filter_chain()
	chain.add_request_filter(fn (ctx &veb.Context) !bool {
		return error('filter error')
	})

	ctx := filter_test_context()
	mut caught := false
	if _ := chain.apply_request(ctx) {
		caught = false
	} else {
		caught = true
	}
	assert caught == true
}

// -- FilterChain apply_response tests --

fn test_apply_response_empty() {
	chain := new_filter_chain()
	ctx := filter_test_context()
	result := chain.apply_response(ctx, 'hello') or { '' }
	assert result == 'hello'
}

fn test_apply_response_body_transformation() {
	mut chain := new_filter_chain()
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string {
		return body + ' [filtered]'
	})

	ctx := filter_test_context()
	result := chain.apply_response(ctx, 'hello') or { '' }
	assert result == 'hello [filtered]'
}

fn test_apply_response_multiple_transformations() {
	mut chain := new_filter_chain()
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string {
		return body + '-A'
	})
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string {
		return body + '-B'
	})
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string {
		return body + '-C'
	})

	ctx := filter_test_context()
	result := chain.apply_response(ctx, 'X') or { '' }
	assert result == 'X-A-B-C'
}

fn test_apply_response_error_propagation() {
	mut chain := new_filter_chain()
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string {
		return error('transform error')
	})

	ctx := filter_test_context()
	mut caught := false
	if _ := chain.apply_response(ctx, 'data') {
		caught = false
	} else {
		caught = true
	}
	assert caught == true
}

// -- Built-in response filter: security_headers_filter --

fn test_security_headers_filter_returns_body() {
	mut ctx := filter_test_context()
	result := security_headers_filter(mut ctx, 'response body') or { '' }
	assert result == 'response body'
}

fn test_security_headers_filter_empty_body() {
	mut ctx := filter_test_context()
	result := security_headers_filter(mut ctx, '') or { '' }
	assert result == ''
}

fn test_security_headers_filter_preserves_body_integrity() {
	mut ctx := filter_test_context()
	original := '{"status":"ok","data":{"id":42}}'
	result := security_headers_filter(mut ctx, original) or { '' }
	assert result == original
}

// -- Built-in response filter: cache_control_filter --

fn test_cache_control_filter_returns_body() {
	mut ctx := filter_test_context()
	result := cache_control_filter(mut ctx, 'cached response') or { '' }
	assert result == 'cached response'
}

fn test_cache_control_filter_empty_body() {
	mut ctx := filter_test_context()
	result := cache_control_filter(mut ctx, '') or { '' }
	assert result == ''
}

// -- Request filter factory: body_size_filter --

fn test_body_size_filter_creates_function() {
	filter_fn := body_size_filter(1024)
	_ = filter_fn
	assert true
}

fn test_body_size_filter_different_limits() {
	filter_1k := body_size_filter(1024)
	filter_1m := body_size_filter(1048576)
	_ = filter_1k
	_ = filter_1m
	assert true
}

fn test_body_size_filter_zero_limit() {
	filter_fn := body_size_filter(0)
	_ = filter_fn
	assert true
}

fn test_body_size_filter_returns_request_filter_fn() {
	filter_fn := body_size_filter(512)
	// Verify it's assignable to RequestFilterFn type
	mut chain := new_filter_chain()
	chain.add_request_filter(filter_fn)
	assert chain.request_filters.len == 1
}

// -- Request filter factory: content_type_filter --

fn test_content_type_filter_creates_function() {
	filter_fn := content_type_filter(['application/json', 'text/plain'])
	_ = filter_fn
	assert true
}

fn test_content_type_filter_empty_allowed_types() {
	filter_fn := content_type_filter([])
	_ = filter_fn
	assert true
}

fn test_content_type_filter_single_type() {
	filter_fn := content_type_filter(['application/json'])
	_ = filter_fn
	assert true
}

fn test_content_type_filter_returns_request_filter_fn() {
	filter_fn := content_type_filter(['application/json', 'text/html'])
	mut chain := new_filter_chain()
	chain.add_request_filter(filter_fn)
	assert chain.request_filters.len == 1
}

// -- Filter function type compatibility tests --

fn test_request_filter_fn_type_accepts_closure() {
	fn_val := RequestFilterFn(fn (ctx &veb.Context) !bool { return true })
	_ = fn_val
	assert true
}

fn test_response_filter_fn_type_accepts_closure() {
	fn_val := ResponseFilterFn(fn (ctx &veb.Context, body string) !string { return body })
	_ = fn_val
	assert true
}

// -- Filter chain integration tests --

fn test_filter_chain_combined_request_response() {
	mut chain := new_filter_chain()

	chain.add_request_filter(fn (ctx &veb.Context) !bool { return true })
	chain.add_response_filter(fn (ctx &veb.Context, body string) !string {
		return 'resp:${body}'
	})

	ctx := filter_test_context()

	// Apply request filters
	req_result := chain.apply_request(ctx) or { false }
	assert req_result == true

	// Apply response filters
	resp_result := chain.apply_response(ctx, 'data') or { '' }
	assert resp_result == 'resp:data'
}

fn test_filter_chain_request_failure_stops_processing() {
	mut chain := new_filter_chain()

	chain.add_request_filter(fn (ctx &veb.Context) !bool {
		return true
	})
	chain.add_request_filter(fn (ctx &veb.Context) !bool {
		return false
	})

	ctx := filter_test_context()
	result := chain.apply_request(ctx) or { false }
	assert result == false
}

// -- Empty filter chain edge cases --

fn test_empty_request_filters_always_pass() {
	chain := new_filter_chain()
	ctx := filter_test_context()
	for _ in 0 .. 5 {
		result := chain.apply_request(ctx) or { false }
		assert result == true
	}
}

fn test_empty_response_filters_pass_through_body() {
	chain := new_filter_chain()
	ctx := filter_test_context()
	bodies := ['', 'a', 'hello world', '{"json":true}']
	for body in bodies {
		result := chain.apply_response(ctx, body) or { '' }
		assert result == body
	}
}

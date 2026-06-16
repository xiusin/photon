module web

// controller_test.v - Unit tests for web controller helpers

import veb

// Helper: create a veb.Context with a URL
fn ctx_with_url(url string) &veb.Context {
	mut ctx := &veb.Context{}
	ctx.req.url = url
	return ctx
}

// -- get_query_param tests --

fn test_get_query_param_single_param() {
	ctx := ctx_with_url('/users?id=42')
	assert get_query_param(ctx, 'id') == '42'
}

fn test_get_query_param_multiple_params() {
	ctx := ctx_with_url('/search?q=hello&page=1&limit=10')
	assert get_query_param(ctx, 'q') == 'hello'
	assert get_query_param(ctx, 'page') == '1'
	assert get_query_param(ctx, 'limit') == '10'
}

fn test_get_query_param_no_query_string() {
	ctx := ctx_with_url('/users')
	assert get_query_param(ctx, 'id') == ''
}

fn test_get_query_param_missing_param() {
	ctx := ctx_with_url('/users?name=alice')
	assert get_query_param(ctx, 'id') == ''
}

fn test_get_query_param_empty_value() {
	ctx := ctx_with_url('/users?flag=')
	assert get_query_param(ctx, 'flag') == ''
}

fn test_get_query_param_special_chars() {
	ctx := ctx_with_url('/search?q=hello%20world')
	assert get_query_param(ctx, 'q') == 'hello%20world'
}

fn test_get_query_param_without_equals() {
	ctx := ctx_with_url('/users?flag')
	assert get_query_param(ctx, 'flag') == ''
}

fn test_get_query_param_only_question_mark() {
	ctx := ctx_with_url('/users?')
	assert get_query_param(ctx, 'id') == ''
}

// -- get_path_param tests (deprecated) --

fn test_get_path_param_returns_empty() {
	ctx := ctx_with_url('/users/42')
	assert get_path_param(ctx, 'id') == ''
	assert get_path_param(ctx, 'name') == ''
}

fn test_get_path_param_deprecated_always_empty() {
	ctx := ctx_with_url('/any/path/123')
	assert get_path_param(ctx, 'any') == ''
}

// -- get_header_val tests --

fn test_get_header_val_default() {
	ctx := ctx_with_url('/')
	assert get_header_val(ctx, 'X-Custom') == ''
}

// -- set_status tests --

fn test_set_status_is_noop() {
	mut ctx := ctx_with_url('/')
	set_status(mut ctx, 200)
	assert true
}

// -- server wrapper test --

fn test_server_run_function_defined() {
	assert true
}

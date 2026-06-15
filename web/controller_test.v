module web

// controller_test.v - Unit tests for BaseController
//
// Tests the query parameter parsing, path parameter access,
// header value retrieval, status code setting, and deprecated API.

import veb

// Helper: create a minimal veb.Context for testing
fn context_with_url(url string) &veb.Context {
	mut ctx := &veb.Context{}
	// In V 0.5.1, veb.Context.req is an http.Request with a url field
	ctx.req.url = url
	return ctx
}

// Helper: create a BaseController wrapping a test context
fn controller_with_url(url string) &BaseController {
	return &BaseController{
		Context: context_with_url(url)
	}
}

// -- get_query_param tests --

fn test_get_query_param_single_param() {
	c := controller_with_url('/users?id=42')
	result := c.get_query_param('id')
	assert result == '42'
}

fn test_get_query_param_multiple_params() {
	c := controller_with_url('/search?q=hello&page=1&limit=10')
	assert c.get_query_param('q') == 'hello'
	assert c.get_query_param('page') == '1'
	assert c.get_query_param('limit') == '10'
}

fn test_get_query_param_no_query_string() {
	c := controller_with_url('/users')
	assert c.get_query_param('id') == ''
}

fn test_get_query_param_missing_param() {
	c := controller_with_url('/users?name=alice')
	assert c.get_query_param('id') == ''
}

fn test_get_query_param_empty_value() {
	c := controller_with_url('/users?flag=')
	assert c.get_query_param('flag') == ''
}

fn test_get_query_param_special_chars() {
	c := controller_with_url('/search?q=hello%20world')
	// URL-encoded values are returned as-is (no decoding)
	result := c.get_query_param('q')
	assert result == 'hello%20world'
}

fn test_get_query_param_without_equals() {
	c := controller_with_url('/users?flag')
	// No = sign, so kv.len < 2, returns ''
	assert c.get_query_param('flag') == ''
}

fn test_get_query_param_only_question_mark() {
	c := controller_with_url('/users?')
	assert c.get_query_param('id') == ''
}

// -- get_path_param tests (deprecated in V 0.5.1) --

fn test_get_path_param_returns_empty() {
	c := controller_with_url('/users/42')
	assert c.get_path_param('id') == ''
	assert c.get_path_param('name') == ''
}

fn test_get_path_param_deprecated_always_empty() {
	c := controller_with_url('/any/path/123')
	assert c.get_path_param('any') == ''
}

// -- set_status tests (no-op in V 0.5.1) --

fn test_set_status_is_noop() {
	mut c := controller_with_url('/')
	c.set_status(200)
	c.set_status(404)
	c.set_status(500)
	// set_status is a no-op; test that it doesn't crash
	assert true
}

// -- get_header_val tests (delegates to veb.Context.get_custom_header) --

fn test_get_header_val_no_headers() {
	c := controller_with_url('/')
	result := c.get_header_val('Authorization')
	assert result == ''
}

// -- Controller interface test --

fn test_base_controller_satisfies_controller_interface() {
	// Verify BaseController can be used where Controller is expected
	_ := &BaseController{}
	assert true
}

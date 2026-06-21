module web

// mockmvc_test.v - Tests for the MockMvc HTTP request simulation tool
//
// Verifies:
//   - MockMvc creation and handler registration (GET, POST, PUT, DELETE, PATCH)
//   - perform() dispatches requests to the correct handler
//   - 404 returned for unknown routes
//   - MockResult assertion methods (status, header, json_contains, body_contains)
//   - Assertion failures return errors (negative tests)

// ============================================================
// Handler Helpers — reusable handlers for tests
// ============================================================

// handler returning a simple 200 JSON response
fn ok_json_handler(req MockRequest) !MockResult {
	return MockResult{
		status:  200
		body:    '{"status":"ok","method":"${req.method}"}'
		headers: {
			'Content-Type': 'application/json'
		}
	}
}

// handler echoing the request body back with 201
fn echo_post_handler(req MockRequest) !MockResult {
	return MockResult{
		status:  201
		body:    req.body
		headers: {
			'Content-Type': 'application/json'
			'X-Handler':    'echo'
		}
	}
}

// handler returning nested JSON for path navigation tests
fn nested_json_handler(req MockRequest) !MockResult {
	return MockResult{
		status:  200
		body:    '{"data":{"user":{"name":"Alice","role":"admin"},"items":["a","b","c"]}}'
		headers: {
			'Content-Type': 'application/json'
		}
	}
}

// handler that returns a Photon Result via mock_result_from_result
fn photon_result_handler(req MockRequest) !MockResult {
	return mock_result_from_result(ok('{"id":1,"name":"Bob"}'))
}

// handler that returns not_found Result
fn not_found_handler(req MockRequest) !MockResult {
	return mock_result_from_result(not_found('user not found'))
}

// ============================================================
// MockMvc Construction Tests
// ============================================================

fn test_mockmvc_new() {
	mvc := new_mockmvc()
	assert mvc != unsafe { nil }
	assert mvc.handlers.len == 0
}

fn test_mockmvc_register_get() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)
	assert mvc.handlers.len == 1
	assert 'GET /users' in mvc.handlers
}

fn test_mockmvc_register_post() {
	mut mvc := new_mockmvc()
	mvc.post('/users', echo_post_handler)
	assert mvc.handlers.len == 1
	assert 'POST /users' in mvc.handlers
}

fn test_mockmvc_register_multiple() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)
	mvc.post('/users', echo_post_handler)
	mvc.put('/users/1', ok_json_handler)
	mvc.delete('/users/1', ok_json_handler)
	mvc.patch('/users/1', ok_json_handler)
	assert mvc.handlers.len == 5
}

fn test_mockmvc_route_method() {
	mut mvc := new_mockmvc()
	mvc.route('GET', '/custom', ok_json_handler)
	assert mvc.handlers.len == 1
	assert 'GET /custom' in mvc.handlers
}

// ============================================================
// perform() Dispatch Tests
// ============================================================

fn test_mockmvc_perform_get() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/users'
	})!

	result.assert_status(200)!
	result.assert_ok()!
	result.assert_body_contains('"status":"ok"')!
}

fn test_mockmvc_perform_post_with_body() {
	mut mvc := new_mockmvc()
	mvc.post('/users', echo_post_handler)

	req := MockRequest{
		method: 'POST'
		path:   '/users'
		body:   '{"name":"Alice","age":30}'
	}
	result := mvc.perform(req)!

	result.assert_status(201)!
	result.assert_created()!
	result.assert_body('{"name":"Alice","age":30}')!
	result.assert_body_contains('Alice')!
}

fn test_mockmvc_perform_put() {
	mut mvc := new_mockmvc()
	mvc.put('/users/1', ok_json_handler)

	result := mvc.perform(MockRequest{
		method: 'PUT'
		path:   '/users/1'
	})!

	result.assert_status(200)!
	result.assert_json_contains('method', 'PUT')!
}

fn test_mockmvc_perform_delete() {
	mut mvc := new_mockmvc()
	mvc.delete('/users/1', ok_json_handler)

	result := mvc.perform(MockRequest{
		method: 'DELETE'
		path:   '/users/1'
	})!

	result.assert_status(200)!
	result.assert_json_contains('method', 'DELETE')!
}

fn test_mockmvc_perform_patch() {
	mut mvc := new_mockmvc()
	mvc.patch('/users/1', ok_json_handler)

	result := mvc.perform(MockRequest{
		method: 'PATCH'
		path:   '/users/1'
	})!

	result.assert_status(200)!
	result.assert_json_contains('method', 'PATCH')!
}

// ============================================================
// 404 Not Found Tests
// ============================================================

fn test_mockmvc_unknown_route_returns_404() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)

	// Unknown path
	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/unknown'
	})!

	result.assert_status(404)!
	result.assert_not_found()!
	result.assert_body_contains('Not Found')!
}

fn test_mockmvc_unknown_method_returns_404() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)

	// POST to a GET-only route
	result := mvc.perform(MockRequest{
		method: 'POST'
		path:   '/users'
	})!

	result.assert_status(404)!
}

fn test_mockmvc_empty_handlers_returns_404() {
	mvc := new_mockmvc()

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/anything'
	})!

	result.assert_not_found()!
}

// ============================================================
// Header Assertion Tests
// ============================================================

fn test_mockmvc_assert_header_present() {
	mut mvc := new_mockmvc()
	mvc.post('/echo', echo_post_handler)

	result := mvc.perform(MockRequest{
		method: 'POST'
		path:   '/echo'
		body:   'hello'
	})!

	result.assert_header('Content-Type', 'application/json')!
	result.assert_header('X-Handler', 'echo')!
}

fn test_mockmvc_assert_header_missing_returns_error() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/users'
	})!

	mut failed := false
	result.assert_header('X-Nonexistent', 'val') or { failed = true }
	assert failed
}

fn test_mockmvc_assert_header_wrong_value_returns_error() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/users'
	})!

	mut failed := false
	result.assert_header('Content-Type', 'text/html') or { failed = true }
	assert failed
}

// ============================================================
// JSON Path Assertion Tests (assert_json_contains)
// ============================================================

fn test_mockmvc_assert_json_contains_simple() {
	mut mvc := new_mockmvc()
	mvc.get('/data', nested_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/data'
	})!

	result.assert_json_contains('data.user.name', 'Alice')!
	result.assert_json_contains('data.user.role', 'admin')!
}

fn test_mockmvc_assert_json_contains_array_index() {
	mut mvc := new_mockmvc()
	mvc.get('/data', nested_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/data'
	})!

	result.assert_json_contains('data.items.0', 'a')!
	result.assert_json_contains('data.items.1', 'b')!
	result.assert_json_contains('data.items.2', 'c')!
}

fn test_mockmvc_assert_json_contains_wrong_value_returns_error() {
	mut mvc := new_mockmvc()
	mvc.get('/data', nested_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/data'
	})!

	mut failed := false
	result.assert_json_contains('data.user.name', 'Bob') or { failed = true }
	assert failed
}

fn test_mockmvc_assert_json_contains_missing_path_returns_error() {
	mut mvc := new_mockmvc()
	mvc.get('/data', nested_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/data'
	})!

	mut failed := false
	result.assert_json_contains('data.user.email', 'x@y.com') or { failed = true }
	assert failed
}

// ============================================================
// Body Assertion Tests
// ============================================================

fn test_mockmvc_assert_body_contains_success() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/users'
	})!

	result.assert_body_contains('ok')!
	result.assert_body_contains('status')!
}

fn test_mockmvc_assert_body_contains_failure() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/users'
	})!

	mut failed := false
	result.assert_body_contains('nonexistent') or { failed = true }
	assert failed
}

fn test_mockmvc_assert_body_exact() {
	mut mvc := new_mockmvc()
	mvc.post('/echo', echo_post_handler)

	result := mvc.perform(MockRequest{
		method: 'POST'
		path:   '/echo'
		body:   'exact body'
	})!

	result.assert_body('exact body')!
}

fn test_mockmvc_assert_body_exact_failure() {
	mut mvc := new_mockmvc()
	mvc.post('/echo', echo_post_handler)

	result := mvc.perform(MockRequest{
		method: 'POST'
		path:   '/echo'
		body:   'actual body'
	})!

	mut failed := false
	result.assert_body('expected body') or { failed = true }
	assert failed
}

// ============================================================
// Photon Result Integration Tests
// ============================================================

fn test_mockmvc_with_photon_result_ok() {
	mut mvc := new_mockmvc()
	mvc.get('/user/1', photon_result_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/user/1'
	})!

	result.assert_ok()!
	result.assert_json_contains('id', '1')!
	result.assert_json_contains('name', 'Bob')!
}

fn test_mockmvc_with_photon_result_not_found() {
	mut mvc := new_mockmvc()
	mvc.get('/user/999', not_found_handler)

	result := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/user/999'
	})!

	result.assert_not_found()!
}

// ============================================================
// mock_request Helper Tests
// ============================================================

fn test_mock_request_helper() {
	req := mock_request('GET', '/test')
	assert req.method == 'GET'
	assert req.path == '/test'
	assert req.headers.len == 0
	assert req.query.len == 0
	assert req.body == ''
}

fn test_mock_request_with_custom_data() {
	mut req := mock_request('POST', '/submit')
	req.body = '{"key":"value"}'
	req.headers['Content-Type'] = 'application/json'
	req.query['debug'] = '1'

	mut mvc := new_mockmvc()
	mvc.post('/submit', echo_post_handler)

	result := mvc.perform(req)!

	result.assert_status(201)!
	result.assert_body('{"key":"value"}')!
}

// ============================================================
// Chaining / Multiple Assertions Tests
// ============================================================

fn test_mockmvc_multiple_assertions() {
	mut mvc := new_mockmvc()
	mvc.post('/echo', echo_post_handler)

	result := mvc.perform(MockRequest{
		method: 'POST'
		path:   '/echo'
		body:   '{"name":"Alice"}'
	})!

	// Chain multiple assertions
	result.assert_status(201)!
	result.assert_created()!
	result.assert_header('Content-Type', 'application/json')!
	result.assert_header('X-Handler', 'echo')!
	result.assert_body_contains('Alice')!
	result.assert_body('{"name":"Alice"}')!
}

fn test_mockmvc_multiple_routes() {
	mut mvc := new_mockmvc()
	mvc.get('/users', ok_json_handler)
	mvc.post('/users', echo_post_handler)
	mvc.get('/data', nested_json_handler)

	// GET /users
	r1 := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/users'
	})!
	r1.assert_ok()!
	r1.assert_json_contains('status', 'ok')!

	// POST /users
	r2 := mvc.perform(MockRequest{
		method: 'POST'
		path:   '/users'
		body:   'created'
	})!
	r2.assert_created()!
	r2.assert_body('created')!

	// GET /data
	r3 := mvc.perform(MockRequest{
		method: 'GET'
		path:   '/data'
	})!
	r3.assert_ok()!
	r3.assert_json_contains('data.user.name', 'Alice')!
}

// ============================================================
// mock_result_from_result Tests
// ============================================================

fn test_mock_result_from_result_ok() {
	r := ok('{"status":"ok"}')
	mr := mock_result_from_result(r)
	assert mr.status == 200
	assert mr.body == '{"status":"ok"}'
	assert mr.headers['Content-Type'] == 'application/json'
}

fn test_mock_result_from_result_created() {
	r := created('{"id":1}')
	mr := mock_result_from_result(r)
	assert mr.status == 201
	assert mr.body == '{"id":1}'
}

fn test_mock_result_from_result_not_found() {
	r := not_found('missing')
	mr := mock_result_from_result(r)
	assert mr.status == 404
	assert mr.body == 'missing'
}

fn test_mock_result_from_result_error() {
	r := fail(422, 'validation error')
	mr := mock_result_from_result(r)
	assert mr.status == 422
	assert mr.body == 'validation error'
}

// ============================================================
// Status Assertion Failure Tests
// ============================================================

fn test_assert_status_failure_returns_error() {
	r := MockResult{
		status: 200
		body:   ''
	}
	mut failed := false
	r.assert_status(404) or { failed = true }
	assert failed
}

fn test_assert_ok_failure_returns_error() {
	r := MockResult{
		status: 500
		body:   ''
	}
	mut failed := false
	r.assert_ok() or { failed = true }
	assert failed
}

fn test_assert_not_found_failure_returns_error() {
	r := MockResult{
		status: 200
		body:   ''
	}
	mut failed := false
	r.assert_not_found() or { failed = true }
	assert failed
}

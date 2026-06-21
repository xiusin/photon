module web

// testing_test.v - Tests for the fluent HTTP testing helpers

// ============================================================
// Status Assertion Tests
// ============================================================

fn test_response_assert_status() {
	mut r := response_from_raw(200, 'ok')
	r.assert_status(200)
}

fn test_response_assert_ok() {
	mut r := response_from_raw(200, 'ok')
	r.assert_ok()
}

fn test_response_assert_created() {
	mut r := response_from_raw(201, 'created')
	r.assert_created()
}

fn test_response_assert_accepted() {
	mut r := response_from_raw(202, 'accepted')
	r.assert_accepted()
}

fn test_response_assert_no_content() {
	mut r := response_from_raw(204, '')
	r.assert_no_content()
}

fn test_response_assert_bad_request() {
	mut r := response_from_raw(400, 'bad')
	r.assert_bad_request()
}

fn test_response_assert_unauthorized() {
	mut r := response_from_raw(401, 'unauthorized')
	r.assert_unauthorized()
}

fn test_response_assert_payment_required() {
	mut r := response_from_raw(402, 'payment required')
	r.assert_payment_required()
}

fn test_response_assert_forbidden() {
	mut r := response_from_raw(403, 'forbidden')
	r.assert_forbidden()
}

fn test_response_assert_not_found() {
	mut r := response_from_raw(404, 'not found')
	r.assert_not_found()
}

fn test_response_assert_method_not_allowed() {
	mut r := response_from_raw(405, 'method not allowed')
	r.assert_method_not_allowed()
}

fn test_response_assert_conflict() {
	mut r := response_from_raw(409, 'conflict')
	r.assert_conflict()
}

fn test_response_assert_unprocessable() {
	mut r := response_from_raw(422, 'unprocessable')
	r.assert_unprocessable()
}

fn test_response_assert_too_many_requests() {
	mut r := response_from_raw(429, 'too many')
	r.assert_too_many_requests()
}

fn test_response_assert_internal_error() {
	mut r := response_from_raw(500, 'error')
	r.assert_internal_error()
}

fn test_response_assert_service_unavailable() {
	mut r := response_from_raw(503, 'unavailable')
	r.assert_service_unavailable()
}

// ============================================================
// Range Assertion Tests
// ============================================================

fn test_response_assert_successful() {
	mut r1 := response_from_raw(200, 'ok')
	r1.assert_successful()

	mut r2 := response_from_raw(201, 'created')
	r2.assert_successful()

	mut r3 := response_from_raw(299, 'custom')
	r3.assert_successful()
}

fn test_response_assert_failed() {
	mut r1 := response_from_raw(400, 'bad')
	r1.assert_failed()

	mut r2 := response_from_raw(500, 'error')
	r2.assert_failed()
}

fn test_response_assert_client_error() {
	mut r1 := response_from_raw(400, 'bad')
	r1.assert_client_error()

	mut r2 := response_from_raw(499, 'custom')
	r2.assert_client_error()
}

fn test_response_assert_server_error() {
	mut r1 := response_from_raw(500, 'error')
	r1.assert_server_error()

	mut r2 := response_from_raw(503, 'unavailable')
	r2.assert_server_error()
}

// ============================================================
// Redirect Tests
// ============================================================

fn test_response_assert_redirect() {
	mut r := response_with_headers(302, '', {
		'Location': '/login'
	})
	r.assert_redirect('/login')
}

fn test_response_assert_redirect_noloc() {
	mut r := response_from_raw(301, '')
	r.assert_redirect('')
}

// ============================================================
// Body Assertion Tests
// ============================================================

fn test_response_assert_body() {
	mut r := response_from_raw(200, 'Hello, World!')
	r.assert_body('Hello, World!')
}

fn test_response_assert_body_contains() {
	mut r := response_from_raw(200, 'Hello, Photon World!')
	r.assert_body_contains('Photon')
}

fn test_response_assert_body_missing() {
	mut r := response_from_raw(200, 'Hello, World!')
	r.assert_body_missing('Error')
}

// ============================================================
// JSON Assertion Tests
// ============================================================

fn test_response_assert_json_exact_match() {
	mut r := response_from_raw(200, '{"name":"Alice","age":"30"}')
	r.assert_json('{"name":"Alice","age":"30"}')
}

fn test_response_assert_json_different_order() {
	mut r := response_from_raw(200, '{"age":"30","name":"Alice"}')
	// JSON comparison should be order-independent
	r.assert_json('{"name":"Alice","age":"30"}')
}

fn test_response_assert_json_path_simple() {
	mut r := response_from_raw(200, '{"name":"Alice","email":"alice@example.com"}')
	r.assert_json_path('name', 'Alice')
	r.assert_json_path('email', 'alice@example.com')
}

fn test_response_assert_json_path_nested() {
	mut r := response_from_raw(200, '{"user":{"name":"Bob","role":"admin"}}')
	r.assert_json_path('user.name', 'Bob')
	r.assert_json_path('user.role', 'admin')
}

fn test_response_assert_json_path_deep() {
	mut r := response_from_raw(200, '{"data":{"users":{"0":{"name":"Alice"}}}}')
	r.assert_json_path('data.users.0.name', 'Alice')
}

fn test_response_assert_json_missing_path() {
	mut r := response_from_raw(200, '{"name":"Alice"}')
	r.assert_json_missing('email')
	r.assert_json_missing('user.name')
}

fn test_response_assert_json_structure() {
	mut r := response_from_raw(200, '{"name":"Alice","email":"alice@example.com","role":"admin"}')
	r.assert_json_structure(['name'])
	r.assert_json_structure(['name', 'email'])
	r.assert_json_structure(['name', 'email', 'role'])
}

fn test_response_assert_json_count_root_array() {
	mut r := response_from_raw(200, '["a","b","c"]')
	r.assert_json_count('', 3)
}

fn test_response_assert_json_count_root_object() {
	mut r := response_from_raw(200, '{"a":1,"b":2,"c":3}')
	r.assert_json_count('', 3)
}

fn test_response_assert_json_count_empty_array() {
	mut r := response_from_raw(200, '[]')
	r.assert_json_count('', 0)
}

fn test_response_assert_json_count_single_array() {
	mut r := response_from_raw(200, '["only"]')
	r.assert_json_count('', 1)
}

fn test_response_assert_json_count_nested_array() {
	mut r := response_from_raw(200, '{"data":{"items":["a","b","c"]}}')
	r.assert_json_count('data.items', 3)
}

fn test_response_assert_json_count_nested_empty_array() {
	mut r := response_from_raw(200, '{"data":{"items":[]}}')
	r.assert_json_count('data.items', 0)
}

fn test_response_assert_json_count_nested_object() {
	mut r := response_from_raw(200, '{"data":{"meta":{"page":"1","total":"30"}}}')
	r.assert_json_count('data.meta', 2)
}

// ============================================================
// Header Assertion Tests
// ============================================================

fn test_response_assert_header() {
	mut r := response_with_headers(200, 'ok', {
		'X-Request-ID': 'abc-123'
	})
	r.assert_header('X-Request-ID', 'abc-123')
}

fn test_response_assert_header_missing() {
	mut r := response_with_headers(200, 'ok', {
		'X-Custom': 'value'
	})
	r.assert_header_missing('X-Request-ID')
}

fn test_response_assert_content_type() {
	mut r := response_from_raw(200, 'ok')
	r.content_type = 'application/json; charset=utf-8'
	r.assert_content_type('application/json')
}

// ============================================================
// Header Builder Test
// ============================================================

fn test_response_with_header_builder() {
	mut r := response_from_raw(200, 'ok')
	r.with_header('X-Custom', 'value')
	r.assert_header('X-Custom', 'value')
}

// ============================================================
// Result Integration Test
// ============================================================

fn test_response_from_result_ok() {
	result := ok('{"status":"ok"}')
	mut r := response_from_result(result)
	r.assert_ok()
	r.assert_json('{"status":"ok"}')
}

fn test_response_from_result_created() {
	result := created('{"id":1}')
	mut r := response_from_result(result)
	r.assert_created()
}

fn test_response_from_result_not_found() {
	result := not_found('user not found')
	mut r := response_from_result(result)
	r.assert_not_found()
	r.assert_failed()
}

fn test_response_from_result_error() {
	result := fail(422, 'validation error')
	mut r := response_from_result(result)
	r.assert_unprocessable()
	r.assert_client_error()
}

// ============================================================
// Chaining Tests (Fluent API)
// ============================================================

fn test_response_sequential_multiple_assertions() {
	result := ok('{"name":"Alice","age":"30"}')
	mut r := response_from_result(result)
	r.assert_ok()
	r.assert_successful()
	r.assert_json_structure(['name', 'age'])
	r.assert_json_path('name', 'Alice')
	r.assert_json_path('age', '30')
}

fn test_response_sequential_with_body_checks() {
	mut r := response_from_raw(200, 'Hello, Photon!')
	r.assert_status(200)
	r.assert_body_contains('Photon')
	r.assert_body_missing('Error')
}

fn test_response_sequential_with_headers() {
	mut r := response_with_headers(301, '', {
		'Location': '/dashboard'
	})
	r.assert_redirect('/dashboard')
	r.with_header('X-Custom', 'test')
	r.assert_header('X-Custom', 'test')
}

// ============================================================
// Alias Tests
// ============================================================

fn test_response_aliases() {
	mut r := response_from_raw(200, 'ok')
	r.assert_is_ok()

	mut r2 := response_from_raw(201, 'created')
	r2.assert_is_created()

	mut r3 := response_from_raw(204, '')
	r3.assert_is_no_content()

	mut r4 := response_from_raw(400, 'bad')
	r4.assert_is_bad_request()

	mut r5 := response_from_raw(404, 'not found')
	r5.assert_is_not_found()
}

// ============================================================
// JSON Path Navigation Edge Cases
// ============================================================

fn test_json_path_get_numeric_value() {
	mut r := response_from_raw(200, '{"count":"42"}')
	r.assert_json_path('count', '42')
}

fn test_json_path_get_empty_object() {
	mut r := response_from_raw(200, '{}')
	r.assert_json_path('name', '')
}

fn test_json_path_get_boolean() {
	mut r := response_from_raw(200, '{"active":"true"}')
	r.assert_json_path('active', 'true')
}

fn test_json_path_get_numeric_zero() {
	mut r := response_from_raw(200, '{"count":0}')
	r.assert_json_path('count', '0')
}

fn test_json_path_get_boolean_false() {
	mut r := response_from_raw(200, '{"active":false}')
	r.assert_json_path('active', 'false')
}

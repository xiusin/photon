module web

// testing.v - Fluent HTTP Testing Helpers
//
// Provides Laravel-inspired fluent HTTP test assertion methods for
// TDD-style development. Build test responses from web.Result or raw
// values, then chain assertions for clean, readable tests.
//
// Usage:
//   import photon.web
//
//   // From a controller result:
//   result := my_controller.index()
//   web.response_from_result(result)
//       .assert_ok()
//       .assert_json_path('users.0.name', 'Alice')
//
//   // From raw values:
//   web.response_from_raw(200, '{"ok":true}')
//       .assert_status(200)
//       .assert_json('{"ok":true}')
//
//   // With headers:
//   web.response_with_headers(302, '', {'Location': '/login'})
//       .assert_redirect('/login')
//       .dump()
import json2
import math

// TestResponse wraps an HTTP response for fluent assertions.
// All assertion methods return &TestResponse so you can chain them.
@[heap]
pub struct TestResponse {
pub mut:
	status       int
	body         string
	headers      map[string]string
	content_type string = 'application/json'
}

// response_from_result creates a TestResponse from a web.Result
pub fn response_from_result(result Result) &TestResponse {
	return &TestResponse{
		status: result.code
		body:   result.data
	}
}

// response_from_raw creates a TestResponse from raw status and body
pub fn response_from_raw(status int, body string) &TestResponse {
	return &TestResponse{
		status: status
		body:   body
	}
}

// response_with_headers creates a TestResponse with custom headers
pub fn response_with_headers(status int, body string, headers map[string]string) &TestResponse {
	return &TestResponse{
		status:  status
		body:    body
		headers: headers
	}
}

// with_header adds a header to the response (fluent builder)
pub fn (mut tr TestResponse) with_header(key string, value string) &TestResponse {
	tr.headers[key] = value
	return tr
}

// ============================================================
// Status Assertions
// ============================================================

// assert_status asserts the exact HTTP status code
pub fn (mut tr TestResponse) assert_status(expected int) &TestResponse {
	assert tr.status == expected, 'Expected status ${expected} but got ${tr.status}. Body: ${tr.body}'
	return tr
}

// assert_successful asserts the status is in the 2xx range
pub fn (mut tr TestResponse) assert_successful() &TestResponse {
	assert tr.status >= 200 && tr.status < 300, 'Expected successful status (2xx) but got ${tr.status}'

	return tr
}

// assert_ok asserts the status is 200 OK
pub fn (mut tr TestResponse) assert_ok() &TestResponse {
	return tr.assert_status(200)
}

// assert_created asserts the status is 201 Created
pub fn (mut tr TestResponse) assert_created() &TestResponse {
	return tr.assert_status(201)
}

// assert_accepted asserts the status is 202 Accepted
pub fn (mut tr TestResponse) assert_accepted() &TestResponse {
	return tr.assert_status(202)
}

// assert_no_content asserts the status is 204 No Content
pub fn (mut tr TestResponse) assert_no_content() &TestResponse {
	return tr.assert_status(204)
}

// assert_redirect asserts the status is in the 3xx range and optionally
// checks the Location header
pub fn (mut tr TestResponse) assert_redirect(location string) &TestResponse {
	assert tr.status >= 300 && tr.status < 400, 'Expected redirect status (3xx) but got ${tr.status}'

	if location.len > 0 {
		loc := tr.headers['Location'] or { '' }
		assert loc == location, 'Expected redirect to "${location}" but got "${loc}"'
	}
	return tr
}

// assert_bad_request asserts the status is 400 Bad Request
pub fn (mut tr TestResponse) assert_bad_request() &TestResponse {
	return tr.assert_status(400)
}

// assert_unauthorized asserts the status is 401 Unauthorized
pub fn (mut tr TestResponse) assert_unauthorized() &TestResponse {
	return tr.assert_status(401)
}

// assert_payment_required asserts the status is 402 Payment Required
pub fn (mut tr TestResponse) assert_payment_required() &TestResponse {
	return tr.assert_status(402)
}

// assert_forbidden asserts the status is 403 Forbidden
pub fn (mut tr TestResponse) assert_forbidden() &TestResponse {
	return tr.assert_status(403)
}

// assert_not_found asserts the status is 404 Not Found
pub fn (mut tr TestResponse) assert_not_found() &TestResponse {
	return tr.assert_status(404)
}

// assert_method_not_allowed asserts the status is 405 Method Not Allowed
pub fn (mut tr TestResponse) assert_method_not_allowed() &TestResponse {
	return tr.assert_status(405)
}

// assert_conflict asserts the status is 409 Conflict
pub fn (mut tr TestResponse) assert_conflict() &TestResponse {
	return tr.assert_status(409)
}

// assert_unprocessable asserts the status is 422 Unprocessable Entity
pub fn (mut tr TestResponse) assert_unprocessable() &TestResponse {
	return tr.assert_status(422)
}

// assert_too_many_requests asserts the status is 429 Too Many Requests
pub fn (mut tr TestResponse) assert_too_many_requests() &TestResponse {
	return tr.assert_status(429)
}

// assert_internal_error asserts the status is 500 Internal Server Error
pub fn (mut tr TestResponse) assert_internal_error() &TestResponse {
	return tr.assert_status(500)
}

// assert_service_unavailable asserts the status is 503 Service Unavailable
pub fn (mut tr TestResponse) assert_service_unavailable() &TestResponse {
	return tr.assert_status(503)
}

// assert_failed asserts the status is in the 4xx or 5xx range
pub fn (mut tr TestResponse) assert_failed() &TestResponse {
	assert tr.status >= 400, 'Expected failed status (4xx/5xx) but got ${tr.status}'

	return tr
}

// assert_client_error asserts the status is in the 4xx range
pub fn (mut tr TestResponse) assert_client_error() &TestResponse {
	assert tr.status >= 400 && tr.status < 500, 'Expected client error (4xx) but got ${tr.status}'

	return tr
}

// assert_server_error asserts the status is in the 5xx range
pub fn (mut tr TestResponse) assert_server_error() &TestResponse {
	assert tr.status >= 500, 'Expected server error (5xx) but got ${tr.status}'

	return tr
}

// ============================================================
// Body Assertions
// ============================================================

// assert_body asserts the body equals the expected string exactly
pub fn (mut tr TestResponse) assert_body(expected string) &TestResponse {
	assert tr.body == expected, 'Body mismatch.\nExpected: ${expected}\nActual:   ${tr.body}'

	return tr
}

// assert_body_contains asserts the body contains the expected substring
pub fn (mut tr TestResponse) assert_body_contains(expected string) &TestResponse {
	assert tr.body.contains(expected), 'Expected body to contain "${expected}" but body is:\n${tr.body}'

	return tr
}

// assert_body_missing asserts the body does NOT contain the given substring
pub fn (mut tr TestResponse) assert_body_missing(needle string) &TestResponse {
	assert !tr.body.contains(needle), 'Expected body to NOT contain "${needle}" but it does'

	return tr
}

// ============================================================
// JSON Assertions
// ============================================================

// assert_json asserts the body JSON matches the expected JSON string.
// Both sides are parsed into json2.Any and compared deeply, so key ordering
// doesn't matter and nested objects/arrays/numbers are compared properly
// (the old map[string]string comparison flattened every leaf to a string).
pub fn (mut tr TestResponse) assert_json(expected string) &TestResponse {
	expected_doc := json_parse_any(expected) or {
		assert false, 'assert_json: invalid expected JSON.\nExpected: ${expected}'
		return tr
	}
	actual_doc := json_parse_any(tr.body) or {
		assert false, 'assert_json: invalid response JSON.\nBody: ${tr.body}'
		return tr
	}

	if json_any_equal(expected_doc, actual_doc) {
		return tr
	}
	assert false, 'JSON mismatch.\nExpected: ${expected}\nActual:   ${tr.body}'
	return tr
}

// json_any_equal compares two parsed JSON documents structurally.
//
// Numbers are compared through their float64 value so that `1` and `1.0`
// match, mirroring how a JSON consumer sees them.
fn json_any_equal(a json2.Any, b json2.Any) bool {
	return match a {
		map[string]json2.Any {
			bm := b as map[string]json2.Any
			if a.len != bm.len {
				return false
			}
			for key, av in a {
				if key !in bm {
					return false
				}
				if !json_any_equal(av, bm[key]) {
					return false
				}
			}
			true
		}
		[]json2.Any {
			barr := b as []json2.Any
			if a.len != barr.len {
				return false
			}
			for i in 0 .. a.len {
				if !json_any_equal(a[i], barr[i]) {
					return false
				}
			}
			true
		}
		string {
			b is string && a == b
		}
		bool {
			b is bool && a == b
		}
		i8, i16, int, i64, u8, u16, u32, u64, f32, f64 {
			json_number_of(b) == json_number_of(a)
		}
		else {
			false
		}
	}
}

// safe_nan produces a NaN at runtime so the compiler does not reject the
// literal division by zero.
fn safe_nan() f64 {
	zero := f64(unsafe { (&u64(0))[0] })
	return zero / zero
}

// json_number_of normalises a numeric json2.Any to f64; non-numbers return NaN
// so that a numeric/string comparison never spuriously matches.
fn json_number_of(v json2.Any) f64 {
	return match v {
		i8 { f64(v) }
		i16 { f64(v) }
		int { f64(v) }
		i64 { f64(v) }
		u8 { f64(v) }
		u16 { f64(v) }
		u32 { f64(v) }
		u64 { f64(v) }
		f32 { f64(v) }
		f64 { v }
		else { safe_nan() }
	}
}

// assert_json_path asserts a value at a dot-notation path within the JSON body.
//
// Path examples:
//   'name'               → root.name
//   'data.users.0.name'  → nested arrays/objects
//   'meta.pagination.total' → deep nesting
//
// Values are compared as strings. For exact type matching, use assert_json.
pub fn (mut tr TestResponse) assert_json_path(path string, expected string) &TestResponse {
	value := json_path_get(tr.body, path)
	assert value == expected, 'assert_json_path("${path}"): expected "${expected}" but got "${value}"'

	return tr
}

// assert_json_missing asserts a dot-notation path does NOT exist in the JSON
pub fn (mut tr TestResponse) assert_json_missing(path string) &TestResponse {
	value := json_path_get(tr.body, path)
	assert value == '', 'assert_json_missing("${path}"): path exists with value "${value}"'

	return tr
}

// assert_json_structure asserts the JSON has specific top-level keys
pub fn (mut tr TestResponse) assert_json_structure(keys []string) &TestResponse {
	present := json_root_keys(tr.body)
	for key in keys {
		assert key in present, 'assert_json_structure: expected key "${key}" in JSON. Keys present: ${present}'
	}
	return tr
}

// assert_json_count asserts the JSON array at the given path has the expected
// length. Use '' (empty string) for root array/object counting.
//
// For root arrays like '["a","b","c"]', pass path ''.
// For root objects like '{"a":1,"b":2}', pass path '' to count top-level keys.
pub fn (mut tr TestResponse) assert_json_count(path string, expected int) &TestResponse {
	root := json_parse_any(tr.body) or {
		assert false, 'assert_json_count: failed to parse JSON. Body: ${tr.body}'
		return tr
	}
	count := if path.len == 0 {
		match root {
			map[string]json2.Any { root.len }
			[]json2.Any { root.len }
			else { 0 }
		}
	} else {
		json_path_count(tr.body, path)
	}
	assert count == expected, 'assert_json_count("${path}"): expected ${expected} items but got ${count}. Body: ${tr.body}'
	return tr
}

// ============================================================
// Header Assertions
// ============================================================

// assert_header asserts a response header value
pub fn (mut tr TestResponse) assert_header(key string, expected string) &TestResponse {
	value := tr.headers[key] or { '' }
	assert value == expected, 'Expected header "${key}" to be "${expected}" but got "${value}"'

	return tr
}

// assert_header_missing asserts a response header is NOT present
pub fn (mut tr TestResponse) assert_header_missing(key string) &TestResponse {
	has := key in tr.headers
	assert !has, 'Expected header "${key}" to be missing but it is present'

	return tr
}

// assert_content_type asserts the Content-Type header
pub fn (mut tr TestResponse) assert_content_type(expected string) &TestResponse {
	mut ct := tr.content_type
	if 'Content-Type' in tr.headers {
		ct = tr.headers['Content-Type']
	}
	assert ct.contains(expected), 'Expected Content-Type to contain "${expected}" but got "${ct}"'

	return tr
}

// ============================================================
// Convenience Assertions
// ============================================================

// assert_is_ok is an alias for assert_ok
pub fn (mut tr TestResponse) assert_is_ok() &TestResponse {
	return tr.assert_ok()
}

// assert_is_created is an alias for assert_created
pub fn (mut tr TestResponse) assert_is_created() &TestResponse {
	return tr.assert_created()
}

// assert_is_no_content is an alias for assert_no_content
pub fn (mut tr TestResponse) assert_is_no_content() &TestResponse {
	return tr.assert_no_content()
}

// assert_is_bad_request is an alias for assert_bad_request
pub fn (mut tr TestResponse) assert_is_bad_request() &TestResponse {
	return tr.assert_bad_request()
}

// assert_is_not_found is an alias for assert_not_found
pub fn (mut tr TestResponse) assert_is_not_found() &TestResponse {
	return tr.assert_not_found()
}

// ============================================================
// Debugging
// ============================================================

// dump prints the response details and returns self for continued chaining
pub fn (mut tr TestResponse) dump() &TestResponse {
	println('')
	println('  ─── TestResponse Dump ───')
	println('  Status:  ${tr.status}')
	println('  Body:    ${tr.body}')
	if tr.headers.len > 0 {
		println('  Headers:')
		for k, v in tr.headers {
			println('    ${k}: ${v}')
		}
	}
	println('  ─────────────────────────')
	println('')
	return tr
}

// ============================================================
// Helpers
// ============================================================

// ── JSON traversal (json2.Any based) ──
//
// These helpers used to hand-parse JSON with string scanning, because the old
// `json` module could only decode into `map[string]string` and silently turned
// every non-string leaf into "". After the move to json2 there is no reason to
// keep a second parser in the test kit: json2.Any models the document exactly,
// so navigation is a straight walk with no quoting/bracket heuristics.

// json_parse_any decodes a JSON document into json2.Any, returning none if the
// text is not valid JSON.
fn json_parse_any(body string) ?json2.Any {
	if body.trim_space().len == 0 {
		return none
	}
	return json2.decode[json2.Any](body) or { return none }
}

// json_navigate walks `path` (dot-notation) into an already-parsed document.
// Numeric segments index arrays, everything else indexes objects.
fn json_navigate(root json2.Any, path string) ?json2.Any {
	if path.len == 0 {
		return root
	}
	mut cur := root
	for part in path.split('.') {
		cur = match cur {
			map[string]json2.Any {
				cur[part] or { return none }
			}
			[]json2.Any {
				if !is_numeric_part(part) {
					return none
				}
				idx := part.int()
				if idx < 0 || idx >= cur.len {
					return none
				}
				cur[idx]
			}
			else {
				return none
			}
		}
	}
	return cur
}

// json_value_to_string renders a leaf as the string the assertions compare
// against. Strings are unquoted; numbers/bools/null render naturally.
fn json_value_to_string(v json2.Any) string {
	return match v {
		string { v }
		bool { v.str() }
		i8, i16, int, i64, u8, u16, u32, u64 { '${v}' }
		// Floating point is rendered without a trailing ".0" so that a JSON
		// integer written by an encoder as 0.0 still compares as "0" — the
		// assertions historically compared textual values.
		f32 { format_json_float(f64(v)) }
		f64 { format_json_float(v) }
		else { '' }
	}
}

// format_json_float renders a float the way a JSON encoder would when the
// value happens to be integral.
fn format_json_float(v f64) string {
	iv := i64(v)
	if v == f64(iv) && math.abs(v) < 1000000000000000.0 {
		return '${iv}'
	}
	return '${v}'
}

// is_numeric_part returns true if the string is a valid non-negative integer.
// Used to distinguish array indices ('0', '1', '42') from map keys ('name').
fn is_numeric_part(s string) bool {
	if s.len == 0 {
		return false
	}
	for ch in s {
		if ch < `0` || ch > `9` {
			return false
		}
	}
	return true
}

// json_path_get traverses a raw JSON string using dot-notation
// and returns the string representation of the value at that path.
//
// Supports:
//   'name'              → root.name
//   'user.email'        → root.user.email
//   'data.items.0.id'   → root.data.items[0].id
//
// Returns '' if the path does not exist, or if the value at the path is an
// object/array (compare those with assert_json / assert_json_count).
fn json_path_get(body string, path string) string {
	root := json_parse_any(body) or { return '' }
	value := json_navigate(root, path) or { return '' }
	return json_value_to_string(value)
}

// json_path_count navigates the JSON body to the given path and returns
// the number of object keys or array elements. Returns 0 for leaves/missing.
fn json_path_count(body string, path string) int {
	root := json_parse_any(body) or { return 0 }
	value := json_navigate(root, path) or { return 0 }
	return match value {
		map[string]json2.Any { value.len }
		[]json2.Any { value.len }
		else { 0 }
	}
}

// json_root_count counts the top level of the document: keys for an object,
// elements for an array.
fn json_root_count(body string) int {
	return json_path_count(body, '')
}

// json_root_keys returns the top-level keys of an object document.
fn json_root_keys(body string) []string {
	root := json_parse_any(body) or { return [] }
	if root is map[string]json2.Any {
		return root.keys()
	}
	return []string{}
}

// ============================================================
// MockMvc — Spring-style HTTP Request Simulation
// ============================================================
//
// Provides a MockMvc test tool inspired by Spring's MockMvc.
// Simulates the full HTTP request lifecycle without actual
// network I/O. Register handlers with get()/post()/etc., then
// call perform() to dispatch a MockRequest and assert on the
// MockResult.
//
// Since Photon's routing is compile-time via veb, MockMvc holds
// handler functions directly (keyed by "METHOD /path") for
// runtime dispatch in tests.
//
// Usage:
//   mut mvc := web.new_mockmvc()
//   mvc.get('/users', fn (req web.MockRequest) !web.MockResult {
//       return web.MockResult{
//           status:  200
//           body:    '{"name":"Alice"}'
//           headers: {'Content-Type': 'application/json'}
//       }
//   })
//   result := mvc.perform(web.MockRequest{method: 'GET', path: '/users'})!
//   result.assert_status(200)!
//   result.assert_json_contains('name', 'Alice')!

// MockRequest represents a simulated HTTP request for testing.
pub struct MockRequest {
pub mut:
	method  string            // HTTP method: GET, POST, PUT, DELETE, PATCH
	path    string            // Request path: /users/123
	headers map[string]string // Request headers
	body    string            // Request body (raw string)
	query   map[string]string // Query parameters
}

// MockResult represents a simulated HTTP response.
pub struct MockResult {
pub mut:
	status  int               // HTTP status code
	body    string            // Response body
	headers map[string]string // Response headers
}

// MockHandler processes a MockRequest and returns a MockResult.
pub type MockHandler = fn (req MockRequest) !MockResult

// MockMvc simulates Spring's MockMvc for testing HTTP request
// handling without actual network I/O.
@[heap]
pub struct MockMvc {
pub mut:
	handlers map[string]MockHandler // key: "METHOD /path"
}

// new_mockmvc creates a new MockMvc instance.
pub fn new_mockmvc() &MockMvc {
	return &MockMvc{
		handlers: map[string]MockHandler{}
	}
}

// mock_request creates a new MockRequest with initialized maps.
pub fn mock_request(method string, path string) MockRequest {
	return MockRequest{
		method:  method
		path:    path
		headers: map[string]string{}
		query:   map[string]string{}
	}
}

// route registers a handler for a method+path combination.
// Returns self for chaining.
pub fn (mut m MockMvc) route(method string, path string, handler MockHandler) &MockMvc {
	key := '${method} ${path}'
	m.handlers[key] = handler
	return m
}

// get registers a GET handler.
pub fn (mut m MockMvc) get(path string, handler MockHandler) &MockMvc {
	return m.route('GET', path, handler)
}

// post registers a POST handler.
pub fn (mut m MockMvc) post(path string, handler MockHandler) &MockMvc {
	return m.route('POST', path, handler)
}

// put registers a PUT handler.
pub fn (mut m MockMvc) put(path string, handler MockHandler) &MockMvc {
	return m.route('PUT', path, handler)
}

// delete registers a DELETE handler.
pub fn (mut m MockMvc) delete(path string, handler MockHandler) &MockMvc {
	return m.route('DELETE', path, handler)
}

// patch registers a PATCH handler.
pub fn (mut m MockMvc) patch(path string, handler MockHandler) &MockMvc {
	return m.route('PATCH', path, handler)
}

// perform dispatches a MockRequest through the registered handlers.
// Returns a 404 MockResult if no handler matches the method+path.
// Simulates the full request lifecycle without network I/O.
pub fn (m &MockMvc) perform(req MockRequest) !MockResult {
	key := '${req.method} ${req.path}'
	handler := m.handlers[key] or {
		return MockResult{
			status:  404
			body:    '{"error":"Not Found","path":"${req.path}"}'
			headers: {
				'Content-Type': 'application/json'
			}
		}
	}
	return handler(req)!
}

// mock_result_from_result converts a Photon Result to a MockResult.
// Useful for writing handlers that return Photon Result values.
// For success results, uses the data field as the body; for error results
// (where data is empty), uses the message field.
pub fn mock_result_from_result(r Result) MockResult {
	body := if r.data.len > 0 { r.data } else { r.message }
	return MockResult{
		status:  r.code
		body:    body
		headers: {
			'Content-Type': 'application/json'
		}
	}
}

// ============================================================
// MockResult Assertion Methods
// ============================================================
//
// These methods return errors (via `!`) instead of using `assert`,
// so failures can be propagated with `!` or handled explicitly.

// assert_status asserts the response status code matches expected.
pub fn (r MockResult) assert_status(expected int) ! {
	if r.status != expected {
		return error('expected status ${expected}, got ${r.status}')
	}
}

// assert_header asserts a response header value matches expected.
pub fn (r MockResult) assert_header(key string, expected string) ! {
	actual := r.headers[key] or { return error('header ${key} not found') }
	if actual != expected {
		return error('expected header ${key}=${expected}, got ${actual}')
	}
}

// assert_json_contains navigates the JSON body to the given dot-notation
// path and asserts the value matches expected.
//
// Path examples:
//   'name'              → root.name
//   'user.email'        → root.user.email
//   'data.items.0.id'   → root.data.items[0].id
pub fn (r MockResult) assert_json_contains(path string, expected string) ! {
	value := json_path_get(r.body, path)
	if value != expected {
		return error('expected JSON path "${path}" to be "${expected}", got "${value}"')
	}
}

// assert_body_contains asserts the body contains the given substring.
pub fn (r MockResult) assert_body_contains(substr string) ! {
	if !r.body.contains(substr) {
		return error('body does not contain "${substr}". Body: ${r.body}')
	}
}

// assert_body asserts the body equals the expected string exactly.
pub fn (r MockResult) assert_body(expected string) ! {
	if r.body != expected {
		return error('expected body "${expected}", got "${r.body}"')
	}
}

// assert_ok asserts the status is 200 OK.
pub fn (r MockResult) assert_ok() ! {
	return r.assert_status(200)
}

// assert_created asserts the status is 201 Created.
pub fn (r MockResult) assert_created() ! {
	return r.assert_status(201)
}

// assert_not_found asserts the status is 404 Not Found.
pub fn (r MockResult) assert_not_found() ! {
	return r.assert_status(404)
}

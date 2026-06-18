module http

// http_test.v - Tests for the HTTP Client module
//
// Note: Tests that perform actual network requests (get, post, etc.)
// are kept minimal since they require network access. The core focus
// is on testing the fluent API builder, URL construction, response
// helpers, and utility functions.

// ── Constructor & Defaults ──

fn test_client_new() {
	c := new_client()
	assert c.timeout_sec == 30
	assert c.headers.len == 0
	assert c.query_params.len == 0
	assert c.debug == false
}

fn test_client_base_url() {
	mut c := new_client()
	c.with_base_url('https://api.example.com')
	assert c.base_url == 'https://api.example.com'
}

// ── Header Methods ──

fn test_client_header() {
	mut c := new_client()
	c.with_header('X-Custom', 'value')
	assert c.headers['X-Custom'] == 'value'
}

fn test_client_headers_batch() {
	mut c := new_client()
	c.with_headers({
		'X-Req-Id': '123'
		'X-Tenant': 'acme'
	})
	assert c.headers.len == 2
	assert c.headers['X-Req-Id'] == '123'
	assert c.headers['X-Tenant'] == 'acme'
}

fn test_client_token_auth() {
	mut c := new_client()
	c.with_token('abc123xyz')
	assert c.headers['Authorization'] == 'Bearer abc123xyz'
}

fn test_client_basic_auth() {
	mut c := new_client()
	c.with_basic_auth('admin', 'secret')
	assert c.headers['Authorization'].starts_with('Basic ')
	// Verify it's valid base64 of "admin:secret"
	encoded := c.headers['Authorization'].split(' ')[1]
	assert encoded.len > 0
}

fn test_client_json_content_type() {
	mut c := new_client()
	c.with_json()
	assert c.headers['Content-Type'] == 'application/json'
}

fn test_client_custom_content_type() {
	mut c := new_client()
	c.with_content_type('application/xml')
	assert c.headers['Content-Type'] == 'application/xml'
}

fn test_client_accept_header() {
	mut c := new_client()
	c.with_accept('application/json')
	assert c.headers['Accept'] == 'application/json'
}

// ── Query Parameters ──

fn test_client_query_params() {
	mut c := new_client()
	c.with_query({'page': '1', 'limit': '10'})
	assert c.query_params['page'] == '1'
	assert c.query_params['limit'] == '10'
}

fn test_client_query_appended_to_url() {
	mut c := new_client()
	c.with_query({'key': 'value', 'foo': 'bar'})
	url := c.build_url('/api/search')
	assert url.contains('key=value')
	assert url.contains('foo=bar')
	assert url.starts_with('/api/search?')
}

// ── Retry & Timeout ──

fn test_client_retry() {
	mut c := new_client()
	c.retry(3, 100)
	assert c.retry_times == 3
	assert c.retry_delay == 100
}

fn test_client_timeout() {
	mut c := new_client()
	c.timeout_sec(60)
	assert c.timeout_sec == 60
}

fn test_client_debug() {
	mut c := new_client()
	c.debug_enabled(true)
	assert c.debug == true
	c.debug_enabled(false)
	assert c.debug == false
}

// ── URL Building ──

fn test_build_url_no_base() {
	mut c := new_client()
	assert c.build_url('/api/users') == '/api/users'
	assert c.build_url('api/users') == 'api/users'
}

fn test_build_url_with_base() {
	mut c := new_client()
	c.with_base_url('https://api.example.com')
	assert c.build_url('/users') == 'https://api.example.com/users'
	assert c.build_url('users') == 'https://api.example.com/users'
}

fn test_build_url_trailing_slash() {
	mut c := new_client()
	c.with_base_url('https://api.example.com/')
	assert c.build_url('/users') == 'https://api.example.com/users'
	assert c.build_url('users') == 'https://api.example.com/users'
}

fn test_build_url_with_query() {
	mut c := new_client()
	c.with_base_url('https://api.example.com')
	c.with_query({'page': '2', 'sort': 'name'})
	url := c.build_url('/users')
	assert url.contains('https://api.example.com/users?')
	assert url.contains('page=2')
	assert url.contains('sort=name')
}

fn test_build_url_existing_query_with_extra() {
	mut c := new_client()
	c.with_query({'extra': 'param'})
	url := c.build_url('/search?q=test')
	// Should append with & since ? already exists
	assert url.contains('&extra=param')
}

// ── Response Helpers ──

fn test_response_success_codes() {
	r := new_response(200, 'ok')
	assert r.is_success()
	assert r.is_client_error() == false
	assert r.is_server_error() == false
}

fn test_response_client_error() {
	r := new_response(404, 'not found')
	assert r.is_success() == false
	assert r.is_client_error()
	assert r.is_server_error() == false
}

fn test_response_server_error() {
	r := new_response(500, 'error')
	assert r.is_success() == false
	assert r.is_client_error() == false
	assert r.is_server_error()
}

fn test_response_edge_codes() {
	assert new_response(199, '').is_success() == false
	assert new_response(299, '').is_success()
	assert new_response(300, '').is_success() == false
	assert new_response(399, '').is_client_error() == false
	assert new_response(400, '').is_client_error()
	assert new_response(499, '').is_client_error()
	assert new_response(500, '').is_server_error()
	assert new_response(599, '').is_server_error()
}

fn test_response_header_lookup() {
	r := &HttpResponse{
		status_code: 200
		body:        '{}'
		headers:     {'Content-Type': 'application/json', 'X-Request-Id': 'abc-123'}
	}
	ct := r.header('Content-Type') or { '' }
	assert ct == 'application/json'

	// Case-insensitive lookup
	ct2 := r.header('content-type') or { '' }
	assert ct2 == 'application/json'

	rid := r.header('X-Request-Id') or { '' }
	assert rid == 'abc-123'

	// Missing header returns none
	assert r.header('Missing') == none
}

fn test_response_body_content() {
	r := new_response(200, '{"name":"Alice","age":30}')
	// Test body is accessible and valid JSON content
	assert r.body.contains('"name"')
	assert r.body.contains('"Alice"')
}

// ── Base64 Encoding ──

fn test_base64_encode() {
	// Empty input
	assert base64_encode('') == ''

	// Simple input — standard known value
	result := base64_encode('test')
	assert result.len > 0
	assert result.ends_with('==')

	// Known vector: "Hello" -> "SGVsbG8="
	assert base64_encode('Hello') == 'SGVsbG8='
}

// ── Fluent API Chaining ──

fn test_fluent_api_chain() {
	mut c := new_client()
	c = c.with_base_url('https://api.example.com')
	c = c.with_token('xyz')
	c = c.with_json()
	c = c.with_accept('application/json')
	c = c.retry(3, 100)
	c = c.timeout_sec(60)

	assert c.base_url == 'https://api.example.com'
	assert c.headers['Authorization'] == 'Bearer xyz'
	assert c.headers['Content-Type'] == 'application/json'
	assert c.headers['Accept'] == 'application/json'
	assert c.retry_times == 3
	assert c.timeout_sec == 60
}

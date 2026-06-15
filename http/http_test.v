module http

// http_test.v - Tests for the HTTP Client module

fn test_client_new() {
	c := new_client()
	assert c.timeout_sec == 30
	assert c.headers.len == 0
}

fn test_client_base_url() {
	mut c := new_client()
	c.with_base_url('https://api.example.com')
	assert c.base_url == 'https://api.example.com'
}

fn test_client_header() {
	mut c := new_client()
	c.with_header('X-Custom', 'value')
	assert c.headers['X-Custom'] == 'value'
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

fn test_client_get() {
	c := new_client()
	resp := c.get('/test') or {
		assert false
		return
	}
	assert resp.is_success()
	assert resp.status_code == 200
	assert resp.body.contains('GET')
}

fn test_client_post() {
	c := new_client()
	resp := c.post('/test', '{"data":"hello"}') or {
		assert false
		return
	}
	assert resp.status_code == 201
}

fn test_client_put() {
	c := new_client()
	resp := c.put('/items/1', '{"name":"updated"}') or {
		assert false
		return
	}
	assert resp.status_code == 200
}

fn test_client_delete() {
	c := new_client()
	resp := c.delete('/items/1') or {
		assert false
		return
	}
	assert resp.status_code == 204
	assert resp.body == ''
}

fn test_client_patch() {
	c := new_client()
	resp := c.patch('/items/1', '{"name":"patched"}') or {
		assert false
		return
	}
	assert resp.status_code == 200
}

fn test_build_url() {
	mut c := new_client()
	
	// No base URL — path used as-is
	assert c.build_url('/api/users') == '/api/users'
	assert c.build_url('api/users') == 'api/users'

	// With base URL
	c.with_base_url('https://api.example.com')
	assert c.build_url('/users') == 'https://api.example.com/users'
	assert c.build_url('users') == 'https://api.example.com/users'

	// Base URL with trailing slash
	c.with_base_url('https://api.example.com/')
	assert c.build_url('/users') == 'https://api.example.com/users'
	assert c.build_url('users') == 'https://api.example.com/users'
}

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

fn test_base64_encode() {
	// Empty input
	assert base64_encode('') == ''

	// Simple input
	result := base64_encode('test')
	assert result.len > 0
	assert result.ends_with('==')
}

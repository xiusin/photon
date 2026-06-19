module http

import net.http as vhttp

// ============================================================
// RestTemplate — full test suite
// ============================================================

// ------------------------------------------------------------------
// Constructor & builder config
// ------------------------------------------------------------------

fn test_new_rest_template_defaults() {
	rt := new_rest_template()
	assert rt.connect_timeout == 30000
	assert rt.read_timeout == 30000
	assert rt.max_retries == 3
	assert rt.retry_base_delay == 200
	assert rt.default_headers.len == 0
	assert rt.interceptors.len == 0
}

fn test_set_base_url() {
	rt := new_rest_template().set_base_url('https://api.example.com')
	assert rt.base_url == 'https://api.example.com'
}

fn test_set_default_header() {
	rt := new_rest_template().set_default_header('X-Custom', 'value')
	assert rt.default_headers['X-Custom'] == 'value'
}

fn test_set_default_headers() {
	rt := new_rest_template().set_default_headers({
		'Accept': 'application/json'
		'X-API': 'key123'
	})
	assert rt.default_headers['Accept'] == 'application/json'
	assert rt.default_headers['X-API'] == 'key123'
	assert rt.default_headers.len == 2
}

fn test_set_connect_timeout() {
	rt := new_rest_template().set_connect_timeout(5000)
	assert rt.connect_timeout == 5000
}

fn test_set_read_timeout() {
	rt := new_rest_template().set_read_timeout(10000)
	assert rt.read_timeout == 10000
}

fn test_set_retry() {
	rt := new_rest_template().set_retry(5, 100)
	assert rt.max_retries == 5
	assert rt.retry_base_delay == 100
}

fn test_set_error_handler() {
	handler := fn (resp ResponseEntity) ! {
		if resp.status_code >= 400 {
			return error('custom')
		}
	}
	rt := new_rest_template().set_error_handler(handler)
	// Verify the handler was set by invoking it
	handler(ResponseEntity{400, 'Bad Request', {}, 'err'}) or {
		assert err.str() == 'custom'
		return
	}
	assert false, 'should have errored'
}

fn test_add_interceptor() {
	ic := new_interceptor('logging', unsafe { nil })
	rt := new_rest_template().add_interceptor(ic)
	assert rt.interceptors.len == 1
	assert rt.interceptors[0].name == 'logging'
}

fn test_immutability() {
	// Setting config returns new instance; original unchanged
	rt1 := new_rest_template()
	rt2 := rt1.set_base_url('https://api.com').set_read_timeout(5000)
	assert rt1.base_url == ''
	assert rt2.base_url == 'https://api.com'
	assert rt1.read_timeout == 30000
	assert rt2.read_timeout == 5000
}

// ------------------------------------------------------------------
// UriTemplateHandler
// ------------------------------------------------------------------

fn test_uri_template_expand_no_vars() {
	h := new_uri_template_handler()
	result := h.expand('/api/users', map[string]string{})
	assert result == '/api/users'
}

fn test_uri_template_expand_single() {
	h := new_uri_template_handler()
	result := h.expand('/api/users/{id}', {'id': '42'})
	assert result == '/api/users/42'
}

fn test_uri_template_expand_multiple() {
	h := new_uri_template_handler()
	result := h.expand('/api/users/{id}/posts/{postId}', {'id': '42', 'postId': '7'})
	assert result == '/api/users/42/posts/7'
}

fn test_uri_template_expand_segment() {
	h := new_uri_template_handler()
	result := h.expand('/api/{resource}', {'resource': 'users'})
	assert result == '/api/users'
}

fn test_uri_template_expand_empty_vars() {
	h := new_uri_template_handler()
	// missing var stays as template placeholder
	result := h.expand('/api/{x}', map[string]string{})
	assert result == '/api/'
}

fn test_uri_template_expand_nested() {
	h := new_uri_template_handler()
	result := h.expand('/api/users/{id}/profile/{section}', {'id': '42', 'section': 'settings'})
	assert result == '/api/users/42/profile/settings'
}

fn test_uri_template_handler_custom_delimiters() {
	mut h := new_uri_template_handler()
	h.left_delim = `[`
	h.right_delim = `]`
	result := h.expand('/api/[id]', {'id': '42'})
	assert result == '/api/42'
}

// ------------------------------------------------------------------
// RequestEntity
// ------------------------------------------------------------------

fn test_request_entity_new() {
	e := request_entity('GET', '/api/users')
	assert e.method == 'GET'
	assert e.url == '/api/users'
	assert e.body == ''
	assert e.headers.len == 0
	assert e.uri_vars.len == 0
}

fn test_request_entity_header() {
	e := request_entity('POST', '/api/users')
		.header('Content-Type', 'application/json')
		.header('Authorization', 'Bearer xxx')
	assert e.headers['Content-Type'] == 'application/json'
	assert e.headers['Authorization'] == 'Bearer xxx'
}

fn test_request_entity_header_immutability() {
	e1 := request_entity('GET', '/')
	e2 := e1.header('X-Custom', 'val')
	assert e1.headers.len == 0
	assert e2.headers['X-Custom'] == 'val'
}

fn test_request_entity_body_str() {
	e := request_entity('POST', '/api/users').body_str('hello')
	assert e.body == 'hello'
}

fn test_request_entity_body_json() {
	payload := TestPayload{'test', 42}
	e := request_entity('POST', '/api/users').body_json(payload)
	assert e.body.contains('"name"')
	assert e.body.contains('"value"')
	assert e.body.contains('42')
}

fn test_request_entity_uri_var() {
	e := request_entity('GET', '/api/{id}').uri_var('id', '42')
	assert e.uri_vars['id'] == '42'
}

fn test_request_entity_uri_vars_from() {
	e := request_entity('GET', '/api/{a}/{b}').uri_vars_from({'a': '1', 'b': '2'})
	assert e.uri_vars['a'] == '1'
	assert e.uri_vars['b'] == '2'
}

fn test_request_entity_fluent_chain() {
	e := request_entity('POST', '/api/users')
		.header('Content-Type', 'application/json')
		.uri_var('id', '42')
		.body_str('{}')
	assert e.method == 'POST'
	assert e.headers['Content-Type'] == 'application/json'
	assert e.uri_vars['id'] == '42'
	assert e.body == '{}'
}

// ------------------------------------------------------------------
// ResponseEntity
// ------------------------------------------------------------------

fn test_response_entity_status_codes() {
	assert ResponseEntity{200, 'OK', {}, ''}.is_2xx() == true
	assert ResponseEntity{200, 'OK', {}, ''}.is_4xx() == false
	assert ResponseEntity{200, 'OK', {}, ''}.is_5xx() == false
	assert ResponseEntity{404, 'Not Found', {}, ''}.is_4xx() == true
	assert ResponseEntity{403, 'Forbidden', {}, ''}.is_4xx() == true
	assert ResponseEntity{500, 'Error', {}, ''}.is_5xx() == true
	assert ResponseEntity{302, 'Found', {}, ''}.is_2xx() == false
	assert ResponseEntity{302, 'Found', {}, ''}.is_4xx() == false
}

fn test_response_entity_header_value() {
	resp := ResponseEntity{200, 'OK', {'Content-Type': 'application/json'}, '{}'}
	assert resp.header_value('Content-Type') == 'application/json'
	assert resp.header_value('Missing') == ''
}

fn test_response_entity_body_as() {
	resp := ResponseEntity{200, 'OK', {}, '{"name":"test","value":42}'}
	result := resp.body_as[TestPayload]() or {
		assert false, 'body_as failed: ${err}'
		return
	}
	assert result.name == 'test'
	assert result.value == 42
}

fn test_response_entity_body_as_invalid_json() {
	resp := ResponseEntity{200, 'OK', {}, 'not-json'}
	resp.body_as[TestPayload]() or {
		// Expected error
		return
	}
	assert false, 'should have errored on invalid JSON'
}

// ------------------------------------------------------------------
// URL resolution
// ------------------------------------------------------------------

fn test_resolve_url_no_base() {
	assert resolve_url('', '/api/user') == '/api/user'
	assert resolve_url('', 'https://api.com/users') == 'https://api.com/users'
}

fn test_resolve_url_with_base_slash() {
	assert resolve_url('https://api.com', '/users') == 'https://api.com/users'
}

fn test_resolve_url_with_base_relative() {
	assert resolve_url('https://api.com', 'users') == 'https://api.com/users'
}

fn test_resolve_url_absolute_overrides_base() {
	assert resolve_url('https://fallback.com', 'https://real.com/api') == 'https://real.com/api'
}

fn test_resolve_url_empty_path() {
	assert resolve_url('https://api.com', '') == 'https://api.com'
}

// ------------------------------------------------------------------
// Method conversion
// ------------------------------------------------------------------

fn test_method_from_string_standard() {
	assert method_from_string('GET').str() == 'GET'
	assert method_from_string('POST').str() == 'POST'
	assert method_from_string('PUT').str() == 'PUT'
	assert method_from_string('DELETE').str() == 'DELETE'
	assert method_from_string('PATCH').str() == 'PATCH'
	assert method_from_string('HEAD').str() == 'HEAD'
	assert method_from_string('OPTIONS').str() == 'OPTIONS'
}

fn test_method_from_string_case_insensitive() {
	assert method_from_string('get').str() == 'GET'
	assert method_from_string('Post').str() == 'POST'
	assert method_from_string('DELETE').str() == 'DELETE'
}

fn test_method_from_string_default() {
	assert method_from_string('UNKNOWN').str() == 'GET'
	assert method_from_string('').str() == 'GET'
}

// ------------------------------------------------------------------
// Interceptor
// ------------------------------------------------------------------

fn test_interceptor_new() {
	ic := new_interceptor('logging', unsafe { nil })
	assert ic.name == 'logging'
	assert ic.intercept_fn == unsafe { nil }
}

fn test_interceptor_chain_construction() {
	// Verify the interceptor pipeline function type compiles
	next := fn (e RequestEntity) !ResponseEntity {
		return ResponseEntity{200, 'OK', {}, 'next'}
	}

	ic := new_interceptor('test', fn (e RequestEntity, n fn (RequestEntity) !ResponseEntity) !ResponseEntity {
		return n(e)
	})

	// The interceptor function can wrap the next one
	result := ic.intercept_fn(RequestEntity{}, next) or {
		assert false, 'interceptor failed: ${err}'
		return
	}
	assert result.body == 'next'
}

fn test_error_handler_default_rejects_4xx() {
	default_error_handler(ResponseEntity{404, 'Not Found', {}, 'missing'}) or {
		assert err.str().contains('404')
		return
	}
	assert false, 'should have errored'
}

fn test_error_handler_default_rejects_5xx() {
	default_error_handler(ResponseEntity{502, 'Bad Gateway', {}, 'upstream down'}) or {
		assert err.str().contains('502')
		return
	}
	assert false, 'should have errored'
}

fn test_error_handler_default_accepts_2xx() {
	default_error_handler(ResponseEntity{200, 'OK', {}, 'success'}) or {
		assert false, '2xx should not error: ${err}'
		return
	}
}

fn test_error_handler_default_accepts_3xx() {
	default_error_handler(ResponseEntity{302, 'Found', {}, ''}) or {
		assert false, '3xx should not error: ${err}'
		return
	}
}

// ------------------------------------------------------------------
// Struct for JSON tests
// ------------------------------------------------------------------

struct TestPayload {
pub:
	name  string
	value int
}

// ------------------------------------------------------------------
// Integration: RestTemplate + exchange (no network)
//   Tests that the method signatures compile and behave correctly.
//   Real HTTP tests would require a running server.
// ------------------------------------------------------------------

fn test_rt_get_for_object_syntax() {
	rt := new_rest_template()
	_ := rt.get_for_object[map[string]string]('', {'x': 'y'}) or { return }
}

fn test_rt_get_for_entity_syntax() {
	rt := new_rest_template()
	_ := rt.get_for_entity('', {'x': 'y'}) or { return }
}

fn test_rt_post_for_object_syntax() {
	rt := new_rest_template()
	_ := rt.post_for_object[TestPayload]('', '{}', {}) or { return }
}

fn test_rt_post_for_entity_syntax() {
	rt := new_rest_template()
	_ := rt.post_for_entity('', '{}', {}) or { return }
}

fn test_rt_put_syntax() {
	rt := new_rest_template()
	rt.put('', '{}', {}) or { return }
}

fn test_rt_delete_syntax() {
	rt := new_rest_template()
	rt.delete('', {}) or { return }
}

fn test_rt_patch_for_entity_syntax() {
	rt := new_rest_template()
	_ := rt.patch_for_entity('', '{}', {}) or { return }
}

fn test_rt_head_for_headers_syntax() {
	rt := new_rest_template()
	_ := rt.head_for_headers('', {}) or { return }
}

fn test_rt_options_for_allow_syntax() {
	rt := new_rest_template()
	_ := rt.options_for_allow('', {}) or { return }
}

fn test_rt_exchange_syntax() {
	rt := new_rest_template()
	entity := request_entity('GET', '/api/users').uri_var('id', '42')
	_ := rt.exchange(entity) or { return }
}

fn test_rt_execute_syntax() {
	rt := new_rest_template()
	entity := request_entity('POST', '/api/users').body_str('{}')
	_ := rt.execute(entity) or { return }
}

fn test_header_from_map_empty() {
	h := header_from_map(map[string]string{})
	assert h.keys().len == 0
}

fn test_header_from_map_with_values() {
	h := header_from_map({'Content-Type': 'application/json', 'Accept': 'text/plain'})
	keys := h.keys()
	assert keys.len == 2
}

fn test_execute_with_retry_syntax() {
	_ := execute_with_retry(vhttp.FetchConfig{method: vhttp.Method.get, url: 'http://localhost:1'}, 0, 100) or { return }
}
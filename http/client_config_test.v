module http

import time
import x.json2

// FetchConfig 的组装逻辑单独抽出来，这样不用真发请求也能断言配置有没有生效。
fn test_proxy_config_is_applied() {
	rt := new_rest_template().set_proxy(ProxyConfig{
		host:     '127.0.0.1'
		port:     8080
		username: 'u'
		password: 'p'
	})
	cfg := rt.fetch_config(RequestEntity{
		method: 'GET'
		url:    'http://example.com/x'
	})!
	assert cfg.proxy != unsafe { nil }
	assert cfg.proxy.str().contains('127.0.0.1:8080')
}

fn test_read_timeout_is_applied() {
	rt := new_rest_template().set_read_timeout(1234)
	cfg := rt.fetch_config(RequestEntity{ method: 'GET', url: 'http://example.com/' })!
	// FetchConfig carries durations in nanoseconds.
	assert cfg.read_timeout == 1234 * i64(time.millisecond)
	// connect_timeout is not settable on its own; write_timeout keeps its default.
	assert cfg.write_timeout == 30 * i64(time.second)
}

fn test_ssl_config_maps_to_fetch_config() {
	rt := new_rest_template().set_ssl_config(SSLConfig{
		enable:               true
		cert_file:            '/tmp/cert.pem'
		key_file:             '/tmp/key.pem'
		ca_file:              '/tmp/ca.pem'
		insecure_skip_verify: true
	})
	cfg := rt.fetch_config(RequestEntity{ method: 'GET', url: 'https://example.com/' })!
	assert cfg.cert == '/tmp/cert.pem'
	assert cfg.cert_key == '/tmp/key.pem'
	assert cfg.verify == '/tmp/ca.pem'
	// insecure_skip_verify => do not stop on invalid certs
	assert cfg.validate == false
}

fn test_ssl_disabled_does_not_require_certs() {
	rt := new_rest_template()
	cfg := rt.fetch_config(RequestEntity{ method: 'GET', url: 'https://example.com/' })!
	assert cfg.cert == ''
	assert cfg.proxy == unsafe { nil }
}

fn test_uri_template_expand() {
	h := new_uri_template_handler()
	assert h.expand('/users/{id}', { 'id': '42' }) == '/users/42'
	assert h.expand('/a/{x}/b/{y}', { 'x': '1', 'y': '2' }) == '/a/1/b/2'
	// Escaped delimiters stay literal, they are not expanded.
	assert h.expand('/users/{{id}}', { 'id': '42' }) == '/users/{{id}}'
	// An unclosed placeholder must not silently swallow the rest of the path.
	assert h.expand('/users/{id', { 'id': '42' }) == '/users/{id'
}

fn test_body_as_roundtrip() {
	resp := ResponseEntity{
		status_code: 200
		body:        '{"name":"photon","n":2}'
	}
	data := resp.body_as[map[string]json2.Any]()!
	assert data['name'] or { json2.Any('') }.str() == 'photon'
}

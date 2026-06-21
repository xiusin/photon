module http

fn test_ssl_config_creation() {
	config := SSLConfig{
		enable:               true
		cert_file:            'client.crt'
		key_file:             'client.key'
		ca_file:              'ca.crt'
		insecure_skip_verify: false
	}
	assert config.enable == true
	assert config.cert_file == 'client.crt'
	assert config.key_file == 'client.key'
	assert config.ca_file == 'ca.crt'
	assert config.insecure_skip_verify == false
}

fn test_ssl_config_default() {
	config := SSLConfig{}
	assert config.enable == false
	assert config.cert_file == ''
	assert config.insecure_skip_verify == false
}

fn test_proxy_config_creation() {
	config := ProxyConfig{
		host:     'proxy.example.com'
		port:     8080
		username: 'user'
		password: 'pass'
	}
	assert config.host == 'proxy.example.com'
	assert config.port == 8080
	assert config.username == 'user'
	assert config.password == 'pass'
}

fn test_proxy_config_default() {
	config := ProxyConfig{}
	assert config.host == ''
	assert config.port == 0
}

fn test_rest_template_set_ssl_config() {
	rt := new_rest_template()
	rt2 := rt.set_ssl_config(SSLConfig{ enable: true, cert_file: 'test.crt' })
	config := rt2.ssl_config or { SSLConfig{} }
	assert config.enable == true
	assert config.cert_file == 'test.crt'
}

fn test_rest_template_set_proxy() {
	rt := new_rest_template()
	rt2 := rt.set_proxy(ProxyConfig{ host: 'proxy.com', port: 3128 })
	config := rt2.proxy_config or { ProxyConfig{} }
	assert config.host == 'proxy.com'
	assert config.port == 3128
}

fn test_rest_template_ssl_config_default_none() {
	rt := new_rest_template()
	assert rt.ssl_config == none
}

fn test_rest_template_proxy_config_default_none() {
	rt := new_rest_template()
	assert rt.proxy_config == none
}

fn test_noop_interceptor_creation() {
	ic := new_noop_interceptor()
	assert ic.name == 'noop'
	assert !isnil(ic.intercept_fn)
}

fn test_noop_interceptor_passes_through() {
	ic := new_noop_interceptor()
	// Create a simple next function that returns a fixed response
	next := fn (e RequestEntity) !ResponseEntity {
		return ResponseEntity{
			status_code: 200
			body:        'passed through'
		}
	}
	entity := request_entity('GET', '/test')
	result := ic.intercept_fn(entity, next)!
	assert result.status_code == 200
	assert result.body == 'passed through'
}

fn test_rest_template_chained_config() {
	rt := new_rest_template()
	rt2 := rt.set_ssl_config(SSLConfig{ enable: true }).set_proxy(ProxyConfig{ host: 'p.com' })
	ssl := rt2.ssl_config or { SSLConfig{} }
	proxy := rt2.proxy_config or { ProxyConfig{} }
	assert ssl.enable == true
	assert proxy.host == 'p.com'
}

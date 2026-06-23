module web

// introspection_test.v - Tests for the /env, /beans, /mappings introspection
// endpoints (SubTask D6.4)
//
// Verifies that the introspection endpoints:
//   - Return 200 OK with JSON bodies
//   - Set Content-Type: application/json
//   - /env: returns all properties, masks sensitive keys, includes normal keys
//   - /beans: returns bean list with name/type/scope/lazy fields
//   - /mappings: returns route mappings with method/path/handler
//   - Handle empty registries gracefully (empty arrays)
//   - mask_sensitive_value covers password/secret/token/key/credential
import core

// ── mask_sensitive_value unit tests ──

fn test_mask_sensitive_value_password() {
	masked := mask_sensitive_value('db.password', 'secret123')
	assert masked == masked_value
}

fn test_mask_sensitive_value_token() {
	masked := mask_sensitive_value('api.token', 'abc-xyz-123')
	assert masked == masked_value
}

fn test_mask_sensitive_value_secret() {
	masked := mask_sensitive_value('jwt.secret', 'super-secret')
	assert masked == masked_value
}

fn test_mask_sensitive_value_key() {
	masked := mask_sensitive_value('encryption.key', '0xdeadbeef')
	assert masked == masked_value
}

fn test_mask_sensitive_value_credential() {
	masked := mask_sensitive_value('aws.credential', 'AKIA...')
	assert masked == masked_value
}

fn test_mask_sensitive_value_api_key() {
	masked := mask_sensitive_value('service.api_key', 'sk_test_123')
	assert masked == masked_value
}

fn test_mask_sensitive_value_normal() {
	value := mask_sensitive_value('app.name', 'Photon')
	assert value == 'Photon'
}

fn test_mask_sensitive_value_case_insensitive() {
	// Uppercase key should still be masked
	masked := mask_sensitive_value('DB.PASSWORD', 'secret123')
	assert masked == masked_value
}

fn test_mask_sensitive_value_mixed_case() {
	masked := mask_sensitive_value('Api.Token', 'tok_abc')
	assert masked == masked_value
}

fn test_mask_sensitive_value_empty_value() {
	// Empty value for a sensitive key still returns the mask
	masked := mask_sensitive_value('db.password', '')
	assert masked == masked_value
}

fn test_mask_sensitive_value_non_sensitive_empty() {
	// Empty value for a non-sensitive key returns empty
	value := mask_sensitive_value('app.version', '')
	assert value == ''
}

// ── /env endpoint tests ──

fn test_env_endpoint_returns_200() {
	mut env := core.new_environment()
	env.set_property('app.name', 'Photon')

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/env'))!
	result.assert_status(200)!
}

fn test_env_endpoint_content_type_is_json() {
	mut env := core.new_environment()
	env.set_property('app.name', 'Photon')

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/env'))!
	result.assert_header('Content-Type', introspection_content_type)!
}

fn test_env_endpoint_returns_property_sources() {
	mut env := core.new_environment()
	env.set_property('app.name', 'Photon')

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/env'))!
	result.assert_body_contains('"propertySources"')!
	result.assert_body_contains('"environment"')!
	result.assert_body_contains('"properties"')!
}

fn test_env_endpoint_includes_normal_keys() {
	mut env := core.new_environment()
	env.set_property('app.name', 'Photon')

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/env'))!
	result.assert_body_contains('"app.name"')!
	result.assert_body_contains('"value":"Photon"')!
}

fn test_env_endpoint_masks_sensitive_keys() {
	mut env := core.new_environment()
	env.set_property('db.password', 'super-secret-value')
	env.set_property('app.name', 'Photon')

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/env'))!
	// The sensitive value must NOT appear in the output
	assert !result.body.contains('super-secret-value')
	// The key should still be present, but with masked value
	result.assert_body_contains('"db.password"')!
	result.assert_body_contains('"value":"${masked_value}"')!
}

fn test_env_endpoint_masks_multiple_sensitive_keys() {
	mut env := core.new_environment()
	env.set_property('db.password', 'pw1')
	env.set_property('api.token', 'tok1')
	env.set_property('jwt.secret', 'sec1')
	env.set_property('encryption.key', 'key1')
	env.set_property('aws.credential', 'cred1')
	env.set_property('app.name', 'Photon')

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/env'))!
	// None of the sensitive values should appear
	assert !result.body.contains('pw1')
	assert !result.body.contains('tok1')
	assert !result.body.contains('sec1')
	assert !result.body.contains('key1')
	assert !result.body.contains('cred1')
	// But the masked value should appear for each
	assert result.body.count('"value":"${masked_value}"') == 5
}

fn test_env_endpoint_empty_environment() {
	mut env := core.new_environment()

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/env'))!
	result.assert_status(200)!
	result.assert_body_contains('"propertySources"')!
	// Empty properties object
	result.assert_body_contains('"properties":{}')!
}

fn test_env_endpoint_multiple_properties() {
	mut env := core.new_environment()
	env.set_property('app.name', 'Photon')
	env.set_property('app.port', '8080')
	env.set_property('app.host', 'localhost')

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/env'))!
	result.assert_body_contains('"app.name"')!
	result.assert_body_contains('"app.port"')!
	result.assert_body_contains('"app.host"')!
	result.assert_body_contains('"8080"')!
	result.assert_body_contains('"localhost"')!
}

fn test_serve_env_returns_body_content_type_status() {
	mut env := core.new_environment()
	env.set_property('app.name', 'Photon')

	body, ct, code := serve_env(env)

	assert ct == introspection_content_type
	assert code == 200
	assert body.contains('"propertySources"')
	assert body.contains('"app.name"')
}

// ── /beans endpoint tests ──

fn test_beans_endpoint_returns_200() {
	mut ctx := core.new_application_context()
	ctx.register(core.new_bean_definition('UserService'))!

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/beans'))!
	result.assert_status(200)!
}

fn test_beans_endpoint_content_type_is_json() {
	mut ctx := core.new_application_context()
	ctx.register(core.new_bean_definition('UserService'))!

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/beans'))!
	result.assert_header('Content-Type', introspection_content_type)!
}

fn test_beans_endpoint_returns_beans_array() {
	mut ctx := core.new_application_context()
	ctx.register(core.new_bean_definition('UserService'))!

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/beans'))!
	result.assert_body_contains('"context":"application"')!
	result.assert_body_contains('"beans":[')!
	result.assert_body_contains('"UserService"')!
}

fn test_beans_endpoint_has_name_type_scope_lazy_fields() {
	mut ctx := core.new_application_context()
	ctx.register(core.new_bean_definition('UserService'))!

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/beans'))!
	result.assert_body_contains('"name":"UserService"')!
	result.assert_body_contains('"type":"UserService"')!
	result.assert_body_contains('"scope":"singleton"')!
	result.assert_body_contains('"lazy":false')!
}

fn test_beans_endpoint_multiple_beans() {
	mut ctx := core.new_application_context()
	ctx.register(core.new_bean_definition('UserService'))!
	ctx.register(core.new_bean_definition('OrderService'))!
	ctx.register(core.new_bean_definition('ProductService'))!

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/beans'))!
	result.assert_body_contains('"UserService"')!
	result.assert_body_contains('"OrderService"')!
	result.assert_body_contains('"ProductService"')!
}

fn test_beans_endpoint_prototype_scope() {
	mut def := core.new_bean_definition('PrototypeService')
	def.scope = .prototype
	mut ctx := core.new_application_context()
	ctx.register(def)!

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/beans'))!
	result.assert_body_contains('"scope":"prototype"')!
}

fn test_beans_endpoint_lazy_bean() {
	mut def := core.new_bean_definition('LazyService')
	def.is_lazy = true
	mut ctx := core.new_application_context()
	ctx.register(def)!

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/beans'))!
	result.assert_body_contains('"lazy":true')!
}

fn test_beans_endpoint_empty_context() {
	mut ctx := core.new_application_context()

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/beans'))!
	result.assert_status(200)!
	result.assert_body_contains('"beans":[]')!
}

fn test_serve_beans_returns_body_content_type_status() {
	mut ctx := core.new_application_context()
	ctx.register(core.new_bean_definition('UserService'))!

	body, ct, code := serve_beans(ctx)

	assert ct == introspection_content_type
	assert code == 200
	assert body.contains('"beans"')
	assert body.contains('"UserService"')
}

// ── /mappings endpoint tests ──

fn test_mappings_endpoint_returns_200() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/users', handler_name: 'users'}

	mut mvc := new_mockmvc()
	mvc.get('/mappings', mappings_mock_handler(mock_routes))

	result := mvc.perform(mock_request('GET', '/mappings'))!
	result.assert_status(200)!
}

fn test_mappings_endpoint_content_type_is_json() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/users', handler_name: 'users'}

	mut mvc := new_mockmvc()
	mvc.get('/mappings', mappings_mock_handler(mock_routes))

	result := mvc.perform(mock_request('GET', '/mappings'))!
	result.assert_header('Content-Type', introspection_content_type)!
}

fn test_mappings_endpoint_returns_mappings_structure() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/users', handler_name: 'users'}

	mut mvc := new_mockmvc()
	mvc.get('/mappings', mappings_mock_handler(mock_routes))

	result := mvc.perform(mock_request('GET', '/mappings'))!
	result.assert_body_contains('"contexts"')!
	result.assert_body_contains('"application"')!
	result.assert_body_contains('"mappings"')!
	result.assert_body_contains('"dispatcherServlets"')!
	result.assert_body_contains('"dispatcherServlet"')!
}

fn test_mappings_endpoint_has_method_path_handler() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/users', handler_name: 'users'}

	mut mvc := new_mockmvc()
	mvc.get('/mappings', mappings_mock_handler(mock_routes))

	result := mvc.perform(mock_request('GET', '/mappings'))!
	result.assert_body_contains('"methods":["GET"]')!
	result.assert_body_contains('"patterns":["/users"]')!
	result.assert_body_contains('"handler":"users"')!
}

fn test_mappings_endpoint_multiple_routes() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/users', handler_name: 'list_users'}
	mock_routes << RouteInfo{method: 'POST', path: '/users', handler_name: 'create_user'}
	mock_routes << RouteInfo{method: 'GET', path: '/orders', handler_name: 'list_orders'}
	mock_routes << RouteInfo{method: 'DELETE', path: '/orders/:id', handler_name: 'delete_order'}

	mut mvc := new_mockmvc()
	mvc.get('/mappings', mappings_mock_handler(mock_routes))

	result := mvc.perform(mock_request('GET', '/mappings'))!
	result.assert_body_contains('"GET"')!
	result.assert_body_contains('"POST"')!
	result.assert_body_contains('"DELETE"')!
	result.assert_body_contains('"/users"')!
	result.assert_body_contains('"/orders"')!
	result.assert_body_contains('"/orders/:id"')!
	result.assert_body_contains('"list_users"')!
	result.assert_body_contains('"create_user"')!
	result.assert_body_contains('"list_orders"')!
	result.assert_body_contains('"delete_order"')!
}

fn test_mappings_endpoint_empty_routes() {
	mut mvc := new_mockmvc()
	mvc.get('/mappings', mappings_mock_handler([]RouteInfo{}))

	result := mvc.perform(mock_request('GET', '/mappings'))!
	result.assert_status(200)!
	result.assert_body_contains('"dispatcherServlet":[]')!
}

fn test_mappings_endpoint_all_http_methods() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/r1', handler_name: 'h1'}
	mock_routes << RouteInfo{method: 'POST', path: '/r2', handler_name: 'h2'}
	mock_routes << RouteInfo{method: 'PUT', path: '/r3', handler_name: 'h3'}
	mock_routes << RouteInfo{method: 'DELETE', path: '/r4', handler_name: 'h4'}
	mock_routes << RouteInfo{method: 'PATCH', path: '/r5', handler_name: 'h5'}

	mut mvc := new_mockmvc()
	mvc.get('/mappings', mappings_mock_handler(mock_routes))

	result := mvc.perform(mock_request('GET', '/mappings'))!
	result.assert_body_contains('"GET"')!
	result.assert_body_contains('"POST"')!
	result.assert_body_contains('"PUT"')!
	result.assert_body_contains('"DELETE"')!
	result.assert_body_contains('"PATCH"')!
}

fn test_serve_mappings_returns_body_content_type_status() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/users', handler_name: 'users'}

	body, ct, code := serve_mappings(mock_routes)

	assert ct == introspection_content_type
	assert code == 200
	assert body.contains('"mappings"')
	assert body.contains('"GET"')
	assert body.contains('"/users"')
}

// ── JSON format validity tests ──

fn test_env_json_format_valid() {
	mut env := core.new_environment()
	env.set_property('app.name', 'Photon')
	env.set_property('app.port', '8080')

	body, _, _ := serve_env(env)

	// Should start with { and end with }
	assert body.starts_with('{')
	assert body.ends_with('}')
	// Should contain the propertySources structure
	assert body.contains('"propertySources":[{')
	assert body.contains('}]}')
}

fn test_beans_json_format_valid() {
	mut ctx := core.new_application_context()
	ctx.register(core.new_bean_definition('UserService'))!

	body, _, _ := serve_beans(ctx)

	assert body.starts_with('{')
	assert body.ends_with('}')
	assert body.contains('"context":"application"')
	assert body.contains('"beans":[')
}

fn test_mappings_json_format_valid() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/users', handler_name: 'users'}

	body, _, _ := serve_mappings(mock_routes)

	assert body.starts_with('{')
	assert body.ends_with('}')
	// Verify the nested structure closes properly
	assert body.count('{') == body.count('}')
	assert body.count('[') == body.count(']')
}

fn test_mappings_json_format_valid_empty() {
	body, _, _ := serve_mappings([]RouteInfo{})

	assert body.starts_with('{')
	assert body.ends_with('}')
	assert body.count('{') == body.count('}')
	assert body.count('[') == body.count(']')
}

// ── Unknown path returns 404 ──

fn test_env_endpoint_unknown_path_returns_404() {
	mut env := core.new_environment()
	env.set_property('app.name', 'Photon')

	mut mvc := new_mockmvc()
	mvc.get('/env', env_mock_handler(env))

	result := mvc.perform(mock_request('GET', '/unknown'))!
	result.assert_not_found()!
}

fn test_beans_endpoint_unknown_path_returns_404() {
	mut ctx := core.new_application_context()
	ctx.register(core.new_bean_definition('UserService'))!

	mut mvc := new_mockmvc()
	mvc.get('/beans', beans_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/unknown'))!
	result.assert_not_found()!
}

fn test_mappings_endpoint_unknown_path_returns_404() {
	mut mock_routes := []RouteInfo{}
	mock_routes << RouteInfo{method: 'GET', path: '/users', handler_name: 'users'}

	mut mvc := new_mockmvc()
	mvc.get('/mappings', mappings_mock_handler(mock_routes))

	result := mvc.perform(mock_request('GET', '/unknown'))!
	result.assert_not_found()!
}

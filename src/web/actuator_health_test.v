module web

// actuator_health_test.v - Tests for the /health actuator endpoint (SubTask D3.3)
//
// Verifies that the /health endpoint:
//   - Returns 200 OK with JSON body when overall status is UP
//   - Returns 503 Service Unavailable when overall status is DOWN
//   - Sets Content-Type: application/json
//   - Includes "status" and "components" fields in the JSON body
//   - Aggregates all registered indicators
//   - Returns 200 for an empty registry (considered healthy)
import health

fn test_health_endpoint_up_returns_200() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/tmp'
	})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_status(200)!
}

fn test_health_endpoint_down_returns_503() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/nonexistent/path/that/should/not/exist'
	})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_status(503)!
}

fn test_health_endpoint_empty_registry_returns_200() {
	mut registry := health.new_health_registry()

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_ok()!
}

fn test_health_endpoint_content_type_is_json() {
	mut registry := health.new_health_registry()

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_header('Content-Type', health_content_type)!
}

fn test_health_endpoint_body_contains_status_up() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/tmp'
	})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_body_contains('"status":"UP"')!
}

fn test_health_endpoint_body_contains_status_down() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/nonexistent/path/that/should/not/exist'
	})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_body_contains('"status":"DOWN"')!
}

fn test_health_endpoint_body_contains_components() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/tmp'
	})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_body_contains('"components"')!
	result.assert_body_contains('"disk"')!
}

fn test_health_endpoint_aggregates_multiple_indicators() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/tmp'
	})
	registry.register(&health.MemoryHealthIndicator{})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_status(200)!
	result.assert_body_contains('"disk"')!
	result.assert_body_contains('"memory"')!
}

fn test_health_endpoint_mixed_up_down_returns_503() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/tmp'
	})
	registry.register(&health.DiskHealthIndicator{
		path: '/nonexistent/path/that/should/not/exist'
	})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	// Any DOWN → 503
	result.assert_status(503)!
}

fn test_health_endpoint_empty_registry_body() {
	mut registry := health.new_health_registry()

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_body('{"status":"UP","components":{}}')!
}

fn test_serve_health_returns_body_content_type_status_up() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/tmp'
	})

	body, ct, code := serve_health(registry)

	assert ct == health_content_type
	assert code == 200
	assert body.contains('"status":"UP"')
}

fn test_serve_health_returns_503_on_down() {
	mut registry := health.new_health_registry()
	registry.register(&health.DiskHealthIndicator{
		path: '/nonexistent/path/that/should/not/exist'
	})

	body, ct, code := serve_health(registry)

	assert ct == health_content_type
	assert code == 503
	assert body.contains('"status":"DOWN"')
}

fn test_health_endpoint_db_indicator_up() {
	mut registry := health.new_health_registry()
	registry.register(&health.DbHealthIndicator{
		ping_fn: fn () ! {}
	})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_status(200)!
	result.assert_body_contains('"db"')!
	result.assert_body_contains('"database":"connected"')!
}

fn test_health_endpoint_db_indicator_down() {
	mut registry := health.new_health_registry()
	registry.register(&health.DbHealthIndicator{
		ping_fn: fn () ! {
			return error('connection refused')
		}
	})

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/health'))!
	result.assert_status(503)!
	result.assert_body_contains('"error":"connection refused"')!
}

fn test_health_endpoint_unknown_path_returns_404() {
	mut registry := health.new_health_registry()

	mut mvc := new_mockmvc()
	mvc.get('/health', health_mock_handler(registry))

	// /health is registered, but /unknown is not.
	result := mvc.perform(mock_request('GET', '/unknown'))!
	result.assert_not_found()!
}

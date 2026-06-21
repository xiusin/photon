module web

// actuator_metrics_test.v - Tests for the /metrics actuator endpoint
//
// Verifies that the /metrics endpoint (SubTask D1.3):
//   - Returns 200 OK with the Prometheus text exposition format
//   - Sets the correct Content-Type (text/plain; version=0.0.4)
//   - Includes all meter types (counter/gauge/timer) in the body
//   - Renders tags in Prometheus label format
//   - Returns an empty body for an empty registry
//   - Reflects live meter updates on subsequent scrapes
import metrics
import time

fn test_metrics_endpoint_returns_ok() {
	mut registry := metrics.new_in_memory_registry()
	mut c := registry.counter('http_requests', {})
	c.increment_by(5)

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/metrics'))!
	result.assert_ok()!
}

fn test_metrics_endpoint_content_type() {
	mut registry := metrics.new_in_memory_registry()
	registry.counter('requests', {})

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/metrics'))!
	result.assert_header('Content-Type', prometheus_content_type)!
}

fn test_metrics_endpoint_contains_counter() {
	mut registry := metrics.new_in_memory_registry()
	mut c := registry.counter('http_requests', {})
	c.increment_by(42)

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/metrics'))!
	result.assert_body_contains('# TYPE http_requests counter')!
	result.assert_body_contains('http_requests 42')!
}

fn test_metrics_endpoint_contains_gauge() {
	mut registry := metrics.new_in_memory_registry()
	mut g := registry.gauge('queue_depth', {})
	g.set(7.5)

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/metrics'))!
	result.assert_body_contains('# TYPE queue_depth gauge')!
	result.assert_body_contains('queue_depth 7.5')!
}

fn test_metrics_endpoint_contains_timer() {
	mut registry := metrics.new_in_memory_registry()
	mut t := registry.timer('request_duration', {})
	t.record(150 * time.millisecond)

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/metrics'))!
	result.assert_body_contains('# TYPE request_duration summary')!
	result.assert_body_contains('request_duration_count 1')!
}

fn test_metrics_endpoint_contains_all_meter_types() {
	mut registry := metrics.new_in_memory_registry()
	mut c := registry.counter('http_requests', {})
	mut g := registry.gauge('queue_depth', {})
	mut t := registry.timer('request_duration', {})

	c.increment_by(3)
	g.set(9.0)
	t.record(20 * time.millisecond)

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/metrics'))!
	result.assert_body_contains('# TYPE http_requests counter')!
	result.assert_body_contains('# TYPE queue_depth gauge')!
	result.assert_body_contains('# TYPE request_duration summary')!
}

fn test_metrics_endpoint_renders_tags() {
	mut registry := metrics.new_in_memory_registry()
	mut c := registry.counter('http_requests', {'method': 'GET', 'status': '200'})
	c.increment()

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/metrics'))!
	result.assert_body_contains('http_requests{method="GET",status="200"} 1')!
}

fn test_metrics_endpoint_empty_registry() {
	mut registry := metrics.new_in_memory_registry()

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	result := mvc.perform(mock_request('GET', '/metrics'))!
	result.assert_ok()!
	result.assert_body('')!
}

fn test_metrics_endpoint_reflects_live_updates() {
	mut registry := metrics.new_in_memory_registry()
	mut c := registry.counter('live_counter', {})

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	// First scrape: counter is 1.
	c.increment()
	r1 := mvc.perform(mock_request('GET', '/metrics'))!
	r1.assert_body_contains('live_counter 1')!

	// Second scrape after more increments: counter is 4.
	c.increment()
	c.increment()
	c.increment()
	r2 := mvc.perform(mock_request('GET', '/metrics'))!
	r2.assert_body_contains('live_counter 4')!
}

fn test_serve_metrics_returns_body_and_content_type() {
	mut registry := metrics.new_in_memory_registry()
	mut c := registry.counter('served', {})
	c.increment_by(2)

	body, ct := serve_metrics(registry)

	assert ct == prometheus_content_type
	assert body.contains('# TYPE served counter')
	assert body.contains('served 2')
}

fn test_metrics_endpoint_unknown_path_returns_404() {
	mut registry := metrics.new_in_memory_registry()

	mut mvc := new_mockmvc()
	mvc.get('/metrics', metrics_mock_handler(registry))

	// /metrics is registered, but /unknown is not.
	result := mvc.perform(mock_request('GET', '/unknown'))!
	result.assert_not_found()!
}

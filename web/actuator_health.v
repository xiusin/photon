module web

// actuator_health.v - Spring Boot Actuator-style /health Endpoint (SubTask D3.3)
//
// Exposes the aggregated health of all registered HealthIndicators over HTTP
// at /health in JSON format, following the Spring Boot Health endpoint
// convention:
//
//   {"status":"UP","components":{"db":{"status":"UP","details":{"database":"connected"}}}}
//
// Status codes:
//   - 200 OK              when overall status is UP (or UNKNOWN)
//   - 503 Service Unavailable when overall status is DOWN
//
// Because Photon's routing is compile-time (veb scans @[get('/path')] methods
// on the App struct), the endpoint is wired in by adding a method to the
// application's App that delegates to serve_health(). This keeps the actuator
// decoupled from any specific App shape while remaining trivial to integrate:
//
//   import health
//   import web
//
//   pub struct App {
//       veb.Context
//   pub mut:
//       health_registry &health.HealthRegistry = unsafe { nil }
//   }
//
//   @[get('/health')]
//   pub fn (mut app App) health() veb.Result {
//       body, ct, code := web.serve_health(app.health_registry)
//       app.set_content_type(ct)
//       return app.status(code).text(body)
//   }
//
// For tests, health_mock_handler() returns a MockMvc-compatible handler.
import health

// health_content_type is the Content-Type used by the /health endpoint.
pub const health_content_type = 'application/json'

// health_status_up is the HTTP status code returned when overall health is UP.
pub const health_status_up = 200

// health_status_down is the HTTP status code returned when overall health is DOWN.
pub const health_status_down = 503

// serve_health aggregates all registered indicators, renders the result as
// JSON, and returns the body together with the appropriate Content-Type and
// HTTP status code (200 for UP, 503 for DOWN). Intended to be called from a
// veb route handler (see file header for usage).
//
// Returns a 200 with status "UP" and empty components when the registry
// holds no indicators — an empty registry is considered healthy.
pub fn serve_health(registry &health.HealthRegistry) (string, string, int) {
	mut r := unsafe { registry }
	agg := r.check_all()
	body := health.format_health_json(agg)
	status_code := if agg.status == .down { health_status_down } else { health_status_up }
	return body, health_content_type, status_code
}

// health_mock_handler returns a MockHandler that serves the registry's
// aggregated health in JSON format. Use it with MockMvc to test the
// /health endpoint without a running HTTP server:
//
//   mut registry := health.new_health_registry()
//   registry.register(&health.DiskHealthIndicator{ path: '/tmp' })
//
//   mut mvc := web.new_mockmvc()
//   mvc.get('/health', web.health_mock_handler(registry))
//   result := mvc.perform(web.mock_request('GET', '/health'))!
//   result.assert_ok()!
//   result.assert_body_contains('"status":"UP"')!
pub fn health_mock_handler(registry &health.HealthRegistry) MockHandler {
	return fn [registry] (req MockRequest) !MockResult {
		body, ct, code := serve_health(registry)
		return MockResult{
			status:  code
			body:    body
			headers: {
				'Content-Type': ct
			}
		}
	}
}

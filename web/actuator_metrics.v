module web

// actuator_metrics.v - Spring Boot Actuator-style /metrics Endpoint
//
// Exposes the metrics collected by a metrics.InMemoryMeterRegistry over HTTP
// at /metrics in the Prometheus text exposition format (version 0.0.4), ready
// for scraping by Prometheus / Grafana Agent.
//
// Because Photon's routing is compile-time (veb scans @[get('/path')] methods
// on the App struct), the endpoint is wired in by adding a method to the
// application's App that delegates to serve_metrics(). This keeps the actuator
// decoupled from any specific App shape while remaining trivial to integrate:
//
//   import metrics
//   import web
//
//   pub struct App {
//       veb.Context
//   pub mut:
//       registry &metrics.InMemoryMeterRegistry = unsafe { nil }
//   }
//
//   @[get('/metrics')]
//   pub fn (mut app App) metrics() veb.Result {
//       body, ct := web.serve_metrics(app.registry)
//       app.set_content_type(ct)
//       return app.text(body)
//   }
//
// For tests, metrics_mock_handler() returns a MockMvc-compatible handler.
import metrics

// PrometheusContentVersion is the Content-Type version token used by the
// /metrics endpoint, matching the Prometheus text exposition format 0.0.4.
pub const prometheus_content_type = 'text/plain; version=0.0.4; charset=utf-8'

// serve_metrics renders the registry's meters in Prometheus text format and
// returns the body together with the appropriate Content-Type. Intended to be
// called from a veb route handler (see file header for usage).
//
// Returns an empty body when the registry holds no meters, which is a valid
// Prometheus scrape response.
pub fn serve_metrics(registry &metrics.InMemoryMeterRegistry) (string, string) {
	body := registry.format_prometheus()
	return body, prometheus_content_type
}

// metrics_mock_handler returns a MockHandler that serves the registry's
// metrics in Prometheus format. Use it with MockMvc to test the /metrics
// endpoint without a running HTTP server:
//
//   mut mvc := web.new_mockmvc()
//   mvc.get('/metrics', web.metrics_mock_handler(registry))
//   result := mvc.perform(web.mock_request('GET', '/metrics'))!
//   result.assert_ok()!
//   result.assert_body_contains('# TYPE http_requests counter')!
pub fn metrics_mock_handler(registry &metrics.InMemoryMeterRegistry) MockHandler {
	return fn [registry] (req MockRequest) !MockResult {
		body, ct := serve_metrics(registry)
		return MockResult{
			status: 200
			body:   body
			headers: {
				'Content-Type': ct
			}
		}
	}
}

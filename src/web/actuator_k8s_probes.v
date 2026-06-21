module web

// actuator_k8s_probes.v - Kubernetes Liveness & Readiness Probes (SubTask D8.1, D8.2)
//
// Implements the two HTTP probes Kubernetes uses to manage pod lifecycle:
//
//   GET /health/liveness   — "is the process alive?"
//     200 {"status":"UP"}    → kubelet keeps routing traffic & won't restart
//     (never returns non-200; a dead process can't respond at all)
//
//   GET /health/readiness   — "is the app ready to serve traffic?"
//     200 {"status":"UP"}                → all SmartLifecycle beans running
//     503 {"status":"OUT_OF_SERVICE"}    → still starting up or shutting down
//
// These follow the K8s probe convention (200 = healthy, anything else =
// unhealthy) rather than the Spring Boot /health convention (which also
// uses 503 for DOWN). The split into separate liveness/readiness endpoints
// matches Spring Boot Actuator's health groups: "liveness" and "readiness".
//
// ── Liveness vs Readiness ──
//
// Liveness is a pure process-alive check. If the HTTP server can respond
// at all, the process is alive — so liveness always returns 200. K8s uses
// this to decide whether to restart the pod: a failing liveness probe
// triggers a restart. Returning non-200 from liveness would cause K8s to
// kill and restart the pod, which is rarely what you want for a transient
// "still starting" condition.
//
// Readiness is a "ready to serve" check. K8s uses this to decide whether
// to route traffic to the pod: a failing readiness probe removes the pod
// from the Service's endpoints but does NOT restart it. This is the
// correct place to report "still starting up" (503) — the pod stays alive
// but receives no traffic until all SmartLifecycle beans are running.
//
// ── Wiring ──
//
// Because Photon's routing is compile-time (veb scans @[get('/path')]
// methods on the App struct), the probes are wired in by adding methods
// to the application's App that delegate to serve_liveness() /
// serve_readiness(). This keeps the actuator decoupled from any specific
// App shape while remaining trivial to integrate:
//
//   import core
//   import web
//
//   pub struct App {
//       veb.Context
//   pub mut:
//       ctx &core.ApplicationContext = unsafe { nil }
//   }
//
//   @[get('/health/liveness')]
//   pub fn (mut app App) liveness() veb.Result {
//       body, ct, code := web.serve_liveness()
//       app.set_content_type(ct)
//       return app.status(code).text(body)
//   }
//
//   @[get('/health/readiness')]
//   pub fn (mut app App) readiness() veb.Result {
//       body, ct, code := web.serve_readiness(app.ctx)
//       app.set_content_type(ct)
//       return app.status(code).text(body)
//   }
//
// For tests, k8s_probe_mock_handler() returns a MockMvc-compatible handler
// that dispatches both probes.
import core

// probe_content_type is the Content-Type used by both K8s probe endpoints.
pub const probe_content_type = 'application/json'

// probe_status_up is the HTTP status code returned when the probe passes.
pub const probe_status_up = 200

// probe_status_down is the HTTP status code returned when the readiness
// probe fails (still starting or shutting down). The liveness probe never
// returns this — see file header for rationale.
pub const probe_status_down = 503

// serve_liveness implements the K8s liveness probe.
//
// Returns 200 with body {"status":"UP"} unconditionally — if the HTTP
// server can respond, the process is alive. K8s uses a failing liveness
// probe (non-200 or timeout) as a signal to restart the pod, so this
// endpoint must only fail when the process is genuinely broken.
//
// See file header for the liveness vs readiness distinction.
pub fn serve_liveness() (string, string, int) {
	body := '{"status":"UP"}'
	return body, probe_content_type, probe_status_up
}

// serve_readiness implements the K8s readiness probe.
//
// Returns 200 with body {"status":"UP"} when the application is ready to
// serve traffic (state is .ready/.started AND all SmartLifecycle beans
// report is_running() == true). Returns 503 with body
// {"status":"OUT_OF_SERVICE"} otherwise — K8s removes the pod from the
// Service's endpoints but does NOT restart it, which is the correct
// behavior for "still starting up" or "draining during shutdown".
//
// The readiness decision is delegated to ApplicationContext.is_readiness_ready(),
// which performs the state + SmartLifecycle aggregation under proper locking.
//
// A nil context is treated as not-ready (503) — this is the safe default
// for a misconfigured probe that hasn't been wired to the context.
pub fn serve_readiness(ctx &core.ApplicationContext) (string, string, int) {
	ready := if isnil(ctx) {
		false
	} else {
		mut c := unsafe { ctx }
		c.is_readiness_ready()
	}

	if ready {
		body := '{"status":"UP"}'
		return body, probe_content_type, probe_status_up
	}
	body := '{"status":"OUT_OF_SERVICE"}'
	return body, probe_content_type, probe_status_down
}

// k8s_probe_mock_handler returns a MockHandler that dispatches both the
// liveness and readiness probes. Use it with MockMvc to test the probe
// endpoints without a running HTTP server:
//
//   mut ctx := core.new_application_context()
//   // ... register beans, refresh() ...
//
//   mut mvc := web.new_mockmvc()
//   mvc.get('/health/liveness', web.k8s_probe_mock_handler(ctx))
//   mvc.get('/health/readiness', web.k8s_probe_mock_handler(ctx))
//
//   live := mvc.perform(web.mock_request('GET', '/health/liveness'))!
//   live.assert_ok()!
//
//   ready := mvc.perform(web.mock_request('GET', '/health/readiness'))!
//   ready.assert_status(200)!  // or 503 if still starting
//
// Unknown paths return 404 so the handler can be registered under both
// probe routes without path collisions.
pub fn k8s_probe_mock_handler(ctx &core.ApplicationContext) MockHandler {
	return fn [ctx] (req MockRequest) !MockResult {
		if req.method == 'GET' && req.path == '/health/liveness' {
			body, ct, code := serve_liveness()
			return MockResult{
				status:  code
				body:    body
				headers: {
					'Content-Type': ct
				}
			}
		}
		if req.method == 'GET' && req.path == '/health/readiness' {
			body, ct, code := serve_readiness(ctx)
			return MockResult{
				status:  code
				body:    body
				headers: {
					'Content-Type': ct
				}
			}
		}
		return MockResult{
			status:  404
			body:    '{"error":"not found"}'
			headers: {
				'Content-Type': probe_content_type
			}
		}
	}
}

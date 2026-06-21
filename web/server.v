module web

// server.v — Photon Web Server (Spring Boot-style wrapper)
//
// Encapsulates V's veb framework behind a clean single-generic API.
// The user only sees `web.run[MyApp](port)` — no dual-generics,
// no raw veb imports needed in application code.
//
// Also provides built-in request logging utilities and graceful shutdown
// integration (Task D4).
import veb
import net.http
import time

// ── Server — clean single-generic wrapper ──

// run starts the Photon web server on the given port, binding to 0.0.0.0 (all interfaces).
//
// Usage:
//   web.run[MyApp, MyContext](8080)
//
// Requirements:
//   - MyApp: global application struct (can be empty or hold shared state)
//   - MyContext: per-request context struct that embeds veb.Context
//   - Route handlers: fn (mut app MyApp) handler(mut ctx MyContext) veb.Result
//
// Example:
//   pub struct Context { veb.Context }
//   pub struct App {}
//   pub fn (mut app App) index(mut ctx Context) veb.Result {
//       return ctx.text('Hello')
//   }
//   web.run[App, Context](8080)
pub fn run[A, X](port int) {
	mut app := &A{}
	veb.run_at[A, X](mut app, host: '0.0.0.0', port: port, family: .ip) or { panic(err) }
}

// run_with_routes starts the Photon web server and prints all registered routes.
//
// Usage:
//   web.run_with_routes[MyApp, MyContext](8080)
pub fn run_with_routes[A, X](port int) {
	mut app := &A{}
	routes := scan_controller[A]()
	println('')
	println('  Photon Web Server starting on port ${port}...')
	print_routes(routes)
	veb.run_at[A, X](mut app, host: '0.0.0.0', port: port, family: .ip) or { panic(err) }
}

// ── Graceful Shutdown Integration (Task D4) ──

// GracefulServerConfig configures a graceful-shutdown-enabled web server.
//
// Usage:
//   mut cfg := web.GracefulServerConfig{
//       port: 8080
//       shutdown_timeout: 30 * time.second
//   }
//   cfg.run[App, Context]()
pub struct GracefulServerConfig {
pub:
	port             int = 8080
	shutdown_timeout time.Duration = default_graceful_shutdown_timeout
	// on_shutdown is called after in-flight requests have drained (or the
	// timeout has elapsed). Typically used to call ApplicationContext.shutdown().
	on_shutdown fn () = unsafe { nil }
}

// new_graceful_server_config creates a default GracefulServerConfig for the
// given port. The shutdown timeout defaults to 30 seconds.
pub fn new_graceful_server_config(port int) GracefulServerConfig {
	return GracefulServerConfig{
		port: port
	}
}

// run_with_graceful_shutdown starts the Photon web server with SIGTERM/SIGINT-
// triggered graceful shutdown. The server blocks the calling goroutine until
// a shutdown signal is received and in-flight requests have drained.
//
// This is the recommended way to run a production Photon web server. The
// returned GracefulShutdownManager can be used in before_request() to reject
// new requests during shutdown:
//
//   mut gsm := web.run_with_graceful_shutdown[App, Context](8080, fn () {
//       app_ctx.shutdown()
//   })
//
// In the App's before_request():
//   pub fn (mut app App) before_request() {
//       gsm.request_started()!  // rejects with 503 if shutting down
//   }
//
// In the App's after_request():
//   pub fn (mut app App) after_request() {
//       gsm.request_completed()
//   }
pub fn run_with_graceful_shutdown[A, X](port int, on_shutdown fn ()) &GracefulShutdownManager {
	mut gsm := new_graceful_shutdown_manager()
	gsm.set_on_shutdown(on_shutdown)
	gsm.start_signal_listener()

	mut app := &A{}
	routes := scan_controller[A]()
	println('')
	println('  Photon Web Server starting on port ${port}... (graceful shutdown enabled)')
	print_routes(routes)
	println('  Shutdown timeout: ${gsm.timeout}')
	println('  Send SIGTERM/SIGINT to initiate graceful shutdown.')

	// Run the veb server in a background goroutine. The main goroutine
	// blocks on gsm.wait() until a signal is received.
	spawn fn [mut gsm, mut app] () {
		veb.run_at[A, X](mut app, host: '0.0.0.0', port: port, family: .ip) or {
			eprintln('[web] veb server error: ${err}')
			// If the server fails to start, trigger shutdown so the main
			// goroutine doesn't block forever.
			gsm.shutdown()
		}
	}(mut gsm, mut app)

	// Block until shutdown() is called (by the signal listener or by
	// request_started() rejection logic). shutdown() drains in-flight
	// requests and calls the on_shutdown callback.
	gsm.wait()

	// Give the veb server a moment to stop accepting new connections.
	// In production, the on_shutdown callback should call veb.Server.shutdown()
	// if the app implements HasInitServer.
	time.sleep(100 * time.millisecond)

	return gsm
}

// handle_request_with_gsm wraps a request handler with graceful-shutdown
// tracking. Call this at the start of before_request() and pair it with
// complete_request_with_gsm() in after_request().
//
// Returns an error if the server is shutting down — the caller should
// return a 503 Service Unavailable response.
//
// Usage in App.before_request():
//   pub fn (mut app App) before_request() {
//       web.handle_request_with_gsm(mut app.gsm)!  // 503 if shutting down
//   }
//
// Usage in App.after_request():
//   pub fn (mut app App) after_request() {
//       web.complete_request_with_gsm(mut app.gsm)
//   }
pub fn handle_request_with_gsm(mut gsm GracefulShutdownManager) ! {
	gsm.request_started()!
}

// complete_request_with_gsm marks a request as completed. Must be called
// exactly once for each successful handle_request_with_gsm() call.
pub fn complete_request_with_gsm(mut gsm GracefulShutdownManager) {
	gsm.request_completed()
}

// reject_if_shutting_down returns a 503 Service Unavailable veb.Result if
// the GracefulShutdownManager is shutting down. Otherwise it returns
// veb.Result{} (no response — the request should proceed normally).
//
// Usage in App.before_request():
//   pub fn (mut app App) before_request() {
//       if result := web.reject_if_shutting_down(mut app.gsm, mut app.Context) {
//           return result
//       }
//       app.gsm.request_started()!
//   }
pub fn reject_if_shutting_down(mut gsm GracefulShutdownManager, mut ctx veb.Context) ?veb.Result {
	gsm.request_started() or {
		ctx.res.set_status(unsafe { http.Status(503) })
		ctx.set_content_type('application/json')
		return ctx.text('{"error":"server is shutting down","code":503}')
	}
	return none
}

// ── Request Logging — Spring Boot-style structured format ──

// RequestInfo captures rich request metadata for logging.
pub struct RequestInfo {
pub:
	method     string
	path       string
	host       string
	ip         string
	user_agent string
	start_ms   i64
}

// new_request_info creates a RequestInfo from the current veb.Context.
// Extracts method, path, host, client IP, and User-Agent.
//
// Usage inside before_request():
//   pub fn (mut app MyApp) before_request() {
//       info := web.new_request_info(mut app.Context)
//       web.log_request_start(app.logger.info, info)
//       app.request_info = info  // store for end logging
//   }
pub fn new_request_info(mut ctx veb.Context) RequestInfo {
	return RequestInfo{
		method:     ctx.req.method.str()
		path:       ctx.req.url
		host:       ctx.req.host
		ip:         client_ip(&ctx)
		user_agent: ctx.req.user_agent
		start_ms:   time.ticks()
	}
}

// client_ip extracts the client IP address from the request.
// Checks X-Forwarded-For and X-Real-IP headers first (for proxied setups),
// then falls back to remote connection address.
pub fn client_ip(ctx &veb.Context) string {
	// Check common proxy headers
	if ip := ctx.get_custom_header('X-Forwarded-For') {
		// X-Forwarded-For may contain multiple IPs; take the first one
		parts := ip.split(',')
		if parts.len > 0 {
			return parts[0].trim_space()
		}
	}
	if ip := ctx.get_custom_header('X-Real-IP') {
		return ip
	}
	// Try remote connection address
	if ctx.conn != unsafe { nil } {
		mut conn := ctx.conn
		addr := conn.peer_ip() or { return '-' }
		return addr.str()
	}
	return '-'
}

// log_request_start logs the start of a request in a structured format.
// Format: "GET /api/users | IP: 192.168.1.1 | UA: Chrome/120"
pub fn log_request_start(log_fn fn (string), info RequestInfo) {
	log_fn('${info.method} ${info.path} | IP: ${info.ip} | UA: ${info.user_agent}')
}

// log_request_end logs the end of a request with status and duration.
// Format: "GET /api/users → 200 (12ms)"
pub fn log_request_end(log_fn fn (string), info RequestInfo, status int) {
	elapsed_ms := time.ticks() - info.start_ms
	log_fn('${info.method} ${info.path} → ${status} (${elapsed_ms}ms)')
}

// log_error logs a request that resulted in an error.
// Format: "GET /api/users → ERROR: connection refused (500)"
pub fn log_request_error(log_fn fn (string), info RequestInfo, code int, msg string) {
	elapsed_ms := time.ticks() - info.start_ms
	log_fn('${info.method} ${info.path} → ${code} "${msg}" (${elapsed_ms}ms)')
}

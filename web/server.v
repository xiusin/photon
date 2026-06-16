module web

// server.v — Photon Web Server (Spring Boot-style wrapper)
//
// Encapsulates V's veb framework behind a clean single-generic API.
// The user only sees `web.run[MyApp](port)` — no dual-generics,
// no raw veb imports needed in application code.
//
// Also provides built-in request logging utilities.
import veb
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

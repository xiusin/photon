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

// run starts the Photon web server on the given port.
//
// Usage:
//   web.run[MyController](8080)
//
// Requirements: MyController must embed veb.Context directly.
//
// This is equivalent to Spring Boot's @SpringBootApplication → run().
pub fn run[T](port int) {
	mut app := &T{}
	veb.run[T, T](mut app, port)
}

// run_with_routes starts the Photon web server and prints all registered routes.
//
// Usage:
//   web.run_with_routes[MyController](8080)
//
// This is useful for development to see all available endpoints at startup.
pub fn run_with_routes[T](port int) {
	routes := scan_controller[T]()
	println('')
	println('  Photon Web Server starting on port ${port}...')
	print_routes(routes)
	mut app := &T{}
	veb.run[T, T](mut app, port)
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

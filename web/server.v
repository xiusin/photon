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
// Requirements: MyController must embed web.BaseController (which embeds veb.Context).
//
// This is equivalent to Spring Boot's @SpringBootApplication → run().
pub fn run[T](port int) {
	mut app := &T{}
	veb.run[T, T](mut app, port)
}

// ── Request Logging Utilities ──

// RequestInfo captures request metadata for logging.
pub struct RequestInfo {
pub:
	method   string
	path     string
	start_ms i64
}

// request_info creates a RequestInfo for the current request.
pub fn request_info(mut ctx veb.Context) RequestInfo {
	return RequestInfo{
		method: ctx.req.method.str()
		path: ctx.req.url
		start_ms: time.ticks()
	}
}

// log_request_start logs the start of a request.
pub fn log_request_start(log_fn fn (string), info &RequestInfo) {
	log_fn('[${info.method}] ${info.path}')
}

// log_request_end logs the end of a request with duration in ms.
pub fn log_request_end(log_fn fn (string), info &RequestInfo, status int) {
	elapsed_ms := time.ticks() - info.start_ms
	log_fn('[${info.method}] ${info.path} → ${status} (${elapsed_ms}ms)')
}

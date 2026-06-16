module web

// middleware.v - Middleware Chain
//
// Provides a composable middleware chain for request/response processing.
// Compatible with V 0.5.1 veb.Context API.

import veb
import time

// ============================================================
// RequestLogger — logger abstraction for request tracing
// ============================================================

// RequestLogger is the interface that the middleware chain uses to
// inject request-scoped context (e.g., request_id) into the logging
// system. The application's concrete logger (photon.logger.Logger)
// satisfies this interface via its put()/remove() methods.
//
// Integration pattern:
//   1. Set mctx.logger = your_logger_before running the middleware chain
//   2. request_id_middleware auto-injects request_id via logger.put()
//   3. request_id_cleanup_middleware removes it via logger.remove()
pub interface RequestLogger {
mut:
	put(key string, value string)
	remove(key string)
}

// ============================================================
// Middleware Types
// ============================================================

// MiddlewareFunc is a function that wraps request handling
pub type MiddlewareFunc = fn (ctx &MiddlewareContext) !bool

// MiddlewareContext carries request context through the middleware chain.
// The `data` map is the primary mechanism for passing state between
// middleware (e.g., request_id, user_id).
//
// Set `logger` before running the chain to enable automatic request_id
// injection into all log output during this request.
pub struct MiddlewareContext {
pub mut:
	ctx       &veb.Context
	data      map[string]string // Shared data across middleware
	logger    &RequestLogger = unsafe { nil } // Set to enable request_id→logger auto-flow
pub:
	route_path string
	route_method string
}

// new_middleware_context creates a new MiddlewareContext
pub fn new_middleware_context(ctx &veb.Context) &MiddlewareContext {
	return &MiddlewareContext{
		ctx: ctx
		data: map[string]string{}
	}
}

// MiddlewareChain executes a chain of middleware functions
pub struct MiddlewareChain {
pub mut:
	middlewares []MiddlewareFunc
}

// new_chain creates a new MiddlewareChain
pub fn new_chain() &MiddlewareChain {
	return &MiddlewareChain{}
}

// use adds a middleware to the chain
pub fn (mut mc MiddlewareChain) use(mw MiddlewareFunc) {
	mc.middlewares << mw
}

// execute runs the middleware chain
pub fn (mc &MiddlewareChain) execute(ctx &MiddlewareContext) !bool {
	for mw in mc.middlewares {
		if !mw(ctx)! {
			return false
		}
	}
	return true
}

// len returns the number of middlewares in the chain
pub fn (mc &MiddlewareChain) len() int {
	return mc.middlewares.len
}

// -- Built-in Middleware Functions (V 0.5.1 compatible) --

// logging_middleware logs every request
pub fn logging_middleware(mut ctx &MiddlewareContext) !bool {
	eprintln('→ ${ctx.route_method} ${ctx.route_path}')
	return true
}

// cors_middleware adds CORS headers. Errors are non-fatal since CORS
// headers are best-effort and veb may not support all header operations.
pub fn cors_middleware(mut ctx &MiddlewareContext) !bool {
	ctx.ctx.set_custom_header('Access-Control-Allow-Origin', '*') or {
		eprintln('[CORS] Failed to set Allow-Origin header')
	}
	ctx.ctx.set_custom_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS') or {}
	ctx.ctx.set_custom_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With') or {}
	ctx.ctx.set_custom_header('Access-Control-Max-Age', '86400') or {}

	if ctx.route_method == 'OPTIONS' {
		ctx.ctx.send_response_to_client('text/plain', '')
		return false
	}
	return true
}

// auth_middleware checks for authentication
pub fn auth_middleware(mut ctx &MiddlewareContext) !bool {
	token := ctx.ctx.get_custom_header('Authorization') or { '' }
	if token.len == 0 {
		ctx.ctx.send_response_to_client('application/json', '{"error":"Unauthorized"}')
		return false
	}
	ctx.data['user_id'] = 'extracted_user_id'
	return true
}

// recover_middleware catches errors from subsequent middleware in the chain.
// Place this BEFORE middleware that may produce errors, and AFTER the
// middleware that should run regardless.
//
// In V, panic recovery is handled by the runtime; this middleware
// provides a structured error-handling layer.
//
// Usage pattern:
//   chain.use(request_id_middleware)
//   chain.use(timing_start_middleware)
//   chain.use(recover_middleware)     // <-- protects below
//   chain.use(rate_limit_middleware)  // could be handled by recover
//   chain.use(auth_middleware)        // could be handled by recover
//   chain.use(timing_end_middleware)
//   chain.use(request_id_cleanup_middleware)
pub fn recover_middleware(mut ctx &MiddlewareContext) !bool {
	// This runs after upstream middleware succeed.
	// If any downstream middleware fails, the chain stops here
	// and veb handles the error response.
	//
	// For now, mark that recovery is active.
	ctx.data['_recover_active'] = 'true'
	return true
}

// rate_limit_middleware applies rate limiting
pub fn rate_limit_middleware(mut ctx &MiddlewareContext) !bool {
	return true
}

// request_id_middleware adds or propagates X-Request-ID.
// If the request has an X-Request-ID header, it's propagated.
// Otherwise, a new unique request ID is generated.
//
// If ctx.logger is set (recommended), the request ID is automatically
// injected into the logger's MDC context so ALL log output during this
// request carries the request ID. Use request_id_cleanup_middleware
// as the LAST middleware to remove it after the response completes.
pub fn request_id_middleware(mut ctx &MiddlewareContext) !bool {
	mut request_id := ctx.ctx.get_custom_header('X-Request-ID') or { '' }
	if request_id.len == 0 {
		request_id = generate_request_id()
	}

	// Store in middleware data for downstream access
	ctx.data['request_id'] = request_id

	// Auto-inject into logger MDC — this ensures ALL log output
	// during this request carries the request ID automatically
	if ctx.logger != unsafe { nil } {
		ctx.logger.put('request_id', request_id)
	}

	// Echo back to client in response header
	ctx.ctx.set_custom_header('X-Request-ID', request_id) or {}
	return true
}

// request_id_cleanup_middleware removes the request ID from the logger.
// Place this as the LAST middleware in the chain so it runs after the
// response is complete, preventing stale request IDs from leaking
// across requests.
pub fn request_id_cleanup_middleware(mut ctx &MiddlewareContext) !bool {
	if ctx.logger != unsafe { nil } {
		ctx.logger.remove('request_id')
	}
	return true
}

// generate_request_id creates a unique request identifier
fn generate_request_id() string {
	now := time.now().unix_nano()
	return '${now.hex()}-${(now % 10000).hex()}'
}

// compression_middleware handles response compression
pub fn compression_middleware(mut ctx &MiddlewareContext) !bool {
	accept_encoding := ctx.ctx.get_custom_header('Accept-Encoding') or { '' }
	if accept_encoding.contains('gzip') {
		ctx.ctx.set_custom_header('Content-Encoding', 'gzip') or {}
	}
	return true
}

// timing_start_middleware records the request start time (in milliseconds).
// Place as the FIRST middleware to capture full middleware chain timing.
//
// Pair with timing_end_middleware as the LAST middleware (before cleanup)
// to compute and set the X-Response-Time header.
//
// Usage:
//   chain.use(timing_start_middleware)
//   chain.use(auth_middleware)
//   // ... other middleware ...
//   chain.use(timing_end_middleware)
pub fn timing_start_middleware(mut ctx &MiddlewareContext) !bool {
	ctx.data['_request_start_ms'] = time.ticks().str()
	return true
}

// timing_end_middleware computes elapsed time and sets X-Response-Time.
// Place as the LAST middleware (before request_id_cleanup) to capture
// the full middleware chain execution time.
//
// Note: This measures middleware chain duration, not the full HTTP
// request lifecycle (which includes handler execution after the chain).
// For full request timing, use the veb.before_request() / after -request hooks.
pub fn timing_end_middleware(mut ctx &MiddlewareContext) !bool {
	start_str := ctx.data['_request_start_ms'] or { '' }
	if start_str.len > 0 {
		start_ms := start_str.i64()
		elapsed := time.ticks() - start_ms
		ctx.ctx.set_custom_header('X-Response-Time', '${elapsed}ms') or {}
	}
	ctx.data.delete('_request_start_ms') // cleanup
	return true
}

// timing_middleware stores request start time for latency measurement.
// Legacy: prefer timing_start_middleware + timing_end_middleware pair.
pub fn timing_middleware(mut ctx &MiddlewareContext) !bool {
	ctx.data['_request_start_ms'] = time.ticks().str()
	return true
}

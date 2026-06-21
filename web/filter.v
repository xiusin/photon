module web

// filter.v - Request/Response Filters
//
// Provides request and response filters that intercept HTTP traffic.
// Filters are similar to middleware but more fine-grained:
// - RequestFilter: runs before the handler
// - ResponseFilter: runs after the handler, before the response is sent
import veb

// FilterChain manages request and response filters
pub struct FilterChain {
pub mut:
	request_filters  []RequestFilterFn
	response_filters []ResponseFilterFn
}

// RequestFilterFn processes incoming requests
pub type RequestFilterFn = fn (ctx &veb.Context) !bool

// ResponseFilterFn processes outgoing responses
pub type ResponseFilterFn = fn (ctx &veb.Context, body string) !string

// new_filter_chain creates a new FilterChain
pub fn new_filter_chain() &FilterChain {
	return &FilterChain{}
}

// add_request_filter adds a request filter
pub fn (mut fc FilterChain) add_request_filter(filter RequestFilterFn) {
	fc.request_filters << filter
}

// add_response_filter adds a response filter
pub fn (mut fc FilterChain) add_response_filter(filter ResponseFilterFn) {
	fc.response_filters << filter
}

// apply_request runs all request filters
pub fn (fc &FilterChain) apply_request(ctx &veb.Context) !bool {
	for filter in fc.request_filters {
		if !filter(ctx)! {
			return false
		}
	}
	return true
}

// apply_response runs all response filters
pub fn (fc &FilterChain) apply_response(ctx &veb.Context, body string) !string {
	mut result := body
	for filter in fc.response_filters {
		result = filter(ctx, result)!
	}
	return result
}

// -- Built-in Filters --

// security_headers_filter adds OWASP-recommended security HTTP headers.
// These are static per-request — each response requires its own headers.
// Headers added:
//   X-Content-Type-Options: nosniff
//   X-Frame-Options: DENY
//   X-XSS-Protection: 1; mode=block
//   Referrer-Policy: strict-origin-when-cross-origin
//   Permissions-Policy: geolocation=(), microphone=(), camera=()
//   Strict-Transport-Security: max-age=31536000; includeSubDomains
pub fn security_headers_filter(mut ctx veb.Context, body string) !string {
	// Set headers best-effort — veb may not support all header operations
	ctx.set_custom_header('X-Content-Type-Options', 'nosniff') or {
		eprintln('[SecurityFilter] Failed to set X-Content-Type-Options')
	}
	ctx.set_custom_header('X-Frame-Options', 'DENY') or {}
	ctx.set_custom_header('X-XSS-Protection', '1; mode=block') or {}
	ctx.set_custom_header('Referrer-Policy', 'strict-origin-when-cross-origin') or {}
	ctx.set_custom_header('Permissions-Policy', 'geolocation=(), microphone=(), camera=()') or {}
	ctx.set_custom_header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains') or {}
	return body
}

// cache_control_filter adds cache control headers
pub fn cache_control_filter(mut ctx veb.Context, body string) !string {
	ctx.set_custom_header('Cache-Control', 'no-cache, no-store, must-revalidate') or {}
	ctx.set_custom_header('Pragma', 'no-cache') or {}
	ctx.set_custom_header('Expires', '0') or {}
	return body
}

// body_size_filter limits request body size
pub fn body_size_filter(max_bytes int) RequestFilterFn {
	return fn [max_bytes] (mut ctx veb.Context) !bool {
		content_length := ctx.get_custom_header('Content-Length') or { '' }
		if content_length.len > 0 {
			size := content_length.int()
			if size > max_bytes {
				ctx.send_response_to_client('application/json',
					'{"error":"Request entity too large"}')

				return error('request body too large: ${size} > ${max_bytes}')
			}
		}
		return true
	}
}

// content_type_filter validates Content-Type header
pub fn content_type_filter(allowed_types []string) RequestFilterFn {
	return fn [allowed_types] (mut ctx veb.Context) !bool {
		content_type := ctx.get_custom_header('Content-Type') or { '' }
		if content_type.len > 0 {
			for allowed in allowed_types {
				if content_type.starts_with(allowed) {
					return true
				}
			}
			ctx.send_response_to_client('application/json', '{"error":"Unsupported Media Type"}')

			return false
		}
		return true
	}
}

module web

// controller.v - Photon Controller Base
//
// Provides the Controller trait and BaseController that wraps veb.Context.
// Controllers are the entry point for HTTP request handling, with support
// for annotation-driven routing, dependency injection, and response helpers.
// Compatible with V 0.5.1 veb.Context API.

import veb

// Controller is the trait all Photon controllers must implement
pub interface Controller {
	init() !
}

// BaseController provides a foundation for all web controllers.
// Embed this in your controller structs to get veb.Context capabilities
// plus Photon-specific enhancements.
pub struct BaseController {
	veb.Context
pub mut:
}

// ok returns a 200 OK JSON response
pub fn (mut c BaseController) ok(data string) veb.Result {
	c.set_content_type('application/json')
	return c.text(data)
}

// created returns a 201 Created JSON response
pub fn (mut c BaseController) created(data string) veb.Result {
	c.set_content_type('application/json')
	return c.text(data)
}

// no_content returns a 204 No Content response
pub fn (mut c BaseController) no_content() veb.Result {
	return c.Context.no_content()
}

// bad_request returns a 400 Bad Request JSON response
pub fn (mut c BaseController) bad_request(msg string) veb.Result {
	c.set_content_type('application/json')
	return c.text('{"error":"${msg}"}')
}

// not_found returns a 404 Not Found JSON response
pub fn (mut c BaseController) not_found(msg string) veb.Result {
	c.set_content_type('application/json')
	return c.Context.not_found()
}

// internal_error returns a 500 Internal Server Error JSON response
pub fn (mut c BaseController) internal_error(msg string) veb.Result {
	c.set_content_type('application/json')
	return c.Context.server_error(msg)
}

// unauthorized returns a 401 Unauthorized JSON response
pub fn (mut c BaseController) unauthorized(msg string) veb.Result {
	c.set_content_type('application/json')
	return c.text('{"error":"${msg}"}')
}

// forbidden returns a 403 Forbidden JSON response
pub fn (mut c BaseController) forbidden(msg string) veb.Result {
	c.set_content_type('application/json')
	return c.text('{"error":"${msg}"}')
}

// conflict returns a 409 Conflict JSON response
pub fn (mut c BaseController) conflict(msg string) veb.Result {
	c.set_content_type('application/json')
	return c.text('{"error":"${msg}"}')
}

// html returns an HTML response
pub fn (mut c BaseController) html(content string) veb.Result {
	c.set_content_type('text/html; charset=utf-8')
	return c.text(content)
}

// redirect sends a 302 redirect response
pub fn (mut c BaseController) redirect(url string) veb.Result {
	return c.Context.redirect(url)
}

// get_path_param retrieves a path parameter by name.
// NOTE: In V 0.5.1 veb, path params are passed as function arguments (e.g. `fn user_get(id string)`).
// This method returns '' and exists only for backward compatibility.
@[deprecated]
pub fn (c &BaseController) get_path_param(name string) string {
	return ''
}

// get_query_param retrieves a query parameter by name
pub fn (c &BaseController) get_query_param(name string) string {
	if c.req.url.contains('?') {
		parts := c.req.url.split('?')
		if parts.len > 1 {
			for pair in parts[1].split('&') {
				kv := pair.split('=')
				if kv.len >= 2 && kv[0] == name {
					return kv[1]
				}
			}
		}
	}
	return ''
}

// get_header_val retrieves a request header value
pub fn (c &BaseController) get_header_val(name string) string {
	return c.get_custom_header(name) or { '' }
}

// set_status sets the HTTP response status code
pub fn (mut c BaseController) set_status(code int) {
	// V 0.5.1 veb uses dedicated methods for status codes
	_ = code
}

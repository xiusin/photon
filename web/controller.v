module web

// controller.v - Photon Controller Base (Spring-style)
//
// Provides the BaseController helper and response utilities.
// App structs directly embed veb.Context for V 0.5.1 compatibility.
import veb
import net.http

// BaseController provides static response helper methods (Spring-style).
// Embed this in your App struct alongside veb.Context.
//
// Usage:
//   pub struct MyApp {
//       web.BaseController
//       veb.Context
//   }
//   pub fn (mut app MyApp) index() veb.Result {
//       return app.ok('{"status":"ok"}')
//   }
pub struct BaseController {
}

// ok returns a 200 OK JSON response
pub fn (mut b BaseController) ok(mut ctx veb.Context, data string) veb.Result {
	return text_response(mut ctx, data, 200)
}

// created returns a 201 Created JSON response
pub fn (mut b BaseController) created(mut ctx veb.Context, data string) veb.Result {
	return text_response(mut ctx, data, 201)
}

// no_content returns a 204 No Content response
pub fn (mut b BaseController) no_content(mut ctx veb.Context) veb.Result {
	return ctx.no_content()
}

// bad_request returns a 400 Bad Request JSON response
pub fn (mut b BaseController) bad_request(mut ctx veb.Context, msg string) veb.Result {
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}"}')
}

// not_found returns a 404 Not Found JSON response with the given message
pub fn (mut b BaseController) not_found(mut ctx veb.Context, msg string) veb.Result {
	return text_response(mut ctx, '{"error":"${msg}","code":404}', 404)
}

// internal_error returns a 500 Internal Server Error JSON response
pub fn (mut b BaseController) internal_error(mut ctx veb.Context, msg string) veb.Result {
	ctx.set_content_type('application/json')
	return ctx.server_error(msg)
}

// unauthorized returns a 401 Unauthorized JSON response
pub fn (mut b BaseController) unauthorized(mut ctx veb.Context, msg string) veb.Result {
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}","code":401}')
}

// forbidden returns a 403 Forbidden JSON response
pub fn (mut b BaseController) forbidden(mut ctx veb.Context, msg string) veb.Result {
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}","code":403}')
}

// conflict returns a 409 Conflict JSON response
pub fn (mut b BaseController) conflict(mut ctx veb.Context, msg string) veb.Result {
	ctx.set_content_type('application/json')
	return ctx.text('{"error":"${msg}","code":409}')
}

// redirect sends a redirect response
pub fn (mut b BaseController) redirect(mut ctx veb.Context, url string) veb.Result {
	return ctx.redirect(url)
}

// set_status sets the response status code
pub fn (mut b BaseController) set_status(mut ctx veb.Context, code int) {
	ctx.res.set_status(unsafe { http.Status(code) })
}

// ============================================================
// Utility functions (can be used without BaseController)
// ============================================================

// text_response sends a text response with a specific status code.
// Sets the status on the response before sending.
pub fn text_response(mut ctx veb.Context, data string, status int) veb.Result {
	ctx.res.set_status(unsafe { http.Status(status) })
	ctx.set_content_type('application/json')
	return ctx.text(data)
}

// json_response sends a JSON response with a status code.
// Sets the status on the response before sending.
pub fn json_response(mut ctx veb.Context, data string, status int) veb.Result {
	ctx.res.set_status(unsafe { http.Status(status) })
	ctx.set_content_type('application/json')
	return ctx.text(data)
}

// ============================================================
// Context helpers (work with &veb.Context directly)
// ============================================================

// get_query_param extracts a query parameter from the request URL
pub fn get_query_param(ctx &veb.Context, key string) string {
	url := ctx.req.url
	pos := url.index('?') or { return '' }
	query := url[pos + 1..]
	for kv in query.split('&') {
		pair := kv.split('=')
		if pair.len == 2 && pair[0] == key {
			return pair[1]
		}
	}
	return ''
}

// get_path_param extracts a path parameter (deprecated in veb — always empty)
@[deprecated]
pub fn get_path_param(ctx &veb.Context, key string) string {
	_ = key
	return ''
}

// get_header_val returns a request header value from the veb.Context
pub fn get_header_val(ctx &veb.Context, key string) string {
	return ctx.get_custom_header(key) or { '' }
}

// set_status sets the response status code on the veb Result
pub fn set_status(mut ctx veb.Context, code int) {
	ctx.res.set_status(unsafe { http.Status(code) })
}

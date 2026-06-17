module apidoc

// handler.v — Self-hosted API Documentation Handler
//
// Provides serve_* functions that can be called from veb route handlers.
// The user needs to define thin wrapper methods on their App struct.
//
// Integration:
//   1. Embed apidoc.ApidocHandler in your App struct
//   2. Call app.setup_middleware[T]() to register before/after middleware
//   3. Define thin route wrappers for /__docs endpoints

import veb
import os

// ApidocHandler provides self-hosted API documentation.
// Embed this in your App struct alongside veb.Middleware[T].
@[heap]
pub struct ApidocHandler {
pub mut:
	store     &ApiDocStore = unsafe { nil }
	collector &Collector   = unsafe { nil }
}

// enable initializes the apidoc module.
pub fn enable() &ApidocHandler {
	store, collector := init('data/apidoc') or {
		eprintln('[apidoc] init failed: ${err}')
		panic('apidoc init failed: ${err}')
	}
	eprintln('[apidoc] enable() — initialized')
	return &ApidocHandler{
		store:     store
		collector: collector
	}
}

// before_middleware returns a veb middleware handler that captures request metadata.
// Register with: app.use(veb.MiddlewareOptions[T]{ handler: handler.before_middleware[T]() })
pub fn (mut h ApidocHandler) before_middleware[T]() veb.MiddlewareOptions[T] {
	return veb.MiddlewareOptions[T]{
		handler: fn [mut h] [T](mut ctx T) bool {
			if isnil(h.collector) || isnil(h.store) {
				eprintln('[apidoc] before_middleware — handler not initialized!')
				return true
			}
			path := ctx.req.url
			if path.starts_with('/__docs') {
				return true // skip docs paths
			}
			h.collector.collect(mut ctx.Context)
			return true
		}
	}
}

// after_middleware returns a veb middleware handler that captures response metadata.
// Register with: app.use(veb.MiddlewareOptions[T]{ handler: handler.after_middleware[T]() })
pub fn (mut h ApidocHandler) after_middleware[T]() veb.MiddlewareOptions[T] {
	return veb.MiddlewareOptions[T]{
		after:   true
		handler: fn [mut h] [T](mut ctx T) bool {
			if isnil(h.collector) || isnil(h.store) {
				return true
			}
			path := ctx.req.url
			if path.starts_with('/__docs') {
				return true // skip docs paths
			}
			h.collector.collect_response(mut ctx.Context)
			return true
		}
	}
}

// serve_index serves the dashboard HTML page
pub fn (mut h ApidocHandler) serve_index(mut ctx veb.Context) veb.Result {
	content := os.read_file('apidoc/static/index.html') or {
		return ctx.text('API Documentation UI not found')
	}
	ctx.set_content_type('text/html; charset=utf-8')
	return ctx.text(content)
}

// serve_static_file serves static assets (CSS, JS, etc.)
pub fn (mut h ApidocHandler) serve_static_file(mut ctx veb.Context, file string) veb.Result {
	safe := file.ends_with('.css') || file.ends_with('.js') || file.ends_with('.html')
		|| file.ends_with('.json') || file.ends_with('.png') || file.ends_with('.svg')
	if !safe {
		return ctx.text('unsupported file type')
	}

	content := os.read_file('apidoc/static/' + file) or {
		return ctx.text('file not found')
	}

	if file.ends_with('.css') { ctx.set_content_type('text/css; charset=utf-8') }
	else if file.ends_with('.js') { ctx.set_content_type('application/javascript; charset=utf-8') }
	else if file.ends_with('.json') { ctx.set_content_type('application/json; charset=utf-8') }
	else if file.ends_with('.png') { ctx.set_content_type('image/png') }
	else if file.ends_with('.svg') { ctx.set_content_type('image/svg+xml') }

	return ctx.text(content)
}

// serve_entries returns all documented endpoints as JSON
pub fn (mut h ApidocHandler) serve_entries(mut ctx veb.Context) veb.Result {
	entries := h.store.get_entries()
	mut items := []string{cap: entries.len}
	for e in entries {
		items << e.to_json()
	}
	ctx.set_content_type('application/json')
	return ctx.text('{"code":0,"msg":"OK","data":[' + items.join(',') + ']}')
}

// serve_entry returns or modifies a single endpoint
pub fn (mut h ApidocHandler) serve_entry(mut ctx veb.Context, id string) veb.Result {
	method := ctx.req.method.str()
	match method {
		'GET' {
			entry := h.store.get_entry(id) or {
				ctx.set_content_type('application/json')
				return ctx.text('{"code":404,"msg":"entry not found"}')
			}
			ctx.set_content_type('application/json')
			return ctx.text('{"code":0,"msg":"OK","data":' + entry.to_json() + '}')
		}
		'PUT' {
			action := ctx.query['action'] or { 'lock' }
			match action {
				'lock' { h.store.lock_endpoint(id) }
				'unlock' { h.store.unlock_endpoint(id) }
				else {}
			}
			ctx.set_content_type('application/json')
			return ctx.text('{"code":0,"msg":"OK","data":{}}')
		}
		'DELETE' {
			h.store.delete_entry(id) or {
				ctx.set_content_type('application/json')
				return ctx.text('{"code":500,"msg":"delete failed"}')
			}
			ctx.set_content_type('application/json')
			return ctx.text('{"code":0,"msg":"deleted","data":{}}')
		}
		else {
			ctx.set_content_type('application/json')
			return ctx.text('{"code":405,"msg":"method not allowed"}')
		}
	}
}

// serve_export exports OpenAPI 3.0 JSON
pub fn (mut h ApidocHandler) serve_export(mut ctx veb.Context) veb.Result {
	openapi := h.store.export_openapi()
	ctx.set_content_type('application/json')
	return ctx.text(openapi)
}
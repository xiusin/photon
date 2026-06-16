module web

// web_integration_test.v - Integration tests for veb server with two-type pattern [App, Context]
//
// NOTE: veb.run_at must run in the main thread and cannot be spawned.
// Server integration tests are verified via example/main.v which demonstrates:
// - Two-type pattern: App (global state) + Context (per-request)
// - Route handlers: fn (mut app App) handler(mut ctx Context) veb.Result
// - HTTP responses work correctly with this pattern

import veb

// ── Test App & Context (two-type pattern) ──

pub struct TestContext {
	veb.Context
}

pub struct TestApp {
pub mut:
	request_count int
}

pub fn (mut app TestApp) index(mut ctx TestContext) veb.Result {
	return ctx.text('hello')
}

pub fn (mut app TestApp) ping(mut ctx TestContext) veb.Result {
	return ctx.text('pong')
}

pub fn (mut app TestApp) echo(mut ctx TestContext) veb.Result {
	name := ctx.query['name'] or { 'world' }
	return ctx.text('hello ${name}')
}

pub fn (mut app TestApp) count(mut ctx TestContext) veb.Result {
	app.request_count++
	return ctx.text('${app.request_count}')
}

// ── Route Scanning Tests ──
// These tests verify that scan_controller correctly detects routes
// using the two-type pattern [App, Context].
// Routes are methods on the App type, so we scan TestApp.

fn test_scan_controller_detects_routes() {
	routes := scan_controller[TestApp]()
	assert routes.len >= 4
}

fn test_scan_controller_index_route() {
	routes := scan_controller[TestApp]()
	mut found := false
	for r in routes {
		if r.path == '/' && r.handler_name == 'index' {
			found = true
			assert r.method == 'GET'
		}
	}
	assert found
}

fn test_scan_controller_ping_route() {
	routes := scan_controller[TestApp]()
	mut found := false
	for r in routes {
		if r.path == '/ping' && r.handler_name == 'ping' {
			found = true
			assert r.method == 'GET'
		}
	}
	assert found
}

fn test_scan_controller_echo_route() {
	routes := scan_controller[TestApp]()
	mut found := false
	for r in routes {
		if r.path == '/echo' && r.handler_name == 'echo' {
			found = true
			assert r.method == 'GET'
		}
	}
	assert found
}

fn test_scan_controller_count_route() {
	routes := scan_controller[TestApp]()
	mut found := false
	for r in routes {
		if r.path == '/count' && r.handler_name == 'count' {
			found = true
			assert r.method == 'GET'
		}
	}
	assert found
}

fn test_scan_controller_skips_lifecycle_hooks() {
	routes := scan_controller[TestApp]()
	for r in routes {
		assert r.handler_name != 'before_request'
		assert r.handler_name != 'after_request'
	}
}

fn test_print_routes_output() {
	routes := scan_controller[TestApp]()
	// Verify print_routes doesn't panic with valid routes
	print_routes(routes)
	assert routes.len > 0
}

fn test_print_routes_empty() {
	// Verify print_routes handles empty routes gracefully
	print_routes([])
}

module web

// router.v - Annotation-Driven Router
//
// Provides compile-time route scanning and generation on top of veb.
// Scans controller structs for @[get('/path')], @[post('/path')], etc.
// and generates corresponding veb route handlers at compile time.
import veb

// RouteInfo describes a single route
pub struct RouteInfo {
pub:
	method       string   // HTTP method: GET, POST, PUT, DELETE, PATCH
	path         string   // Route path: /users/:id
	handler_name string   // Method name
	middlewares  []string // Middleware names to apply
}

// RouterConfig configures the route scanner
pub struct RouterConfig {
pub mut:
	base_path    string = '/' // Base path prefix for all routes
	scan_package string // Package to scan for controllers
	enable_log   bool   // Log route registration
}

// RouteRegistry holds all registered routes
pub struct RouteRegistry {
pub mut:
	routes []RouteInfo
}

// new_route_registry creates a new RouteRegistry
pub fn new_route_registry() &RouteRegistry {
	return &RouteRegistry{}
}

// register adds a route to the registry
pub fn (mut rr RouteRegistry) register(method string, path string, handler_name string) {
	rr.routes << RouteInfo{
		method:       method
		path:         path
		handler_name: handler_name
	}
}

// get returns a GET route
pub fn get(path string, handler_name string) RouteInfo {
	return RouteInfo{
		method:       'GET'
		path:         path
		handler_name: handler_name
	}
}

// post returns a POST route
pub fn post(path string, handler_name string) RouteInfo {
	return RouteInfo{
		method:       'POST'
		path:         path
		handler_name: handler_name
	}
}

// put returns a PUT route
pub fn put(path string, handler_name string) RouteInfo {
	return RouteInfo{
		method:       'PUT'
		path:         path
		handler_name: handler_name
	}
}

// del returns a DELETE route
pub fn del(path string, handler_name string) RouteInfo {
	return RouteInfo{
		method:       'DELETE'
		path:         path
		handler_name: handler_name
	}
}

// patch returns a PATCH route
pub fn patch(path string, handler_name string) RouteInfo {
	return RouteInfo{
		method:       'PATCH'
		path:         path
		handler_name: handler_name
	}
}

// group creates a route group with a common prefix and optional shared middleware.
// Middleware specified on the group is inherited by all routes in the group.
pub fn group(prefix string, routes []RouteInfo) []RouteInfo {
	mut result := []RouteInfo{}
	for route in routes {
		result << RouteInfo{
			method:       route.method
			path:         prefix + route.path
			handler_name: route.handler_name
			middlewares:  route.middlewares.clone()
		}
	}
	return result
}

// group_with_middleware creates a route group with shared middleware
pub fn group_with_middleware(prefix string, routes []RouteInfo, middlewares []string) []RouteInfo {
	mut result := []RouteInfo{}
	for route in routes {
		mut mw := middlewares.clone()
		mw << route.middlewares
		result << RouteInfo{
			method:       route.method
			path:         prefix + route.path
			handler_name: route.handler_name
			middlewares:  mw
		}
	}
	return result
}

// scan_controller uses comptime to scan a controller for route attributes
// and generate veb-compatible route handlers.
// Supports both annotation-based routes (@[get('/path')]) and convention-based
// routes (methods returning veb.Result with automatic path mapping).
pub fn scan_controller[T]() []RouteInfo {
	mut routes := []RouteInfo{}

	$for method in T.methods {
		mut found_route := false
		mut http_method := ''
		mut path := ''

		// Check for HTTP method attributes (annotation-based)
		for attr in method.attrs {
			if attr == 'get' || attr == 'post' || attr == 'put' || attr == 'delete'
				|| attr == 'patch' {
				http_method = attr.to_upper()
				found_route = true
			}
			if attr.starts_with('/') {
				path = attr
			}
		}

		// Convention-based: methods returning veb.Result are routes
		$if method.return_type is veb.Result {
			if !found_route {
				http_method = 'GET'
				found_route = true
			}
		}

		if found_route {
			name := method.name
			// Skip lifecycle hooks
			if name != 'before_request' && name != 'after_request' {
				if path.len == 0 {
					if name == 'index' {
						path = '/'
					} else {
						path = '/${name}'
					}
				}
				// Collect middleware declarations from @[middleware('name')] attributes.
				// V stores attributes as strings; middleware names follow the 'middleware' keyword.
				mut middlewares := []string{}
				mut collecting := false
				for attr in method.attrs {
					if attr == 'middleware' {
						collecting = true
						continue
					}
					if collecting {
						// Eat individual middleware name arguments
						trimmed := attr.trim_space().trim("'").trim('"')
						if trimmed.len > 0 && trimmed[0] != `/` {
							middlewares << trimmed
							continue
						}
						collecting = false
					}
				}
				routes << RouteInfo{
					method:       http_method
					path:         path
					handler_name: name
					middlewares:  middlewares
				}
			}
		}
	}
	return routes
}

// print_routes prints all registered routes in a clean table format
pub fn print_routes(routes []RouteInfo) {
	if routes.len == 0 {
		return
	}
	println('')
	println('  Registered Routes:')
	println('  ${'─'.repeat(60)}')
	println('  ${'METHOD':-8s} ${'PATH':-30s} ${'HANDLER'}')
	println('  ${'─'.repeat(60)}')
	for route in routes {
		println('  ${route.method:-8s} ${route.path:-30s} ${route.handler_name}')
	}
	println('  ${'─'.repeat(60)}')
	println('  Total: ${routes.len} route(s)')
	println('')
}

// print_registered_routes scans a controller type and prints all its routes
pub fn print_registered_routes[T]() {
	routes := scan_controller[T]()
	print_routes(routes)
}

module web

// actuator_introspection.v - Spring Boot Actuator-style Introspection Endpoints
// (SubTask D6: /env, /beans, /mappings)
//
// Exposes application internals over HTTP in JSON format, following the
// Spring Boot Actuator convention:
//
//   GET /env      — all configuration key-values (sensitive keys masked)
//   GET /beans    — all registered beans (name/type/scope/lazy)
//   GET /mappings — all route mappings (method/path/handler)
//
// Sensitive keys (password, secret, token, key, credential, api_key) are
// automatically masked with '******' to prevent accidental credential
// leakage through the /env endpoint.
//
// Because Photon's routing is compile-time (veb scans @[get('/path')] methods
// on the App struct), the endpoints are wired in by adding methods to the
// application's App that delegate to serve_env()/serve_beans()/serve_mappings().
// This keeps the actuator decoupled from any specific App shape while
// remaining trivial to integrate:
//
//   import core
//   import web
//
//   pub struct App {
//       veb.Context
//   pub mut:
//       environment      &core.Environment       = unsafe { nil }
//       app_context      &core.ApplicationContext = unsafe { nil }
//       route_registry   &web.RouteRegistry       = unsafe { nil }
//   }
//
//   @[get('/env')]
//   pub fn (mut app App) env() veb.Result {
//       body, ct, code := web.serve_env(app.environment)
//       app.set_content_type(ct)
//       return app.status(code).text(body)
//   }
//
//   @[get('/beans')]
//   pub fn (mut app App) beans() veb.Result {
//       body, ct, code := web.serve_beans(app.app_context)
//       app.set_content_type(ct)
//       return app.status(code).text(body)
//   }
//
//   @[get('/mappings')]
//   pub fn (mut app App) mappings() veb.Result {
//       body, ct, code := web.serve_mappings(app.route_registry.routes)
//       app.set_content_type(ct)
//       return app.status(code).text(body)
//   }
//
// For tests, env_mock_handler()/beans_mock_handler()/mappings_mock_handler()
// return MockMvc-compatible handlers.
import core
import strings

// introspection_content_type is the Content-Type used by all introspection
// endpoints (/env, /beans, /mappings).
pub const introspection_content_type = 'application/json'

// sensitive_patterns are the substrings (matched case-insensitively) that
// cause a property value to be masked in the /env output. Adding a pattern
// here is the single point of change for extending the masking policy.
//
// Spring equivalent: Spring Boot's Sanitizer with keys matching
// "password|secret|token|key|credential".
pub const sensitive_patterns = ['password', 'secret', 'token', 'key', 'credential', 'api_key']

// masked_value is the placeholder shown in place of a sensitive property's
// real value in the /env output.
pub const masked_value = '******'

// mask_sensitive_value returns the masked value if the key matches any
// sensitive pattern (case-insensitive), otherwise returns the original value.
//
// The match is a substring check on the lowercased key, so 'db.password',
// 'API_TOKEN', and 'secret_key' are all masked.
//
// Usage:
//   mask_sensitive_value('db.password', 'hunter2')  // → '******'
//   mask_sensitive_value('app.name', 'Photon')      // → 'Photon'
pub fn mask_sensitive_value(key string, value string) string {
	key_lower := key.to_lower()
	for pattern in sensitive_patterns {
		if key_lower.contains(pattern) {
			return masked_value
		}
	}
	return value
}

// json_escape escapes a string for safe inclusion as a JSON string value.
// Handles the required characters: " \ and control characters (\n, \r, \t).
fn json_escape(s string) string {
	if s.len == 0 {
		return ''
	}
	mut sb := strings.new_builder(s.len)
	for ch in s {
		match ch {
			`"` { sb.write_string('\\"') }
			`\\` { sb.write_string('\\\\') }
			`\n` { sb.write_string('\\n') }
			`\r` { sb.write_string('\\r') }
			`\t` { sb.write_string('\\t') }
			else {
				if ch < 0x20 {
					sb.write_string('\\u${ch:04x}')
				} else {
					sb.write_string(ch.ascii_str())
				}
			}
		}
	}
	return sb.str()
}

// serve_env renders all environment properties as JSON following the Spring
// Boot Actuator /env convention. Sensitive keys are masked.
//
// Returns the JSON body, Content-Type, and HTTP status code (always 200).
// Intended to be called from a veb route handler (see file header for usage).
//
// Output structure:
//   {"propertySources":[{"name":"environment","properties":{
//     "app.name":{"value":"Photon"},
//     "db.password":{"value":"******"}
//   }}]}
pub fn serve_env(env &core.Environment) (string, string, int) {
	mut e := unsafe { env }
	keys := e.all_property_keys()

	mut sb := strings.new_builder(512)
	sb.write_string('{"propertySources":[{')
	sb.write_string('"name":"environment",')
	sb.write_string('"properties":{')

	mut first := true
	for key in keys {
		if !first {
			sb.write_string(',')
		}
		first = false
		value := e.get_property(key)
		masked := mask_sensitive_value(key, value)
		sb.write_string('"${json_escape(key)}":{"value":"${json_escape(masked)}"}')
	}

	sb.write_string('}}]}')
	return sb.str(), introspection_content_type, 200
}

// serve_beans renders all registered beans as JSON following the Spring Boot
// Actuator /beans convention.
//
// Returns the JSON body, Content-Type, and HTTP status code (always 200).
// Intended to be called from a veb route handler (see file header for usage).
//
// Output structure:
//   {"context":"application","beans":[
//     {"name":"UserService","type":"UserService","scope":"singleton","lazy":false}
//   ]}
pub fn serve_beans(ctx &core.ApplicationContext) (string, string, int) {
	mut c := unsafe { ctx }
	beans := c.list_beans()

	mut sb := strings.new_builder(512)
	sb.write_string('{"context":"application",')
	sb.write_string('"beans":[')

	mut first := true
	for bean in beans {
		if !first {
			sb.write_string(',')
		}
		first = false
		sb.write_string('{')
		sb.write_string('"name":"${json_escape(bean.name)}",')
		sb.write_string('"type":"${json_escape(bean.typ)}",')
		sb.write_string('"scope":"${json_escape(bean.scope)}",')
		sb.write_string('"lazy":${bean.lazy}')
		sb.write_string('}')
	}

	sb.write_string(']}')
	return sb.str(), introspection_content_type, 200
}

// serve_mappings renders all route mappings as JSON following the Spring Boot
// Actuator /mappings convention.
//
// Returns the JSON body, Content-Type, and HTTP status code (always 200).
// Intended to be called from a veb route handler (see file header for usage).
//
// Output structure:
//   {"contexts":{"application":{"mappings":{"dispatcherServlets":{
//     "dispatcherServlet":[
//       {"details":{"requestMappingConditions":{
//         "methods":["GET"],"patterns":["/users"]
//       }},"handler":"users"}
//     ]
//   }}}}}
pub fn serve_mappings(routes []RouteInfo) (string, string, int) {
	mut sb := strings.new_builder(512)
	sb.write_string('{"contexts":{')
	sb.write_string('"application":{')
	sb.write_string('"mappings":{')
	sb.write_string('"dispatcherServlets":{')
	sb.write_string('"dispatcherServlet":[')

	mut first := true
	for route in routes {
		if !first {
			sb.write_string(',')
		}
		first = false
		sb.write_string('{')
		sb.write_string('"details":{')
		sb.write_string('"requestMappingConditions":{')
		sb.write_string('"methods":["${json_escape(route.method)}"],')
		sb.write_string('"patterns":["${json_escape(route.path)}"]')
		sb.write_string('}},')
		sb.write_string('"handler":"${json_escape(route.handler_name)}"')
		sb.write_string('}')
	}

	sb.write_string(']}}}}}')
	return sb.str(), introspection_content_type, 200
}

// env_mock_handler returns a MockHandler that serves the environment's
// properties in JSON format. Use it with MockMvc to test the /env endpoint
// without a running HTTP server:
//
//   mut env := core.new_environment()
//   env.set_property('app.name', 'Photon')
//
//   mut mvc := web.new_mockmvc()
//   mvc.get('/env', web.env_mock_handler(env))
//   result := mvc.perform(web.mock_request('GET', '/env'))!
//   result.assert_ok()!
//   result.assert_body_contains('"app.name"')!
pub fn env_mock_handler(env &core.Environment) MockHandler {
	return fn [env] (req MockRequest) !MockResult {
		body, ct, code := serve_env(env)
		return MockResult{
			status:  code
			body:    body
			headers: {
				'Content-Type': ct
			}
		}
	}
}

// beans_mock_handler returns a MockHandler that serves the application
// context's registered beans in JSON format. Use it with MockMvc to test
// the /beans endpoint without a running HTTP server:
//
//   mut ctx := core.new_application_context()
//   ctx.register(core.new_bean_definition('UserService'))!
//
//   mut mvc := web.new_mockmvc()
//   mvc.get('/beans', web.beans_mock_handler(ctx))
//   result := mvc.perform(web.mock_request('GET', '/beans'))!
//   result.assert_ok()!
//   result.assert_body_contains('"UserService"')!
pub fn beans_mock_handler(ctx &core.ApplicationContext) MockHandler {
	return fn [ctx] (req MockRequest) !MockResult {
		body, ct, code := serve_beans(ctx)
		return MockResult{
			status:  code
			body:    body
			headers: {
				'Content-Type': ct
			}
		}
	}
}

// mappings_mock_handler returns a MockHandler that serves the route mappings
// in JSON format. Use it with MockMvc to test the /mappings endpoint without
// a running HTTP server:
//
//   mut registry := web.new_route_registry()
//   registry.register('GET', '/users', 'users')
//
//   mut mvc := web.new_mockmvc()
//   mvc.get('/mappings', web.mappings_mock_handler(registry.routes))
//   result := mvc.perform(web.mock_request('GET', '/mappings'))!
//   result.assert_ok()!
//   result.assert_body_contains('"GET"')!
pub fn mappings_mock_handler(routes []RouteInfo) MockHandler {
	return fn [routes] (req MockRequest) !MockResult {
		body, ct, code := serve_mappings(routes)
		return MockResult{
			status:  code
			body:    body
			headers: {
				'Content-Type': ct
			}
		}
	}
}

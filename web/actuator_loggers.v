module web

// actuator_loggers.v - Spring Boot Actuator-style /loggers Endpoint (SubTask D5.2)
//
// Exposes runtime log level management over HTTP, following the Spring Boot
// Loggers endpoint convention:
//
//   GET  /loggers            → {"loggers":{"ROOT":{"configuredLevel":"INFO"},"com.photon":{"configuredLevel":"DEBUG"}}}
//   POST /loggers/{name}     ← {"configuredLevel":"DEBUG"}   (also accepts {"level":"DEBUG"})
//                              → {"status":"ok","logger":"<name>","level":"DEBUG"}
//
// The special name "ROOT" addresses the default (root) log level; any other
// dot-separated name (e.g. "com.photon.db") addresses a namespace override
// with hierarchical inheritance resolved by logger.LoggerConfig.
//
// Because Photon's routing is compile-time (veb scans @[get]/@[post] methods
// on the App struct), the endpoint is wired in by adding methods to the
// application's App that delegate to serve_loggers()/serve_logger_update().
// This keeps the actuator decoupled from any specific App shape while
// remaining trivial to integrate:
//
//   import logger
//   import web
//
//   pub struct App {
//       veb.Context
//   pub mut:
//       logger_config &logger.LoggerConfig = unsafe { nil }
//   }
//
//   @[get('/loggers')]
//   pub fn (mut app App) loggers_index() veb.Result {
//       body, ct, _ := web.serve_loggers(app.logger_config)
//       app.set_content_type(ct)
//       return app.text(body)
//   }
//
//   @[post('/loggers/:name')]
//   pub fn (mut app App) loggers_update(name string) veb.Result {
//       body := app.body  // raw request body
//       resp, ct, code := web.serve_logger_update(app.logger_config, name, body)
//       app.set_content_type(ct)
//       return app.status(code).text(resp)
//   }
//
// For tests, loggers_get_mock_handler() and loggers_post_mock_handler()
// return MockMvc-compatible handlers.
import logger
import strings

// loggers_content_type is the Content-Type used by the /loggers endpoint.
pub const loggers_content_type = 'application/json'

// loggers_path_prefix is the path prefix for individual logger updates.
const loggers_path_prefix = '/loggers/'

// serve_loggers renders all configured loggers as JSON following the
// Spring Boot Loggers endpoint convention and returns the body together
// with the appropriate Content-Type and HTTP status code (always 200).
//
// The response shape is:
//   {"loggers":{"ROOT":{"configuredLevel":"INFO"},...}}
//
// Intended to be called from a veb route handler (see file header).
pub fn serve_loggers(config &logger.LoggerConfig) (string, string, int) {
	mut cfg := unsafe { config }
	loggers := cfg.list_loggers()

	mut sb := strings.new_builder(256)
	sb.write_string('{"loggers":{')

	mut first := true
	for l in loggers {
		if !first {
			sb.write_string(',')
		}
		first = false
		sb.write_string('"')
		sb.write_string(l.name)
		sb.write_string('":{"configuredLevel":"')
		sb.write_string(l.level)
		sb.write_string('"}')
	}

	sb.write_string('}}')
	return sb.str(), loggers_content_type, 200
}

// serve_logger_update adjusts the log level for a single logger and
// returns a JSON acknowledgement. The request body may use either the
// Spring Boot field name "configuredLevel" or the shorthand "level".
//
// Status codes:
//   200 OK              on success
//   400 Bad Request     when the level field is missing or invalid
//
// The special name "ROOT" adjusts the default (root) level; any other
// name sets a namespace override.
pub fn serve_logger_update(config &logger.LoggerConfig, logger_name string, body string) (string, string, int) {
	// Accept both "configuredLevel" (Spring Boot) and "level" (shorthand).
	level_str := extract_loggers_json_string_field(body, 'configuredLevel') or {
		extract_loggers_json_string_field(body, 'level') or {
			return '{"error":"missing configuredLevel field / 缺少 configuredLevel 字段"}', loggers_content_type, 400
		}
	}

	level := logger.level_from_str(level_str) or {
		return '{"error":"invalid level: ${level_str} / 无效的日志级别: ${level_str}"}', loggers_content_type, 400
	}

	mut cfg := unsafe { config }
	if logger_name == 'ROOT' {
		cfg.set_default_level(level)
	} else {
		cfg.set_namespace_level(logger_name, level)
	}

	resp := '{"status":"ok","logger":"${logger_name}","level":"${level.str()}"}'
	return resp, loggers_content_type, 200
}

// extract_loggers_json_string_field extracts a string value for a JSON
// field from a flat JSON object (e.g. {"configuredLevel":"DEBUG"}).
// Returns none if the field is absent or malformed.
fn extract_loggers_json_string_field(json_str string, field string) ?string {
	search := '"${field}":"'
	mut start := json_str.index(search) or { return none }
	start += search.len
	end := json_str.index_after('"', start) or { return none }
	return json_str[start..end]
}

// loggers_get_mock_handler returns a MockHandler that serves the
// /loggers index (all configured loggers) in JSON format. Register it
// at GET /loggers:
//
//   mut mvc := web.new_mockmvc()
//   mvc.get('/loggers', web.loggers_get_mock_handler(config))
//   result := mvc.perform(web.mock_request('GET', '/loggers'))!
pub fn loggers_get_mock_handler(config &logger.LoggerConfig) MockHandler {
	return fn [config] (req MockRequest) !MockResult {
		body, ct, code := serve_loggers(config)
		return MockResult{
			status:  code
			body:    body
			headers: {
				'Content-Type': ct
			}
		}
	}
}

// loggers_post_mock_handler returns a MockHandler that serves
// POST /loggers/{name} updates. The logger name is extracted from the
// request path (everything after '/loggers/'), and the request body is
// used as the update payload. Register it at the specific POST path:
//
//   mut mvc := web.new_mockmvc()
//   mvc.post('/loggers/com.photon', web.loggers_post_mock_handler(config))
//   req := web.mock_request('POST', '/loggers/com.photon')
//   req.body = '{"configuredLevel":"DEBUG"}'
//   result := mvc.perform(req)!
pub fn loggers_post_mock_handler(config &logger.LoggerConfig) MockHandler {
	return fn [config] (req MockRequest) !MockResult {
		name := extract_logger_name_from_path(req.path)
		body, ct, code := serve_logger_update(config, name, req.body)
		return MockResult{
			status:  code
			body:    body
			headers: {
				'Content-Type': ct
			}
		}
	}
}

// extract_logger_name_from_path extracts the logger name from a
// /loggers/{name} path. Returns 'ROOT' for the bare '/loggers' path.
fn extract_logger_name_from_path(path string) string {
	if path.starts_with(loggers_path_prefix) {
		return path[loggers_path_prefix.len..]
	}
	if path == '/loggers' {
		return 'ROOT'
	}
	return path
}

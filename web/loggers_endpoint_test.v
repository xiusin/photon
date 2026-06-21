module web

// loggers_endpoint_test.v - Tests for the /loggers actuator endpoint (SubTask D5.3)
//
// Verifies that the /loggers endpoint and the underlying logger.LoggerConfig:
//   - Resolve levels with hierarchical namespace inheritance
//   - Support runtime level updates via POST
//   - Report all configured loggers via GET
//   - Take effect immediately after an update (should_log reflects new level)
//   - Are thread-safe under concurrent reads/writes
//   - Follow the Spring Boot Loggers endpoint JSON convention
import logger
import sync

// ============================================================
// LoggerConfig — Default level & basic resolution
// ============================================================

fn test_logger_config_default_level_is_info() {
	mut cfg := logger.new_logger_config()
	assert cfg.get_level('any.namespace') == .info
	assert cfg.get_level('com.photon.db.query') == .info
	assert cfg.get_level('') == .info
}

fn test_logger_config_default_level_custom() {
	mut cfg := logger.new_logger_config_with_level(.warn)
	assert cfg.get_default_level() == .warn
	assert cfg.get_level('any.namespace') == .warn
}

fn test_logger_config_set_namespace_level() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon.db', .debug)
	assert cfg.get_level('com.photon.db') == .debug
}

// ============================================================
// Hierarchical namespace inheritance
// ============================================================

fn test_logger_config_namespace_inheritance() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .warn)
	// Child namespace inherits from parent.
	assert cfg.get_level('com.photon.db.query') == .warn
	assert cfg.get_level('com.photon.db') == .warn
}

fn test_logger_config_most_specific_match_wins() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .warn)
	cfg.set_namespace_level('com.photon.db', .debug)
	// 'com.photon.db.query' should resolve to .debug (most specific ancestor).
	assert cfg.get_level('com.photon.db.query') == .debug
}

fn test_logger_config_exact_match_preferred_over_parent() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon.db', .debug)
	cfg.set_namespace_level('com.photon', .warn)
	// Exact match on 'com.photon.db' wins over parent 'com.photon'.
	assert cfg.get_level('com.photon.db') == .debug
}

fn test_logger_config_deep_hierarchy_walk() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com', .error)
	// Walks up: com.photon.db.query → com.photon.db → com.photon → com (match).
	assert cfg.get_level('com.photon.db.query') == .error
}

fn test_logger_config_unrelated_namespace_uses_default() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .warn)
	// 'org.example' has no configured ancestor → default (.info).
	assert cfg.get_level('org.example') == .info
}

// ============================================================
// should_log — level filtering
// ============================================================

fn test_should_log_debug_below_info_returns_false() {
	mut cfg := logger.new_logger_config()
	// Default threshold is .info; .debug is below → should NOT log.
	assert cfg.should_log('any.ns', .debug) == false
}

fn test_should_log_warn_above_info_returns_true() {
	mut cfg := logger.new_logger_config()
	// Default threshold is .info; .warn is above → should log.
	assert cfg.should_log('any.ns', .warn) == true
}

fn test_should_log_equal_level_returns_true() {
	mut cfg := logger.new_logger_config()
	// Equal to threshold → should log.
	assert cfg.should_log('any.ns', .info) == true
}

fn test_should_log_respects_namespace_override() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .debug)
	// Namespace threshold is .debug → .debug should log.
	assert cfg.should_log('com.photon', .debug) == true
	assert cfg.should_log('com.photon.db', .debug) == true
}

// ============================================================
// list_loggers & remove_namespace
// ============================================================

fn test_list_loggers_includes_root_only_by_default() {
	mut cfg := logger.new_logger_config()
	loggers := cfg.list_loggers()
	assert loggers.len == 1
	assert loggers[0].name == 'ROOT'
	assert loggers[0].level == 'INFO'
}

fn test_list_loggers_returns_namespaces_plus_root() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .warn)
	cfg.set_namespace_level('com.photon.db', .debug)
	cfg.set_namespace_level('org.example', .error)
	loggers := cfg.list_loggers()
	// 3 namespaces + ROOT = 4 entries.
	assert loggers.len == 4
	// ROOT is always present.
	mut has_root := false
	for l in loggers {
		if l.name == 'ROOT' {
			has_root = true
			assert l.level == 'INFO'
		}
	}
	assert has_root
}

fn test_remove_namespace_falls_back_to_default() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .debug)
	assert cfg.get_level('com.photon') == .debug
	cfg.remove_namespace('com.photon')
	assert cfg.get_level('com.photon') == .info
}

fn test_remove_namespace_falls_back_to_parent() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .warn)
	cfg.set_namespace_level('com.photon.db', .debug)
	assert cfg.get_level('com.photon.db') == .debug
	cfg.remove_namespace('com.photon.db')
	// After removal, falls back to parent 'com.photon' → .warn.
	assert cfg.get_level('com.photon.db') == .warn
}

fn test_get_namespace_level_returns_explicit_only() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .warn)
	// Explicit override.
	assert cfg.get_namespace_level('com.photon') or { logger.Level.fatal } == .warn
	// No explicit override → none (even though get_level would inherit).
	opt := cfg.get_namespace_level('com.photon.db')
	assert opt == none
}

// ============================================================
// Level helpers
// ============================================================

fn test_level_from_str_all_six_levels() {
	assert logger.level_from_str('trace') or { logger.Level.fatal } == .trace
	assert logger.level_from_str('debug') or { logger.Level.fatal } == .debug
	assert logger.level_from_str('info') or { logger.Level.fatal } == .info
	assert logger.level_from_str('warn') or { logger.Level.fatal } == .warn
	assert logger.level_from_str('error') or { logger.Level.fatal } == .error
	assert logger.level_from_str('fatal') or { logger.Level.fatal } == .fatal
}

fn test_level_from_str_case_insensitive() {
	assert logger.level_from_str('DEBUG') or { logger.Level.fatal } == .debug
	assert logger.level_from_str('Info') or { logger.Level.fatal } == .info
	assert logger.level_from_str('WARN') or { logger.Level.fatal } == .warn
}

fn test_level_from_str_warning_alias() {
	assert logger.level_from_str('warning') or { logger.Level.fatal } == .warn
}

fn test_level_from_str_invalid_returns_none() {
	opt := logger.level_from_str('verbose')
	assert opt == none
	opt2 := logger.level_from_str('')
	assert opt2 == none
}

fn test_level_str_all_six_levels() {
	assert logger.Level.trace.str() == 'TRACE'
	assert logger.Level.debug.str() == 'DEBUG'
	assert logger.Level.info.str() == 'INFO'
	assert logger.Level.warn.str() == 'WARN'
	assert logger.Level.error.str() == 'ERROR'
	assert logger.Level.fatal.str() == 'FATAL'
}

// ============================================================
// Level takes effect after update
// ============================================================

fn test_level_takes_effect_after_namespace_update() {
	mut cfg := logger.new_logger_config()
	// Initially .info: .debug should NOT log.
	assert cfg.should_log('com.photon', .debug) == false
	// Update to .debug.
	cfg.set_namespace_level('com.photon', .debug)
	// Now .debug SHOULD log.
	assert cfg.should_log('com.photon', .debug) == true
	assert cfg.should_log('com.photon.db', .debug) == true
}

fn test_level_takes_effect_after_root_update() {
	mut cfg := logger.new_logger_config()
	// Initially .info: .trace should NOT log.
	assert cfg.should_log('any.ns', .trace) == false
	// Update ROOT to .trace.
	cfg.set_default_level(.trace)
	// Now .trace SHOULD log for any namespace.
	assert cfg.should_log('any.ns', .trace) == true
	assert cfg.should_log('com.photon.deep', .trace) == true
}

// ============================================================
// GET /loggers endpoint
// ============================================================

fn test_get_loggers_returns_200() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.get('/loggers', loggers_get_mock_handler(cfg))

	result := mvc.perform(mock_request('GET', '/loggers'))!
	result.assert_status(200)!
}

fn test_get_loggers_content_type_is_json() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.get('/loggers', loggers_get_mock_handler(cfg))

	result := mvc.perform(mock_request('GET', '/loggers'))!
	result.assert_header('Content-Type', loggers_content_type)!
}

fn test_get_loggers_body_contains_root() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.get('/loggers', loggers_get_mock_handler(cfg))

	result := mvc.perform(mock_request('GET', '/loggers'))!
	result.assert_body_contains('"ROOT"')!
	result.assert_body_contains('"configuredLevel":"INFO"')!
}

fn test_get_loggers_body_contains_namespaces() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .debug)
	cfg.set_namespace_level('com.photon.db', .warn)
	mut mvc := new_mockmvc()
	mvc.get('/loggers', loggers_get_mock_handler(cfg))

	result := mvc.perform(mock_request('GET', '/loggers'))!
	result.assert_body_contains('"com.photon"')!
	result.assert_body_contains('"com.photon.db"')!
	result.assert_body_contains('"configuredLevel":"DEBUG"')!
	result.assert_body_contains('"configuredLevel":"WARN"')!
}

fn test_get_loggers_reflects_live_updates() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.get('/loggers', loggers_get_mock_handler(cfg))

	// Initially only ROOT at INFO.
	r1 := mvc.perform(mock_request('GET', '/loggers'))!
	r1.assert_body_contains('"configuredLevel":"INFO"')!

	// Update a namespace.
	cfg.set_namespace_level('com.photon', .debug)

	// Subsequent GET reflects the new logger.
	r2 := mvc.perform(mock_request('GET', '/loggers'))!
	r2.assert_body_contains('"com.photon"')!
	r2.assert_body_contains('"configuredLevel":"DEBUG"')!
}

fn test_serve_loggers_returns_body_content_type_status() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .debug)

	body, ct, code := serve_loggers(cfg)
	assert ct == loggers_content_type
	assert code == 200
	assert body.starts_with('{"loggers":{')
	assert body.contains('"ROOT"')
	assert body.contains('"com.photon"')
}

// ============================================================
// POST /loggers/{name} endpoint
// ============================================================

fn test_post_logger_update_namespace_level() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.post('/loggers/com.photon', loggers_post_mock_handler(cfg))

	mut req := mock_request('POST', '/loggers/com.photon')
	req.body = '{"configuredLevel":"DEBUG"}'
	result := mvc.perform(req)!
	result.assert_status(200)!
	result.assert_body_contains('"status":"ok"')!
	result.assert_body_contains('"logger":"com.photon"')!
	result.assert_body_contains('"level":"DEBUG"')!

	// Verify the level actually changed.
	assert cfg.get_level('com.photon') == .debug
}

fn test_post_logger_update_root_level() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.post('/loggers/ROOT', loggers_post_mock_handler(cfg))

	mut req := mock_request('POST', '/loggers/ROOT')
	req.body = '{"configuredLevel":"WARN"}'
	result := mvc.perform(req)!
	result.assert_status(200)!
	result.assert_body_contains('"logger":"ROOT"')!
	result.assert_body_contains('"level":"WARN"')!

	// Verify the root level changed.
	assert cfg.get_default_level() == .warn
	assert cfg.get_level('any.unconfigured.ns') == .warn
}

fn test_post_logger_accepts_level_shorthand_field() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.post('/loggers/com.photon', loggers_post_mock_handler(cfg))

	// The shorthand "level" field is also accepted.
	mut req := mock_request('POST', '/loggers/com.photon')
	req.body = '{"level":"ERROR"}'
	result := mvc.perform(req)!
	result.assert_status(200)!
	assert cfg.get_level('com.photon') == .error
}

fn test_post_logger_invalid_level_returns_400() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.post('/loggers/com.photon', loggers_post_mock_handler(cfg))

	mut req := mock_request('POST', '/loggers/com.photon')
	req.body = '{"configuredLevel":"VERBOSE"}'
	result := mvc.perform(req)!
	result.assert_status(400)!
	result.assert_body_contains('"error"')!
	// Level should NOT have changed.
	assert cfg.get_level('com.photon') == .info
}

fn test_post_logger_missing_level_field_returns_400() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.post('/loggers/com.photon', loggers_post_mock_handler(cfg))

	mut req := mock_request('POST', '/loggers/com.photon')
	req.body = '{"foo":"bar"}'
	result := mvc.perform(req)!
	result.assert_status(400)!
	result.assert_body_contains('"error"')!
}

fn test_post_logger_takes_effect_immediately() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.post('/loggers/com.photon', loggers_post_mock_handler(cfg))

	// Before update: .debug should NOT log (default .info).
	assert cfg.should_log('com.photon', .debug) == false

	// Perform the update via the endpoint.
	mut req := mock_request('POST', '/loggers/com.photon')
	req.body = '{"configuredLevel":"DEBUG"}'
	result := mvc.perform(req)!
	result.assert_status(200)!

	// After update: .debug SHOULD log.
	assert cfg.should_log('com.photon', .debug) == true
	assert cfg.should_log('com.photon.db', .debug) == true
}

fn test_serve_logger_update_returns_body_content_type_status() {
	mut cfg := logger.new_logger_config()
	body, ct, code := serve_logger_update(cfg, 'com.photon', '{"configuredLevel":"TRACE"}')
	assert ct == loggers_content_type
	assert code == 200
	assert body.contains('"status":"ok"')
	assert body.contains('"level":"TRACE"')
	assert cfg.get_level('com.photon') == .trace
}

fn test_serve_logger_update_invalid_level_returns_400() {
	mut cfg := logger.new_logger_config()
	body, ct, code := serve_logger_update(cfg, 'com.photon', '{"configuredLevel":"nope"}')
	assert ct == loggers_content_type
	assert code == 400
	assert body.contains('"error"')
}

fn test_serve_logger_update_missing_field_returns_400() {
	mut cfg := logger.new_logger_config()
	body, _, code := serve_logger_update(cfg, 'com.photon', '{}')
	assert code == 400
	assert body.contains('"error"')
}

// ============================================================
// Concurrent access — thread safety
// ============================================================

fn test_logger_config_concurrent_reads_and_writes_no_race() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('com.photon', .info)
	cfg.set_namespace_level('com.photon.db', .info)
	cfg.set_namespace_level('org.example', .info)

	mut wg := sync.new_waitgroup()

	// Writers: continuously update levels.
	for i in 0 .. 20 {
		wg.add(1)
		spawn fn (mut c logger.LoggerConfig, idx int, mut w sync.WaitGroup) {
			defer {
				w.done()
			}
			ns := if idx % 2 == 0 { 'com.photon' } else { 'com.photon.db' }
			lvl := if idx % 3 == 0 { logger.Level.debug } else if idx % 3 == 1 { logger.Level.warn } else { logger.Level.error }
			c.set_namespace_level(ns, lvl)
		}(mut cfg, i, mut wg)
	}

	// Readers: continuously query levels.
	for _ in 0 .. 30 {
		wg.add(1)
		spawn fn (mut c logger.LoggerConfig, mut w sync.WaitGroup) {
			defer {
				w.done()
			}
			// Should never panic; result is always a valid Level.
			_ = c.get_level('com.photon.db.query')
			_ = c.get_level('com.photon')
			_ = c.should_log('com.photon', .debug)
			_ = c.list_loggers()
		}(mut cfg, mut wg)
	}

	wg.wait()
	// If we reach here without deadlock/panic, thread-safety holds.
	assert true
}

// ============================================================
// Edge cases
// ============================================================

fn test_logger_config_empty_namespace_uses_default() {
	mut cfg := logger.new_logger_config()
	cfg.set_default_level(.warn)
	// Empty namespace → default level.
	assert cfg.get_level('') == .warn
}

fn test_logger_config_single_segment_namespace() {
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('root', .error)
	// Single-segment namespace with no dots — exact match.
	assert cfg.get_level('root') == .error
	// Unrelated single segment → default.
	assert cfg.get_level('other') == .info
}

fn test_post_logger_update_then_remove_via_config() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.post('/loggers/com.photon', loggers_post_mock_handler(cfg))

	// Set via endpoint.
	mut req := mock_request('POST', '/loggers/com.photon')
	req.body = '{"configuredLevel":"DEBUG"}'
	result := mvc.perform(req)!
	result.assert_status(200)!
	assert cfg.get_level('com.photon') == .debug

	// Remove via config directly.
	cfg.remove_namespace('com.photon')
	assert cfg.get_level('com.photon') == .info
}

fn test_get_loggers_unknown_path_returns_404() {
	mut cfg := logger.new_logger_config()
	mut mvc := new_mockmvc()
	mvc.get('/loggers', loggers_get_mock_handler(cfg))

	// /loggers is registered, but /unknown is not.
	result := mvc.perform(mock_request('GET', '/unknown'))!
	result.assert_not_found()!
}

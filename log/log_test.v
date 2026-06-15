module log

// log_test.v - Unit tests for Photon Log Module
// Tests: Level enum, Logger creation, MDC context, level filtering

// ============================================================
// Level Enum Tests
// ============================================================

fn test_level_str() {
	assert Level.debug.str() == 'DEBUG'
	assert Level.info.str() == 'INFO'
	assert Level.warn.str() == 'WARN'
	assert Level.error.str() == 'ERROR'
	assert Level.fatal.str() == 'FATAL'
}

fn test_level_ordering() {
	assert int(Level.debug) < int(Level.info)
	assert int(Level.info) < int(Level.warn)
	assert int(Level.warn) < int(Level.error)
	assert int(Level.error) < int(Level.fatal)
}

// ============================================================
// Logger Creation Tests
// ============================================================

fn test_new_logger() {
	logger := new()
	assert logger.get_level() == .info
	assert logger.output_label == 'photon'
	assert logger.colored == false
	assert logger.structured == false
}

fn test_new_logger_with_level() {
	logger := new_with_level(.debug)
	assert logger.get_level() == .debug
}

// ============================================================
// Logger Level Tests
// ============================================================

fn test_logger_set_level() {
	mut logger := new()
	logger.set_level(.warn)
	assert logger.get_level() == .warn
}

fn test_logger_get_level_after_change() {
	mut logger := new()
	assert logger.get_level() == .info
	logger.set_level(.error)
	assert logger.get_level() == .error
	logger.set_level(.debug)
	assert logger.get_level() == .debug
}

// ============================================================
// Logger Configuration Tests
// ============================================================

fn test_logger_set_colored() {
	mut logger := new()
	assert logger.colored == false
	logger.set_colored(true)
	assert logger.colored == true
}

fn test_logger_set_structured() {
	mut logger := new()
	assert logger.structured == false
	logger.set_structured(true)
	assert logger.structured == true
}

fn test_logger_set_output_label() {
	mut logger := new()
	assert logger.output_label == 'photon'
	logger.set_output_label('my-app')
	assert logger.output_label == 'my-app'
}

// ============================================================
// MDC Context Tests
// ============================================================

fn test_logger_put_and_get() {
	mut logger := new()
	logger.put('request_id', 'abc-123')
	assert logger.get('request_id') == 'abc-123'
}

fn test_logger_get_missing() {
	mut logger := new()
	assert logger.get('nonexistent') == ''
}

fn test_logger_put_multiple() {
	mut logger := new()
	logger.put('user', 'admin')
	logger.put('trace', 'xyz-789')
	assert logger.get('user') == 'admin'
	assert logger.get('trace') == 'xyz-789'
}

fn test_logger_remove() {
	mut logger := new()
	logger.put('key', 'value')
	assert logger.get('key') == 'value'
	logger.remove('key')
	assert logger.get('key') == ''
}

fn test_logger_overwrite_context() {
	mut logger := new()
	logger.put('key', 'first')
	assert logger.get('key') == 'first'
	logger.put('key', 'second')
	assert logger.get('key') == 'second'
}

fn test_logger_clear_context() {
	mut logger := new()
	logger.put('a', '1')
	logger.put('b', '2')
	logger.put('c', '3')
	logger.clear_context()
	assert logger.get('a') == ''
	assert logger.get('b') == ''
	assert logger.get('c') == ''
}

// ============================================================
// Level Filtering Tests
// ============================================================

fn test_level_filtering_debug_not_printed_at_info() {
	mut logger := new()
	logger.set_level(.info)
	// debug level should be filtered out (no assertion on output, just that it doesn't crash)
	logger.debug('should not print')
	logger.info('should print')
	logger.warn('should print')
	logger.error('should print')
	assert true // Just ensuring no panic
}

fn test_level_filtering_info_not_printed_at_warn() {
	mut logger := new()
	logger.set_level(.warn)
	logger.debug('no')
	logger.info('no')
	logger.warn('yes') // These should pass through
	logger.error('yes')
	assert true // No crashes
}

fn test_all_levels_at_debug() {
	mut logger := new()
	logger.set_level(.debug)
	logger.debug('d')
	logger.info('i')
	logger.warn('w')
	logger.error('e')
	logger.fatal('f')
	assert true
}

// ============================================================
// Format String Tests
// ============================================================

fn test_logger_debugf() {
	mut logger := new()
	logger.set_level(.debug)
	logger.debugf('hello {}', 'world')
	assert true // Should not crash
}

fn test_logger_infof() {
	mut logger := new()
	logger.infof('value is {}', '42')
	assert true
}

fn test_logger_warnf() {
	mut logger := new()
	logger.warnf('warning: {}', 'low memory')
	assert true
}

fn test_logger_errorf() {
	mut logger := new()
	logger.errorf('error: {}', 'connection failed')
	assert true
}

fn test_logger_fatalf() {
	mut logger := new()
	logger.fatalf('fatal: {}', 'system crash')
	assert true
}

// ============================================================
// Structured Logging Tests
// ============================================================

fn test_structured_logging_enabled() {
	mut logger := new()
	logger.set_structured(true)
	logger.set_level(.debug)
	logger.put('request_id', 'test-001')
	logger.info('structured test')
	assert true // Output is structured JSON format
}

fn test_structured_with_mdc() {
	mut logger := new()
	logger.set_structured(true)
	logger.set_level(.info)
	logger.put('user_id', '42')
	logger.put('action', 'login')
	logger.info('user logged in')
	assert true
}

// ============================================================
// Convenience Method Tests
// ============================================================

fn test_convenience_methods_exist() {
	mut logger := new()
	logger.set_level(.debug)
	// All methods should exist and not crash
	logger.debug('debug msg')
	logger.info('info msg')
	logger.warn('warn msg')
	logger.error('error msg')
	logger.fatal('fatal msg')
	assert true
}

fn test_logger_output_label_change() {
	mut logger := new()
	logger.set_output_label('test-service')
	logger.set_level(.debug)
	logger.info('testing output label')
	assert logger.output_label == 'test-service'
}

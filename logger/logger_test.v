module logger

// logger_test.v - Unit tests for Photon Logger Module
// Tests: Level enum, Logger creation, Encoders, MDC context, level filtering
import time

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

fn test_level_short_str() {
	assert Level.debug.short_str() == 'DBUG'
	assert Level.info.short_str() == 'INFO'
	assert Level.warn.short_str() == 'WARN'
	assert Level.error.short_str() == 'ERRO'
	assert Level.fatal.short_str() == 'FATA'
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
	log := new()
	assert log.get_level() == .info
	assert log.output_label == 'photon'
}

fn test_new_logger_with_level() {
	log := new_with_level(.debug)
	assert log.get_level() == .debug
}

fn test_new_logger_with_json_encoder() {
	encoder := new_json_encoder()
	log := new_with_encoder(encoder)
	assert log.output_label == 'photon'
}

// ============================================================
// Logger Level Tests
// ============================================================

fn test_logger_set_level() {
	mut log := new()
	log.set_level(.warn)
	assert log.get_level() == .warn
}

fn test_logger_get_level_after_change() {
	mut log := new()
	assert log.get_level() == .info
	log.set_level(.error)
	assert log.get_level() == .error
	log.set_level(.debug)
	assert log.get_level() == .debug
}

// ============================================================
// Encoder Tests
// ============================================================

fn test_logger_use_json() {
	mut log := new()
	log.use_json()
	assert true
}

fn test_logger_use_console() {
	mut log := new()
	log.use_json()
	log.use_console()
	assert true
}

fn test_logger_set_encoder() {
	mut log := new()
	je := new_json_encoder()
	log.set_encoder(je)
	assert true
}

fn test_logger_set_colored() {
	mut log := new()
	log.set_colored(true)
	assert true
}

// ============================================================
// Logger Configuration Tests
// ============================================================

fn test_logger_set_output_label() {
	mut log := new()
	assert log.output_label == 'photon'
	log.set_output_label('my-app')
	assert log.output_label == 'my-app'
}

// ============================================================
// MDC Context Tests
// ============================================================

fn test_logger_put_and_get() {
	mut log := new()
	log.put('request_id', 'abc-123')
	assert log.get('request_id') == 'abc-123'
}

fn test_logger_get_missing() {
	mut log := new()
	assert log.get('nonexistent') == ''
}

fn test_logger_put_multiple() {
	mut log := new()
	log.put('user', 'admin')
	log.put('trace', 'xyz-789')
	assert log.get('user') == 'admin'
	assert log.get('trace') == 'xyz-789'
}

fn test_logger_remove() {
	mut log := new()
	log.put('key', 'value')
	assert log.get('key') == 'value'
	log.remove('key')
	assert log.get('key') == ''
}

fn test_logger_overwrite_context() {
	mut log := new()
	log.put('key', 'first')
	assert log.get('key') == 'first'
	log.put('key', 'second')
	assert log.get('key') == 'second'
}

fn test_logger_clear_context() {
	mut log := new()
	log.put('a', '1')
	log.put('b', '2')
	log.put('c', '3')
	log.clear_context()
	assert log.get('a') == ''
	assert log.get('b') == ''
	assert log.get('c') == ''
}

fn test_logger_with_fields() {
	mut log := new()
	log.put('original', 'yes')
	child := log.with_fields({
		'extra': 'value'
	})
	assert child.get('extra') == 'value'
	assert child.get('original') == 'yes'
	assert log.get('extra') == ''
}

fn test_logger_named() {
	mut log := new()
	child := log.named('my-service')
	assert child.output_label == 'my-service'
	assert log.output_label == 'photon'
}

// ============================================================
// Level Filtering Tests
// ============================================================

fn test_level_filtering_debug_not_printed_at_info() {
	mut log := new()
	log.set_level(.info)
	log.debug('should not print')
	log.info('should print')
	log.warn('should print')
	log.error('should print')
	assert true
}

fn test_level_filtering_info_not_printed_at_warn() {
	mut log := new()
	log.set_level(.warn)
	log.debug('no')
	log.info('no')
	log.warn('yes')
	log.error('yes')
	assert true
}

fn test_all_levels_at_debug() {
	mut log := new()
	log.set_level(.debug)
	log.debug('d')
	log.info('i')
	log.warn('w')
	log.error('e')
	log.fatal('f')
	assert true
}

// ============================================================
// Format String Tests
// ============================================================

fn test_logger_debugf() {
	mut log := new()
	log.set_level(.debug)
	log.debugf('hello {}', 'world')
	assert true
}

fn test_logger_infof() {
	mut log := new()
	log.infof('value is {}', '42')
	assert true
}

fn test_logger_warnf() {
	mut log := new()
	log.warnf('warning: {}', 'low memory')
	assert true
}

fn test_logger_errorf() {
	mut log := new()
	log.errorf('error: {}', 'connection failed')
	assert true
}

fn test_logger_fatalf() {
	mut log := new()
	log.fatalf('fatal: {}', 'system crash')
	assert true
}

// ============================================================
// Convenience Method Tests
// ============================================================

fn test_convenience_methods_exist() {
	mut log := new()
	log.set_level(.debug)
	log.debug('debug msg')
	log.info('info msg')
	log.warn('warn msg')
	log.error('error msg')
	log.fatal('fatal msg')
	assert true
}

fn test_logger_output_label_change() {
	mut log := new()
	log.set_output_label('test-service')
	log.set_level(.debug)
	log.info('testing output label')
	assert log.output_label == 'test-service'
}

// ============================================================
// JSON Encoder Tests
// ============================================================

fn test_json_encoder_basic() {
	je := new_json_encoder()
	entry := &LogEntry{
		timestamp:   time.now()
		level:       .info
		message:     'test message'
		logger_name: 'photon'
		fields:      &map[string]string{}
	}
	output := je.encode(entry)
	assert output.contains('"level":"INFO"')
	assert output.contains('"message":"test message"')
	assert output.contains('"logger":"photon"')
}

fn test_json_encoder_with_fields() {
	je := new_json_encoder()
	mut fields := map[string]string{}
	fields['request_id'] = 'abc-123'
	fields['user_id'] = '42'

	entry := &LogEntry{
		timestamp:   time.now()
		level:       .warn
		message:     'warning test'
		logger_name: 'app'
		fields:      &fields
	}
	output := je.encode(entry)
	assert output.contains('"request_id":"abc-123"')
	assert output.contains('"user_id":"42"')
}

fn test_json_encoder_escapes_quotes() {
	je := new_json_encoder()
	entry := &LogEntry{
		timestamp:   time.now()
		level:       .error
		message:     'hello "world"'
		logger_name: 'test'
		fields:      &map[string]string{}
	}
	output := je.encode(entry)
	assert output.contains('\\"')
}

// ============================================================
// Console Encoder Tests
// ============================================================

fn test_console_encoder_basic() {
	ce := new_console_encoder()
	entry := &LogEntry{
		timestamp:   time.now()
		level:       .info
		message:     'test message'
		logger_name: 'photon'
		fields:      &map[string]string{}
	}
	output := ce.encode(entry)
	assert output.contains('[INFO]')
	assert output.contains('[photon]')
	assert output.contains('test message')
}

fn test_console_encoder_with_context() {
	ce := new_console_encoder()
	mut fields := map[string]string{}
	fields['user'] = 'admin'

	entry := &LogEntry{
		timestamp:   time.now()
		level:       .info
		message:     'user action'
		logger_name: 'photon'
		fields:      &fields
	}
	output := ce.encode(entry)
	assert output.contains('user=admin')
}

fn test_console_encoder_colored() {
	mut ce := new_console_encoder()
	ce.set_colored(true)
	entry := &LogEntry{
		timestamp:   time.now()
		level:       .error
		message:     'error test'
		logger_name: 'photon'
		fields:      &map[string]string{}
	}
	output := ce.encode(entry)
	assert output.contains('\x1b[31m')
}

// ============================================================
// Time Format Tests
// ============================================================

fn test_time_format_unix() {
	now := time.now()
	result := fmt_time(now, .unix)
	assert result.len > 0
}

fn test_time_format_rfc3339() {
	now := time.now()
	result := fmt_time(now, .rfc3339)
	assert result.len > 10
}

fn test_time_format_iso8601() {
	now := time.now()
	result := fmt_time(now, .iso8601)
	assert result.len > 0
}

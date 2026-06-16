module logger

// logger.v - Photon Logger Module
//
// Inspired by Go's zap logger design. Provides structured, leveled logging
// with pluggable encoders (JSON, Console) and MDC context support.
//
// Key concepts:
//   - Encoder: Pluggable serialization format (JSON, Console)
//   - EncoderConfig: Fine-grained control over output format
//   - Level: Severity filtering (debug, info, warn, error, fatal)
//   - MDC: Mapped Diagnostic Context for structured fields

import time

// Level represents the severity of a log message
pub enum Level {
	debug = 0
	info  = 1
	warn  = 2
	error = 3
	fatal = 4
}

// str converts Level to uppercase string
pub fn (l Level) str() string {
	return match l {
		.debug { 'DEBUG' }
		.info  { 'INFO' }
		.warn  { 'WARN' }
		.error { 'ERROR' }
		.fatal { 'FATAL' }
	}
}

// short_str returns a 4-char abbreviation for the level
pub fn (l Level) short_str() string {
	return match l {
		.debug { 'DBUG' }
		.info  { 'INFO' }
		.warn  { 'WARN' }
		.error { 'ERRO' }
		.fatal { 'FATA' }
	}
}

// TimeFormat specifies how timestamps are formatted
pub enum TimeFormat {
	unix
	rfc3339
	iso8601
}

// fmt_time formats a Time according to TimeFormat
pub fn fmt_time(t time.Time, format TimeFormat) string {
	return match format {
		.unix    { t.unix().str() }
		.rfc3339 { t.format_rfc3339() }
		.iso8601 { t.format_ss() }
	}
}

// EncoderConfig controls the output format of log entries.
// Inspired by zap's EncoderConfig.
pub struct EncoderConfig {
pub:
	time_key     string = 'timestamp'
	level_key    string = 'level'
	name_key     string = 'logger'
	message_key  string = 'message'
	caller_key   string = 'caller'
	time_format  TimeFormat = .rfc3339
}

// LogEntry represents a complete log entry before encoding
pub struct LogEntry {
pub:
	timestamp   time.Time
	level       Level
	message     string
	logger_name string
	fields      map[string]string
}

// Encoder is the trait for log entry serialization.
// Implement JSONEncoder, ConsoleEncoder, or custom encoders.
// clone() is required for creating independent copies (e.g., per-goroutine encoders).
pub interface Encoder {
	encode(entry &LogEntry) string
	config() &EncoderConfig
	clone() &Encoder
}

// ============================================================
// Logger
// ============================================================

// Logger provides structured, leveled logging with pluggable encoders
@[heap]
pub struct Logger {
pub mut:
	level        Level    = .info
	output_label string   = 'photon'
	encoder      &Encoder = unsafe { nil }
mut:
	context map[string]string // MDC context
}

// new creates a new Logger with default console encoder
pub fn new() &Logger {
	return &Logger{
		encoder: new_console_encoder()
		context: map[string]string{}
	}
}

// new_with_encoder creates a Logger with a custom encoder (e.g., JSONEncoder)
pub fn new_with_encoder(encoder &Encoder) &Logger {
	return &Logger{
		encoder: unsafe { encoder }
		context: map[string]string{}
	}
}

// new_with_level creates a new Logger with a specified level
pub fn new_with_level(level Level) &Logger {
	mut l := new()
	l.set_level(level)
	return l
}

// set_level sets the minimum log level
pub fn (mut l Logger) set_level(level Level) {
	l.level = level
}

// get_level returns the current log level
pub fn (l &Logger) get_level() Level {
	return l.level
}

// set_encoder sets the log output encoder (JSON, Console, or custom)
pub fn (mut l Logger) set_encoder(encoder &Encoder) {
	unsafe {
		l.encoder = encoder
	}
}

// get_encoder returns the current encoder
pub fn (l &Logger) get_encoder() &Encoder {
	return l.encoder
}

// use_json configures the logger to use JSON structured output
pub fn (mut l Logger) use_json() {
	l.encoder = new_json_encoder()
}

// use_console configures the logger to use plain-text console output
pub fn (mut l Logger) use_console() {
	l.encoder = new_console_encoder()
}

// set_colored enables colorized console output (delegates to ConsoleEncoder).
// Note: Call set_colored AFTER setting a console encoder for it to take effect.
pub fn (mut l Logger) set_colored(colored bool) {
	mut ce := new_console_encoder()
	ce.set_colored(colored)
	l.encoder = ce
}

// set_output_label sets the logger label (name in output)
pub fn (mut l Logger) set_output_label(label string) {
	l.output_label = label
}

// MDC context operations

// put adds a context key-value pair (MDC)
pub fn (mut l Logger) put(key string, value string) {
	l.context[key] = value
}

// get retrieves a context value
pub fn (l &Logger) get(key string) string {
	return l.context[key] or { '' }
}

// remove removes a context key
pub fn (mut l Logger) remove(key string) {
	l.context.delete(key)
}

// clear_context clears all MDC context
pub fn (mut l Logger) clear_context() {
	l.context.clear()
}

// with_fields creates a copy of the logger with additional context (immutable pattern).
pub fn (l &Logger) with_fields(fields map[string]string) &Logger {
	mut new_ctx := l.context.clone()
	for k, v in fields {
		new_ctx[k] = v
	}
	return &Logger{
		level:        l.level
		output_label: l.output_label
		encoder:      l.encoder
		context:      new_ctx
	}
}

// named returns a copy of the logger with a new output label
pub fn (l &Logger) named(name string) &Logger {
	mut copy := l.with_fields(map[string]string{})
	copy.output_label = name
	return copy
}

// ============================================================
// Core log writing
// ============================================================

// log writes a log message at the given level
pub fn (l &Logger) log(level Level, msg string) {
	if int(level) < int(l.level) {
		return
	}

	// Guard against nil encoder (defensive: could happen if Logger not created via new())
	if isnil(l.encoder) {
		eprintln('[${fmt_time(time.now(), .rfc3339)}] [${level.str()}] [${l.output_label}] ${msg}')
		return
	}

	entry := &LogEntry{
		timestamp:   time.now()
		level:       level
		message:     msg
		logger_name: l.output_label
		fields:      l.context.clone()
	}

	output := l.encoder.encode(entry)
	eprintln(output)
}

// Convenience methods

pub fn (l &Logger) debug(msg string) { l.log(.debug, msg) }
pub fn (l &Logger) info(msg string)  { l.log(.info, msg) }
pub fn (l &Logger) warn(msg string)  { l.log(.warn, msg) }
pub fn (l &Logger) error(msg string) { l.log(.error, msg) }
pub fn (l &Logger) fatal(msg string) { l.log(.fatal, msg) }

// Formatted convenience methods

pub fn (l &Logger) debugf(msg string, a string) {
	l.debug(msg.replace('{}', a))
}

pub fn (l &Logger) infof(msg string, a string) {
	l.info(msg.replace('{}', a))
}

pub fn (l &Logger) warnf(msg string, a string) {
	l.warn(msg.replace('{}', a))
}

pub fn (l &Logger) errorf(msg string, a string) {
	l.error(msg.replace('{}', a))
}

pub fn (l &Logger) fatalf(msg string, a string) {
	l.fatal(msg.replace('{}', a))
}

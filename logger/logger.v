module logger

// logger.v - Photon Logger Module
//
// Inspired by Go's zap logger design. Provides structured, leveled logging
// with pluggable encoders (JSON, Console) and MDC context support.
//
// Key concepts:
//   - Encoder: Pluggable serialization format (JSON, Console)
//   - EncoderConfig: Fine-grained control over output format
//   - Level: Severity filtering (trace, debug, info, warn, error, fatal)
//   - MDC: Mapped Diagnostic Context for structured fields
import sync
import time

// Level represents the severity of a log message.
// Values are ordered by increasing severity so that level comparison via
// `int(level)` reflects severity ordering (trace < debug < info < ...).
pub enum Level {
	trace = 0
	debug = 1
	info  = 2
	warn  = 3
	error = 4
	fatal = 5
}

// str converts Level to uppercase string
pub fn (l Level) str() string {
	return match l {
		.trace { 'TRACE' }
		.debug { 'DEBUG' }
		.info { 'INFO' }
		.warn { 'WARN' }
		.error { 'ERROR' }
		.fatal { 'FATAL' }
	}
}

// short_str returns a 4-char abbreviation for the level
pub fn (l Level) short_str() string {
	return match l {
		.trace { 'TRAC' }
		.debug { 'DBUG' }
		.info { 'INFO' }
		.warn { 'WARN' }
		.error { 'ERRO' }
		.fatal { 'FATA' }
	}
}

// level_from_str parses a level string (case-insensitive) into a Level.
// Accepts common aliases: 'warning' → .warn. Returns none on unknown input.
pub fn level_from_str(s string) ?Level {
	return match s.to_lower() {
		'trace' { Level.trace }
		'debug' { Level.debug }
		'info' { Level.info }
		'warn', 'warning' { Level.warn }
		'error' { Level.error }
		'fatal' { Level.fatal }
		else { none }
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
		.unix { t.unix().str() }
		.rfc3339 { t.format_rfc3339() }
		.iso8601 { t.format_ss() }
	}
}

// EncoderConfig controls the output format of log entries.
// Inspired by zap's EncoderConfig.
pub struct EncoderConfig {
pub:
	time_key    string     = 'timestamp'
	level_key   string     = 'level'
	name_key    string     = 'logger'
	message_key string     = 'message'
	caller_key  string     = 'caller'
	time_format TimeFormat = .rfc3339
}

// LogEntry represents a complete log entry before encoding.
// `fields` is a shared reference to the Logger's MDC context map.
// This avoids cloning the map on every log entry (Copy-On-Write:
// `with_fields` creates a new map, so the referenced map is never
// mutated after being shared with a LogEntry). LogEntries are
// consumed synchronously by encoders, so sharing is safe.
pub struct LogEntry {
pub:
	timestamp   time.Time
	level       Level
	message     string
	logger_name string
	fields      &map[string]string = unsafe { nil }
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

// Logger provides structured, leveled logging with pluggable encoders.
// The encoder field defaults to a ConsoleEncoder sentinel so it is never nil;
// all constructors (new, new_with_encoder, new_with_level) and with_fields
// propagate a concrete encoder, guaranteeing log() can always call encode().
@[heap]
pub struct Logger {
pub mut:
	level        Level    = .info
	output_label string   = 'photon'
	encoder      &Encoder = &ConsoleEncoder{} // sentinel — never nil (ConsoleEncoder implements Encoder)
mut:
	context &map[string]string = unsafe { nil } // MDC context (heap-allocated, shared by reference with LogEntries)
}

// new creates a new Logger with default console encoder
pub fn new() &Logger {
	ctx := map[string]string{}
	return &Logger{
		encoder: new_console_encoder()
		context: &ctx
	}
}

// new_with_encoder creates a Logger with a custom encoder (e.g., JSONEncoder)
pub fn new_with_encoder(encoder &Encoder) &Logger {
	ctx := map[string]string{}
	return &Logger{
		encoder: unsafe { encoder }
		context: &ctx
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
	unsafe {
		l.context[key] = value
	}
}

// get retrieves a context value
pub fn (l &Logger) get(key string) string {
	return unsafe { l.context[key] or { '' } }
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
// Copy-On-Write: creates a NEW map so the original Logger's context is never mutated,
// allowing `log()` to safely share the context reference with LogEntries.
pub fn (l &Logger) with_fields(fields map[string]string) &Logger {
	mut new_ctx := map[string]string{}
	for k, v in l.context {
		new_ctx[k] = v
	}
	for k, v in fields {
		new_ctx[k] = v
	}
	return &Logger{
		level:        l.level
		output_label: l.output_label
		encoder:      l.encoder
		context:      &new_ctx
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

	// encoder is guaranteed non-nil: the field defaults to &ConsoleEncoder{}
	// and every constructor / with_fields propagates a concrete encoder.
	entry := &LogEntry{
		timestamp:   time.now()
		level:       level
		message:     msg
		logger_name: l.output_label
		fields:      l.context // share reference — no clone (COW: with_fields creates new maps)
	}

	output := l.encoder.encode(entry)
	eprintln(output)
}

// Convenience methods

pub fn (l &Logger) debug(msg string) {
	l.log(.debug, msg)
}

pub fn (l &Logger) info(msg string) {
	l.log(.info, msg)
}

pub fn (l &Logger) warn(msg string) {
	l.log(.warn, msg)
}

pub fn (l &Logger) error(msg string) {
	l.log(.error, msg)
}

pub fn (l &Logger) fatal(msg string) {
	l.log(.fatal, msg)
}

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

// ============================================================
// LoggerConfig — Per-namespace log level management (SubTask D5.1)
// ============================================================
//
// LoggerConfig manages per-namespace log levels with hierarchical
// inheritance, inspired by Spring Boot's logging system and logback.
//
// Hierarchy: namespaces are dot-separated (e.g. 'com.photon.db.query').
// When resolving the level for a namespace, the most specific matching
// ancestor wins; if no ancestor is configured, the default (root) level
// is used.
//
//   config.set_namespace_level('com.photon', .warn)
//   config.get_level('com.photon.db.query')   // → .warn (inherited)
//   config.set_namespace_level('com.photon.db', .debug)
//   config.get_level('com.photon.db.query')   // → .debug (most specific)
//
// Thread-safety: all reads/writes are protected by sync.RwMutex.
// The 'ROOT' name is the conventional alias for the default level.

// LoggerInfo describes a single logger entry as exposed by the /loggers
// endpoint. `name` is the namespace (or 'ROOT' for the default level);
// `level` is the uppercase string representation of the Level.
pub struct LoggerInfo {
pub:
	name  string
	level string
}

// LoggerConfig manages per-namespace log levels with hierarchical
// inheritance and a default (root) level. Thread-safe via sync.RwMutex.
@[heap]
pub struct LoggerConfig {
pub mut:
	mu              sync.RwMutex
	default_level   Level            = .info
	namespace_levels map[string]Level
}

// new_logger_config creates a LoggerConfig with default level .info and
// no namespace overrides.
pub fn new_logger_config() &LoggerConfig {
	return &LoggerConfig{
		namespace_levels: map[string]Level{}
	}
}

// new_logger_config_with_level creates a LoggerConfig with a custom
// default (root) level.
pub fn new_logger_config_with_level(level Level) &LoggerConfig {
	return &LoggerConfig{
		default_level:   level
		namespace_levels: map[string]Level{}
	}
}

// set_default_level sets the root log level. Thread-safe.
// 对应 POST /loggers/ROOT — 调整默认（根）日志级别。
pub fn (mut lc LoggerConfig) set_default_level(level Level) {
	lc.mu.@lock()
	lc.default_level = level
	lc.mu.unlock()
}

// get_default_level returns the root log level. Thread-safe.
pub fn (mut lc LoggerConfig) get_default_level() Level {
	lc.mu.@rlock()
	defer {
		lc.mu.runlock()
	}
	return lc.default_level
}

// set_namespace_level sets the log level for a specific namespace.
// Thread-safe. 对应 POST /loggers/{name} — 调整指定命名空间级别。
pub fn (mut lc LoggerConfig) set_namespace_level(namespace string, level Level) {
	lc.mu.@lock()
	lc.namespace_levels[namespace] = level
	lc.mu.unlock()
}

// get_level resolves the effective log level for a namespace using
// hierarchical inheritance: the most specific configured ancestor wins,
// falling back to the default (root) level. Thread-safe.
//
// Example: for 'com.photon.db.query', checks in order:
//   'com.photon.db.query' → 'com.photon.db' → 'com.photon' → 'com' → default
pub fn (mut lc LoggerConfig) get_level(namespace string) Level {
	lc.mu.@rlock()
	defer {
		lc.mu.runlock()
	}

	if namespace.len > 0 {
		// Exact match — most specific.
		if level := lc.namespace_levels[namespace] {
			return level
		}
		// Walk up the dot-separated hierarchy.
		mut ns := namespace
		for ns.contains('.') {
			last_dot := ns.last_index('.') or { break }
			ns = ns[..last_dot]
			if level := lc.namespace_levels[ns] {
				return level
			}
		}
	}
	return lc.default_level
}

// should_log returns true if a message at `level` should be emitted for
// the given namespace, i.e. its severity is at or above the namespace's
// effective threshold. Thread-safe.
pub fn (mut lc LoggerConfig) should_log(namespace string, level Level) bool {
	current := lc.get_level(namespace)
	return int(level) >= int(current)
}

// list_loggers returns all configured loggers (namespace overrides plus
// the ROOT entry) for the /loggers endpoint. Thread-safe.
pub fn (mut lc LoggerConfig) list_loggers() []LoggerInfo {
	lc.mu.@rlock()
	defer {
		lc.mu.runlock()
	}

	mut loggers := []LoggerInfo{}
	for ns, level in lc.namespace_levels {
		loggers << LoggerInfo{
			name: ns
			level: level.str()
		}
	}
	loggers << LoggerInfo{
		name: 'ROOT'
		level: lc.default_level.str()
	}
	return loggers
}

// remove_namespace removes a namespace level override, causing that
// namespace to fall back to inherited/default behavior. Thread-safe.
pub fn (mut lc LoggerConfig) remove_namespace(namespace string) {
	lc.mu.@lock()
	lc.namespace_levels.delete(namespace)
	lc.mu.unlock()
}

// get_namespace_level returns the explicitly configured level for a
// namespace, or none if no override is set. Unlike get_level(), this
// does NOT perform hierarchical inheritance. Thread-safe.
pub fn (mut lc LoggerConfig) get_namespace_level(namespace string) ?Level {
	lc.mu.@rlock()
	defer {
		lc.mu.runlock()
	}
	if level := lc.namespace_levels[namespace] {
		return level
	}
	return none
}

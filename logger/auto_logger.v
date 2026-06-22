module logger

// auto_logger.v - Automatic Logger Injection (Spring @Slf4j inspired)
//
// Provides LoggerFactory for DI-container-managed Logger creation
// and automatic Logger injection via @[log] annotation support.
//
// Spring equivalent: @Slf4j (Lombok) / LoggerFactory.getLogger(MyClass.class)
// Laravel equivalent: Log facade with automatic channel resolution
//
// Usage:
//   // In bootstrap:
//   mut factory := logger.new_logger_factory(config)
//   ctx.register_instance('LoggerFactory', factory)
//
//   // In any component:
//   @[service]
//   pub struct UserService {
//       @[log]
//       log_ &Logger
//   }
//
//   // Or manually:
//   log_ := factory.get_logger_for[UserService]()

import sync

// LoggerFactory creates and manages Logger instances with
// hierarchical namespace-based level resolution.
//
// Spring equivalent: org.slf4j.LoggerFactory
// Laravel equivalent: Illuminate\Log\LogManager
@[heap]
pub struct LoggerFactory {
pub mut:
	config  &LoggerConfig = unsafe { nil }
	mu      sync.RwMutex
	loggers map[string]&Logger
}

// new_logger_factory creates a LoggerFactory with the given LoggerConfig.
pub fn new_logger_factory(config &LoggerConfig) &LoggerFactory {
	return &LoggerFactory{
		config:  config
		loggers: map[string]&Logger{}
	}
}

// get_logger creates or retrieves a named Logger.
// The Logger's level is automatically set from the LoggerConfig
// hierarchy for the given namespace.
//
// Spring equivalent: LoggerFactory.getLogger("com.photon.UserService")
pub fn (mut f LoggerFactory) get_logger(name string) &Logger {
	f.mu.@lock()
	// Check cache first
	if cached := f.loggers[name] {
		f.mu.unlock()
		return cached
	}
	f.mu.unlock()

	// Create new logger with namespace-appropriate level
	mut log_ := new()
	log_.set_output_label(name)

	// Resolve level from config hierarchy
	if !isnil(f.config) {
		mut cfg := f.config
		level := cfg.get_level(name)
		log_.set_level(level)
	}

	// Cache the logger
	f.mu.@lock()
	f.loggers[name] = log_
	f.mu.unlock()

	return log_
}

// get_logger_for creates a Logger named after type T.
// Uses T.name as the namespace for level resolution.
//
// Spring equivalent: LoggerFactory.getLogger(MyClass.class)
// Usage:
//   log_ := factory.get_logger_for[UserService]()
pub fn get_logger_for[T](mut f LoggerFactory) &Logger {
	return f.get_logger(T.name)
}

// reload_all re-applies the current LoggerConfig levels to all
// cached loggers. Call this after changing config levels to
// hot-update all existing loggers.
//
// Spring equivalent: Logback's JMX-based level reconfiguration
pub fn (mut f LoggerFactory) reload_all() {
	if isnil(f.config) {
		return
	}
	f.mu.@lock()
	mut cfg := f.config
	for name, mut log_ in f.loggers {
		level := cfg.get_level(name)
		log_.set_level(level)
	}
	f.mu.unlock()
}

// logger_count returns the number of cached loggers.
pub fn (mut f LoggerFactory) logger_count() int {
	f.mu.rlock()
	defer { f.mu.runlock() }
	return f.loggers.len
}

// ── LogContext — Request-scoped structured logging context ──
//
// Provides automatic propagation of trace_id, request_id, and
// other contextual fields across the request lifecycle.
// Inspired by Spring Sleuth's trace propagation and
// Go's context.Context pattern.

// LogContext holds request-scoped structured logging fields.
// These fields are automatically included in all log entries
// created from a Logger that has this context attached.
pub struct LogContext {
pub mut:
	trace_id   string
	request_id string
	span       string
	fields     map[string]string
}

// new_log_context creates an empty LogContext.
pub fn new_log_context() &LogContext {
	return &LogContext{
		fields: map[string]string{}
	}
}

// with_trace_id sets the trace ID and returns the context for chaining.
pub fn (mut ctx LogContext) with_trace_id(id string) &LogContext {
	ctx.trace_id = id
	if id.len > 0 {
		ctx.fields['trace_id'] = id
	}
	return ctx
}

// with_request_id sets the request ID and returns the context for chaining.
pub fn (mut ctx LogContext) with_request_id(id string) &LogContext {
	ctx.request_id = id
	if id.len > 0 {
		ctx.fields['request_id'] = id
	}
	return ctx
}

// with_span sets the span name and returns the context for chaining.
pub fn (mut ctx LogContext) with_span(name string) &LogContext {
	ctx.span = name
	if name.len > 0 {
		ctx.fields['span'] = name
	}
	return ctx
}

// with_field adds an arbitrary key-value field and returns the context for chaining.
pub fn (mut ctx LogContext) with_field(key string, value string) &LogContext {
	ctx.fields[key] = value
	return ctx
}

// to_fields returns all context fields as a map for Logger.with_fields().
pub fn (ctx &LogContext) to_fields() map[string]string {
	return ctx.fields.clone()
}

// ── Logger Output Enhancement ──

// LogOutputFn is the function type for log output destinations.
// V 0.5.1 requires a named type alias for function type arrays.
pub type LogOutputFn = fn (string)

// MultiOutputLogger wraps a Logger and sends output to multiple destinations.
// This is useful for simultaneously logging to console and file.
//
// Spring equivalent: Logback's Appender chain
pub struct MultiOutputLogger {
pub mut:
	logger  &Logger
	outputs []LogOutputFn
}

// new_multi_output_logger creates a MultiOutputLogger.
pub fn new_multi_output_logger(log_ &Logger) &MultiOutputLogger {
	return &MultiOutputLogger{
		logger:  log_
		outputs: []LogOutputFn{}
	}
}

// add_output adds an output destination.
pub fn (mut m MultiOutputLogger) add_output(writer fn (string)) {
	m.outputs << writer
}

// info logs at INFO level to all outputs.
pub fn (mut m MultiOutputLogger) info(msg string) {
	m.logger.info(msg)
	m.write_to_all(msg)
}

// warn logs at WARN level to all outputs.
pub fn (mut m MultiOutputLogger) warn(msg string) {
	m.logger.warn(msg)
	m.write_to_all(msg)
}

// error logs at ERROR level to all outputs.
pub fn (mut m MultiOutputLogger) error(msg string) {
	m.logger.error(msg)
	m.write_to_all(msg)
}

// debug logs at DEBUG level to all outputs.
pub fn (mut m MultiOutputLogger) debug(msg string) {
	m.logger.debug(msg)
	m.write_to_all(msg)
}

// write_to_all sends the message to all registered output writers.
fn (m &MultiOutputLogger) write_to_all(msg string) {
	for writer in m.outputs {
		writer(msg)
	}
}
module log

// log.v - Photon Logging Module
//
// Provides structured, leveled logging as a wrapper around V's native log module.
// Supports multiple levels, colored output, structured (JSON) logging, and MDC context.

import time

// Level represents the severity of a log message
pub enum Level {
	debug = 0
	info  = 1
	warn  = 2
	error = 3
	fatal = 4
}

// str converts Level to string
pub fn (l Level) str() string {
	return match l {
		.debug { 'DEBUG' }
		.info  { 'INFO' }
		.warn  { 'WARN' }
		.error { 'ERROR' }
		.fatal { 'FATAL' }
	}
}

// Logger provides structured logging capabilities
pub struct Logger {
pub mut:
	level        Level  = .info
	output_label string = 'photon'
	colored      bool
	structured   bool
mut:
	context       map[string]string // MDC context
}

// new creates a new Logger
pub fn new() &Logger {
	return &Logger{
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

// set_colored enables or disables colored output
pub fn (mut l Logger) set_colored(colored bool) {
	l.colored = colored
}

// set_structured enables or disables structured (JSON) logging
pub fn (mut l Logger) set_structured(structured bool) {
	l.structured = structured
}

// set_output_label sets the logger label
pub fn (mut l Logger) set_output_label(label string) {
	l.output_label = label
}

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

// log writes a log message at the given level
pub fn (l &Logger) log(level Level, msg string) {
	if int(level) < int(l.level) {
		return
	}

	timestamp := time.now().format_rfc3339()
	level_str := level.str()

	if l.structured {
		l.log_structured(level_str, msg, timestamp)
	} else {
		l.log_plain(level_str, msg, timestamp)
	}
}

// log_plain writes a plain text log entry
fn (l &Logger) log_plain(level_str string, msg string, timestamp string) {
	context_str := l.build_context_str()
	if context_str.len > 0 {
		eprintln('[${timestamp}] [${level_str}] [${l.output_label}] ${context_str} ${msg}')
	} else {
		eprintln('[${timestamp}] [${level_str}] [${l.output_label}] ${msg}')
	}
}

// log_structured writes a JSON structured log entry
fn (l &Logger) log_structured(level_str string, msg string, timestamp string) {
	mut parts := []string{}
	parts << '"timestamp":"${timestamp}"'
	parts << '"level":"${level_str}"'
	parts << '"logger":"${l.output_label}"'
	parts << '"message":"${msg}"'
	for key, value in l.context {
		parts << '"${key}":"${value}"'
	}
	eprintln('{ ${parts.join(', ')} }')
}

// build_context_str builds the MDC context string
fn (l &Logger) build_context_str() string {
	if l.context.len == 0 {
		return ''
	}
	mut pairs := []string{}
	for key, value in l.context {
		pairs << '${key}=${value}'
	}
	return '[${pairs.join(' ')}]'
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

// debugf formats and logs a debug message
pub fn (l &Logger) debugf(msg string, a string) {
	l.debug(msg.replace('{}', a))
}

// infof formats and logs an info message
pub fn (l &Logger) infof(msg string, a string) {
	l.info(msg.replace('{}', a))
}

// warnf formats and logs a warn message
pub fn (l &Logger) warnf(msg string, a string) {
	l.warn(msg.replace('{}', a))
}

// errorf formats and logs an error message
pub fn (l &Logger) errorf(msg string, a string) {
	l.error(msg.replace('{}', a))
}

// fatalf formats and logs a fatal message
pub fn (l &Logger) fatalf(msg string, a string) {
	l.fatal(msg.replace('{}', a))
}

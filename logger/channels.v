module logger

// channels.v - Log Channels & Sensitive Data Masking (Laravel/Monolog inspired)
//
// Provides:
//   - Multiple log channels (stderr, file, syslog)
//   - Channel stacking (log to multiple targets simultaneously)
//   - Sensitive data masking (auto-redact passwords, tokens, keys)
//   - Request ID auto-injection into log output

import time
import os

// Channel is a log output destination
pub interface Channel {
	write(level Level, msg string, context map[string]string)
	name() string
}

// StderrChannel writes log entries to stderr (default)
pub struct StderrChannel {
pub:
	name_str string = 'stderr'
}

pub fn (c &StderrChannel) name() string { return c.name_str }

pub fn (c &StderrChannel) write(level Level, msg string, context map[string]string) {
	mut line := format_log_line(level, msg, context)
	line = mask_sensitive_data(line)
	eprintln(line)
}

// FileChannel writes log entries to a file.
// For high-throughput scenarios, consider using a buffered writer
// or an external log aggregation pipeline.
pub struct FileChannel {
pub:
	name_str string = 'file'
	filepath string
}

pub fn (c &FileChannel) name() string { return c.name_str }

pub fn (c &FileChannel) write(level Level, msg string, context map[string]string) {
	mut line := format_log_line(level, msg, context)
	line = mask_sensitive_data(line)

	mut f := os.open_append(c.filepath) or {
		eprintln('[LOG ERROR] Failed to open log file: ${c.filepath}')
		return
	}
	f.writeln(line) or {
		eprintln('[LOG ERROR] Failed to write to log file: ${c.filepath}')
	}
	f.close()
}

// SyslogChannel writes to syslog (stub for Linux)
pub struct SyslogChannel {
pub:
	name_str string = 'syslog'
	facility string = 'user'
}

pub fn (c &SyslogChannel) name() string { return c.name_str }

pub fn (c &SyslogChannel) write(level Level, msg string, context map[string]string) {
	mut line := format_log_line(level, msg, context)
	line = mask_sensitive_data(line)
	// Stub: on Linux, would use os.syslog()
	eprintln(line)
}

// ChannelLogger sends log entries to multiple channels
pub struct ChannelLogger {
pub mut:
	channels []&Channel
	context  map[string]string
	level    Level = .info
}

// new_channel_logger creates a ChannelLogger with default stderr channel
pub fn new_channel_logger() &ChannelLogger {
	return &ChannelLogger{
		channels: [StderrChannel{}]
		context: map[string]string{}
	}
}

// add_channel registers a log channel
pub fn (mut cl ChannelLogger) add_channel(ch &Channel) {
	cl.channels << ch
}

// put adds context (e.g., request_id) to all subsequent log entries
pub fn (mut cl ChannelLogger) put(key string, value string) {
	cl.context[key] = value
}

// remove deletes a context key
pub fn (mut cl ChannelLogger) remove(key string) {
	cl.context.delete(key)
}

// log writes to all channels
pub fn (cl &ChannelLogger) log(level Level, msg string) {
	if int(level) < int(cl.level) {
		return
	}
	for ch in cl.channels {
		ch.write(level, msg, cl.context)
	}
}

// Convenience methods
pub fn (cl &ChannelLogger) debug(msg string) { cl.log(.debug, msg) }
pub fn (cl &ChannelLogger) info(msg string)  { cl.log(.info, msg) }
pub fn (cl &ChannelLogger) warn(msg string)  { cl.log(.warn, msg) }
pub fn (cl &ChannelLogger) error(msg string) { cl.log(.error, msg) }
pub fn (cl &ChannelLogger) fatal(msg string) { cl.log(.fatal, msg) }

// WithContext creates a copy with additional context (immutable pattern)
pub fn (cl &ChannelLogger) with_context(key string, value string) &ChannelLogger {
	mut new_ctx := cl.context.clone()
	new_ctx[key] = value
	return &ChannelLogger{
		channels: cl.channels
		context: new_ctx
		level: cl.level
	}
}

// WithRequestId is a convenience for setting the request ID context
pub fn (cl &ChannelLogger) with_request_id(request_id string) &ChannelLogger {
	return cl.with_context('request_id', request_id)
}

// ============================================================
// Helper: format log line
// ============================================================

fn format_log_line(level Level, msg string, context map[string]string) string {
	ts := time.now().format_rfc3339()
	level_str := level.str()

	mut ctx_str := ''
	if context.len > 0 {
		mut pairs := []string{}
		for k, v in context {
			pairs << '${k}=${v}'
		}
		ctx_str = ' [${pairs.join(' ')}]'
	}

	return '[${ts}] [${level_str}]${ctx_str} ${msg}'
}

// ============================================================
// Sensitive Data Masking
// ============================================================

// Sensitive patterns that should be redacted from log output
const sensitive_patterns = [
	'password',
	'passwd',
	'secret',
	'token',
	'api_key',
	'apikey',
	'authorization',
	'credit_card',
	'ssn',
	'private_key',
]

// mask_sensitive_data redacts passwords, tokens, and other sensitive info
pub fn mask_sensitive_data(msg string) string {
	mut result := msg

	for pattern in sensitive_patterns {
		lower := result.to_lower()
		mut pos := 0
		for {
			idx := lower.index_after(pattern, pos) or { break }
			pos = idx + 1
			after_key := result[idx + pattern.len..]
			eq_idx := after_key.index('=') or {
				colon_idx := after_key.index(':') or { continue }
				colon_idx
			}
			if eq_idx >= 0 && eq_idx < 50 {
				value_start := idx + pattern.len + eq_idx + 1
				value_rest := result[value_start..]
				mut end_idx := value_rest.index(' ') or { value_rest.len }
				comma_idx := value_rest.index(',') or { value_rest.len }
				nl_idx := value_rest.index('\n') or { value_rest.len }
				if comma_idx < end_idx { end_idx = comma_idx }
				if nl_idx < end_idx { end_idx = nl_idx }

				masked := result[..value_start] + '***' + result[value_start + end_idx..]
				result = masked
			}
		}
	}

	if result.to_lower().contains('bearer ') {
		mut masked := ''
		mut i := 0
		for i < result.len {
			rest := result[i..].to_lower()
			if rest.starts_with('bearer ') {
				token_start := i + 7
				mut token_end := token_start
				for token_end < result.len && result[token_end] != ` ` && result[token_end] != `\n` {
					token_end++
				}
				masked += result[i..token_start] + '***'
				i = token_end
			} else {
				masked += result[i].ascii_str()
				i++
			}
		}
		result = masked
	}

	return result
}

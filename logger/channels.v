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
import sync

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

pub fn (c &StderrChannel) name() string {
	return c.name_str
}

pub fn (c &StderrChannel) write(level Level, msg string, context map[string]string) {
	mut line := format_log_line(level, msg, context)
	line = mask_sensitive_data(line)
	eprintln(line)
}

// FileChannel writes log entries to a file.
// The file handle is opened lazily on the first write and kept open
// for subsequent writes (no per-write open/close syscalls), so it is
// suitable for high-throughput logging. Call close() on shutdown to
// flush and release the handle; call reopen() after external log
// rotation to re-acquire the file at the same path.
pub struct FileChannel {
pub:
	name_str string = 'file'
	filepath string
mut:
	file os.File   // cached handle, kept open between writes
	mu   sync.Mutex // guards file open/write/close
}

pub fn (c &FileChannel) name() string {
	return c.name_str
}

pub fn (c &FileChannel) write(level Level, msg string, context map[string]string) {
	mut line := format_log_line(level, msg, context)
	line = mask_sensitive_data(line)

	// The Channel interface requires an immutable receiver; the cached
	// handle is mutated through unsafe, guarded by the mutex.
	mut ch := unsafe { c }
	ch.mu.@lock()
	defer {
		ch.mu.unlock()
	}

	if !ch.file.is_opened {
		ch.file = os.open_append(c.filepath) or {
			eprintln('[LOG ERROR] Failed to open log file: ${c.filepath}')
			return
		}
	}
	ch.file.writeln(line) or {
		// Write failed (e.g., stale handle after rotation): close,
		// reopen once, and retry.
		ch.file.close()
		ch.file = os.open_append(c.filepath) or {
			eprintln('[LOG ERROR] Failed to reopen log file: ${c.filepath}')
			return
		}
		ch.file.writeln(line) or {
			eprintln('[LOG ERROR] Failed to write to log file: ${c.filepath}')
		}
	}
	// Flush after every write so log lines are immediately durable and
	// visible to external readers (same semantics as the old
	// open/write/close-per-line implementation).
	ch.file.flush()
}

// close flushes and closes the cached file handle. Call on shutdown.
// The next write() lazily reopens the file, so logging can continue.
pub fn (c &FileChannel) close() {
	mut ch := unsafe { c }
	ch.mu.@lock()
	defer {
		ch.mu.unlock()
	}
	if ch.file.is_opened {
		ch.file.flush()
		ch.file.close()
	}
}

// reopen closes the cached file handle (if open) so the next write
// reopens the file at the same path. Call after external log rotation.
pub fn (c &FileChannel) reopen() {
	mut ch := unsafe { c }
	ch.mu.@lock()
	defer {
		ch.mu.unlock()
	}
	if ch.file.is_opened {
		ch.file.close()
	}
}

// SyslogChannel writes to syslog (stub for Linux)
pub struct SyslogChannel {
pub:
	name_str string = 'syslog'
	facility string = 'user'
}

pub fn (c &SyslogChannel) name() string {
	return c.name_str
}

pub fn (c &SyslogChannel) write(level Level, msg string, context map[string]string) {
	mut line := format_log_line(level, msg, context)
	line = mask_sensitive_data(line)
	// Stub: on Linux, would use os.syslog()
	eprintln(line)
}

// ChannelLogger sends log entries to multiple channels.
// @deprecated: Use Logger with add_sink() instead.
// ChannelLogger will be removed in a future version.
// Migration: replace `cl := new_channel_logger()` with `l := logger.new()`,
// then use `l.add_sink(FileChannel{...})` for file output.
@[deprecated: 'use Logger with add_sink() instead']
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
		context:  map[string]string{}
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
pub fn (cl &ChannelLogger) debug(msg string) {
	cl.log(.debug, msg)
}

pub fn (cl &ChannelLogger) info(msg string) {
	cl.log(.info, msg)
}

pub fn (cl &ChannelLogger) warn(msg string) {
	cl.log(.warn, msg)
}

pub fn (cl &ChannelLogger) error(msg string) {
	cl.log(.error, msg)
}

pub fn (cl &ChannelLogger) fatal(msg string) {
	cl.log(.fatal, msg)
}

// WithContext creates a copy with additional context (immutable pattern)
pub fn (cl &ChannelLogger) with_context(key string, value string) &ChannelLogger {
	mut new_ctx := cl.context.clone()
	new_ctx[key] = value
	return &ChannelLogger{
		channels: cl.channels
		context:  new_ctx
		level:    cl.level
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
	lower := msg.to_lower()

	for pattern in sensitive_patterns {
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

	if lower.contains('bearer ') {
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

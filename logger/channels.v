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
import strings
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
//
// This is the multi-sink logger and it is still fully supported; the type is
// only *scheduled* for consolidation into Logger.add_sink(). It must not carry
// @[deprecated] until that migration exists: `-prod` turns deprecation warnings
// into errors, so the marker alone breaks the production build while every
// caller is still using this type.
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

// format_log_line renders one log line.
//
// Built with a strings.Builder sized up front: the previous version allocated
// a []string plus a joined string for the MDC context and then concatenated
// everything again, so a line with context cost ~4 allocations per write.
fn format_log_line(level Level, msg string, context map[string]string) string {
	ts := time.now().format_rfc3339()
	level_str := level.str()

	mut size := ts.len + level_str.len + msg.len + 8
	if context.len > 0 {
		for k, v in context {
			size += k.len + v.len + 4
		}
	}
	mut sb := strings.new_builder(size)
	sb.write_u8(`[`)
	sb.write_string(ts)
	sb.write_string2('] [', level_str)
	sb.write_u8(`]`)
	if context.len > 0 {
		sb.write_string(' [')
		mut first := true
		for k, v in context {
			if !first {
				sb.write_u8(` `)
			}
			first = false
			sb.write_string2(k, '=')
			sb.write_string(v)
		}
		sb.write_u8(`]`)
	}
	sb.write_u8(` `)
	sb.write_string(msg)
	return sb.str()
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

// mask_separator_index returns the offset of the separator that sits between a
// sensitive key and its value, or -1 when the text right after the key is not
// a `key<sep>value` shape.
//
// A `=` / `:` only counts when it is the FIRST structural character after the
// key — anything else means we matched a substring inside an unrelated word
// (`token` inside `tokenizer`), and the search must move on. Both separators
// are considered, whichever comes first, so `token=x` and `token: x` behave
// the same.
fn mask_separator_index(after_key string) int {
	mut best := -1
	for sep in [mask_eq_sep, mask_colon_sep] {
		sep_idx := after_key.index(sep) or { continue }
		if best < 0 || sep_idx < best {
			best = sep_idx
		}
	}
	if best < 0 {
		return -1
	}
	// Only whitespace may sit between the key and its separator.
	for ch in after_key[..best] {
		if ch != ` ` && ch != `\t` {
			return -1
		}
	}
	return best
}

const mask_eq_sep = '='
const mask_colon_sep = ':'

// span_less orders spans by start, then by end.
fn span_less(a []int, b []int) bool {
	if a[0] != b[0] {
		return a[0] < b[0]
	}
	return a[1] < b[1]
}

// apply_mask_spans replaces every [start, end) range in `spans` with `***`.
// Ranges are sorted and merged first, so overlapping or touching masks produce
// a single placeholder instead of duplicated text or a torn value.
fn apply_mask_spans(text string, spans [][]int) string {
	// Insertion sort: `sort_with_compare` on [][]int mis-ordered the inner
	// slices in practice (V cgen gave the comparator bogus elements), and the
	// span count here is tiny — one entry per masked value in a log line.
	mut sorted := spans.clone()
	for i in 1 .. sorted.len {
		mut j := i
		for j > 0 && span_less(sorted[j], sorted[j - 1]) {
			sorted[j], sorted[j - 1] = sorted[j - 1], sorted[j]
			j--
		}
	}

	mut merged := [][]int{cap: sorted.len}
	for i in 0 .. sorted.len {
		start := if sorted[i][0] < 0 { 0 } else { sorted[i][0] }
		end := if sorted[i][1] > text.len { text.len } else { sorted[i][1] }
		if start >= end {
			continue
		}
		if merged.len > 0 && start <= merged[merged.len - 1][1] {
			if end > merged[merged.len - 1][1] {
				merged[merged.len - 1][1] = end
			}
			continue
		}
		merged << [start, end]
	}

	mut out := strings.new_builder(text.len)
	mut cursor := 0
	for i in 0 .. merged.len {
		out.write_string(text[cursor..merged[i][0]])
		out.write_string(mask_placeholder)
		cursor = merged[i][1]
	}
	out.write_string(text[cursor..])
	return out.str()
}

// mask_placeholder is what redacted values are replaced with.
const mask_placeholder = '***'

// mask_value_separators terminate a sensitive value.
const mask_value_separators = [' ', ',', '\n', '&', ';', '"', "'"]

// mask_sensitive_data redacts passwords, tokens, and other sensitive info
// 脱敏密码、令牌等敏感信息。
//
// The scan works on a lowercased snapshot that is never mutated, and masks are
// recorded as (start, end) byte ranges. Only after every pattern has been
// scanned is the output rebuilt in one pass. Two classes of bug came from the
// previous "search a stale copy, rewrite `result` in place" approach:
//
//   - hard panic — `substr(out of bounds)` once `***` changed the length of
//     the text the offsets were computed against
//     (e.g. `password=x&token`, `token=xx&token=yy`);
//   - silent over-masking — a second match of the same key landed inside the
//     `***` placeholder already written, so the rest of the value was eaten
//     (`token=xx&token=yy` became `token=***`).
//
// Recording ranges instead of rewriting keeps every offset valid and lets
// overlapping masks collapse into one. `pos` only ever moves past the key that
// was just matched, so the loop always terminates.
pub fn mask_sensitive_data(msg string) string {
	lower := msg.to_lower()
	if lower.len == 0 {
		return msg
	}

	// Byte ranges to replace with '***'.
	mut spans := [][]int{}
	for pattern in sensitive_patterns {
		mut pos := 0
		for {
			idx := lower.index_after(pattern, pos) or { break }

			// Advance past the matched key no matter what happens below —
			// this is what guarantees termination.
			next_pos := idx + pattern.len
			after_key := if next_pos <= lower.len { lower[next_pos..] } else { '' }
			eq_idx := mask_separator_index(after_key)
			if eq_idx < 0 || eq_idx >= 50 {
				// Not a `key = value` / `key: value` shape.
				pos = next_pos
				continue
			}

			// Skip the padding between the separator and the value so
			// `password = secret` masks `secret` rather than giving up on the
			// leading space.
			mut value_start := next_pos + eq_idx + 1
			for value_start < lower.len && (lower[value_start] == ` ` || lower[value_start] == `\t`) {
				value_start++
			}
			if value_start >= lower.len {
				pos = next_pos
				continue
			}
			value_rest := lower[value_start..]
			// A value ends at whitespace, a comma, a newline, or `&` — the
			// last one matters for query strings (`a=1&token=x&b=2`), where
			// stopping only on whitespace would swallow the rest of the line.
			mut end_idx := value_rest.len
			for sep in mask_value_separators {
				if sep_idx := value_rest.index(sep) {
					if sep_idx < end_idx {
						end_idx = sep_idx
					}
				}
			}
			// An empty value has nothing to redact.
			if end_idx > 0 {
				spans << [value_start, value_start + end_idx]
				pos = value_start + end_idx
			} else {
				pos = value_start
			}
		}
	}

	mut result := if spans.len == 0 { msg } else { apply_mask_spans(msg, spans) }

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

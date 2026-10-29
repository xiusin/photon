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
//
// Size-based rotation (opt-in):
//   max_size_bytes > 0 时，单次写入会让文件超过该大小时先把当前文件
//   改名为 <filepath>.1（旧的 .1 顺延为 .2，依此类推），再写新文件。
//   max_backups 决定保留几份历史文件（默认 3），0 表示不保留 —— 轮转后
//   直接 truncate 同一个文件。
//
// 为什么在 write() 里判断而不是起后台协程：日志量不均匀，后台轮询要么
// 太慢（已超限很久还没切），要么空转。写入点本来就知道即将写多少字节，
// 判断是 O(1) 的，不用额外状态。
pub struct FileChannel {
pub:
	name_str string = 'file'
	filepath string
	// max_size_bytes 单文件大小上限，<= 0 表示不轮转
	max_size_bytes i64
	// max_backups 保留的历史文件份数（.1 .. .N），0 表示不保留
	max_backups int = 3
mut:
	file os.File // cached handle, kept open between writes
	// written 是当前文件已写入的字节数，打开文件时按实际大小初始化
	written i64
	// rotations 累计轮转次数（诊断用），由 mu 保护
	rotations int
	mu        sync.Mutex // guards file open/write/close, written, rotations
}

// FileChannelConfig 配置带轮转的文件通道（@[params] 便于用命名参数构造）。
@[params]
pub struct FileChannelConfig {
pub:
	name     string = 'file'
	filepath string
	// max_size_bytes 单文件大小上限（字节），<= 0 表示不轮转
	max_size_bytes i64
	// max_backups 保留的历史文件份数
	max_backups int = 3
}

// new_file_channel 创建文件通道（默认不轮转，与直接构造 FileChannel 等价）。
pub fn new_file_channel(filepath string) &FileChannel {
	return &FileChannel{
		filepath: filepath
	}
}

// new_rolling_file_channel 创建按大小轮转的文件通道。
//
//   rot := logger.new_rolling_file_channel(
//       filepath:      '/var/log/app.log'
//       max_size_bytes: 50 * 1024 * 1024  // 50MB
//       max_backups:   7
//   )
//   mut log_ := logger.new()
//   log_.add_sink(rot)
pub fn new_rolling_file_channel(config FileChannelConfig) &FileChannel {
	// 显式写全字段：V 的 @[params] 结构体会把缺省实参取成结构体默认值
	// （max_backups 默认 3），所以「调用方没传」和「调用方传了 3」在这里
	// 等价 —— 想要「不保留历史」必须显式写 max_backups: 0。
	return &FileChannel{
		name_str:       config.name
		filepath:       config.filepath
		max_size_bytes: config.max_size_bytes
		max_backups:    config.max_backups
	}
}

// should_rotate 判断再写入 incoming 字节是否会越过上限。
fn (c &FileChannel) should_rotate(incoming i64) bool {
	if c.max_size_bytes <= 0 || c.filepath.len == 0 {
		return false
	}
	return c.written + incoming > c.max_size_bytes
}

// backup_path 返回第 index 份历史文件的路径（index 从 1 开始）。
fn (c &FileChannel) backup_path(index int) string {
	return '${c.filepath}.${index}'
}

// rotate_locked 把当前文件顺延成 .1，其余历史文件依次后移，然后丢弃缓存的
// 文件句柄（下一次 write 会重建）。调用方必须已持有 mu，且最好先关闭句柄。
fn (mut c FileChannel) rotate_locked() {
	if c.max_backups <= 0 {
		// 不留历史：直接清空当前文件，句柄照样需要重建。
		if c.file.is_opened {
			c.file.flush()
			c.file.close()
		}
		if os.exists(c.filepath) {
			os.rm(c.filepath) or {
				eprintln('[LOG ERROR] Failed to truncate log file: ${c.filepath}')
			}
		}
		c.written = 0
		c.rotations++
		return
	}

	if c.file.is_opened {
		c.file.flush()
		c.file.close()
	}

	// 最旧的一份直接删掉，否则改名会一路撞名。
	oldest := c.backup_path(c.max_backups)
	if os.exists(oldest) {
		os.rm(oldest) or { eprintln('[LOG ERROR] Failed to remove oldest log backup: ${oldest}') }
	}
	// 从最旧的往里顺延：文件名里的序号是 int，不能拿字符串排序代替。
	// V 的 for 条件只支持 `<`，倒序用 while 表达。
	mut i := c.max_backups - 1
	for i >= 1 {
		src := c.backup_path(i)
		if os.exists(src) {
			os.mv(src, c.backup_path(i + 1)) or {
				eprintln('[LOG ERROR] Failed to rotate log backup: ${src}')
			}
		}
		i--
	}
	if os.exists(c.filepath) {
		os.mv(c.filepath, c.backup_path(1)) or {
			eprintln('[LOG ERROR] Failed to rotate log file: ${c.filepath}')
		}
	}
	c.written = 0
	c.rotations++
}

// rotation_count 返回本通道累计轮转次数（诊断用）。
pub fn (c &FileChannel) rotation_count() int {
	mut ch := unsafe { c }
	ch.mu.@lock()
	defer {
		ch.mu.unlock()
	}
	return ch.rotations
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
		// 打开时按文件实际大小初始化计数：进程重启后不能让计数器归零，
		// 否则「已经写了 900MB 的文件」会被当成空文件继续追加。
		ch.written = 0
		if os.exists(c.filepath) {
			ch.written = os.file_size(c.filepath)
		}
	}

	// 轮转判断放在写入前：先切文件再写，避免单行日志被撕成两个文件。
	// +1 是 writeln 追加的换行符。
	if ch.should_rotate(i64(line.len) + 1) {
		ch.rotate_locked()
		ch.file = os.open_append(c.filepath) or {
			eprintln('[LOG ERROR] Failed to reopen rotated log file: ${c.filepath}')
			return
		}
		ch.written = 0
	}

	ch.file.writeln(line) or {
		// Write failed (e.g., stale handle after rotation): close,
		// reopen once, and retry.
		ch.file.close()
		ch.file = os.open_append(c.filepath) or {
			eprintln('[LOG ERROR] Failed to reopen log file: ${c.filepath}')
			return
		}
		ch.written = 0
		ch.file.writeln(line) or {
			eprintln('[LOG ERROR] Failed to write to log file: ${c.filepath}')
			return
		}
	}
	ch.written += i64(line.len) + 1
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
		ch.written = 0
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
		ch.written = 0
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
// Keys are matched as case-insensitive substrings; the separator must follow
// the key (see mask_separator_index). Header spellings are listed explicitly:
// an HTTP header is written `X-Api-Key`, and the underscore form alone never
// matched it — the most common way an API key reaches a log line went through
// unredacted.
const sensitive_patterns = [
	'password',
	'passwd',
	'secret',
	'token',
	'api_key',
	'api-key',
	'apikey',
	'authorization',
	'credit_card',
	'credit-card',
	'ssn',
	'private_key',
	'private-key',
]

// may_contain_sensitive_key reports whether `msg` has any chance of containing
// a redactable pair, matching case-insensitively and without allocating the
// lowercased copy the slow path would build (`AUTHORIZATION:` is a header just
// as much as `authorization:` is).
//
// It is a filter, not a decision: a hit only means "worth running the full
// scan", which then validates the key/separator shape.
fn may_contain_sensitive_key(msg string) bool {
	for pattern in sensitive_patterns {
		if contains_ignore_ascii_case(msg, pattern) {
			return true
		}
	}
	return false
}

// contains_ignore_ascii_case reports whether `haystack` contains `needle`,
// comparing ASCII letters case-insensitively. Allocation-free.
fn contains_ignore_ascii_case(haystack string, needle string) bool {
	if needle.len == 0 {
		return true
	}
	if haystack.len < needle.len {
		return false
	}
	for i in 0 .. haystack.len - needle.len + 1 {
		if eq_ignore_ascii_case(haystack, i, needle) {
			return true
		}
	}
	return false
}

// bearer_token_end_after returns the end offset of a `Bearer <token>` value
// that starts exactly at `value_start`, or none.
//
// Only the credential that follows the scheme word is masked; the scheme word
// itself carries no secret, and masking it produced the misleading
// `Authorization: *** abc.def.ghi`.
fn bearer_token_end_after(text string, value_start int) ?int {
	scheme := 'bearer '
	if value_start + scheme.len > text.len {
		return none
	}
	if !eq_ignore_ascii_case(text, value_start, scheme) {
		return none
	}
	mut end := value_start + scheme.len
	for end < text.len && text[end] != ` ` && text[end] != `\t` && text[end] != `\n` {
		end++
	}
	if end <= value_start + scheme.len {
		return none
	}
	return end
}

// mask_quoted_value_span handles `"value"` / 'value' shaped values.
//
// Log lines are frequently JSON: `{"password":"s3cret"}`. The generic value
// scan stops at the first separator, and the opening quote would terminate it
// immediately — an empty span means "nothing to redact", so the secret stayed
// in the output verbatim. Returns the span INSIDE the quotes, or none when the
// value is not quoted.
fn mask_quoted_value_span(text string, value_start int) ?[]int {
	if value_start >= text.len {
		return none
	}
	quote := text[value_start]
	if quote != `"` && quote != `'` {
		return none
	}
	mut i := value_start + 1
	for i < text.len {
		if text[i] == quote {
			if i > value_start + 1 {
				return [value_start + 1, i]
			}
			return none
		}
		i++
	}
	return none
}

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
	// A quote right after the key is the shape structured output takes
	// (`"password":"s3cret"`); step over it the same way, so the separator
	// search starts where the separator actually is.
	mut skip := 0
	for skip < after_key.len && skip < 40 {
		ch := after_key[skip]
		if ch == `-` || ch == `_` || ch == `.` || ch == `"` || ch == `'` {
			skip++
			continue
		}
		break
	}
	mut best := -1
	for sep in [mask_eq_sep, mask_colon_sep] {
		sep_idx := after_key.index_after(sep, skip) or { continue }
		if best < 0 || sep_idx < best {
			best = sep_idx
		}
	}
	if best < 0 {
		return -1
	}
	// Only the skipped glue characters plus whitespace may sit between the key
	// and its separator.
	for ch in after_key[skip..best] {
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
//
// Quotes are deliberately NOT separators: JSON log output wraps the value in
// quotes (`{"password":"p@ss word"}`), and stopping at the opening quote made
// the span empty — "nothing to redact" — so the whole secret stayed in the
// output. Quoted values are unwrapped by mask_quoted_value_span() instead.
const mask_value_separators = [' ', '\t', ',', '\n', '\r', '&', ';']

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
	if msg.len == 0 {
		return msg
	}

	// Fast path: most lines carry no sensitive key at all. Scanning the raw
	// message for the needles before lowercasing it means the common case
	// allocates nothing and runs ~1 memchr pass per pattern.
	//
	// The lowercase pass below is unavoidable in general (a header can arrive
	// as `AUTHORIZATION:`), but it is only worth paying when there is
	// something to mask.
	//
	// `bearer <token>` is the one shape this filter must not gate: it carries
	// no key/separator pair, so it is detected on its own below.
	lower := if may_contain_sensitive_key(msg) { msg.to_lower() } else { '' }

	// Byte ranges to replace with '***'.
	mut spans := [][]int{}
	if lower.len == 0 {
		// Nothing key-shaped in this line; only the bearer scan may apply.
		if has_bearer_credential(msg) {
			return mask_bearer_tokens(msg)
		}
		return msg
	}
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
			// A quoted value is unwrapped before the generic scan: the quote
			// itself terminates a plain value span, which would leave the
			// secret unredacted right after a `"password":` key.
			if quoted := mask_quoted_value_span(msg, value_start) {
				spans << quoted
				pos = quoted[1] + 1
				continue
			}
			// `Authorization: Bearer <token>`: the generic scan redacts the
			// literal word "Bearer" and leaves the credential right behind a
			// `***`. That reads as redacted and is not — extend the span over
			// the token itself.
			if bearer_end := bearer_token_end_after(msg, value_start) {
				spans << [value_start, bearer_end]
				pos = bearer_end
				continue
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

	// `Bearer <token>` is the one shape the key/value scan cannot see (there is
	// no separator). Detect it on the already-lowercased snapshot instead of
	// lowercasing the line a second time, then rebuild in one pass.
	//
	// A line whose key scan found nothing (`lower.len == 0`) took the early
	// return above, so a fresh `lower` is never needed here.
	if lower.contains('bearer ') {
		result = mask_bearer_tokens(result)
	}

	return result
}

// has_bearer_credential reports whether `text` contains a `bearer ` credential,
// case-insensitively and without allocating a lowercased copy of the line.
//
// This gate is what keeps `Bearer ...` masking off the hot path: the previous
// version lowercased the entire log line just to run `.contains('bearer ')`.
fn has_bearer_credential(text string) bool {
	needle := 'bearer '
	if text.len < needle.len {
		return false
	}
	for i in 0 .. text.len - needle.len + 1 {
		if !eq_ignore_ascii_case(text, i, needle) {
			continue
		}
		return true
	}
	return false
}

// eq_ignore_ascii_case reports whether text[pos..] starts with `needle`,
// comparing ASCII letters case-insensitively.
fn eq_ignore_ascii_case(text string, pos int, needle string) bool {
	if pos + needle.len > text.len {
		return false
	}
	for k in 0 .. needle.len {
		a := text[pos + k]
		b := needle[k]
		la := if a >= `A` && a <= `Z` { a + 32 } else { a }
		lb := if b >= `A` && b <= `Z` { b + 32 } else { b }
		if la != lb {
			return false
		}
	}
	return true
}

// mask_bearer_tokens replaces `Bearer <token>` credentials with `Bearer ***`.
//
// Byte scan instead of a substring-per-character rebuild: it works on a single
// lowercased copy (allocation-free lookahead for the `bearer ` needle) and
// writes whole runs into one builder.
fn mask_bearer_tokens(text string) string {
	mut out := strings.new_builder(text.len)
	mut i := 0
	mut copy_from := 0
	for i + 7 <= text.len {
		if !eq_ignore_ascii_case(text, i, 'bearer ') {
			i++
			continue
		}
		token_start := i + 7
		if token_start >= text.len {
			break
		}
		mut token_end := token_start
		for token_end < text.len && text[token_end] != ` ` && text[token_end] != `\n` {
			token_end++
		}
		out.write_string(text[copy_from..token_start])
		out.write_string(mask_placeholder)
		copy_from = token_end
		i = token_end
	}
	out.write_string(text[copy_from..])
	return out.str()
}

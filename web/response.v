module web

// response.v - Response 增强（流式/下载/缓存控制）
//
// Response Enhancement: streaming responses, file downloads, cache control,
// conditional requests (ETag/If-None-Match, Last-Modified/If-Modified-Since),
// and a fluent ResponseBuilder API.
//
// Response 增强：流式响应、文件下载、缓存控制、条件请求
// （ETag/If-None-Match、Last-Modified/If-Modified-Since）
// 以及 Fluent API 的 ResponseBuilder。
import veb
import net.http
import os
import crypto.sha256
import encoding.hex
import time
import strings

// ── ResponseBuilder / 响应构建器 ──

// ResponseBuilder provides a fluent API for constructing HTTP responses.
// ResponseBuilder 提供 Fluent API 构建 HTTP 响应。
//
// 线程安全说明：
//   - ResponseBuilder 是请求级对象，每个请求独占一个实例，
//     不需要锁保护。Builder 模式通过链式调用在单线程中完成构建。
//
// Thread-safety notes:
//   - ResponseBuilder is a request-scoped object; each request owns
//     an exclusive instance, so no locking is needed. The Builder pattern
//     completes construction through chained calls in a single thread.
pub struct ResponseBuilder {
pub mut:
	status_code  int              = 200
	content_type string           = 'application/json'
	headers      map[string]string
	body         string
	// Cache-related fields / 缓存相关字段
	cache_control_str string
	etag_str         string
	last_modified_str string
}

// response creates a new ResponseBuilder with default values.
// response 创建带默认值的 ResponseBuilder。
pub fn response() ResponseBuilder {
	return ResponseBuilder{
		headers: map[string]string{}
	}
}

// status sets the HTTP status code. Returns self for chaining.
// status 设置 HTTP 状态码。返回自身以支持链式调用。
pub fn (mut rb ResponseBuilder) status(code int) &ResponseBuilder {
	rb.status_code = code
	return rb
}

// content_type sets the Content-Type header. Returns self for chaining.
// content_type 设置 Content-Type 头。返回自身以支持链式调用。
pub fn (mut rb ResponseBuilder) content_type(ct string) &ResponseBuilder {
	rb.content_type = ct
	return rb
}

// header adds a custom header. Returns self for chaining.
// header 添加自定义响应头。返回自身以支持链式调用。
pub fn (mut rb ResponseBuilder) header(key string, value string) &ResponseBuilder {
	rb.headers[key] = value
	return rb
}

// body sets the response body. Returns self for chaining.
// body 设置响应体。返回自身以支持链式调用。
pub fn (mut rb ResponseBuilder) body(data string) &ResponseBuilder {
	rb.body = data
	return rb
}

// send applies all settings to the veb.Context and sends the response.
// send 将所有设置应用到 veb.Context 并发送响应。
pub fn (rb &ResponseBuilder) send(mut ctx veb.Context) veb.Result {
	ctx.res.set_status(unsafe { http.Status(rb.status_code) })
	ctx.set_content_type(rb.content_type)

	// Apply custom headers / 应用自定义头
	for key, val in rb.headers {
		ctx.set_custom_header(key, val) or {}
	}

	// Apply cache headers if set / 如果设置了缓存头则应用
	if rb.cache_control_str.len > 0 {
		ctx.set_custom_header('Cache-Control', rb.cache_control_str) or {}
	}
	if rb.etag_str.len > 0 {
		ctx.set_custom_header('ETag', rb.etag_str) or {}
	}
	if rb.last_modified_str.len > 0 {
		ctx.set_custom_header('Last-Modified', rb.last_modified_str) or {}
	}

	return ctx.text(rb.body)
}

// ── CacheControlBuilder / 缓存控制构建器 ──

// CacheControlBuilder constructs Cache-Control header values.
// CacheControlBuilder 构建 Cache-Control 头值。
pub struct CacheControlBuilder {
pub mut:
	max_age         int
	s_max_age       int
	is_public       bool
	no_cache        bool
	no_store        bool
	must_revalidate bool
}

// cache_control sets the Cache-Control header using a CacheControlBuilder.
// Returns self for chaining.
//
// cache_control 使用 CacheControlBuilder 设置 Cache-Control 头。
// 返回自身以支持链式调用。
pub fn (mut rb ResponseBuilder) cache_control(cc CacheControlBuilder) &ResponseBuilder {
	mut parts := []string{}
	if cc.is_public {
		parts << 'public'
	} else {
		parts << 'private'
	}
	if cc.max_age > 0 {
		parts << 'max-age=${cc.max_age}'
	}
	if cc.s_max_age > 0 {
		parts << 's-maxage=${cc.s_max_age}'
	}
	if cc.no_cache {
		parts << 'no-cache'
	}
	if cc.no_store {
		parts << 'no-store'
	}
	if cc.must_revalidate {
		parts << 'must-revalidate'
	}
	rb.cache_control_str = parts.join(', ')
	return rb
}

// etag sets the ETag header. The tag is automatically wrapped in double quotes.
// Returns self for chaining.
//
// etag 设置 ETag 头。tag 自动包裹双引号。
// 返回自身以支持链式调用。
pub fn (mut rb ResponseBuilder) etag(tag string) &ResponseBuilder {
	rb.etag_str = '"${tag}"'
	return rb
}

// last_modified sets the Last-Modified header from a time.Time value.
// Uses the HTTP-date format (RFC 7231).
// Returns self for chaining.
//
// last_modified 从 time.Time 设置 Last-Modified 头。
// 使用 HTTP-date 格式（RFC 7231）。
// 返回自身以支持链式调用。
pub fn (mut rb ResponseBuilder) last_modified(modified time.Time) &ResponseBuilder {
	rb.last_modified_str = modified.http_header_string()
	return rb
}

// check_not_modified checks conditional request headers (If-None-Match,
// If-Modified-Since) and returns true if a 304 Not Modified response
// should be sent. The caller should return immediately when this returns true.
//
// check_not_modified 检查条件请求头（If-None-Match、If-Modified-Since），
// 如果应发送 304 Not Modified 响应则返回 true。
// 当返回 true 时，调用方应立即返回。
pub fn (rb &ResponseBuilder) check_not_modified(ctx &veb.Context) bool {
	// Check If-None-Match / 检查 If-None-Match
	if_none_match := ctx.get_custom_header('If-None-Match') or { '' }
	if if_none_match.len > 0 && rb.etag_str.len > 0 {
		// The client may send multiple ETags separated by commas
		// 客户端可能发送多个 ETag，以逗号分隔
		for client_etag in if_none_match.split(',') {
			if client_etag.trim_space() == rb.etag_str {
				return true
			}
		}
	}

	// Check If-Modified-Since / 检查 If-Modified-Since
	if_modified_since := ctx.get_custom_header('If-Modified-Since') or { '' }
	if if_modified_since.len > 0 && rb.last_modified_str.len > 0 {
		if if_modified_since == rb.last_modified_str {
			return true
		}
	}

	return false
}

// apply writes all response headers to the veb.Context without sending the body.
// Useful when you want to set headers manually and then send the body yourself.
//
// apply 将所有响应头写入 veb.Context，但不发送响应体。
// 当你想手动设置头然后自行发送响应体时很有用。
pub fn (rb &ResponseBuilder) apply(mut ctx veb.Context) {
	ctx.res.set_status(unsafe { http.Status(rb.status_code) })
	ctx.set_content_type(rb.content_type)

	for key, val in rb.headers {
		ctx.set_custom_header(key, val) or {}
	}

	if rb.cache_control_str.len > 0 {
		ctx.set_custom_header('Cache-Control', rb.cache_control_str) or {}
	}
	if rb.etag_str.len > 0 {
		ctx.set_custom_header('ETag', rb.etag_str) or {}
	}
	if rb.last_modified_str.len > 0 {
		ctx.set_custom_header('Last-Modified', rb.last_modified_str) or {}
	}
}

// ── Streaming Response / 流式响应 ──

// stream_response sends a response using chunked transfer encoding.
// chunk_fn produces data chunks; returning an empty array signals the end.
// Uses a 64KB buffer for each chunk.
//
// stream_response 使用分块传输编码发送响应。
// chunk_fn 产生数据块，返回空数组表示结束。
// 每个数据块使用 64KB 缓冲区。
pub fn stream_response(mut ctx veb.Context, content_type string, chunk_fn fn () ![]u8) veb.Result {
	ctx.set_content_type(content_type)
	ctx.set_custom_header('Transfer-Encoding', 'chunked') or {}

	mut sb := strings.new_builder(65536)
	for {
		chunk := chunk_fn() or { break }
		if chunk.len == 0 {
			break
		}
		sb.write(chunk.bytestr()) or { break }
	}

	return ctx.text(sb.str())
}

// ── File Download / 文件下载 ──

// Common MIME type mappings for file downloads.
// 常见 MIME 类型映射，用于文件下载。
const download_mime_types = {
	'.txt':    'text/plain'
	'.html':   'text/html'
	'.htm':    'text/html'
	'.css':    'text/css'
	'.js':     'text/javascript'
	'.json':   'application/json'
	'.xml':    'application/xml'
	'.pdf':    'application/pdf'
	'.zip':    'application/zip'
	'.gz':     'application/gzip'
	'.tar':    'application/x-tar'
	'.png':    'image/png'
	'.jpg':    'image/jpeg'
	'.jpeg':   'image/jpeg'
	'.gif':    'image/gif'
	'.svg':    'image/svg+xml'
	'.ico':    'image/x-icon'
	'.webp':   'image/webp'
	'.mp3':    'audio/mpeg'
	'.mp4':    'video/mp4'
	'.avi':    'video/x-msvideo'
	'.csv':    'text/csv'
	'.doc':    'application/msword'
	'.docx':   'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
	'.xls':    'application/vnd.ms-excel'
	'.xlsx':   'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
}

// download_file sends a file as a downloadable attachment.
// Reads the file in 64KB chunks to keep memory usage bounded.
// Automatically sets Content-Disposition, Content-Type, and Content-Length.
//
// ⚠️ Security: file_path is validated against path traversal (../).
// filename is sanitized to prevent Content-Disposition header injection.
//
// download_file 以可下载附件方式发送文件。
// 以 64KB 分块读取文件，保持内存使用有界。
// 自动设置 Content-Disposition、Content-Type 和 Content-Length。
//
// ⚠️ 安全：file_path 会验证路径遍历（../）。
// filename 会清理以防止 Content-Disposition 头注入。
pub fn download_file(mut ctx veb.Context, file_path string, filename string) veb.Result {
	// Path traversal prevention: reject paths containing ../
	// 路径遍历防护：拒绝包含 ../ 的路径
	if file_path.contains('..') {
		ctx.res.set_status(unsafe { http.Status(400) })
		ctx.set_content_type('application/json')
		return ctx.text('{"error":"invalid file path","code":400}')
	}

	if !os.exists(file_path) {
		ctx.res.set_status(unsafe { http.Status(404) })
		ctx.set_content_type('application/json')
		return ctx.text('{"error":"file not found","code":404}')
	}

	// Determine Content-Type from file extension
	// 根据文件扩展名推断 Content-Type
	mut content_type := 'application/octet-stream'
	ext := os.file_ext(file_path)
	if ext.len > 0 {
		if ct := download_mime_types[ext.to_lower()] {
			content_type = ct
		}
	}

	// Sanitize filename to prevent Content-Disposition header injection.
	// Remove CR/LF characters that could inject additional headers.
	// 清理 filename 以防止 Content-Disposition 头注入。
	// 移除可能注入额外头的 CR/LF 字符。
	safe_filename := filename.replace('\r', '').replace('\n', '')

	// Set response headers / 设置响应头
	ctx.set_custom_header('Content-Disposition', 'attachment; filename="${safe_filename}"') or {}
	ctx.set_content_type(content_type)

	// Set Content-Length if file size is known
	// 如果文件大小已知，设置 Content-Length
	file_size := os.file_size(file_path)
	ctx.set_custom_header('Content-Length', '${file_size}') or {}

	// Open and read the file in 64KB chunks
	// 以 64KB 分块打开并读取文件
	mut f := os.open(file_path) or {
		ctx.res.set_status(unsafe { http.Status(500) })
		ctx.set_content_type('application/json')
		return ctx.text('{"error":"cannot open file","code":500}')
	}
	defer { f.close() }

	mut buf := []u8{len: 65536, cap: 65536} // 64KB buffer / 64KB 缓冲区
	mut sb := strings.new_builder(65536)
	for {
		n := f.read(mut buf) or { break }
		if n == 0 {
			break
		}
		sb.write(buf[..n].bytestr()) or { break }
	}

	return ctx.text(sb.str())
}

// ── Cache Control Helpers / 缓存控制辅助函数 ──

// cache_control sets Cache-Control header on the response.
// max_age: maximum age in seconds; public: whether the response is cacheable by shared caches.
//
// cache_control 在响应上设置 Cache-Control 头。
// max_age：最大缓存时间（秒）；public：是否可被共享缓存缓存。
pub fn cache_control(mut ctx veb.Context, max_age int, public bool) {
	mut value := ''
	if public {
		value = 'public'
	} else {
		value = 'private'
	}
	if max_age > 0 {
		value += ', max-age=${max_age}'
	}
	ctx.set_custom_header('Cache-Control', value) or {}
}

// set_etag computes a SHA-256 ETag from the data and sets the ETag header.
// The ETag is wrapped in double quotes per HTTP specification.
//
// set_etag 从数据计算 SHA-256 ETag 并设置 ETag 头。
// ETag 按 HTTP 规范包裹双引号。
pub fn set_etag(mut ctx veb.Context, data string) {
	digest := sha256.sum(data.bytes())
	mut arr := []u8{len: 32, cap: 32}
	for i in 0 .. 32 {
		arr[i] = digest[i]
	}
	etag_value := '"${hex.encode(arr)}"'
	ctx.set_custom_header('ETag', etag_value) or {}
}

// set_last_modified sets the Last-Modified header from a time.Time value.
// Uses the HTTP-date format (RFC 7231).
//
// set_last_modified 从 time.Time 设置 Last-Modified 头。
// 使用 HTTP-date 格式（RFC 7231）。
pub fn set_last_modified(mut ctx veb.Context, modified time.Time) {
	ctx.set_custom_header('Last-Modified', modified.http_header_string()) or {}
}

// check_not_modified checks conditional request headers and returns true
// if the client's cached copy is still valid (304 Not Modified should be sent).
//
// Checks:
//   - If-None-Match: compared against the current ETag header
//   - If-Modified-Since: compared against the current Last-Modified header
//
// When this returns true, the handler should immediately return a 304 response.
//
// check_not_modified 检查条件请求头，如果客户端缓存副本仍然有效则返回 true
// （应发送 304 Not Modified）。
//
// 检查：
//   - If-None-Match：与当前 ETag 头比较
//   - If-Modified-Since：与当前 Last-Modified 头比较
//
// 当返回 true 时，处理程序应立即返回 304 响应。
pub fn check_not_modified(ctx &veb.Context) bool {
	// Get current response headers / 获取当前响应头
	current_etag := ctx.get_custom_header('ETag') or { '' }
	current_last_modified := ctx.get_custom_header('Last-Modified') or { '' }

	// Check If-None-Match / 检查 If-None-Match
	if_none_match := ctx.get_custom_header('If-None-Match') or { '' }
	if if_none_match.len > 0 && current_etag.len > 0 {
		for client_etag in if_none_match.split(',') {
			if client_etag.trim_space() == current_etag {
				return true
			}
		}
	}

	// Check If-Modified-Since / 检查 If-Modified-Since
	if_modified_since := ctx.get_custom_header('If-Modified-Since') or { '' }
	if if_modified_since.len > 0 && current_last_modified.len > 0 {
		if if_modified_since == current_last_modified {
			return true
		}
	}

	return false
}
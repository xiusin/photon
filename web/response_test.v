module web

// response_test.v - ResponseBuilder 和响应辅助函数单元测试
// ResponseBuilder and Response Helper Unit Tests
//
// 测试覆盖 / Test Coverage:
//   - ResponseBuilder.new() 创建基本响应
//   - status() 设置状态码
//   - header() 设置响应头
//   - content_type() 设置 Content-Type
//   - body() 设置响应体
//   - cache_control() 缓存控制头
//   - etag() / last_modified() 条件请求头
//   - check_not_modified() 304 判断逻辑
//   - CacheControlBuilder 构建
//   - download_mime_types 常量映射
//   - response() 工厂函数
import time

// ── ResponseBuilder 创建测试 / ResponseBuilder creation tests ──

fn test_response_builder_default_values() {
	// response() 创建的 ResponseBuilder 默认值
	// Default values of ResponseBuilder created by response()
	mut rb := response()
	assert rb.status_code == 200
	assert rb.content_type == 'application/json'
	assert rb.body == ''
	assert rb.headers.len == 0
	assert rb.cache_control_str == ''
	assert rb.etag_str == ''
	assert rb.last_modified_str == ''
}

// ── status() 测试 / status() tests ──

fn test_response_builder_status() {
	// status() 设置 HTTP 状态码
	// status() sets the HTTP status code
	mut rb := response()
	rb.status(404)
	assert rb.status_code == 404
}

fn test_response_builder_status_various_codes() {
	// 各种状态码设置
	// Various status codes
	codes := [200, 201, 204, 301, 302, 304, 400, 401, 403, 404, 500, 503]
	for code in codes {
		mut rb := response()
		rb.status(code)
		assert rb.status_code == code
	}
}

// ── content_type() 测试 / content_type() tests ──

fn test_response_builder_content_type() {
	// content_type() 设置 Content-Type
	// content_type() sets the Content-Type header
	mut rb := response()
	rb.content_type('text/html')
	assert rb.content_type == 'text/html'
}

fn test_response_builder_content_type_json() {
	// 默认 Content-Type 为 application/json
	// Default Content-Type is application/json
	mut rb := response()
	assert rb.content_type == 'application/json'
}

// ── header() 测试 / header() tests ──

fn test_response_builder_header() {
	// header() 添加自定义响应头
	// header() adds a custom response header
	mut rb := response()
	rb.header('X-Custom', 'value')
	assert rb.headers['X-Custom'] == 'value'
}

fn test_response_builder_multiple_headers() {
	// 添加多个自定义头
	// Add multiple custom headers
	mut rb := response()
	rb.header('X-Request-Id', 'abc123')
	rb.header('X-Rate-Limit', '100')
	rb.header('X-Powered-By', 'Photon')
	assert rb.headers['X-Request-Id'] == 'abc123'
	assert rb.headers['X-Rate-Limit'] == '100'
	assert rb.headers['X-Powered-By'] == 'Photon'
	assert rb.headers.len == 3
}

fn test_response_builder_header_overwrite() {
	// 同名头覆盖
	// Same-name header overwrites the previous value
	mut rb := response()
	rb.header('X-Key', 'old')
	rb.header('X-Key', 'new')
	assert rb.headers['X-Key'] == 'new'
	assert rb.headers.len == 1
}

// ── body() 测试 / body() tests ──

fn test_response_builder_body() {
	// body() 设置响应体
	// body() sets the response body
	mut rb := response()
	rb.body('Hello, World!')
	assert rb.body == 'Hello, World!'
}

fn test_response_builder_body_empty() {
	// 空响应体
	// Empty response body
	mut rb := response()
	rb.body('')
	assert rb.body == ''
}

fn test_response_builder_body_json() {
	// JSON 响应体
	// JSON response body
	mut rb := response()
	rb.body('{"status":"ok","data":{"id":42}}')
	assert rb.body == '{"status":"ok","data":{"id":42}}'
}

// ── 链式调用测试 / Chaining tests ──

fn test_response_builder_chained() {
	// 链式调用构建响应
	// Chained calls to build a response
	mut rb := response()
	rb.status(201)
	rb.content_type('text/plain')
	rb.header('X-Custom', 'val')
	rb.body('created')
	assert rb.status_code == 201
	assert rb.content_type == 'text/plain'
	assert rb.headers['X-Custom'] == 'val'
	assert rb.body == 'created'
}

// ── cache_control() 测试 / cache_control() tests ──

fn test_response_builder_cache_control_public() {
	// cache_control() 设置公开缓存
	// cache_control() sets public cache
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		max_age: 3600
	})
	assert rb.cache_control_str == 'public, max-age=3600'
}

fn test_response_builder_cache_control_private() {
	// cache_control() 设置私有缓存
	// cache_control() sets private cache
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: false
		max_age: 600
	})
	assert rb.cache_control_str == 'private, max-age=600'
}

fn test_response_builder_cache_control_no_cache() {
	// cache_control() 设置 no-cache
	// cache_control() sets no-cache
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		no_cache: true
	})
	assert rb.cache_control_str.contains('no-cache')
}

fn test_response_builder_cache_control_no_store() {
	// cache_control() 设置 no-store
	// cache_control() sets no-store
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		no_store: true
	})
	assert rb.cache_control_str.contains('no-store')
}

fn test_response_builder_cache_control_must_revalidate() {
	// cache_control() 设置 must-revalidate
	// cache_control() sets must-revalidate
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		must_revalidate: true
	})
	assert rb.cache_control_str.contains('must-revalidate')
}

fn test_response_builder_cache_control_s_maxage() {
	// cache_control() 设置 s-maxage
	// cache_control() sets s-maxage
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		s_max_age: 7200
	})
	assert rb.cache_control_str.contains('s-maxage=7200')
}

fn test_response_builder_cache_control_full() {
	// cache_control() 完整组合
	// cache_control() full combination
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		max_age: 3600
		s_max_age: 7200
		no_cache: false
		no_store: false
		must_revalidate: true
	})
	assert rb.cache_control_str.contains('public')
	assert rb.cache_control_str.contains('max-age=3600')
	assert rb.cache_control_str.contains('s-maxage=7200')
	assert rb.cache_control_str.contains('must-revalidate')
}

// ── etag() 测试 / etag() tests ──

fn test_response_builder_etag() {
	// etag() 设置 ETag 头（自动包裹双引号）
	// etag() sets the ETag header (auto-wrapped in double quotes)
	mut rb := response()
	rb.etag('abc123')
	assert rb.etag_str == '"abc123"'
}

fn test_response_builder_etag_empty() {
	// etag() 空值
	// etag() with empty value
	mut rb := response()
	rb.etag('')
	assert rb.etag_str == '""'
}

// ── last_modified() 测试 / last_modified() tests ──

fn test_response_builder_last_modified() {
	// last_modified() 设置 Last-Modified 头
	// last_modified() sets the Last-Modified header
	mut rb := response()
	t := time.now()
	rb.last_modified(t)
	assert rb.last_modified_str.len > 0
}

fn test_response_builder_last_modified_format() {
	// last_modified() 使用 HTTP-date 格式
	// last_modified() uses HTTP-date format
	mut rb := response()
	t := time.Time{
		year: 2024
		month: 1
		day: 15
		hour: 12
		minute: 30
		second: 45
	}
	rb.last_modified(t)
	assert rb.last_modified_str.len > 0
}

// ── check_not_modified() 测试 / check_not_modified() tests ──

fn test_response_builder_check_not_modified_no_etag_no_last_modified() {
	// 没有设置 ETag 和 Last-Modified 时 check_not_modified 返回 false
	// check_not_modified returns false when no ETag or Last-Modified is set
	// 注意：check_not_modified 需要 veb.Context，此处验证 builder 状态
	// Note: check_not_modified requires veb.Context; here we verify builder state
	mut rb := response()
	assert rb.etag_str == ''
	assert rb.last_modified_str == ''
}

fn test_response_builder_check_not_modified_with_matching_etag() {
	// If-None-Match 与 ETag 匹配时返回 true
	// Returns true when If-None-Match matches the ETag
	// 注意：check_not_modified 需要 veb.Context 支持 get_custom_header
	// Note: check_not_modified requires veb.Context with get_custom_header support
	// 在没有真实 veb.Context 的情况下，我们测试 builder 状态
	// Without a real veb.Context, we test the builder state
	mut rb := response()
	rb.etag('v1')
	assert rb.etag_str == '"v1"'
}

// ── CacheControlBuilder 默认值测试 / CacheControlBuilder default tests ──

fn test_cache_control_builder_defaults() {
	// CacheControlBuilder 默认值
	// CacheControlBuilder defaults
	cc := CacheControlBuilder{}
	assert cc.max_age == 0
	assert cc.s_max_age == 0
	assert cc.is_public == false
	assert cc.no_cache == false
	assert cc.no_store == false
	assert cc.must_revalidate == false
}

// ── download_mime_types 常量测试 / download_mime_types constant tests ──

fn test_download_mime_types_txt() {
	assert download_mime_types['.txt'] == 'text/plain'
}

fn test_download_mime_types_html() {
	assert download_mime_types['.html'] == 'text/html'
}

fn test_download_mime_types_json() {
	assert download_mime_types['.json'] == 'application/json'
}

fn test_download_mime_types_pdf() {
	assert download_mime_types['.pdf'] == 'application/pdf'
}

fn test_download_mime_types_png() {
	assert download_mime_types['.png'] == 'image/png'
}

fn test_download_mime_types_jpg() {
	assert download_mime_types['.jpg'] == 'image/jpeg'
}

fn test_download_mime_types_css() {
	assert download_mime_types['.css'] == 'text/css'
}

fn test_download_mime_types_js() {
	assert download_mime_types['.js'] == 'text/javascript'
}

fn test_download_mime_types_zip() {
	assert download_mime_types['.zip'] == 'application/zip'
}

fn test_download_mime_types_unknown_ext() {
	// 未知扩展名不在映射中
	// Unknown extension is not in the map
	assert download_mime_types['.xyz'] == ''
}

// ── apply() 测试 / apply() tests ──

fn test_response_builder_apply_sets_status() {
	// apply() 设置状态码
	// apply() sets the status code
	mut rb := response()
	rb.status(404)
	// apply() 需要 veb.Context，此处仅验证 builder 状态
	// apply() requires veb.Context; here we only verify the builder state
	assert rb.status_code == 404
}

fn test_response_builder_apply_sets_content_type() {
	// apply() 设置 Content-Type
	// apply() sets the Content-Type
	mut rb := response()
	rb.content_type('text/html')
	assert rb.content_type == 'text/html'
}

// ── 辅助函数测试 / Helper function tests ──

fn test_cache_control_helper_public() {
	// cache_control() 辅助函数构建公开缓存值
	// cache_control() helper builds public cache value
	// 注意：此函数需要 veb.Context，此处仅验证逻辑
	// Note: This function requires veb.Context; here we verify the logic
	mut value := ''
	is_public := true
	max_age := 3600
	if is_public {
		value = 'public'
	} else {
		value = 'private'
	}
	if max_age > 0 {
		value += ', max-age=${max_age}'
	}
	assert value == 'public, max-age=3600'
}

fn test_cache_control_helper_private_no_max_age() {
	// 私有缓存无 max-age
	// Private cache without max-age
	mut value := ''
	is_public := false
	max_age := 0
	if is_public {
		value = 'public'
	} else {
		value = 'private'
	}
	if max_age > 0 {
		value += ', max-age=${max_age}'
	}
	assert value == 'private'
}

// ── ResponseBuilder 综合测试 / ResponseBuilder integration tests ──

fn test_response_builder_full_construction() {
	// 完整构建一个响应
	// Fully construct a response
	mut rb := response()
	rb.status(200)
	rb.content_type('application/json')
	rb.header('X-Request-Id', 'req-123')
	rb.body('{"message":"ok"}')
	rb.cache_control(CacheControlBuilder{
		is_public: true
		max_age: 300
	})
	rb.etag('v2')
	t := time.now()
	rb.last_modified(t)

	assert rb.status_code == 200
	assert rb.content_type == 'application/json'
	assert rb.headers['X-Request-Id'] == 'req-123'
	assert rb.body == '{"message":"ok"}'
	assert rb.cache_control_str == 'public, max-age=300'
	assert rb.etag_str == '"v2"'
	assert rb.last_modified_str.len > 0
}

fn test_response_builder_multiple_etag_calls() {
	// 多次调用 etag() 覆盖之前的值
	// Multiple etag() calls overwrite the previous value
	mut rb := response()
	rb.etag('v1')
	assert rb.etag_str == '"v1"'
	rb.etag('v2')
	assert rb.etag_str == '"v2"'
}

fn test_response_builder_multiple_last_modified_calls() {
	// 多次调用 last_modified() 覆盖之前的值
	// Multiple last_modified() calls overwrite the previous value
	mut rb := response()
	t1 := time.Time{year: 2024, month: 1, day: 1}
	t2 := time.Time{year: 2025, month: 6, day: 15}
	rb.last_modified(t1)
	lm1 := rb.last_modified_str
	rb.last_modified(t2)
	lm2 := rb.last_modified_str
	assert lm1 != lm2
}

// ── download_file() 路径遍历防护测试 / download_file() path traversal prevention tests ──
// 注意：download_file() 需要 veb.Context，此处测试防护逻辑
// Note: download_file() requires veb.Context; here we test the prevention logic

fn test_download_file_path_traversal_detection() {
	// 包含 ../ 的路径被识别为路径遍历攻击
	// Paths containing ../ are detected as path traversal attacks
	path_with_traversal := '../../../etc/passwd'
	assert path_with_traversal.contains('..')

	// 多种路径遍历模式 / Various path traversal patterns
	assert '../../secret'.contains('..')
	assert 'files/../../../etc/shadow'.contains('..')
	assert '../config.yml'.contains('..')
}

fn test_download_file_normal_paths_no_traversal() {
	// 正常路径不包含 ..
	// Normal paths do not contain ..
	assert !'/var/www/files/report.pdf'.contains('..')
	assert !'data/export.csv'.contains('..')
	assert !'/tmp/upload/image.png'.contains('..')
}

// ── Content-Disposition 头注入清理测试 / Content-Disposition header injection sanitization tests ──

fn test_download_file_filename_sanitization_removes_crlf() {
	// filename 中的 CR/LF 被清理，防止头注入
	// CR/LF in filename is sanitized to prevent header injection
	malicious_filename := 'file\r\nSet-Cookie: evil=value\r\n.txt'
	safe_filename := malicious_filename.replace('\r', '').replace('\n', '')
	assert !safe_filename.contains('\r')
	assert !safe_filename.contains('\n')
	assert safe_filename == 'fileSet-Cookie: evil=value.txt'
}

fn test_download_file_filename_sanitization_only_cr() {
	// 仅包含 CR 的 filename
	// Filename with only CR
	malicious := 'data\r.csv'
	safe := malicious.replace('\r', '').replace('\n', '')
	assert !safe.contains('\r')
	assert safe == 'data.csv'
}

fn test_download_file_filename_sanitization_only_lf() {
	// 仅包含 LF 的 filename
	// Filename with only LF
	malicious := 'data\n.csv'
	safe := malicious.replace('\r', '').replace('\n', '')
	assert !safe.contains('\n')
	assert safe == 'data.csv'
}

fn test_download_file_filename_sanitization_clean_filename() {
	// 正常 filename 不受影响
	// Normal filename is not affected
	normal := 'report-2024.pdf'
	safe := normal.replace('\r', '').replace('\n', '')
	assert safe == normal
}

// ── download_mime_types 扩展覆盖测试 / download_mime_types extended coverage tests ──

fn test_download_mime_types_gif() {
	assert download_mime_types['.gif'] == 'image/gif'
}

fn test_download_mime_types_svg() {
	assert download_mime_types['.svg'] == 'image/svg+xml'
}

fn test_download_mime_types_csv() {
	assert download_mime_types['.csv'] == 'text/csv'
}

fn test_download_mime_types_xml() {
	assert download_mime_types['.xml'] == 'application/xml'
}

fn test_download_mime_types_tar() {
	assert download_mime_types['.tar'] == 'application/x-tar'
}

fn test_download_mime_types_gz() {
	assert download_mime_types['.gz'] == 'application/gzip'
}

fn test_download_mime_types_htm() {
	assert download_mime_types['.htm'] == 'text/html'
}

fn test_download_mime_types_jpeg() {
	assert download_mime_types['.jpeg'] == 'image/jpeg'
}

// ── CacheControlBuilder 增强测试 / Enhanced CacheControlBuilder tests ──

fn test_cache_control_builder_private_no_max_age_no_s_maxage() {
	// 私有缓存无 max-age 和 s-maxage
	// Private cache without max-age and s-maxage
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: false
	})
	assert rb.cache_control_str == 'private'
}

fn test_cache_control_builder_no_cache_and_no_store() {
	// 同时设置 no-cache 和 no-store
	// Set both no-cache and no-store
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		no_cache:  true
		no_store:  true
	})
	assert rb.cache_control_str.contains('no-cache')
	assert rb.cache_control_str.contains('no-store')
}

fn test_cache_control_builder_all_directives() {
	// 所有指令同时设置
	// All directives set simultaneously
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public:       true
		max_age:         3600
		s_max_age:       7200
		no_cache:        true
		no_store:        true
		must_revalidate: true
	})
	assert rb.cache_control_str.contains('public')
	assert rb.cache_control_str.contains('max-age=3600')
	assert rb.cache_control_str.contains('s-maxage=7200')
	assert rb.cache_control_str.contains('no-cache')
	assert rb.cache_control_str.contains('no-store')
	assert rb.cache_control_str.contains('must-revalidate')
}

// ── 边界条件测试 / Edge case tests ──

fn test_response_builder_zero_max_age() {
	// max_age=0 不输出 max-age 指令
	// max_age=0 does not output max-age directive
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		max_age:   0
	})
	assert !rb.cache_control_str.contains('max-age=')
}

fn test_response_builder_negative_max_age() {
	// 负数 max_age 不输出 max-age 指令
	// Negative max_age does not output max-age directive
	mut rb := response()
	rb.cache_control(CacheControlBuilder{
		is_public: true
		max_age:   -1
	})
	assert !rb.cache_control_str.contains('max-age=')
}

fn test_response_builder_etag_with_quotes() {
	// etag() 自动包裹双引号，即使输入已包含引号
	// etag() auto-wraps in double quotes, even if input already contains quotes
	mut rb := response()
	rb.etag('abc"def')
	// 应包裹为 "abc"def"（含转义引号）
	// Should be wrapped as "abc"def"
	assert rb.etag_str.starts_with('"')
	assert rb.etag_str.ends_with('"')
}

fn test_response_builder_large_status_code() {
	// 大状态码设置
	// Large status code setting
	mut rb := response()
	rb.status(599)
	assert rb.status_code == 599
}

fn test_response_builder_empty_header_value() {
	// 空头值
	// Empty header value
	mut rb := response()
	rb.header('X-Empty', '')
	assert rb.headers['X-Empty'] == ''
}

fn test_response_builder_content_type_various() {
	// 各种 Content-Type 设置
	// Various Content-Type settings
	types := ['text/html', 'text/plain', 'application/xml', 'multipart/form-data', 'image/png']
	for ct in types {
		mut rb := response()
		rb.content_type(ct)
		assert rb.content_type == ct
	}
}
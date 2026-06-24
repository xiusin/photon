module web

// result.v - Unified Response Wrapper
//
// Provides a standardized API response format with status codes,
// messages, data payloads, and pagination support.
// Designed for consistent REST API responses.
import json
import time

// Result is the standard API response wrapper
pub struct Result {
pub mut:
	success   bool
	code      int
	message   string
	data      string // JSON string or raw value
	timestamp i64
	path      string
}

// PageResult adds pagination to Result
// Note: fields are flattened (not embedded) to work around a V 0.5.x codegen
// bug in JSON decoder for structs with embedded sub-structs.
pub struct PageResult {
	Result
pub:
	pagination Pagination
}

// Pagination holds page metadata
pub struct Pagination {
pub:
	page        int
	page_size   int
	total       int
	total_pages int
	has_next    bool
	has_prev    bool
}

// success creates a successful Result
pub fn success(data string) Result {
	return Result{
		success:   true
		code:      200
		message:   'OK'
		data:      data
		timestamp: time.now().unix()
	}
}

// success_with_msg creates a successful Result with custom message
pub fn success_with_msg(data string, msg string) Result {
	return Result{
		success:   true
		code:      200
		message:   msg
		data:      data
		timestamp: time.now().unix()
	}
}

// fail creates a failure Result
pub fn fail(code int, msg string) Result {
	return Result{
		success:   false
		code:      code
		message:   msg
		timestamp: time.now().unix()
	}
}

// page creates a paginated Result
pub fn page(data string, page int, page_size int, total int) PageResult {
	// Guard against division by zero — treat page_size == 0 as 1
	safe_page_size := if page_size <= 0 { 1 } else { page_size }
	total_pages := (total + safe_page_size - 1) / safe_page_size
	return PageResult{
		Result:     success(data)
		pagination: Pagination{
			page:        page
			page_size:   safe_page_size
			total:       total
			total_pages: total_pages
			has_next:    page < total_pages
			has_prev:    page > 1
		}
	}
}

// to_json serializes the Result to JSON
pub fn (r &Result) to_json() string {
	return json.encode(r)
}

// to_json serializes the PageResult (including pagination) to JSON
// 注：手动构建 JSON 而非 json.encode，因 V 编译器对嵌入 struct + pub mut 字段
// 的 json.encode 会生成无效 C 代码（struct or union expected）
pub fn (r &PageResult) to_json() string {
	p := r.pagination
	return '{"success":${r.success},"code":${r.code},"message":${json.encode(r.message)},"data":${r.data},"timestamp":${r.timestamp},"path":${json.encode(r.path)},"pagination":{"page":${p.page},"page_size":${p.page_size},"total":${p.total},"total_pages":${p.total_pages},"has_next":${p.has_next},"has_prev":${p.has_prev}}}'
}

// -- Convenience builders --

// ok creates a 200 OK result
pub fn ok(data string) Result {
	return success(data)
}

// created creates a 201 Created result
pub fn created(data string) Result {
	return Result{
		success:   true
		code:      201
		message:   'Created'
		data:      data
		timestamp: time.now().unix()
	}
}

// no_content creates a 204 No Content result
pub fn no_content() Result {
	return Result{
		success:   true
		code:      204
		message:   'No Content'
		timestamp: time.now().unix()
	}
}

// bad_request creates a 400 Bad Request result
pub fn bad_request(msg string) Result {
	return fail(400, msg)
}

// not_found creates a 404 Not Found result
pub fn not_found(msg string) Result {
	return fail(404, msg)
}

// internal_error creates a 500 Internal Server Error result
pub fn internal_error(msg string) Result {
	return fail(500, msg)
}

// unauthorized creates a 401 Unauthorized result
pub fn unauthorized(msg string) Result {
	return fail(401, msg)
}

// forbidden creates a 403 Forbidden result
pub fn forbidden(msg string) Result {
	return fail(403, msg)
}

// conflict creates a 409 Conflict result
pub fn conflict(msg string) Result {
	return fail(409, msg)
}

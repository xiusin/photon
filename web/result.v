module web

// result.v - Unified Response Wrapper
//
// Provides a standardized API response format with status codes,
// messages, data payloads, and pagination support.
// Designed for consistent REST API responses.

import json

// Result is the standard API response wrapper
pub struct Result {
pub mut:
	success bool
	code    int
	message string
	data    string // JSON string or raw value
	timestamp i64
	path    string
}

// PageResult adds pagination to Result
pub struct PageResult {
	Result
pub mut:
	pagination Pagination
}

// Pagination holds page metadata
pub struct Pagination {
pub:
	page       int
	page_size  int
	total      int
	total_pages int
	has_next   bool
	has_prev   bool
}

// success creates a successful Result
pub fn success(data string) Result {
	return Result{
		success: true
		code: 200
		message: 'OK'
		data: data
	}
}

// success_with_msg creates a successful Result with custom message
pub fn success_with_msg(data string, msg string) Result {
	return Result{
		success: true
		code: 200
		message: msg
		data: data
	}
}

// fail creates a failure Result
pub fn fail(code int, msg string) Result {
	return Result{
		success: false
		code: code
		message: msg
	}
}

// page creates a paginated Result
pub fn page(data string, page int, page_size int, total int) PageResult {
	total_pages := (total + page_size - 1) / page_size
	return PageResult{
		Result: success(data)
		pagination: Pagination{
			page: page
			page_size: page_size
			total: total
			total_pages: total_pages
			has_next: page < total_pages
			has_prev: page > 1
		}
	}
}

// to_json serializes the Result to JSON
pub fn (r &Result) to_json() string {
	return json.encode(r)
}

// -- Convenience builders --

// ok creates a 200 OK result
pub fn ok(data string) Result {
	return success(data)
}

// created creates a 201 Created result
pub fn created(data string) Result {
	return Result{
		success: true
		code: 201
		message: 'Created'
		data: data
	}
}

// no_content creates a 204 No Content result
pub fn no_content() Result {
	return Result{
		success: true
		code: 204
		message: 'No Content'
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

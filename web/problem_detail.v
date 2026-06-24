module web

// problem_detail.v - ProblemDetail (RFC 7807 / RFC 9457)
//
// Provides a standardized error response format following RFC 7807
// (Problem Details for HTTP APIs). This is the modern best practice
// for HTTP API error responses, adopted by Spring Framework 6
// (ProblemDetail) and recommended for all REST APIs.
//
// ── RFC 7807 Fields ──
//
//   type     (string)  — URI reference identifying the problem type
//   title    (string)  — short, human-readable summary
//   status   (int)     — HTTP status code
//   detail   (string)  — human-readable explanation specific to this occurrence
//   instance(string)  — URI reference identifying the specific occurrence
//
// ── Extended Fields (RFC 9457) ──
//
//   errors   ([]FieldError) — validation errors with field-level detail
//
// ── Usage ──
//
//   // In exception handler:
//   detail := web.new_problem_detail(404, 'User Not Found')
//       .set_type('https://example.com/errors/user-not-found')
//       .set_detail('User with ID 42 does not exist')
//       .set_instance('/api/users/42')
//   return detail.to_result(mut ctx)
//
//   // With validation errors:
//   detail := web.new_problem_detail(422, 'Validation Failed')
//       .add_error('email', 'must be a valid email address')
//       .add_error('password', 'must be at least 8 characters')
//   return detail.to_result(mut ctx)
//
// Spring equivalent: org.springframework.http.ProblemDetail

import veb
import json
import net.http

// ── ProblemDetail ──

// ProblemDetail represents an RFC 7807 problem detail response.
//
// All fields are optional except 'status' and 'title'. The 'type'
// field defaults to 'about:blank' if not set (per RFC 7807).
pub struct ProblemDetail {
pub mut:
	// ── RFC 7807 standard fields ──
	type_     string // 'type' is a reserved keyword in V, use 'type_'
	title     string
	status    int    = 500
	detail    string
	instance_ string // 'instance' may conflict, use 'instance_'

	// ── Extension members ──
	errors    []FieldError
}

// FieldError represents a single field-level validation error.
pub struct FieldError {
pub:
	field   string
	message string
}

// ── Factory Functions ──

// new_problem_detail creates a ProblemDetail with the given status and title.
// The 'type' field defaults to 'about:blank' (RFC 7807 default).
pub fn new_problem_detail(status int, title string) ProblemDetail {
	return ProblemDetail{
		type_:  'about:blank'
		title:  title
		status: status
		errors: []FieldError{}
	}
}

// problem_detail_not_found creates a 404 ProblemDetail.
pub fn problem_detail_not_found(title string) ProblemDetail {
	return new_problem_detail(404, title)
}

// problem_detail_bad_request creates a 400 ProblemDetail.
pub fn problem_detail_bad_request(title string) ProblemDetail {
	return new_problem_detail(400, title)
}

// problem_detail_validation creates a 422 ProblemDetail for validation errors.
pub fn problem_detail_validation(title string) ProblemDetail {
	return new_problem_detail(422, title)
}

// problem_detail_internal_error creates a 500 ProblemDetail.
pub fn problem_detail_internal_error(title string) ProblemDetail {
	return new_problem_detail(500, title)
}

// problem_detail_unauthorized creates a 401 ProblemDetail.
pub fn problem_detail_unauthorized(title string) ProblemDetail {
	return new_problem_detail(401, title)
}

// problem_detail_forbidden creates a 403 ProblemDetail.
pub fn problem_detail_forbidden(title string) ProblemDetail {
	return new_problem_detail(403, title)
}

// problem_detail_conflict creates a 409 ProblemDetail.
pub fn problem_detail_conflict(title string) ProblemDetail {
	return new_problem_detail(409, title)
}

// problem_detail_too_many_requests creates a 429 ProblemDetail.
pub fn problem_detail_too_many_requests(title string) ProblemDetail {
	return new_problem_detail(429, title)
}

// ── Builder Methods ──

// set_type sets the 'type' URI. Returns self for chaining.
pub fn (mut pd ProblemDetail) set_type(type_uri string) ProblemDetail {
	pd.type_ = type_uri
	return *pd
}

// set_title sets the 'title' field. Returns self for chaining.
pub fn (mut pd ProblemDetail) set_title(title string) ProblemDetail {
	pd.title = title
	return *pd
}

// set_status sets the HTTP status code. Returns self for chaining.
pub fn (mut pd ProblemDetail) set_status(status int) ProblemDetail {
	pd.status = status
	return *pd
}

// set_detail sets the 'detail' field. Returns self for chaining.
pub fn (mut pd ProblemDetail) set_detail(detail string) ProblemDetail {
	pd.detail = detail
	return *pd
}

// set_instance sets the 'instance' URI. Returns self for chaining.
pub fn (mut pd ProblemDetail) set_instance(instance string) ProblemDetail {
	pd.instance_ = instance
	return *pd
}

// add_error adds a field-level validation error. Returns self for chaining.
pub fn (mut pd ProblemDetail) add_error(field string, message string) ProblemDetail {
	pd.errors << FieldError{ field: field, message: message }
	return *pd
}

// add_errors adds multiple field-level validation errors. Returns self for chaining.
pub fn (mut pd ProblemDetail) add_errors(errors []FieldError) ProblemDetail {
	pd.errors << errors
	return *pd
}

// ── Conversion ──

// to_json serializes the ProblemDetail to a JSON string following
// RFC 7807 conventions. The 'type_' field is serialized as 'type'
// and 'instance_' as 'instance'.
pub fn (pd ProblemDetail) to_json() string {
	mut sb := '{"type":${json.encode(pd.type_)},"title":${json.encode(pd.title)},"status":${pd.status}'
	if pd.detail.len > 0 {
		sb += ',"detail":${json.encode(pd.detail)}'
	}
	if pd.instance_.len > 0 {
		sb += ',"instance":${json.encode(pd.instance_)}'
	}
	if pd.errors.len > 0 {
		sb += ',"errors":['
		for i, err in pd.errors {
			if i > 0 {
				sb += ','
			}
			sb += '{"field":${json.encode(err.field)},"message":${json.encode(err.message)}}'
		}
		sb += ']'
	}
	sb += '}'
	return sb
}

// to_result converts the ProblemDetail to a veb.Result with
// Content-Type: application/problem+json (RFC 7807 media type).
pub fn (pd ProblemDetail) to_result(mut ctx veb.Context) veb.Result {
	body := pd.to_json()
	ctx.res.set_status(unsafe { http.Status(pd.status) })
	ctx.set_content_type('application/problem+json')
	return ctx.text(body)
}

// ── HttpException to ProblemDetail Conversion ──

// from_http_exception converts an HttpException to a ProblemDetail.
// This provides a bridge between the existing exception system and
// the RFC 7807 format.
pub fn from_http_exception(e HttpException) ProblemDetail {
	mut pd := new_problem_detail(e.status_code, e.message)
	pd.set_detail(e.msg())
	if e.details.len > 0 {
		for key, value in e.details {
			pd.add_error(key, value)
		}
	}
	return pd
}

// ── ProblemDetail Exception Handler ──

// ProblemDetailHandler is a handler that converts exceptions to
// ProblemDetail responses. It can be registered with the
// ExceptionResolver for global handling.
pub struct ProblemDetailHandler {
pub:
	default_type string = 'about:blank'
}

pub fn new_problem_detail_handler() ProblemDetailHandler {
	return ProblemDetailHandler{}
}

// handle converts an IError to a ProblemDetail response.
pub fn (h ProblemDetailHandler) handle(err IError, status int) ProblemDetail {
	mut pd := new_problem_detail(status, err.msg())
	pd.set_detail(err.msg())
	return pd
}

// handle_http_exception converts an HttpException to a ProblemDetail.
pub fn (h ProblemDetailHandler) handle_http_exception(e HttpException) ProblemDetail {
	return from_http_exception(e)
}

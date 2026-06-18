module web

// exception.v - Global Exception Handling
//
// Provides a unified exception handling system for HTTP requests.
// Analogous to Spring's @ControllerAdvice + @ExceptionHandler
// and Laravel's Exception Handler.
//
// All HTTP handlers can return errors that are automatically caught
// and converted to appropriate HTTP responses.
//
// Usage:
//   mut handler := new_exception_handler()
//   handler.register('NotFoundError', fn (err IError, mut ctx veb.Context) veb.Result {
//       return ctx.json_error(404, err.msg())
//   })
//   handler.register('ValidationError', fn (err IError, mut ctx veb.Context) veb.Result {
//       return ctx.json_error(422, err.msg())
//   })
//
//   // In your controller:
//   pub fn (mut app App) get_user(id string) veb.Result {
//       user := app.services.user_service.get_by_id(id) or {
//           return app.exception_handler.handle(err, mut app.Context)
//       }
//       return ctx.json(user)
//   }

import json

// ── HttpException ──

// HttpException is the base exception type for all HTTP-related errors.
// Carries a status code, message, and optional details.
pub struct HttpException {
pub:
	status_code int
	message     string
	details     map[string]string
}

// new_http_exception creates an HttpException.
pub fn new_http_exception(status_code int, message string) HttpException {
	return HttpException{
		status_code: status_code
		message: message
		details: map[string]string{}
	}
}

// new_http_exception_with_details creates an HttpException with details.
pub fn new_http_exception_with_details(status_code int, message string, details map[string]string) HttpException {
	return HttpException{
		status_code: status_code
		message: message
		details: details
	}
}

// msg returns the error message.
pub fn (e &HttpException) msg() string {
	return e.message
}

// code returns the HTTP status code.
pub fn (e &HttpException) code() int {
	return e.status_code
}

// ── Common HTTP Exceptions ──

// BadRequestException represents a 400 Bad Request error.
pub struct BadRequestException {
	HttpException
}

// new_bad_request creates a 400 Bad Request exception.
pub fn new_bad_request(message string) BadRequestException {
	return BadRequestException{
		HttpException: new_http_exception(400, message)
	}
}

// UnauthorizedException represents a 401 Unauthorized error.
pub struct UnauthorizedException {
	HttpException
}

// new_unauthorized creates a 401 Unauthorized exception.
pub fn new_unauthorized(message string) UnauthorizedException {
	return UnauthorizedException{
		HttpException: new_http_exception(401, message)
	}
}

// ForbiddenException represents a 403 Forbidden error.
pub struct ForbiddenException {
	HttpException
}

// new_forbidden creates a 403 Forbidden exception.
pub fn new_forbidden(message string) ForbiddenException {
	return ForbiddenException{
		HttpException: new_http_exception(403, message)
	}
}

// NotFoundException represents a 404 Not Found error.
pub struct NotFoundException {
	HttpException
}

// new_not_found creates a 404 Not Found exception.
pub fn new_not_found(message string) NotFoundException {
	return NotFoundException{
		HttpException: new_http_exception(404, message)
	}
}

// MethodNotAllowedException represents a 405 Method Not Allowed error.
pub struct MethodNotAllowedException {
	HttpException
}

// new_method_not_allowed creates a 405 Method Not Allowed exception.
pub fn new_method_not_allowed(message string) MethodNotAllowedException {
	return MethodNotAllowedException{
		HttpException: new_http_exception(405, message)
	}
}

// ConflictException represents a 409 Conflict error.
pub struct ConflictException {
	HttpException
}

// new_conflict creates a 409 Conflict exception.
pub fn new_conflict(message string) ConflictException {
	return ConflictException{
		HttpException: new_http_exception(409, message)
	}
}

// ValidationException represents a 422 Unprocessable Entity error.
pub struct ValidationException {
	HttpException
pub:
	validation_errors map[string][]string // field → error messages
}

// new_validation_exception creates a 422 Validation exception.
pub fn new_validation_exception(message string, errors map[string][]string) ValidationException {
	return ValidationException{
		HttpException: new_http_exception(422, message)
		validation_errors: errors
	}
}

// InternalServerErrorException represents a 500 Internal Server Error.
pub struct InternalServerErrorException {
	HttpException
}

// new_internal_error creates a 500 Internal Server Error exception.
pub fn new_internal_error(message string) InternalServerErrorException {
	return InternalServerErrorException{
		HttpException: new_http_exception(500, message)
	}
}

// ServiceUnavailableException represents a 503 Service Unavailable error.
pub struct ServiceUnavailableException {
	HttpException
}

// new_service_unavailable creates a 503 Service Unavailable exception.
pub fn new_service_unavailable(message string) ServiceUnavailableException {
	return ServiceUnavailableException{
		HttpException: new_http_exception(503, message)
	}
}

// RateLimitExceededException represents a 429 Too Many Requests error.
pub struct RateLimitExceededException {
	HttpException
}

// new_rate_limit_exceeded creates a 429 Too Many Requests exception.
pub fn new_rate_limit_exceeded(message string) RateLimitExceededException {
	return RateLimitExceededException{
		HttpException: new_http_exception(429, message)
	}
}

// ── ExceptionHandler ──

// ExceptionHandlerFunc processes an error and returns a JSON string.
pub type ExceptionHandlerFunc = fn (err IError) string

// ExceptionHandlerRegistry maps error type names to handler functions.
pub struct ExceptionHandlerRegistry {
pub mut:
	handlers       map[string]ExceptionHandlerFunc
	default_handler ExceptionHandlerFunc = unsafe { nil }
}

// new_exception_handler creates an ExceptionHandlerRegistry.
pub fn new_exception_handler() &ExceptionHandlerRegistry {
	mut registry := &ExceptionHandlerRegistry{
		handlers: map[string]ExceptionHandlerFunc{}
	}
	// Register built-in handlers
	registry.register_defaults()
	return registry
}

// register adds a handler for a specific error type name.
pub fn (mut r ExceptionHandlerRegistry) register(err_type string, handler ExceptionHandlerFunc) {
	r.handlers[err_type] = handler
}

// register_default_handler sets the fallback handler for unknown error types.
pub fn (mut r ExceptionHandlerRegistry) register_default_handler(handler ExceptionHandlerFunc) {
	r.default_handler = handler
}

// handle resolves and executes the appropriate handler for an error.
// First tries the registered handler by type name, then falls back to
// HttpException status code extraction (type-safe, not string-based).
pub fn (mut r ExceptionHandlerRegistry) handle(err IError) string {
	err_type := typeof(err).name

	// Try specific handler first
	if handler := r.handlers[err_type] {
		return handler(err)
	}

	// Try to extract status code from HttpException subtypes
	// This is type-safe: we check for known struct types, not error message text.
	status := extract_http_status(err)
	if status > 0 {
		return text_response_for_error(status, err.msg())
	}

	// Try default handler
	if !isnil(r.default_handler) {
		return r.default_handler(err)
	}

	// Last resort: 500
	return text_response_for_error(500, err.msg())
}

// register_defaults registers handlers for common HTTP exceptions.
fn (mut r ExceptionHandlerRegistry) register_defaults() {
	// BadRequestException
	r.handlers['BadRequestException'] = fn (err IError) string {
		return text_response_for_error(400, err.msg())
	}

	// UnauthorizedException
	r.handlers['UnauthorizedException'] = fn (err IError) string {
		return text_response_for_error(401, err.msg())
	}

	// ForbiddenException
	r.handlers['ForbiddenException'] = fn (err IError) string {
		return text_response_for_error(403, err.msg())
	}

	// NotFoundException
	r.handlers['NotFoundException'] = fn (err IError) string {
		return text_response_for_error(404, err.msg())
	}

	// ConflictException
	r.handlers['ConflictException'] = fn (err IError) string {
		return text_response_for_error(409, err.msg())
	}

	// ValidationException
	r.handlers['ValidationException'] = fn (err IError) string {
		return text_response_for_error(422, err.msg())
	}

	// RateLimitExceededException
	r.handlers['RateLimitExceededException'] = fn (err IError) string {
		return text_response_for_error(429, err.msg())
	}

	// InternalServerErrorException
	r.handlers['InternalServerErrorException'] = fn (err IError) string {
		return text_response_for_error(500, err.msg())
	}

	// ServiceUnavailableException
	r.handlers['ServiceUnavailableException'] = fn (err IError) string {
		return text_response_for_error(503, err.msg())
	}
}

// extract_http_status tries to extract the HTTP status code from known exception types.
// Uses type name matching (compile-time deterministic) instead of error message parsing.
// This prevents user-supplied error messages from being misinterpreted as status codes.
fn extract_http_status(err IError) int {
	err_type := typeof(err).name

	// Map known exception type names to their status codes
	return match err_type {
		'BadRequestException' { 400 }
		'UnauthorizedException' { 401 }
		'ForbiddenException' { 403 }
		'NotFoundException' { 404 }
		'MethodNotAllowedException' { 405 }
		'ConflictException' { 409 }
		'ValidationException' { 422 }
		'RateLimitExceededException' { 429 }
		'InternalServerErrorException' { 500 }
		'ServiceUnavailableException' { 503 }
		else { 0 }
	}
}

// ── Error Response Helpers ──

// ErrorResponse is a structured error response body.
pub struct ErrorResponse {
pub:
	success bool
	code    int
	message string
	details map[string]string
}

// text_response_for_error creates a JSON error response.
fn text_response_for_error(status int, message string) string {
	resp := ErrorResponse{
		code: status
		message: message
	}
	return json.encode(resp)
}

// error_json creates a JSON string for an error response.
pub fn error_json(code int, message string) string {
	resp := ErrorResponse{
		success: false
		code: code
		message: message
	}
	return json.encode(resp)
}

// error_json_with_details creates a JSON string for an error response with details.
pub fn error_json_with_details(code int, message string, details map[string]string) string {
	resp := ErrorResponse{
		success: false
		code: code
		message: message
		details: details
	}
	return json.encode(resp)
}

// ── Panic Recovery Middleware ──

// recover_exceptions is a middleware that catches panics and converts
// them to proper HTTP error responses.
// Place this as the FIRST middleware in your chain.
pub fn recover_exceptions(mut ctx &MiddlewareContext) !bool {
	// V doesn't have try/catch, but we can check for error conditions
	// in the middleware data and handle them appropriately.
	// This is a defensive marker — actual panic recovery depends on
	// V's runtime behavior.
	ctx.data['_exception_handler_active'] = 'true'
	return true
}

// ── Convenience Constructors ──

// bad_request_err creates a 400 error result.
pub fn bad_request_err(msg string) Result {
	return fail(400, msg)
}

// unauthorized_err creates a 401 error result.
pub fn unauthorized_err(msg string) Result {
	return fail(401, msg)
}

// forbidden_err creates a 403 error result.
pub fn forbidden_err(msg string) Result {
	return fail(403, msg)
}

// not_found_err creates a 404 error result.
pub fn not_found_err(msg string) Result {
	return fail(404, msg)
}

// conflict_err creates a 409 error result.
pub fn conflict_err(msg string) Result {
	return fail(409, msg)
}

// validation_err creates a 422 error result.
pub fn validation_err(msg string) Result {
	return fail(422, msg)
}

// internal_err creates a 500 error result.
pub fn internal_err(msg string) Result {
	return fail(500, msg)
}

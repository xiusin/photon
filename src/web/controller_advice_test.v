module web

// controller_advice_test.v - Tests for @ControllerAdvice global exception handling
//
// Verifies the ExceptionResolver registry:
//   - Custom error types and controller advice structs implementing ExceptionHandler
//   - Specific handler registration and dispatch
//   - Global catch-all handler
//   - Specific handler takes priority over global
//   - Default status mapping via err.code() (extract_status)
//   - Last-resort 500 fallback for unknown errors
import json

// ── Custom error type ──

// CustomBusinessError is a domain-specific error used to exercise the resolver.
// It implements IError (msg + code) so it can flow through the exception system.
struct CustomBusinessError {
pub:
	msg   string
	code_ int
}

fn (e &CustomBusinessError) msg() string {
	return e.msg
}

fn (e &CustomBusinessError) code() int {
	return e.code_
}

// ── Controller advice implementations ──

// @[controller_advice] marks this struct as a global exception advice.
// It implements ExceptionHandler to handle CustomBusinessError instances.
@[controller_advice]
struct BusinessErrorHandler {}

fn (h &BusinessErrorHandler) handles(err IError) bool {
	return err is CustomBusinessError
}

fn (h &BusinessErrorHandler) handle_exception(err IError) !(int, string) {
	return 418, '{"error":"business_error","detail":"${err.msg()}"}'
}

// @[controller_advice] global catch-all handler.
@[controller_advice]
struct GlobalCatchAllHandler {}

fn (h &GlobalCatchAllHandler) handles(err IError) bool {
	return true
}

fn (h &GlobalCatchAllHandler) handle_exception(err IError) !(int, string) {
	return 500, '{"error":"global_handler","detail":"${err.msg()}"}'
}

// A handler scoped to NotFoundException specifically.
struct NotFoundAdvice {}

fn (h &NotFoundAdvice) handles(err IError) bool {
	return err is NotFoundException
}

fn (h &NotFoundAdvice) handle_exception(err IError) !(int, string) {
	return 404, '{"error":"not_found_advice","detail":"${err.msg()}"}'
}

// ── Tests ──

// Default status mapping: a NotFoundException resolves to 404 via err.code().
fn test_resolver_default_status_not_found() {
	mut resolver := new_exception_resolver()
	err := IError(&NotFoundException{
		HttpException: new_http_exception(404, 'user not found')
	})
	status, body := resolver.resolve(err)!
	assert status == 404
	assert body.contains('user not found')
}

// Default status mapping for BadRequestException -> 400.
fn test_resolver_default_status_bad_request() {
	mut resolver := new_exception_resolver()
	err := IError(&BadRequestException{
		HttpException: new_http_exception(400, 'invalid input')
	})
	status, body := resolver.resolve(err)!
	assert status == 400
	assert body.contains('invalid input')
}

// A specific handler registered for a custom error type is invoked and returns
// the expected status/body.
fn test_resolver_custom_specific_handler() {
	mut resolver := new_exception_resolver()
	err := IError(&CustomBusinessError{
		msg:   'inventory depleted'
		code_: 0
	})
	resolver.register_handler('CustomBusinessError', &BusinessErrorHandler{})
	status, body := resolver.resolve(err)!
	assert status == 418
	assert body.contains('business_error')
	assert body.contains('inventory depleted')
}

// A global catch-all handler handles errors with no specific handler.
fn test_resolver_global_catch_all() {
	mut resolver := new_exception_resolver()
	resolver.register_global(&GlobalCatchAllHandler{})
	err := IError(&CustomBusinessError{
		msg:   'unexpected failure'
		code_: 0
	})
	status, body := resolver.resolve(err)!
	assert status == 500
	assert body.contains('global_handler')
	assert body.contains('unexpected failure')
}

// A specific handler takes priority over a registered global handler.
fn test_resolver_specific_overrides_global() {
	mut resolver := new_exception_resolver()
	resolver.register_global(&GlobalCatchAllHandler{})
	err := IError(&CustomBusinessError{
		msg:   'priority check'
		code_: 0
	})
	resolver.register_handler('CustomBusinessError', &BusinessErrorHandler{})
	status, body := resolver.resolve(err)!
	assert status == 418
	assert body.contains('business_error')
	assert body.contains('priority check')
}

// A specific handler for NotFoundException overrides the default status mapping.
fn test_resolver_specific_overrides_default_status() {
	mut resolver := new_exception_resolver()
	resolver.register_handler('NotFoundException', &NotFoundAdvice{})
	err := IError(&NotFoundException{
		HttpException: new_http_exception(404, 'missing resource')
	})
	status, body := resolver.resolve(err)!
	assert status == 404
	assert body.contains('not_found_advice')
	assert body.contains('missing resource')
}

// extract_status returns the status code carried by HttpException subtypes.
fn test_resolver_extract_status_known_type() {
	mut resolver := new_exception_resolver()
	err := IError(&BadRequestException{
		HttpException: new_http_exception(400, 'bad input')
	})
	assert resolver.extract_status(err) == 400
}

// extract_status returns 0 for errors that do not carry an HTTP status.
fn test_resolver_extract_status_unknown_type() {
	mut resolver := new_exception_resolver()
	err := IError(&CustomBusinessError{
		msg:   'unknown'
		code_: 0
	})
	assert resolver.extract_status(err) == 0
}

// An unknown error with no handlers and no status falls back to 500.
fn test_resolver_unknown_error_falls_back_to_500() {
	mut resolver := new_exception_resolver()
	err := IError(&CustomBusinessError{
		msg:   'no handler'
		code_: 0
	})
	status, body := resolver.resolve(err)!
	assert status == 500
	assert body.contains('no handler')
}

// A custom error that carries its own status code (via code()) is resolved to
// that status through the default mapping, without a registered handler.
fn test_resolver_custom_error_with_code() {
	mut resolver := new_exception_resolver()
	err := IError(&CustomBusinessError{
		msg:   'teapot'
		code_: 418
	})
	status, body := resolver.resolve(err)!
	assert status == 418
	assert body.contains('teapot')
}

// The structured ErrorResponse body is valid JSON with the expected fields.
fn test_resolver_response_body_is_valid_json() {
	mut resolver := new_exception_resolver()
	err := IError(&NotFoundException{
		HttpException: new_http_exception(404, 'gone')
	})
	_, body := resolver.resolve(err)!
	parsed := json.decode(ErrorResponse, body) or {
		assert false, 'body should be valid JSON ErrorResponse'
		return
	}
	assert parsed.code == 404
	assert parsed.message == 'gone'
}

module support

fn test_error_code_str() {
	assert ErrorCode.err_security.str() == 'security'
	assert ErrorCode.err_cache_miss.str() == 'cache_miss'
	assert ErrorCode.err_tx_not_active.str() == 'tx_not_active'
	assert ErrorCode.err_conversion_failed.str() == 'conversion_failed'
	assert ErrorCode.err_resource_not_found.str() == 'resource_not_found'
	assert ErrorCode.err_invalid_argument.str() == 'invalid_argument'
	assert ErrorCode.err_not_implemented.str() == 'not_implemented'
	assert ErrorCode.err_unauthorized.str() == 'unauthorized'
	assert ErrorCode.err_forbidden.str() == 'forbidden'
	assert ErrorCode.err_not_found.str() == 'not_found'
	assert ErrorCode.err_internal.str() == 'internal'
}

fn test_photon_error_creation() {
	e := new_photon_error(.err_security, 'authentication failed')
	assert e.code == .err_security
	assert e.message == 'authentication failed'
	assert e.cause == ''
}

fn test_photon_error_with_cause() {
	e := new_photon_error_with_cause(.err_internal, 'db connection failed', 'timeout')
	assert e.code == .err_internal
	assert e.message == 'db connection failed'
	assert e.cause == 'timeout'
}

fn test_photon_error_str_without_cause() {
	e := new_photon_error(.err_security, 'auth failed')
	assert e.str() == '[security] auth failed'
}

fn test_photon_error_str_with_cause() {
	e := new_photon_error_with_cause(.err_internal, 'db error', 'timeout')
	assert e.str() == '[internal] db error (cause: timeout)'
}

fn test_photon_error_msg_method() {
	e := new_photon_error(.err_security, 'auth failed')
	assert e.msg() == '[security] auth failed'
}

fn test_err_security_error_helper() {
	e := err_security_error('token expired')
	assert e.code == .err_security
	assert e.message == 'token expired'
}

fn test_err_cache_miss_error_helper() {
	e := err_cache_miss_error('user:123')
	assert e.code == .err_cache_miss
	assert e.message == 'cache miss: key "user:123" not found'
}

fn test_err_tx_not_active_error_helper() {
	e := err_tx_not_active_error()
	assert e.code == .err_tx_not_active
	assert e.message == 'no active transaction'
}

fn test_err_conversion_failed_error_helper() {
	e := err_conversion_failed_error('abc', 'int')
	assert e.code == .err_conversion_failed
	assert e.message == 'cannot convert "abc" to int'
}

fn test_err_resource_not_found_error_helper() {
	e := err_resource_not_found_error('/static/app.css')
	assert e.code == .err_resource_not_found
	assert e.message == 'resource not found: /static/app.css'
}

fn test_err_invalid_argument_error_helper() {
	e := err_invalid_argument_error('name must not be empty')
	assert e.code == .err_invalid_argument
	assert e.message == 'name must not be empty'
}

fn test_err_not_implemented_error_helper() {
	e := err_not_implemented_error('websocket')
	assert e.code == .err_not_implemented
	assert e.message == 'websocket not implemented'
}

fn test_photon_error_propagation() {
	f := fn () ! {
		return IError(new_photon_error(.err_security, 'test error'))
	}

	mut failed := false
	mut error_msg := ''
	f() or {
		failed = true
		error_msg = err.msg()
	}
	assert failed
	assert error_msg == '[security] test error'
}

fn test_all_error_codes_have_str() {
	codes := [
		ErrorCode.err_security,
		ErrorCode.err_cache_miss,
		ErrorCode.err_cache_set,
		ErrorCode.err_tx_not_active,
		ErrorCode.err_tx_already_active,
		ErrorCode.err_conversion_failed,
		ErrorCode.err_resource_not_found,
		ErrorCode.err_invalid_argument,
		ErrorCode.err_not_implemented,
		ErrorCode.err_unauthorized,
		ErrorCode.err_forbidden,
		ErrorCode.err_not_found,
		ErrorCode.err_internal,
	]
	for code in codes {
		assert code.str().len > 0
	}
}

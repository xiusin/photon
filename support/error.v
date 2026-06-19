module support

// error.v - Photon Domain Error Types
//
// Provides structured error types with error codes for consistent error handling
// across all Photon modules. Replaces ad-hoc error(string) usage with typed errors.

// ErrorCode enumerates standard Photon error categories.
pub enum ErrorCode {
	err_security           // security-related error (auth, crypto, etc.)
	err_cache_miss         // cache key not found
	err_cache_set          // cache set operation failed
	err_tx_not_active      // no active transaction
	err_tx_already_active  // transaction already in progress
	err_conversion_failed  // type conversion failed
	err_resource_not_found // static resource or file not found
	err_invalid_argument   // invalid argument provided
	err_not_implemented    // feature not implemented
	err_unauthorized       // authentication required
	err_forbidden          // access denied
	err_not_found          // generic not found
	err_internal           // internal server error
}

// str returns the string representation of an ErrorCode.
pub fn (c ErrorCode) str() string {
	return match c {
		.err_security { 'security' }
		.err_cache_miss { 'cache_miss' }
		.err_cache_set { 'cache_set' }
		.err_tx_not_active { 'tx_not_active' }
		.err_tx_already_active { 'tx_already_active' }
		.err_conversion_failed { 'conversion_failed' }
		.err_resource_not_found { 'resource_not_found' }
		.err_invalid_argument { 'invalid_argument' }
		.err_not_implemented { 'not_implemented' }
		.err_unauthorized { 'unauthorized' }
		.err_forbidden { 'forbidden' }
		.err_not_found { 'not_found' }
		.err_internal { 'internal' }
	}
}

// PhotonError is the structured error type carrying an error code, message, and optional cause.
pub struct PhotonError {
pub:
	code    ErrorCode
	message string
	cause   string
}

// str returns a formatted error string: "[code] message (cause)".
pub fn (e PhotonError) str() string {
	if e.cause.len > 0 {
		return '[${e.code.str()}] ${e.message} (cause: ${e.cause})'
	}
	return '[${e.code.str()}] ${e.message}'
}

// msg implements the IError interface so PhotonError can be propagated via `return IError(...)`.
pub fn (e PhotonError) msg() string {
	return e.str()
}

// code implements the IError interface, returning the numeric value of the ErrorCode.
pub fn (e PhotonError) code() int {
	return int(e.code)
}

// new_photon_error creates a PhotonError with code and message.
pub fn new_photon_error(code ErrorCode, message string) PhotonError {
	return PhotonError{
		code:    code
		message: message
	}
}

// new_photon_error_with_cause creates a PhotonError with code, message, and cause.
pub fn new_photon_error_with_cause(code ErrorCode, message string, cause string) PhotonError {
	return PhotonError{
		code:    code
		message: message
		cause:   cause
	}
}

// err_security_error creates a security error.
pub fn err_security_error(message string) PhotonError {
	return new_photon_error(.err_security, message)
}

// err_cache_miss_error creates a cache miss error.
pub fn err_cache_miss_error(key string) PhotonError {
	return new_photon_error(.err_cache_miss, 'cache miss: key "${key}" not found')
}

// err_tx_not_active_error creates a transaction not active error.
pub fn err_tx_not_active_error() PhotonError {
	return new_photon_error(.err_tx_not_active, 'no active transaction')
}

// err_conversion_failed_error creates a conversion failed error.
pub fn err_conversion_failed_error(source string, target_type string) PhotonError {
	return new_photon_error(.err_conversion_failed, 'cannot convert "${source}" to ${target_type}')
}

// err_resource_not_found_error creates a resource not found error.
pub fn err_resource_not_found_error(path string) PhotonError {
	return new_photon_error(.err_resource_not_found, 'resource not found: ${path}')
}

// err_invalid_argument_error creates an invalid argument error.
pub fn err_invalid_argument_error(message string) PhotonError {
	return new_photon_error(.err_invalid_argument, message)
}

// err_not_implemented_error creates a not implemented error.
pub fn err_not_implemented_error(feature string) PhotonError {
	return new_photon_error(.err_not_implemented, '${feature} not implemented')
}

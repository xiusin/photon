module security

// csrf.v - Cross-Site Request Forgery (CSRF) Protection
//
// Implements the Double-Submit Cookie pattern for CSRF protection.
// A random token is set as a cookie and must be submitted as a header
// (X-CSRF-TOKEN) or form field (_csrf) on state-changing requests.

import rand

// CsrfConfig configures CSRF protection behavior
pub struct CsrfConfig {
pub:
	enabled          bool   = true
	cookie_name      string = 'XSRF-TOKEN'
	header_name      string = 'X-CSRF-TOKEN'
	form_field_name  string = '_csrf'
	token_length     int    = 32
	cookie_path      string = '/'
	cookie_http_only bool
	cookie_secure    bool
	cookie_same_site string = 'Lax'
	ignored_methods  []string = ['GET', 'HEAD', 'OPTIONS', 'TRACE']
}

// CsrfToken represents a CSRF token
pub struct CsrfToken {
pub:
	token     string
	parameter string
	header    string
}

// CsrfTokenRepository stores and retrieves CSRF tokens
pub interface CsrfTokenRepository {
mut:
	generate_token() string
	save_token(token string) !
	load_token() !string
}

// CookieCsrfTokenRepository implements the double-submit cookie pattern
pub struct CookieCsrfTokenRepository {
pub mut:
	config    CsrfConfig
	cached_token string
}

// new_cookie_token_repo creates a new CookieCsrfTokenRepository
pub fn new_cookie_token_repo(config CsrfConfig) &CookieCsrfTokenRepository {
	return &CookieCsrfTokenRepository{
		config: config
	}
}

// generate_token creates a random CSRF token
pub fn (ctr &CookieCsrfTokenRepository) generate_token() string {
	mut token := ''
	mut chars_used := 0
	for chars_used < ctr.config.token_length {
		b := rand.u8()
		if (b >= `a` && b <= `z`) || (b >= `A` && b <= `Z`) || (b >= `0` && b <= `9`) {
			token += b.ascii_str()
			chars_used++
		}
	}
	return token
}

// save_token stores a token
pub fn (mut ctr CookieCsrfTokenRepository) save_token(token string) ! {
	ctr.cached_token = token
	// In web context, this would set: Set-Cookie: XSRF-TOKEN=<token>; Path=/; SameSite=Lax
}

// load_token retrieves the stored token
pub fn (mut ctr CookieCsrfTokenRepository) load_token() !string {
	if ctr.cached_token.len == 0 {
		return error('CSRF token not found')
	}
	return ctr.cached_token
}

// CsrfManager handles CSRF token lifecycle
pub struct CsrfManager {
pub mut:
	config     CsrfConfig
	repository &CookieCsrfTokenRepository = unsafe { nil }
}

// new_csrf_manager creates a new CsrfManager
pub fn new_csrf_manager(config CsrfConfig) &CsrfManager {
	return &CsrfManager{
		config: config
		repository: new_cookie_token_repo(config)
	}
}

// generate generates a new CSRF token
pub fn (cm &CsrfManager) generate() string {
	return cm.repository.generate_token()
}

// create_token creates a CsrfToken for use in templates
pub fn (mut cm CsrfManager) create_token() !CsrfToken {
	token := cm.generate()
	cm.repository.save_token(token)!

	return CsrfToken{
		token: token
		parameter: cm.config.form_field_name
		header: cm.config.header_name
	}
}

// validate validates a CSRF token from a request
pub fn (cm &CsrfManager) validate(actual_token string, expected_token string) ! {
	if !cm.config.enabled {
		return
	}
	if actual_token.len == 0 {
		return error('CSRF token is missing')
	}
	if actual_token != expected_token {
		return error('CSRF token mismatch')
	}
}

// is_csrf_required checks if CSRF validation is needed for this method
pub fn (cm &CsrfManager) is_csrf_required(method string) bool {
	if !cm.config.enabled {
		return false
	}
	for ignored in cm.config.ignored_methods {
		if method.to_upper() == ignored {
			return false
		}
	}
	return true
}

// get_expected_token retrieves the expected CSRF token from storage
pub fn (mut cm CsrfManager) get_expected_token() string {
	return cm.repository.load_token() or { '' }
}

// get_actual_token extracts the submitted CSRF token from request
pub fn (cm &CsrfManager) get_actual_token(header_value string, form_value string) string {
	if header_value.len > 0 {
		return header_value
	}
	return form_value
}

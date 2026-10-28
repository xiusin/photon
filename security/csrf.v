module security

// csrf.v - Cross-Site Request Forgery (CSRF) Protection
//
// Implements the Double-Submit Cookie pattern for CSRF protection.
// A random token is set as a cookie and must be submitted as a header
// (X-CSRF-TOKEN) or form field (_csrf) on state-changing requests.
import crypto.rand as crand

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
	cookie_same_site string   = 'Lax'
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
	config       CsrfConfig
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
		buf := crand.read(1) or {
			// crypto/rand failure is fatal — do NOT fall back to weak randomness.
			// A predictable CSRF token would defeat CSRF protection.
			panic('crypto/rand failed: cannot generate secure CSRF token')
		}
		b := buf[0]
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
@[heap]
pub struct CsrfManager {
pub mut:
	config     CsrfConfig
	repository &CookieCsrfTokenRepository = unsafe { nil }
}

// new_csrf_manager creates a new CsrfManager
pub fn new_csrf_manager(config CsrfConfig) &CsrfManager {
	return &CsrfManager{
		config:     config
		repository: new_cookie_token_repo(config)
	}
}

// generate generates a new CSRF token
pub fn (cm &CsrfManager) generate() string {
	if isnil(cm.repository) {
		return ''
	}
	return cm.repository.generate_token()
}

// create_token creates a CsrfToken for use in templates
pub fn (mut cm CsrfManager) create_token() !CsrfToken {
	token := cm.generate()
	cm.repository.save_token(token)!

	return CsrfToken{
		token:     token
		parameter: cm.config.form_field_name
		header:    cm.config.header_name
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
	if expected_token.len == 0 {
		// 服务端还没签发过 token，任何提交都不可能匹配 —— 明确报错，
		// 而不是依赖 `!=` 顺带兜住。
		return error('CSRF token not issued for this session')
	}
	// 逐字节比较且不提前返回：`!=` 会在第一个不同的字节处短路，
	// 攻击者据此可以一字节一字节地把 token 猜出来（经典时序侧信道）。
	// token 只有 32 字节，定长比较的代价可以忽略。
	if !constant_time_eq(actual_token, expected_token) {
		return error('CSRF token mismatch')
	}
}

// constant_time_eq compares two byte strings without an early exit.
//
// 长度差异本身无法隐藏（HTTP 层面的长度差异远大于这里的差），
// 但内容比较必须是定长循环，否则第一个不同字节的位置会通过响应时间泄露。
fn constant_time_eq(a string, b string) bool {
	alen := a.len
	blen := b.len
	mut diff := alen ^ blen
	max_len := if alen > blen { alen } else { blen }
	for i in 0 .. max_len {
		ac := if i < alen { a[i] } else { u8(0) }
		bc := if i < blen { b[i] } else { u8(0) }
		diff |= int(ac ^ bc)
	}
	return diff == 0
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

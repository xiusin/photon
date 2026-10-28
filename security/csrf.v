module security

// csrf.v - Cross-Site Request Forgery (CSRF) Protection
//
// Implements the Double-Submit Cookie pattern for CSRF protection.
// A random token is set as a cookie and must be submitted as a header
// (X-CSRF-TOKEN) or form field (_csrf) on state-changing requests.
import crypto.rand as crand
import sync

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
mut:
	mu sync.Mutex
	// issued 保存仍然有效的 token（服务端会话侧的 token 集合）。
	// 之前只有 repository 里那一个 cached_token：一旦用 create_token() 换了新
	// token，旧 token 立刻失效 —— 同一用户的两个浏览器标签页互相把对方踢下线。
	issued []string
	// max_issued 限制同时有效的 token 数量，超出时淘汰最旧的一条。
	max_issued int = 16
}

// new_csrf_manager creates a new CsrfManager
pub fn new_csrf_manager(config CsrfConfig) &CsrfManager {
	return &CsrfManager{
		config:     config
		repository: new_cookie_token_repo(config)
	}
}

// issued_token_limit 是 token 集合的硬上限，0 或负数时回落到 16。
fn (cm CsrfManager) issued_token_limit() int {
	if cm.max_issued > 0 {
		return cm.max_issued
	}
	return 16
}

// generate generates a new CSRF token
pub fn (cm &CsrfManager) generate() string {
	if isnil(cm.repository) {
		return ''
	}
	return cm.repository.generate_token()
}

// create_token creates a CsrfToken for use in templates
//
// 新 token 会被记进服务端 token 集合，且在集合未满之前不会吊销旧 token：
// 同一会话的多个标签页各自持有自己的 token，都能提交成功。
pub fn (mut cm CsrfManager) create_token() !CsrfToken {
	token := cm.generate()
	cm.remember_token(token)
	cm.repository.save_token(token)!

	return CsrfToken{
		token:     token
		parameter: cm.config.form_field_name
		header:    cm.config.header_name
	}
}

// remember_token 把一个新 token 记进服务端 token 集合（调用方通常不需要直接用它）。
pub fn (mut cm CsrfManager) remember_token(token string) {
	if token.len == 0 {
		return
	}
	cm.mu.@lock()
	defer {
		cm.mu.unlock()
	}
	cm.issued << token
	limit := cm.issued_token_limit()
	if cm.issued.len > limit {
		cm.issued = cm.issued[cm.issued.len - limit..].clone()
	}
}

// revoke_tokens 清空服务端 token 集合（登出 / 会话重建时调用）。
pub fn (mut cm CsrfManager) revoke_tokens() {
	cm.mu.@lock()
	defer {
		cm.mu.unlock()
	}
	cm.issued = []
}

// issued_token_count 返回当前有效的 token 数量（诊断用）。
pub fn (mut cm CsrfManager) issued_token_count() int {
	cm.mu.@lock()
	defer {
		cm.mu.unlock()
	}
	return cm.issued.len
}

// candidate_tokens 返回本次校验需要比对的全部期望值。
//
// 为什么是「集合」而不是「单个 token」：Double-Submit 把 token 同时放进
// cookie 与表单/请求头。服务端在本次请求里读到的 cookie 值就是这一个请求
// 的期望值；而会话级的 token 集合覆盖「上一个响应刚签发、cookie 还没回传」
// 那个窗口。两边都试，才既不误杀并发请求，也不接受从未签发过的 token。
pub fn (mut cm CsrfManager) candidate_tokens(expected_token string) []string {
	mut candidates := []string{}
	if expected_token.len > 0 {
		candidates << expected_token
	}
	cm.mu.@lock()
	for token in cm.issued {
		if token !in candidates {
			candidates << token
		}
	}
	cm.mu.unlock()
	return candidates
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

// validate_any 依次用候选期望值校验提交的 token，任一匹配即通过。
//
// 空候选集合表示「服务端从未签发过 token」——直接报错，别静默放行。
pub fn (cm &CsrfManager) validate_any(actual_token string, expected_tokens []string) ! {
	if !cm.config.enabled {
		return
	}
	if actual_token.len == 0 {
		return error('CSRF token is missing')
	}
	if expected_tokens.len == 0 {
		return error('CSRF token not issued for this session')
	}
	mut last_err := ''
	for expected in expected_tokens {
		if _ := cm.validate(actual_token, expected) {
			return
		} else {
			last_err = err.msg()
		}
	}
	return error(if last_err.len > 0 { last_err } else { 'CSRF token mismatch' })
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

// get_expected_tokens 返回校验时应当比对的全部期望 token。
// 供 web 层直接使用，避免调用方自己拼「单值 + 集合」。
pub fn (mut cm CsrfManager) get_expected_tokens() []string {
	expected := cm.repository.load_token() or { '' }
	return cm.candidate_tokens(expected)
}

// require_token 是「一个请求要过 CSRF 校验」的完整入口：
// 判断该方法是否需要校验、取提交值、按候选集合校验。失败返回错误。
//
// 框架外接入（veb 过滤器、自定义中间件）都应当走这里，而不是只调 validate()
// ——否则要么漏掉方法白名单，要么把并发标签页的合法 token 判成非法。
pub fn (mut cm CsrfManager) require_token(method string, header_value string, form_value string) ! {
	if !cm.is_csrf_required(method) {
		return
	}
	actual := cm.get_actual_token(header_value, form_value)
	cm.validate_any(actual, cm.get_expected_tokens())!
}

// get_actual_token extracts the submitted CSRF token from request
pub fn (cm &CsrfManager) get_actual_token(header_value string, form_value string) string {
	if header_value.len > 0 {
		return header_value
	}
	return form_value
}

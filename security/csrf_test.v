module security

// csrf_test.v - Unit tests for CSRF protection
//
// Tests CsrfConfig, CsrfToken, CookieCsrfTokenRepository,
// CsrfManager, token lifecycle, validation, and method checking.

// -- CsrfConfig tests --

fn test_csrf_config_defaults() {
	config := CsrfConfig{}
	assert config.enabled == true
	assert config.cookie_name == 'XSRF-TOKEN'
	assert config.header_name == 'X-CSRF-TOKEN'
	assert config.form_field_name == '_csrf'
	assert config.token_length == 32
	assert config.ignored_methods.len == 4
}

fn test_csrf_config_custom() {
	config := CsrfConfig{
		enabled:      false
		header_name:  'X-CUSTOM-TOKEN'
		token_length: 16
	}
	assert config.enabled == false
	assert config.header_name == 'X-CUSTOM-TOKEN'
	assert config.token_length == 16
}

// -- CookieCsrfTokenRepository tests --

fn test_new_cookie_token_repo() {
	config := CsrfConfig{
		token_length: 16
	}
	repo := new_cookie_token_repo(config)
	assert repo.config.token_length == 16
	assert repo.cached_token == ''
}

fn test_generate_token_length() {
	config := CsrfConfig{
		token_length: 32
	}
	repo := new_cookie_token_repo(config)
	token := repo.generate_token()
	assert token.len == 32
}

fn test_generate_token_is_alphanumeric() {
	config := CsrfConfig{
		token_length: 32
	}
	repo := new_cookie_token_repo(config)
	token := repo.generate_token()
	for c in token {
		assert (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
	}
}

fn test_generate_token_randomness() {
	config := CsrfConfig{
		token_length: 32
	}
	repo := new_cookie_token_repo(config)
	token1 := repo.generate_token()
	token2 := repo.generate_token()
	assert token1 != token2
}

fn test_generate_token_custom_length() {
	config := CsrfConfig{
		token_length: 8
	}
	repo := new_cookie_token_repo(config)
	token := repo.generate_token()
	assert token.len == 8
}

fn test_generate_token_length_64() {
	config := CsrfConfig{
		token_length: 64
	}
	repo := new_cookie_token_repo(config)
	token := repo.generate_token()
	assert token.len == 64
}

fn test_save_token() {
	config := CsrfConfig{
		token_length: 16
	}
	mut repo := new_cookie_token_repo(config)
	repo.save_token('my-csrf-token') or {
		assert false, 'save should succeed'
		return
	}
	assert repo.cached_token == 'my-csrf-token'
}

fn test_load_token_success() {
	config := CsrfConfig{
		token_length: 16
	}
	mut repo := new_cookie_token_repo(config)
	repo.save_token('stored-token') or {}
	token := repo.load_token() or { '' }
	assert token == 'stored-token'
}

fn test_load_token_not_found() {
	config := CsrfConfig{
		token_length: 16
	}
	mut repo := new_cookie_token_repo(config)
	mut caught := false
	if _ := repo.load_token() {
	} else {
		caught = true
	}
	assert caught == true
}

fn test_save_token_overwrites() {
	config := CsrfConfig{
		token_length: 16
	}
	mut repo := new_cookie_token_repo(config)
	repo.save_token('first') or {}
	repo.save_token('second') or {}
	token := repo.load_token() or { '' }
	assert token == 'second'
}

// -- CsrfToken tests --

fn test_csrf_token_struct() {
	t := CsrfToken{
		token:     'abc123'
		parameter: '_csrf'
		header:    'X-CSRF-TOKEN'
	}
	assert t.token == 'abc123'
	assert t.parameter == '_csrf'
	assert t.header == 'X-CSRF-TOKEN'
}

// -- CsrfManager tests --

fn test_new_csrf_manager() {
	config := CsrfConfig{
		enabled: true
	}
	cm := new_csrf_manager(config)
	assert cm.config.enabled == true
	assert cm.repository != unsafe { nil }
}

fn test_csrf_manager_generate() {
	cm := new_csrf_manager(CsrfConfig{ token_length: 32 })
	token := cm.generate()
	assert token.len == 32
}

fn test_csrf_manager_create_token() {
	mut cm := new_csrf_manager(CsrfConfig{
		enabled:         true
		token_length:    32
		header_name:     'X-CSRF-TOKEN'
		form_field_name: '_csrf'
	})
	csrf_token := cm.create_token() or {
		assert false, 'create_token should succeed'
		return
	}
	assert csrf_token.token.len == 32
	assert csrf_token.parameter == '_csrf'
	assert csrf_token.header == 'X-CSRF-TOKEN'
}

// -- CsrfManager validate tests --

fn test_validate_matching_tokens() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	cm.validate('token-abc', 'token-abc') or { assert false, 'matching tokens should validate' }
	assert true
}

fn test_validate_mismatched_tokens() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	mut caught := false
	if _ := cm.validate('token-a', 'token-b') {
	} else {
		caught = true
	}
	assert caught == true
}

fn test_validate_missing_token() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	mut caught := false
	if _ := cm.validate('', 'expected') {
	} else {
		caught = true
	}
	assert caught == true
}

fn test_validate_disabled_csrf() {
	cm := new_csrf_manager(CsrfConfig{ enabled: false })
	// Validation should pass when CSRF is disabled, even with mismatched tokens
	cm.validate('a', 'b') or { assert false, 'disabled CSRF should pass validation' }
	assert true
}

fn test_validate_disabled_with_empty_tokens() {
	cm := new_csrf_manager(CsrfConfig{ enabled: false })
	cm.validate('', '') or { assert false, 'disabled CSRF should pass empty validation' }
	assert true
}

// -- CsrfManager is_csrf_required tests --

fn test_is_csrf_required_get_method() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('GET') == false
}

fn test_is_csrf_required_head_method() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('HEAD') == false
}

fn test_is_csrf_required_options_method() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('OPTIONS') == false
}

fn test_is_csrf_required_trace_method() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('TRACE') == false
}

fn test_is_csrf_required_post_method() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('POST') == true
}

fn test_is_csrf_required_put_method() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('PUT') == true
}

fn test_is_csrf_required_delete_method() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('DELETE') == true
}

fn test_is_csrf_required_patch_method() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('PATCH') == true
}

fn test_is_csrf_required_case_insensitive() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	assert cm.is_csrf_required('post') == true
	assert cm.is_csrf_required('get') == false
}

fn test_is_csrf_required_disabled() {
	cm := new_csrf_manager(CsrfConfig{ enabled: false })
	assert cm.is_csrf_required('POST') == false
	assert cm.is_csrf_required('GET') == false
}

// -- CsrfManager get_actual_token tests --

fn test_get_actual_token_header_priority() {
	cm := new_csrf_manager(CsrfConfig{})
	result := cm.get_actual_token('header-token', 'form-token')
	assert result == 'header-token'
}

fn test_get_actual_token_form_fallback() {
	cm := new_csrf_manager(CsrfConfig{})
	result := cm.get_actual_token('', 'form-token')
	assert result == 'form-token'
}

fn test_get_actual_token_both_empty() {
	cm := new_csrf_manager(CsrfConfig{})
	result := cm.get_actual_token('', '')
	assert result == ''
}

// -- CsrfManager get_expected_token tests --

fn test_get_expected_token_after_create() {
	mut cm := new_csrf_manager(CsrfConfig{ token_length: 32 })
	csrf_token := cm.create_token() or { CsrfToken{} }
	expected := cm.get_expected_token()
	assert expected == csrf_token.token
}

fn test_get_expected_token_without_create() {
	mut cm := new_csrf_manager(CsrfConfig{ token_length: 32 })
	expected := cm.get_expected_token()
	assert expected == ''
}

// -- 定长比较 / 未签发 token --

fn test_validate_no_issued_token_is_rejected() {
	cm := new_csrf_manager(CsrfConfig{ enabled: true })
	mut caught := false
	if _ := cm.validate('anything', '') {
	} else {
		caught = true
	}
	assert caught, 'submitting a token when none was issued must fail'
}

fn test_constant_time_eq_semantics() {
	assert constant_time_eq('abc', 'abc')
	assert !constant_time_eq('abc', 'abd')
	assert !constant_time_eq('abc', 'ab')
	assert !constant_time_eq('', 'a')
	assert constant_time_eq('', '')
	// 长度相同、内容不同
	assert !constant_time_eq('aaaaaaaa', 'aaaaaaab')
}

// -- 多标签页：旧 token 不应被新 token 立刻吊销 --

fn test_create_token_keeps_previous_token_valid() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 32 })
	first := cm.create_token() or { CsrfToken{} }
	second := cm.create_token() or { CsrfToken{} }
	assert first.token != second.token

	// 第二个标签页提交它自己那份 token，仍然要过
	cm.validate_any(first.token, cm.get_expected_tokens()) or {
		assert false, 'the first tab token must still validate: ${err}'
	}
	cm.validate_any(second.token, cm.get_expected_tokens()) or {
		assert false, 'the newest token must validate: ${err}'
	}
	assert cm.issued_token_count() == 2
}

fn test_validate_any_rejects_unissued_token() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 32 })
	cm.create_token() or { CsrfToken{} }
	mut caught := false
	if _ := cm.validate_any('forged-token', cm.get_expected_tokens()) {
	} else {
		caught = true
	}
	assert caught, 'a token that was never issued must not validate'
}

fn test_validate_any_without_any_issued_token() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 32 })
	mut caught := false
	if _ := cm.validate_any('x', cm.get_expected_tokens()) {
	} else {
		caught = true
	}
	assert caught, 'no issued token + submitted token must fail'
}

fn test_validate_any_missing_submitted_token() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 32 })
	t := cm.create_token() or { CsrfToken{} }
	mut caught := false
	if _ := cm.validate_any('', cm.get_expected_tokens()) {
	} else {
		caught = true
	}
	assert caught
	assert t.token.len == 32
}

fn test_validate_any_respects_disabled() {
	mut cm := new_csrf_manager(CsrfConfig{
		enabled: false
	})
	cm.validate_any('a', ['b']) or { assert false, 'disabled CSRF must skip validation' }
}

fn test_revoke_tokens_clears_set() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 32 })
	first := cm.create_token() or { CsrfToken{} }
	cm.create_token() or { CsrfToken{} }
	assert cm.issued_token_count() == 2

	cm.revoke_tokens()
	assert cm.issued_token_count() == 0

	// 只剩 cookie 里最后签发的那一个期望值，被吊销的旧 token 不再能通过
	mut caught := false
	if _ := cm.validate_any(first.token, cm.get_expected_tokens()) {
	} else {
		caught = true
	}
	assert caught, 'a revoked token must no longer validate'
}

fn test_issued_tokens_are_bounded() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 16 })
	for _ in 0 .. 40 {
		cm.create_token() or { CsrfToken{} }
	}
	assert cm.issued_token_count() == 16, 'token set must stay bounded, got ${cm.issued_token_count()}'
}

// -- require_token：把「方法白名单 + 取值 + 校验」收成一个入口 --

fn test_require_token_skips_ignored_method() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 16 })
	// GET 不在校验范围内，没有 token 也要过
	cm.require_token('GET', '', '') or { assert false, 'GET must not require a token: ${err}' }
	cm.require_token('HEAD', '', '') or { assert false, 'HEAD must not require a token: ${err}' }
}

fn test_require_token_accepts_header() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 16 })
	t := cm.create_token() or { CsrfToken{} }
	cm.require_token('POST', t.token, '') or {
		assert false, 'header token must be accepted: ${err}'
	}
}

fn test_require_token_accepts_form_field() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 16 })
	t := cm.create_token() or { CsrfToken{} }
	cm.require_token('POST', '', t.token) or {
		assert false, 'form token must be accepted: ${err}'
	}
}

fn test_require_token_rejects_missing_on_post() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 16 })
	cm.create_token() or { CsrfToken{} }
	mut caught := false
	if _ := cm.require_token('POST', '', '') {
	} else {
		caught = true
	}
	assert caught, 'POST without a token must be rejected'
}

fn test_require_token_rejects_when_nothing_issued() {
	mut cm := new_csrf_manager(CsrfConfig{ enabled: true, token_length: 16 })
	mut caught := false
	if _ := cm.require_token('POST', 'guess', '') {
	} else {
		caught = true
	}
	assert caught, 'a POST before any token was issued must be rejected'
}

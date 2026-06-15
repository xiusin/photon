module security

// auth_test.v - Unit tests for Authentication, PasswordEncoder,
// AuthenticationManager, and authentication providers.
//
// Tests authentication token lifecycle, password encoding,
// provider chaining, and error handling.

// -- PasswordEncoder tests --

fn test_plain_text_encoder_encode_returns_same() {
	pe := PlainTextPasswordEncoder{}
	encoded := pe.encode('myPassword123')
	assert encoded == 'myPassword123'
}

fn test_plain_text_encoder_matches_correct() {
	pe := PlainTextPasswordEncoder{}
	assert pe.matches('password', 'password') == true
}

fn test_plain_text_encoder_matches_incorrect() {
	pe := PlainTextPasswordEncoder{}
	assert pe.matches('correct', 'wrong') == false
}

fn test_plain_text_encoder_encode_empty() {
	pe := PlainTextPasswordEncoder{}
	assert pe.encode('') == ''
}

// -- Authentication tests --

fn test_new_authentication_unauthenticated() {
	auth := new_authentication('alice', 'secret123')
	assert auth.principal == 'alice'
	assert auth.credentials == 'secret123'
	assert auth.is_authenticated() == false
	assert auth.authorities.len == 0
}

fn test_mark_authenticated() {
	mut auth := new_authentication('alice', 'secret123')
	auth.mark_authenticated(['USER', 'ADMIN'])
	assert auth.is_authenticated() == true
	assert auth.authorities.len == 2
	assert auth.authorities[0] == 'USER'
	assert auth.authorities[1] == 'ADMIN'
}

fn test_mark_authenticated_empty_roles() {
	mut auth := new_authentication('bob', 'secret')
	auth.mark_authenticated([])
	assert auth.is_authenticated() == true
	assert auth.authorities.len == 0
}

fn test_authentication_details_map() {
	mut auth := new_authentication('alice', 'token')
	auth.details['jti'] = 'abc-123'
	auth.details['iss'] = 'photon'
	assert auth.details['jti'] == 'abc-123'
	assert auth.details['iss'] == 'photon'
}

// -- AuthenticationManager tests --

fn test_new_auth_manager_empty() {
	am := new_auth_manager()
	assert am.providers.len == 0
}

fn test_add_provider() {
	mut am := new_auth_manager()
	am.providers << &JwtAuthenticationProvider{
		jwt_manager: new_jwt_manager(JwtConfig{ secret: 'test' })
	}
	assert am.providers.len == 1
}

fn test_authenticate_no_providers() {
	am := new_auth_manager()
	mut auth := new_authentication('alice', 'token')
	mut caught := false
	if _ := am.authenticate(mut auth) {
	} else {
		caught = true
	}
	assert caught == true
}

fn test_authenticate_with_jwt_provider() {
	mut am := new_auth_manager()
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token_str := jm.create_token('alice', ['USER']) or { '' }
	am.providers << &JwtAuthenticationProvider{ jwt_manager: jm }

	mut auth := new_authentication('', 'Bearer ${token_str}')
	am.authenticate(mut auth) or {
		assert false, 'authentication should succeed'
		return
	}
	assert auth.is_authenticated() == true
	assert auth.principal == 'alice'
	assert auth.authorities.contains('USER')
}

fn test_authenticate_with_plain_token_no_bearer() {
	mut am := new_auth_manager()
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token_str := jm.create_token('bob', ['ADMIN']) or { '' }
	am.providers << &JwtAuthenticationProvider{ jwt_manager: jm }

	mut auth := new_authentication('', token_str)
	am.authenticate(mut auth) or {
		assert false, 'plain token should authenticate'
		return
	}
	assert auth.is_authenticated() == true
	assert auth.principal == 'bob'
}

fn test_authenticate_jwt_with_details() {
	mut am := new_auth_manager()
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token_str := jm.create_token('alice', ['USER']) or { '' }
	am.providers << &JwtAuthenticationProvider{ jwt_manager: jm }

	mut auth := new_authentication('', 'Bearer ${token_str}')
	am.authenticate(mut auth) or {
		assert false, 'should succeed'
		return
	}
	assert auth.details['jti'].len > 0
	assert auth.details['iss'] == 'photon'
}

// -- JwtAuthenticationProvider tests --

fn test_jwt_provider_supports_bearer() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test' })
	jp := JwtAuthenticationProvider{ jwt_manager: jm }
	auth := new_authentication('', 'Bearer some-token-value-here-123')
	assert jp.supports(auth) == true
}

fn test_jwt_provider_supports_long_token() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test' })
	jp := JwtAuthenticationProvider{ jwt_manager: jm }
	auth := new_authentication('', 'this-is-a-very-long-token-string-that-exceeds-twenty-chars')
	assert jp.supports(auth) == true
}

fn test_jwt_provider_does_not_support_short_token() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test' })
	jp := JwtAuthenticationProvider{ jwt_manager: jm }
	auth := new_authentication('', 'short')
	assert jp.supports(auth) == false
}

fn test_jwt_provider_does_not_support_empty_credentials() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test' })
	jp := JwtAuthenticationProvider{ jwt_manager: jm }
	auth := new_authentication('', '')
	assert jp.supports(auth) == false
}

// -- UsernamePasswordAuthenticationProvider tests --

fn test_username_provider_supports_credentials() {
	user_service := new_in_memory_service()
	encoder := &PlainTextPasswordEncoder{}
	up := UsernamePasswordAuthenticationProvider{
		user_service: user_service
		password_encoder: encoder
	}
	auth := new_authentication('alice', 'password123')
	assert up.supports(auth) == true
}

fn test_username_provider_does_not_support_bearer() {
	user_service := new_in_memory_service()
	encoder := &PlainTextPasswordEncoder{}
	up := UsernamePasswordAuthenticationProvider{
		user_service: user_service
		password_encoder: encoder
	}
	auth := new_authentication('alice', 'Bearer token123')
	assert up.supports(auth) == false
}

fn test_username_provider_does_not_support_empty() {
	user_service := new_in_memory_service()
	encoder := &PlainTextPasswordEncoder{}
	up := UsernamePasswordAuthenticationProvider{
		user_service: user_service
		password_encoder: encoder
	}
	auth := new_authentication('', '')
	assert up.supports(auth) == false
}

fn test_username_provider_authenticate_success() {
	mut user_service := new_in_memory_service()
	user := new_user('alice', 'pass123', ['USER'])
	user_service.add_user(user)

	encoder := &PlainTextPasswordEncoder{}
	up := UsernamePasswordAuthenticationProvider{
		user_service: user_service
		password_encoder: encoder
	}

	auth := new_authentication('alice', 'pass123')
	result := up.authenticate(auth) or {
		assert false, 'should authenticate'
		return
	}
	assert result.is_authenticated() == true
	assert result.principal == 'alice'
	assert result.authorities.contains('USER')
}

fn test_username_provider_authenticate_wrong_password() {
	mut user_service := new_in_memory_service()
	user := new_user('alice', 'correct', ['USER'])
	user_service.add_user(user)

	encoder := &PlainTextPasswordEncoder{}
	up := UsernamePasswordAuthenticationProvider{
		user_service: user_service
		password_encoder: encoder
	}

	auth := new_authentication('alice', 'wrong')
	mut caught := false
	if _ := up.authenticate(auth) {
	} else {
		caught = true
	}
	assert caught == true
}

fn test_username_provider_authenticate_user_not_found() {
	user_service := new_in_memory_service()
	encoder := &PlainTextPasswordEncoder{}
	up := UsernamePasswordAuthenticationProvider{
		user_service: user_service
		password_encoder: encoder
	}

	auth := new_authentication('nonexistent', 'password')
	mut caught := false
	if _ := up.authenticate(auth) {
	} else {
		caught = true
	}
	assert caught == true
}

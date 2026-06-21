module security

// jwt_test.v - Unit tests for JWT token management
//
// Tests JwtConfig, JwtClaims, token creation, parsing, validation,
// refresh tokens, role checking, and error handling.

// -- JwtConfig tests --

fn test_jwt_config_defaults() {
	config := JwtConfig{
		secret: 'test-secret'
	}
	assert config.secret == 'test-secret'
	assert config.issuer == 'photon'
	assert config.expiration_minutes == 60
	assert config.refresh_token_expiration_hours == 168
}

fn test_jwt_config_custom_values() {
	config := JwtConfig{
		secret:                         'my-secret'
		issuer:                         'my-app'
		expiration_minutes:             30
		refresh_token_expiration_hours: 24
		audience:                       'api-users'
	}
	assert config.issuer == 'my-app'
	assert config.expiration_minutes == 30
	assert config.audience == 'api-users'
}

// -- JwtClaims tests --

fn test_jwt_claims_initialization() {
	claims := JwtClaims{
		sub:   'bob'
		iat:   1000
		exp:   2000
		iss:   'photon'
		roles: ['USER']
	}
	assert claims.sub == 'bob'
	assert claims.iat == 1000
	assert claims.exp == 2000
	assert claims.iss == 'photon'
	assert claims.roles.len == 1
	assert claims.roles[0] == 'USER'
}

// -- JwtManager construction --

fn test_new_jwt_manager() {
	jm := new_jwt_manager(JwtConfig{ secret: 'secret123' })
	assert jm.config.secret == 'secret123'
	assert jm.config.issuer == 'photon'
}

// -- Token creation tests --

fn test_create_token_success() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('alice', ['USER', 'ADMIN']) or { '' }
	assert token.len > 0
	assert token.contains('.')
}

fn test_create_token_format_three_parts() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('alice', ['USER']) or { '' }
	parts := token.split('.')
	assert parts.len == 3
}

fn test_create_token_with_empty_roles() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('guest', []) or { '' }
	assert token.len > 0
}

fn test_create_token_different_users_different_tokens() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token1 := jm.create_token('alice', ['USER']) or { '' }
	token2 := jm.create_token('bob', ['USER']) or { '' }
	assert token1 != token2
}

// -- Token parsing tests --

fn test_parse_token_valid() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('alice', ['USER']) or { '' }
	claims := jm.parse_token(token) or {
		assert false, 'should not fail on valid token'
		return
	}
	assert claims.sub == 'alice'
}

fn test_parse_token_invalid_format() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	mut caught := false
	if _ := jm.parse_token('not-a-valid-token') {
	} else {
		caught = true
	}
	assert caught == true
}

fn test_parse_token_invalid_signature() {
	jm1 := new_jwt_manager(JwtConfig{ secret: 'key-a' })
	jm2 := new_jwt_manager(JwtConfig{ secret: 'key-b' })
	token := jm1.create_token('alice', ['USER']) or { '' }
	mut caught := false
	if _ := jm2.parse_token(token) {
	} else {
		caught = true
	}
	assert caught == true
}

fn test_parse_token_tampered_payload() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('alice', ['USER']) or { '' }
	parts := token.split('.')
	// Tamper with the payload part
	tampered := '${parts[0]}.tampered.${parts[2]}'
	mut caught := false
	if _ := jm.parse_token(tampered) {
	} else {
		caught = true
	}
	assert caught == true
}

// -- validate_token tests --

fn test_validate_token_returns_username() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('bob', ['USER']) or { '' }
	username := jm.validate_token(token) or { '' }
	assert username == 'bob'
}

fn test_validate_token_invalid() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	mut caught := false
	if _ := jm.validate_token('bad-token') {
	} else {
		caught = true
	}
	assert caught == true
}

// -- has_role tests --

fn test_has_role_matching() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('alice', ['USER']) or { '' }
	assert jm.has_role(token, 'USER') == true
}

fn test_has_role_non_matching() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('alice', ['USER']) or { '' }
	assert jm.has_role(token, 'ADMIN') == false
}

fn test_has_role_invalid_token() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	assert jm.has_role('bad-token', 'USER') == false
}

// -- has_any_role tests --

fn test_has_any_role_matching() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('alice', ['USER', 'MODERATOR']) or { '' }
	assert jm.has_any_role(token, ['ADMIN', 'USER']) == true
}

fn test_has_any_role_none_matching() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	token := jm.create_token('alice', ['USER']) or { '' }
	assert jm.has_any_role(token, ['ADMIN', 'MODERATOR']) == false
}

fn test_has_any_role_invalid_token() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	assert jm.has_any_role('bad-token', ['USER']) == false
}

// -- create_refresh_token tests --

fn test_create_refresh_token_different_from_access() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	access := jm.create_token('alice', ['USER']) or { '' }
	refresh := jm.create_refresh_token('alice') or { '' }
	assert access != refresh
	assert refresh.len > 0
}

fn test_create_refresh_token_format() {
	jm := new_jwt_manager(JwtConfig{ secret: 'test-key' })
	refresh := jm.create_refresh_token('alice') or { '' }
	parts := refresh.split('.')
	assert parts.len == 3
}

// -- generate_jti tests --

fn test_generate_jti_format() {
	jti := generate_jti('alice', 1234567890)
	assert jti.contains('alice')
	assert jti.contains('1234567890')
	assert jti == 'alice_1234567890'
}

fn test_generate_jti_different_prefixes() {
	jti1 := generate_jti('alice', 1000)
	jti2 := generate_jti('bob', 1000)
	assert jti1 != jti2
	assert jti1.contains('alice')
	assert jti2.contains('bob')
}

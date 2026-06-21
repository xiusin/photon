module security

// password_encoder_test.v - Unit tests for PasswordEncoder implementations
//
// Tests BCryptPasswordEncoder, Argon2PasswordEncoder, FnvPasswordEncoder,
// and DelegatingPasswordEncoder including cross-verification and migration.

fn test_bcrypt_password_encoder_encode_format() {
	e := new_bcrypt_password_encoder()
	encoded := e.encode('password')!
	assert encoded.starts_with('{bcrypt}$2y$')
}

fn test_bcrypt_password_encoder_matches_valid() {
	e := new_bcrypt_password_encoder()
	encoded := e.encode('mypassword')!
	assert e.matches('mypassword', encoded)!
}

fn test_bcrypt_password_encoder_matches_invalid() {
	e := new_bcrypt_password_encoder()
	encoded := e.encode('correct')!
	assert e.matches('wrong', encoded)! == false
}

fn test_bcrypt_password_encoder_upgrade_encoding() {
	e := BCryptPasswordEncoder{
		strength: 10
	}
	encoded := e.encode('pw')!
	assert e.upgrade_encoding(encoded) == false // same strength, no upgrade

	e2 := BCryptPasswordEncoder{
		strength: 12
	}
	assert e2.upgrade_encoding(encoded) == true // different strength, upgrade
}

fn test_argon2_password_encoder_encode_format() {
	e := new_argon2_password_encoder()
	encoded := e.encode('password')!
	assert encoded.starts_with('{argon2id}$argon2id$')
}

fn test_argon2_password_encoder_matches_valid() {
	e := new_argon2_password_encoder()
	encoded := e.encode('mypassword')!
	assert e.matches('mypassword', encoded)!
}

fn test_argon2_password_encoder_matches_invalid() {
	e := new_argon2_password_encoder()
	encoded := e.encode('correct')!
	assert e.matches('wrong', encoded)! == false
}

fn test_fnv_password_encoder_encode_errors() {
	e := new_fnv_password_encoder()
	mut failed := false
	e.encode('pw') or { failed = true }
	assert failed
}

fn test_fnv_password_encoder_upgrade_always() {
	e := new_fnv_password_encoder()
	assert e.upgrade_encoding('anyhash') == true
}

fn test_delegating_password_encoder_encode_format() {
	e := new_delegating_password_encoder()
	encoded := e.encode('password')!
	assert encoded.starts_with('{bcrypt}')
}

fn test_delegating_password_encoder_matches_valid() {
	e := new_delegating_password_encoder()
	encoded := e.encode('mypassword')!
	assert e.matches('mypassword', encoded)!
}

fn test_delegating_password_encoder_matches_invalid() {
	e := new_delegating_password_encoder()
	encoded := e.encode('correct')!
	assert e.matches('wrong', encoded)! == false
}

fn test_delegating_password_encoder_cross_verify() {
	// Encode with bcrypt, verify with delegating
	bcrypt_e := new_bcrypt_password_encoder()
	encoded := bcrypt_e.encode('secret')!

	delegating := new_delegating_password_encoder()
	assert delegating.matches('secret', encoded)!
}

fn test_delegating_password_encoder_upgrade_encoding() {
	e := new_delegating_password_encoder()
	encoded := e.encode('pw')!
	// Same encoder, no upgrade
	assert e.upgrade_encoding(encoded) == false
}

fn test_delegating_password_encoder_unknown_id_returns_false() {
	e := new_delegating_password_encoder()
	// Unknown encoder id → matches returns false (not error)
	result := e.matches('pw', '{unknown}hash')!
	assert result == false
}

fn test_password_encoder_interface_compatible() {
	// All encoders implement PasswordEncoder interface
	mut encoders := []PasswordEncoder{}
	encoders << new_bcrypt_password_encoder()
	encoders << new_argon2_password_encoder()
	encoders << new_delegating_password_encoder()

	for e in encoders {
		encoded := e.encode('test')!
		assert e.matches('test', encoded)!
		assert e.matches('wrong', encoded)! == false
	}
}

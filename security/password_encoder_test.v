module security

// password_encoder_test.v - Unit tests for PasswordEncoder implementations
//
// Tests BCryptPasswordEncoder, Argon2PasswordEncoder, FnvPasswordEncoder,
// and DelegatingPasswordEncoder including cross-verification and migration.

fn test_bcrypt_password_encoder_encode_format() {
	e := new_bcrypt_password_encoder()
	encoded := e.encode('password')!
	// crypto.bcrypt emits $2a$; $2y$/$2b$ are previews of the same hash.
	assert encoded.starts_with('{bcrypt}$2')
	assert encoded.len > 50
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
	assert encoded.starts_with('{argon2id}\$argon2id\$')
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

// ── 委派编码器的前缀契约 ──
//
// DelegatingPasswordEncoder 的职责是「按前缀选 encoder」，不是自己剥前缀。
// 它一旦多剥一层，各个 encoder 内部的剥前缀逻辑就作用在已经裸掉的串上：
// 有的底层宽容（argon2 verify 认 PHC 串），有的不宽容（bcrypt 需要完整
// 的 `$2a$cost$salt+hash`）。表现出来就是「同一个密码，换成 argon2 存就
// 登不进去」这类只在换算法时才暴露的故障。

fn test_delegating_matches_argon2_encoded() {
	// 用 argon2 encoder 编码，交给委派器验证
	a := new_argon2_password_encoder()
	encoded := a.encode('s3cret')!
	assert encoded.starts_with('{argon2id}')

	d := new_delegating_password_encoder()
	assert d.matches('s3cret', encoded)!
	assert d.matches('wrong', encoded)! == false
}

fn test_delegating_matches_keeps_prefix_intact() {
	probe := PrefixProbeEncoder{}
	d := new_probe_delegating_encoder(probe)
	// 探针只有在拿到 `{probe}...` 时才认密码；前缀被剥掉就恒不匹配
	// 探针把编码后的剩余部分当密码本身，所以传入的 raw 必须与之相同
	assert d.matches('valid', '{probe}valid')!
	assert d.matches('other', '{probe}valid')! == false
}

// new_probe_delegating_encoder 造一个只注册了探针的委派器。
fn new_probe_delegating_encoder(probe PrefixProbeEncoder) DelegatingPasswordEncoder {
	mut encoders := map[string]PasswordEncoder{}
	encoders['probe'] = probe
	return DelegatingPasswordEncoder{
		id_for_encode:          'probe'
		encoders:               encoders
		default_id_for_matches: 'probe'
	}
}

fn test_delegating_upgrade_detects_algorithm_switch() {
	d := new_delegating_password_encoder()
	a := new_argon2_password_encoder()
	encoded := a.encode('pw')!
	// 编码算法与 id_for_encode 不同 → 需要升级到 bcrypt
	assert d.upgrade_encoding(encoded)
}

// PrefixProbeEncoder 是一个只接受「带 {probe} 前缀」输入的探针。
struct PrefixProbeEncoder {}

fn (e PrefixProbeEncoder) encode(raw_password string) !string {
	return '{probe}' + raw_password
}

fn (e PrefixProbeEncoder) matches(raw_password string, encoded string) !bool {
	// 前缀被剥掉就无从判断 —— 直接判不匹配
	if !encoded.starts_with('{probe}') {
		return false
	}
	rest := encoded['{probe}'.len..]
	return rest == raw_password
}

fn (e PrefixProbeEncoder) upgrade_encoding(encoded string) bool {
	return false
}

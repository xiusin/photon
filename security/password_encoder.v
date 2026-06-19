module security

// password_encoder.v - Spring Security PasswordEncoder equivalent
//
// Provides a pluggable password encoding abstraction with migration support
// via DelegatingPasswordEncoder (Spring-style {id}hash prefix format).

// PasswordEncoder is the strategy interface for password encoding.
// Spring equivalent: org.springframework.security.crypto.password.PasswordEncoder
pub interface PasswordEncoder {
	encode(raw_password string) !string
	matches(raw_password string, encoded string) !bool
	upgrade_encoding(encoded string) bool
}

// ── BCryptPasswordEncoder ──

// BCryptPasswordEncoder wraps BcryptHasher with {bcrypt} prefix format.
pub struct BCryptPasswordEncoder {
pub:
	strength int = 10
}

pub fn new_bcrypt_password_encoder() BCryptPasswordEncoder {
	return BCryptPasswordEncoder{}
}

pub fn (e BCryptPasswordEncoder) encode(raw_password string) !string {
	hasher := BcryptHasher{
		rounds: e.strength
	}
	hash := hasher.make(raw_password)
	return '{bcrypt}' + hash
}

pub fn (e BCryptPasswordEncoder) matches(raw_password string, encoded string) !bool {
	mut hash := encoded
	if encoded.starts_with('{bcrypt}') {
		hash = encoded['{bcrypt}'.len..]
	}
	hasher := BcryptHasher{
		rounds: e.strength
	}
	return hasher.check(raw_password, hash)
}

pub fn (e BCryptPasswordEncoder) upgrade_encoding(encoded string) bool {
	mut hash := encoded
	if encoded.starts_with('{bcrypt}') {
		hash = encoded['{bcrypt}'.len..]
	}
	hasher := BcryptHasher{
		rounds: e.strength
	}
	return hasher.needs_rehash(hash)
}

// ── Argon2PasswordEncoder ──

// Argon2PasswordEncoder wraps Argon2Hasher with {argon2id} prefix format.
pub struct Argon2PasswordEncoder {
pub:
	memory  int = 65536
	time    int = 4
	threads int = 1
}

pub fn new_argon2_password_encoder() Argon2PasswordEncoder {
	return Argon2PasswordEncoder{}
}

pub fn (e Argon2PasswordEncoder) encode(raw_password string) !string {
	hasher := Argon2Hasher{
		memory:  e.memory
		time:    e.time
		threads: e.threads
	}
	hash := hasher.make(raw_password)
	return '{argon2id}' + hash
}

pub fn (e Argon2PasswordEncoder) matches(raw_password string, encoded string) !bool {
	mut hash := encoded
	if encoded.starts_with('{argon2id}') {
		hash = encoded['{argon2id}'.len..]
	}
	hasher := Argon2Hasher{
		memory:  e.memory
		time:    e.time
		threads: e.threads
	}
	return hasher.check(raw_password, hash)
}

pub fn (e Argon2PasswordEncoder) upgrade_encoding(encoded string) bool {
	mut hash := encoded
	if encoded.starts_with('{argon2id}') {
		hash = encoded['{argon2id}'.len..]
	}
	hasher := Argon2Hasher{
		memory:  e.memory
		time:    e.time
		threads: e.threads
	}
	return hasher.needs_rehash(hash)
}

// ── FnvPasswordEncoder (legacy adapter, for migration only) ──

// FnvPasswordEncoder adapts legacy FNV-1a hashes for verification only.
// encode() returns an error directing users to upgrade.
pub struct FnvPasswordEncoder {}

pub fn new_fnv_password_encoder() FnvPasswordEncoder {
	return FnvPasswordEncoder{}
}

pub fn (e FnvPasswordEncoder) encode(raw_password string) !string {
	return error('FnvPasswordEncoder cannot encode — upgrade to BCryptPasswordEncoder or Argon2PasswordEncoder')
}

pub fn (e FnvPasswordEncoder) matches(raw_password string, encoded string) !bool {
	// Legacy FNV-1a hashes have no prefix and cannot be safely verified
	// without the original salt. Return false for safety. This encoder
	// exists only to be registered in DelegatingPasswordEncoder for
	// detecting legacy hashes.
	return false
}

pub fn (e FnvPasswordEncoder) upgrade_encoding(encoded string) bool {
	// Legacy hashes always need upgrade
	return true
}

// ── DelegatingPasswordEncoder ──

// DelegatingPasswordEncoder supports multiple encoders identified by {id} prefix.
// Spring equivalent: org.springframework.security.crypto.password.DelegatingPasswordEncoder
pub struct DelegatingPasswordEncoder {
pub:
	id_for_encode          string
	encoders               map[string]PasswordEncoder
	default_id_for_matches string
}

// new_delegating_password_encoder creates a DelegatingPasswordEncoder with
// bcrypt as default for encoding, and all standard encoders registered for matching.
pub fn new_delegating_password_encoder() DelegatingPasswordEncoder {
	mut encoders := map[string]PasswordEncoder{}
	encoders['bcrypt'] = BCryptPasswordEncoder{}
	encoders['argon2id'] = Argon2PasswordEncoder{}
	encoders['fnv'] = FnvPasswordEncoder{}
	return DelegatingPasswordEncoder{
		id_for_encode:          'bcrypt'
		encoders:               encoders
		default_id_for_matches: 'bcrypt'
	}
}

pub fn (e DelegatingPasswordEncoder) encode(raw_password string) !string {
	encoder := e.encoders[e.id_for_encode] or {
		return error('no encoder registered for id "${e.id_for_encode}"')
	}
	return encoder.encode(raw_password)!
}

pub fn (e DelegatingPasswordEncoder) matches(raw_password string, encoded string) !bool {
	id, hash_stripped := parse_encoder_id(encoded)
	encoder_id := if id == '' { e.default_id_for_matches } else { id }
	hash_to_verify := if id == '' { encoded } else { hash_stripped }
	encoder := e.encoders[encoder_id] or { return false }
	return encoder.matches(raw_password, hash_to_verify)!
}

pub fn (e DelegatingPasswordEncoder) upgrade_encoding(encoded string) bool {
	id, _ := parse_encoder_id(encoded)
	// Upgrade needed if id differs from id_for_encode
	if id != e.id_for_encode && id != '' {
		return true
	}
	encoder_id := if id == '' { e.default_id_for_matches } else { id }
	encoder := e.encoders[encoder_id] or { return true }
	return encoder.upgrade_encoding(encoded)
}

// parse_encoder_id extracts the encoder id from a {id}hash formatted string.
// Returns ('', original) if no prefix found.
fn parse_encoder_id(encoded string) (string, string) {
	if !encoded.starts_with('{') {
		return '', encoded
	}
	end := encoded.index('}') or { return '', encoded }
	id := encoded[1..end]
	mut hash := encoded[end + 1..]
	return id, hash
}

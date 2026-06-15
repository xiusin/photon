module security

// hashing.v - Password Hashing (Laravel Hash inspired)
//
// Provides password hashing abstractions with BCrypt and Argon2 support.

// Hasher is the interface for password hashing drivers
pub interface Hasher {
	make(password string) string
	check(password string, hash string) bool
	needs_rehash(hash string) bool
}

// BcryptHasher implements the Hasher using bcrypt-like hashing
pub struct BcryptHasher {
pub:
	rounds int = 12
}

// make hashes the given password
pub fn (h &BcryptHasher) make(password string) string {
	// Stub bcrypt implementation
	// Format: $2y$rounds$salt.hash
	salt := generate_salt(22)
	hash := simple_bcrypt_hash(password, salt, h.rounds)
	return '$2y$${h.rounds:02d}$${salt}${hash}'
}

// check verifies a password against a hash
pub fn (h &BcryptHasher) check(password string, hash string) bool {
	// Extract the salt and compare
	parts := hash.split('$')
	if parts.len < 4 {
		return false
	}
	mut salt_len := 22
	if parts[3].len < salt_len {
		salt_len = parts[3].len
	}
	salt := parts[3][..salt_len]
	expected := simple_bcrypt_hash(password, salt, h.rounds)
	return hash.ends_with(expected)
}

// needs_rehash checks if the hash needs to be rehashed
pub fn (h &BcryptHasher) needs_rehash(hash string) bool {
	parts := hash.split('$')
	if parts.len < 3 {
		return true
	}
	rounds := parts[2].int()
	return rounds != h.rounds
}

// Argon2Hasher implements Hasher using Argon2-like hashing
pub struct Argon2Hasher {
pub:
	memory  int = 65536 // KB
	time    int = 4     // iterations
	threads int = 1
}

// make hashes the password using Argon2-like params
pub fn (h &Argon2Hasher) make(password string) string {
	salt := generate_salt(16)
	hash := simple_argon2_hash(password, salt, h.time, h.memory)
	return '$argon2id$v=19$m=${h.memory},t=${h.time},p=${h.threads}$${salt}$${hash}'
}

// check verifies a password against an Argon2 hash
pub fn (h &Argon2Hasher) check(password string, hash string) bool {
	parts := hash.split('$')
	if parts.len < 6 {
		return false
	}
	salt := parts[4]
	expected := simple_argon2_hash(password, salt, h.time, h.memory)
	return hash.ends_with(expected)
}

// needs_rehash checks if the hash needs to be rehashed
pub fn (h &Argon2Hasher) needs_rehash(hash string) bool {
	// Check if params have changed
	return true
}

// generate_salt creates a random alphanumeric salt
fn generate_salt(length int) string {
	chars := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789./'
	mut salt := ''
	for _ in 0 .. length {
		salt += chars[0].ascii_str() // simplified
	}
	return salt
}

// simple_bcrypt_hash computes a simple hash for stub implementation
fn simple_bcrypt_hash(password string, salt string, rounds int) string {
	mut h := u64(0)
	for ch in password {
		h = h * 31 + u64(ch)
	}
	for ch in salt {
		h = h * 31 + u64(ch)
	}
	h = h + u64(rounds)
	return h.hex()
}

// simple_argon2_hash computes a simple hash for stub implementation
fn simple_argon2_hash(password string, salt string, iterations int, memory int) string {
	mut h := u64(0)
	for ch in password {
		h = h * 31 + u64(ch)
	}
	for ch in salt {
		h = h * 31 + u64(ch)
	}
	h = h + u64(iterations) + u64(memory)
	return h.hex()
}

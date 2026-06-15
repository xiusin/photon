module security

// hashing.v - Password Hashing (Laravel Hash inspired)
//
// Provides password hashing abstractions with BCrypt and Argon2 support.

import rand

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
	hash := hash_string(password, salt, u64(h.rounds))
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
	expected := hash_string(password, salt, u64(h.rounds))
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
	hash := hash_string(password, salt, u64(h.time) + u64(h.memory) + u64(h.threads))
	return '$argon2id$v=19$m=${h.memory},t=${h.time},p=${h.threads}$${salt}$${hash}'
}

// check verifies a password against an Argon2 hash
pub fn (h &Argon2Hasher) check(password string, hash string) bool {
	parts := hash.split('$')
	if parts.len < 6 {
		return false
	}
	salt := parts[4]
	expected := hash_string(password, salt, u64(h.time) + u64(h.memory) + u64(h.threads))
	return hash.ends_with(expected)
}

// needs_rehash checks if the hash parameters have changed from defaults
pub fn (h &Argon2Hasher) needs_rehash(hash string) bool {
	// Parse memory, time, threads from hash format: $argon2id$v=19$m=65536,t=4,p=1$salt$hash
	parts := hash.split('$')
	if parts.len < 4 {
		return true
	}
	// Check if any parameter differs from current config
	default_mem := h.memory.str()
	default_time := h.time.str()
	default_threads := h.threads.str()
	return !parts[3].contains('m=${default_mem}') ||
		!parts[3].contains('t=${default_time}') ||
		!parts[3].contains('p=${default_threads}')
}

// generate_salt creates a random alphanumeric salt string
@[inline]
fn generate_salt(length int) string {
	chars := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789./'
	mut salt := []u8{len: length}
	for i in 0 .. length {
		salt[i] = chars[rand.intn(chars.len) or { 0 }]
	}
	return salt.bytestr()
}

// hash_string is a deterministic string hasher for demo/testing purposes.
// NOT suitable for production password storage — use a real bcrypt/argon2 library.
// Uses FNV-1a-like mixing: h = (h XOR ch) * FNV_prime
@[inline]
fn hash_string(password string, salt string, extra u64) string {
	mut h := u64(0xcbf29ce484222325)
	for ch in password {
		h = (h ^ u64(ch)) * 0x100000001b3
	}
	for ch in salt {
		h = (h ^ u64(ch)) * 0x100000001b3
	}
	h = (h ^ extra) * 0x100000001b3
	return h.hex()
}

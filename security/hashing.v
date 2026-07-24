module security

// hashing.v - Password Hashing (Laravel Hash inspired)
//
// Provides password hashing with real bcrypt (via V crypto.bcrypt) and
// argon2id (via libargon2 C bridge).  Old PBKDF2-SHA256 hashes are
// detected and verified for backward compatibility during migration.

import crypto.bcrypt
import crypto.pbkdf2
import crypto.sha256
import rand

// ── C interop for libargon2 ──
#flag -largon2
#flag -I/opt/homebrew/include
#flag -L/opt/homebrew/lib

fn C.photon_argon2id_hash(password &char, salt &char, t_cost u32, m_cost u32, parallelism u32, encoded &char, encoded_len usize) int

fn C.photon_argon2id_verify(encoded &char, password &char) int

// ── Hasher interface ──

// Hasher is the interface for password hashing drivers
pub interface Hasher {
	make(password string) string
	check(password string, hash string) bool
	needs_rehash(hash string) bool
}

// ── BcryptHasher (REAL bcrypt via V crypto.bcrypt) ──

// BcryptHasher implements Hasher using bcrypt via V's crypto.bcrypt.
// Output format: $2a$<cost>$<22-char-salt><31-char-hash> (standard bcrypt)
pub struct BcryptHasher {
pub:
	rounds int = 12
}

// make hashes the given password using bcrypt.
// Output format: $2a$<cost>$<22-char-salt><31-char-hash>
pub fn (h &BcryptHasher) make(password string) string {
	cost := if h.rounds < bcrypt.min_cost {
		bcrypt.default_cost
	} else if h.rounds > bcrypt.max_cost {
		bcrypt.max_cost
	} else {
		h.rounds
	}
	return bcrypt.generate_from_password(password.bytes(), cost) or {
		// Fallback: should not happen with valid input
		''
	}
}

// check verifies a password against a bcrypt hash.
// Detects old PBKDF2-SHA256 hashes ($2y$ prefix with hex hash) for migration.
pub fn (h &BcryptHasher) check(password string, hash string) bool {
	if hash == '' {
		return false
	}
	// Detect old PBKDF2-SHA256 format: $2y$ prefix + ~90 chars (hex hash)
	if is_old_bcrypt_hash(hash) {
		return check_old_hash(password, hash)
	}
	// Real bcrypt verify
	bcrypt.compare_hash_and_password(password.bytes(), hash.bytes()) or { return false }
	return true
}

// needs_rehash checks if the hash needs to be rehashed.
// Old-format hashes always need rehash. New-format checks cost parameter.
pub fn (h &BcryptHasher) needs_rehash(hash string) bool {
	if hash == '' {
		return true
	}
	// Old format always needs rehash
	if is_old_bcrypt_hash(hash) {
		return true
	}
	// Real bcrypt — extract cost and compare
	parts := hash.split('\$')
	if parts.len < 3 {
		return true
	}
	cost := parts[2].int()
	return cost != h.rounds
}

// ── Argon2Hasher (REAL argon2id via libargon2) ──

// Argon2Hasher implements Hasher using argon2id via libargon2.
// Output format: $argon2id$v=19$m=<mem>,t=<time>,p=<threads>$<salt>$<hash>
// (standard PHC string format produced by libargon2)
pub struct Argon2Hasher {
pub:
	memory  int = 65536 // KB
	time    int = 4     // iterations (t_cost)
	threads int = 1     // parallelism
}

// make hashes the password using argon2id.
// Uses libargon2 for real argon2id key derivation.
pub fn (h &Argon2Hasher) make(password string) string {
	// Generate a 16-byte random salt
	salt := generate_salt(16)
	mut encoded_buf := [u8(0)].repeat(256)
	encoded_buf[0] = u8(0) // ensure null-terminated

	ret := C.photon_argon2id_hash(
		password.str,
		salt.str,
		u32(h.time),
		u32(h.memory),
		u32(h.threads),
		&char(encoded_buf.data),
		usize(encoded_buf.len),
	)
	if ret != 0 {
		// argon2id hash failed — return empty (caller should handle)
		return ''
	}
	// Convert C string to V string
	return unsafe { cstring_to_vstring(&char(encoded_buf.data)) }
}

// check verifies a password against an argon2id hash.
// Detects old PBKDF2-SHA256 hashes (hex-encoded salt/hash) for migration.
pub fn (h &Argon2Hasher) check(password string, hash string) bool {
	if hash == '' {
		return false
	}
	// Try real argon2id verify first
	ret := C.photon_argon2id_verify(hash.str, password.str)
	if ret == 0 {
		return true
	}
	// If real verify failed, try old PBKDF2-SHA256 format (for migration)
	if is_old_argon2_hash(hash) {
		return check_old_hash(password, hash)
	}
	return false
}

// needs_rehash checks if the hash needs to be rehashed.
// Old-format hashes always need rehash. New-format compares parameters.
pub fn (h &Argon2Hasher) needs_rehash(hash string) bool {
	if hash == '' {
		return true
	}
	// Old format always needs rehash
	if is_old_argon2_hash(hash) {
		return true
	}
	// Real argon2id — check if parameters match
	parts := hash.split('\$')
	if parts.len < 6 {
		return true
	}
	default_mem := h.memory.str()
	default_time := h.time.str()
	default_threads := h.threads.str()
	return !parts[3].contains('m=${default_mem}') || !parts[3].contains('t=${default_time}')
		|| !parts[3].contains('p=${default_threads}')
}

// ── Migration helpers — detect old PBKDF2-SHA256 hashes ──

// is_old_bcrypt_hash returns true if the hash was produced by the old
// PBKDF2-SHA256 implementation (format: $2y$<rounds>$<22-char salt><64-char hex hash>).
fn is_old_bcrypt_hash(hash string) bool {
	if !hash.starts_with('\$2y\$') {
		return false
	}
	parts := hash.split('\$')
	if parts.len < 4 {
		return false
	}
	// Old format: salt(22 chars) + hex hash(64 chars) = min 86 chars after prefix
	// Real bcrypt: salt(22 chars) + base64 hash(31 chars) = 53 chars after prefix
	// Use length check: old hashes are significantly longer
	return parts[3].len > 60
}

// is_old_argon2_hash returns true if the hash was produced by the old
// PBKDF2-SHA256 implementation (hex-encoded salt and hash),
// by checking if the salt/hash sections contain hex-only characters.
fn is_old_argon2_hash(hash string) bool {
	if !hash.starts_with('\$argon2id\$') {
		return false
	}
	parts := hash.split('\$')
	if parts.len < 6 {
		return false
	}
	salt := parts[4]
	// Standard libargon2 format uses base64-encoded salt (contains +/=)
	// Old format uses hex-encoded salt (only 0-9a-f)
	// If salt contains any base64-specific chars, it's real argon2
	if salt.contains('+') || salt.contains('/') || salt.contains('=') {
		return false
	}
	// If salt is hex-only and has no base64 special chars, it's likely old format
	return salt.len >= 16 && salt.len <= 64
		&& salt.bytes().all(it in '0123456789abcdefABCDEF'.bytes())
}

// ── Old format verification (for backward-compatible migration) ──

// check_old_hash verifies a password against an old PBKDF2-SHA256 hash.
// Used during migration period to support existing password hashes.
fn check_old_hash(password string, hash string) bool {
	parts := hash.split('\$')
	if parts.len < 4 {
		return false
	}
	// Extract salt from old format
	mut salt := ''
	mut expected_idx := 3
	if hash.starts_with('\$argon2id\$') {
		// Old argon2 format: $argon2id$v=19$params$<salt>$<hash>
		if parts.len < 6 {
			return false
		}
		salt = parts[4]
		expected_idx = 5
	} else {
		// Old bcrypt format: $2y$<rounds>$<salt><hash>
		salt = parts[3][..if parts[3].len >= 22 { 22 } else { parts[3].len }]
	}
	if salt == '' {
		return false
	}
	// Re-derive hash using old PBKDF2-SHA256 path
	// The old format uses hash_string which applies *1000 multiplier
	extra := u64(parts[2].int())
	expected_hash := hash_string(password, salt, extra)
	return hash.ends_with(expected_hash)
}

// ── Internal helpers ──

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

// hash_string derives a key from password+salt using PBKDF2-SHA256.
// Kept for backward-compatible verification of old-format hashes.
// ⚠️ INTERNAL USE ONLY — new passwords use real bcrypt/argon2.
@[inline]
fn hash_string(password string, salt string, extra u64) string {
	// PBKDF2-SHA256 with iterations derived from extra (rounds * 1000)
	iterations := if extra > 0 { int(extra) * 1000 } else { 10000 }
	// Ensure minimum iterations for security; cap to bound latency
	safe_iterations := if iterations < 1000 {
		1000
	} else if iterations > 50000 {
		50000
	} else {
		iterations
	}
	derived := pbkdf2.key(password.bytes(), salt.bytes(), safe_iterations, 32, sha256.new()) or {
		[]u8{}
	}
	return derived.map(it.hex()).join('')
}

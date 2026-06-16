module security

// hashing_test.v - Tests for BcryptHasher and Argon2Hasher

fn test_bcrypt_hasher_new() {
	h := BcryptHasher{}
	assert h.rounds == 12
}

fn test_bcrypt_make_format() {
	h := BcryptHasher{
		rounds: 10
	}
	hash := h.make('password123')
	assert hash.starts_with('\$2y\$')
	assert hash.contains('\$')
	assert hash.len > 0
}

fn test_bcrypt_check_valid() {
	h := BcryptHasher{
		rounds: 10
	}
	hash := h.make('mypassword')
	assert h.check('mypassword', hash)
}

fn test_bcrypt_check_invalid() {
	h := BcryptHasher{
		rounds: 10
	}
	hash := h.make('correct')
	assert h.check('wrong', hash) == false
}

fn test_bcrypt_needs_rehash() {
	h := BcryptHasher{
		rounds: 10
	}
	hash := h.make('test')
	// Should not need rehash — rounds match
	assert h.needs_rehash(hash) == false

	// Different rounds should need rehash
	h2 := BcryptHasher{
		rounds: 14
	}
	assert h2.needs_rehash(hash) == true
}

fn test_bcrypt_different_salts() {
	h := BcryptHasher{
		rounds: 10
	}
	h1 := h.make('password')
	h2 := h.make('password')
	// Same password produces different hashes with random salt
	assert h1 != h2
	// Both verify correctly
	assert h.check('password', h1)
	assert h.check('password', h2)
}

fn test_bcrypt_consistent_check() {
	h := BcryptHasher{
		rounds: 12
	}
	passwords := ['alpha', 'beta123', 'gamma!@#', 'delta_test']
	for pw in passwords {
		hash := h.make(pw)
		assert h.check(pw, hash)
		assert h.check('wrong', hash) == false
	}
}

fn test_argon2_hasher_new() {
	h := Argon2Hasher{}
	assert h.memory == 65536
	assert h.time == 4
	assert h.threads == 1
}

fn test_argon2_make_format() {
	h := Argon2Hasher{}
	hash := h.make('password123')
	assert hash.starts_with('\$argon2id\$')
	assert hash.contains('\$m=')
	assert hash.len > 0
}

fn test_argon2_check_valid() {
	h := Argon2Hasher{}
	hash := h.make('securepass')
	assert h.check('securepass', hash)
}

fn test_argon2_check_invalid() {
	h := Argon2Hasher{}
	hash := h.make('correct')
	assert h.check('wrong', hash) == false
}

fn test_argon2_needs_rehash() {
	h := Argon2Hasher{
		time:   4
		memory: 65536
	}
	hash := h.make('test')
	// Same params → no rehash needed
	assert h.needs_rehash(hash) == false

	// Different params → rehash needed
	h2 := Argon2Hasher{
		time:   6
		memory: 131072
	}
	assert h2.needs_rehash(hash) == true
}

fn test_hasher_interface_compatible() {
	// Verify BcryptHasher and Argon2Hasher methods exist
	bh := BcryptHasher{
		rounds: 10
	}
	ah := Argon2Hasher{}

	bhash := bh.make('pw')
	ahash := ah.make('pw')

	assert bhash.len > 0
	assert ahash.len > 0
	assert bhash != ahash // different algorithms
}

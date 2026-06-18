module security

import encoding.hex

// ── AesCipher Tests ──

fn test_new_aes_cipher_valid_key() ! {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	assert cipher.key.len == 32
}

fn test_new_aes_cipher_invalid_key_short() {
	new_aes_cipher('short') or { return }
	assert false
}

fn test_new_aes_cipher_invalid_key_long() {
	new_aes_cipher('this-key-is-way-too-long-for-aes-256') or { return }
	assert false
}

fn test_aes_encrypt_decrypt_roundtrip() ! {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	original := 'Hello, World! This is a secret message.'
	encrypted := cipher.encrypt(original)!
	assert encrypted != original
	assert encrypted.len > 0

	decrypted := cipher.decrypt(encrypted)!
	assert decrypted == original
}

fn test_aes_encrypt_empty_string() ! {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	encrypted := cipher.encrypt('')!
	assert encrypted == ''
}

fn test_aes_decrypt_empty_string() ! {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	decrypted := cipher.decrypt('')!
	assert decrypted == ''
}

fn test_aes_encrypt_different_each_time() ! {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	encrypted1 := cipher.encrypt('same message')!
	encrypted2 := cipher.encrypt('same message')!
	// Due to random IV, encryptions should differ
	assert encrypted1 != encrypted2
}

fn test_aes_decrypt_tampered_payload() {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	encrypted := cipher.encrypt('secret') or { '' }
	if encrypted.len == 0 {
		return // empty string decrypts to empty, skip
	}
	// Tamper with the payload (change bytes in the middle)
	mut tampered_bytes := []u8{}
	for b in encrypted.bytes() {
		tampered_bytes << b
	}
	// Change some bytes in the middle of the base64 to corrupt the payload
	if tampered_bytes.len > 10 {
		tampered_bytes[5] = if tampered_bytes[5] == `A` { `B` } else { `A` }
		tampered_bytes[6] = if tampered_bytes[6] == `X` { `Y` } else { `X` }
	}
	tampered := tampered_bytes.bytestr()
	cipher.decrypt(tampered) or { return }
	assert false
}

fn test_aes_encrypt_special_characters() ! {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	original := 'Special chars: !@#\$%^&*()_+-=[]{}|;:\'",.<>?/`~中文🎉'
	encrypted := cipher.encrypt(original)!
	decrypted := cipher.decrypt(encrypted)!
	assert decrypted == original
}

// ── KeyDerivation Tests ──

fn test_new_key_derivation() {
	kd := new_key_derivation()
	assert kd.iterations == 10000
	assert kd.memory_kb == 65536
	assert kd.parallelism == 4
	assert kd.key_len == 32
	assert kd.salt_len == 16
}

fn test_key_derivation_derive_key() {
	kd := new_key_derivation()
	salt := kd.generate_salt()
	key1 := kd.derive_key('password123', salt)
	key2 := kd.derive_key('password123', salt)
	// Same password + salt should produce same key
	assert key1 == key2
}

fn test_key_derivation_different_passwords() {
	kd := new_key_derivation()
	salt := kd.generate_salt()
	key1 := kd.derive_key('password1', salt)
	key2 := kd.derive_key('password2', salt)
	// Different passwords should produce different keys
	assert key1 != key2
}

fn test_key_derivation_different_salts() {
	kd := new_key_derivation()
	salt1 := kd.generate_salt()
	salt2 := kd.generate_salt()
	key1 := kd.derive_key('same_password', salt1)
	key2 := kd.derive_key('same_password', salt2)
	// Different salts should produce different keys
	assert key1 != key2
}

fn test_key_derivation_generate_salt() {
	kd := new_key_derivation()
	salt1 := kd.generate_salt()
	salt2 := kd.generate_salt()
	// Salts should be unique
	assert salt1 != salt2
	// Salt should be hex-encoded
	assert salt1.len > 0
}

// ── SHA-512 Tests ──

fn test_sha512_hash() {
	hash := sha512_hash('hello')
	assert hash.len > 0
	// SHA-512 produces 64 bytes = 128 hex chars
	assert hash.len == 128
}

fn test_sha512_hash_different_inputs() {
	hash1 := sha512_hash('hello')
	hash2 := sha512_hash('world')
	assert hash1 != hash2
}

fn test_sha512_hash_with_salt() {
	hashed := sha512_hash_with_salt('password', 'randomsalt')
	plain := sha512_hash('password')
	assert hashed != plain
}

// ── PKCS7 Padding Tests (internal, tested through encrypt/decrypt) ──

fn test_aes_encrypt_long_message() ! {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	mut long_msg := ''
	for i in 0 .. 1000 {
		long_msg += 'A'
	}
	encrypted := cipher.encrypt(long_msg)!
	decrypted := cipher.decrypt(encrypted)!
	assert decrypted == long_msg
}

fn test_aes_encrypt_exact_block_size() ! {
	cipher := new_aes_cipher('12345678901234567890123456789012')!
	// 16 bytes = exactly one AES block
	msg := '0123456789abcdef'
	encrypted := cipher.encrypt(msg)!
	decrypted := cipher.decrypt(encrypted)!
	assert decrypted == msg
}

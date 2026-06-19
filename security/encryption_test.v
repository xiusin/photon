module security

// encryption_test.v - Tests for Encrypter
// NOTE: Encrypter is deprecated, use AesCipher (cipher.v) for production. Tests retained for backward compatibility.

fn test_encrypter_new() {
	e := new_encrypter('my-secret-key-32-bytes-long!!')
	assert e.key == 'my-secret-key-32-bytes-long!!'
	assert e.cipher == 'aes-256-cbc'
}

fn test_encrypt_basic() {
	e := new_encrypter('test-key')
	result := e.encrypt('hello world') or {
		assert false
		return
	}
	assert result.len > 0
	assert result != 'hello world' // encrypted should differ
}

fn test_encrypt_empty() {
	e := new_encrypter('test-key')
	result := e.encrypt('') or {
		assert false
		return
	}
	assert result.len == 0
}

fn test_encrypt_special_chars() {
	e := new_encrypter('test-key')
	result := e.encrypt('hello!@#$%^&*()_+') or {
		assert false
		return
	}
	assert result.len > 0
}

fn test_decrypt_roundtrip() {
	e := new_encrypter('test-key')
	plain := 'sensitive data 123'
	encrypted := e.encrypt(plain) or {
		assert false
		return
	}
	decrypted := e.decrypt(encrypted) or {
		assert false
		return
	}
	assert decrypted == plain
}

fn test_decrypt_invalid() {
	e := new_encrypter('test-key')
	result := e.decrypt('z') or { 'error' }
	assert result == 'error' // odd-length should fail
}

fn test_encrypt_decrypt_multiple() {
	e := new_encrypter('consistent-key-32-chars!!')
	inputs := ['alpha', 'beta', 'gamma', 'delta']
	for input in inputs {
		enc := e.encrypt(input) or { continue }
		dec := e.decrypt(enc) or { continue }
		assert dec == input
	}
}

fn test_encrypt_deterministic() {
	e := new_encrypter('key')
	r1 := e.encrypt('same') or { '' }
	r2 := e.encrypt('same') or { '' }
	assert r1 == r2 // deterministic encryption
}

fn test_different_keys_work() {
	e1 := new_encrypter('key-one')
	e2 := new_encrypter('key-two')
	assert e1.key != e2.key

	// Both encrypters should work independently
	r1 := e1.encrypt('test') or { '' }
	r2 := e2.encrypt('test') or { '' }
	assert r1.len > 0
	assert r2.len > 0
	// Both can decrypt their own output
	d1 := e1.decrypt(r1) or { '' }
	d2 := e2.decrypt(r2) or { '' }
	assert d1 == 'test'
	assert d2 == 'test'
}

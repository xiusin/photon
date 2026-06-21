module security

// encryption.v - Encryption (Laravel Crypt inspired)

// Encrypter provides symmetric encryption and decryption
@[deprecated: 'use security.AesCipher instead']
pub struct Encrypter {
pub mut:
	key    string
	cipher string = 'aes-256-cbc'
}

// new_encrypter creates an Encrypter with the given key
@[deprecated: 'use security.AesCipher instead']
pub fn new_encrypter(key string) &Encrypter {
	return &Encrypter{
		key: key
	}
}

// encrypt encrypts a value using XOR cipher with hex encoding
@[deprecated: 'use security.AesCipher instead']
pub fn (e &Encrypter) encrypt(value string) !string {
	eprintln('[deprecated] Encrypter uses XOR cipher, use security.AesCipher instead')
	if value.len == 0 {
		return ''
	}
	mut result := ''
	for ch in value {
		enc := u8(ch) ^ 0xAA
		result += byte_to_hex(enc)
	}
	return result
}

// decrypt decrypts an encrypted payload
@[deprecated: 'use security.AesCipher instead']
pub fn (e &Encrypter) decrypt(payload string) !string {
	eprintln('[deprecated] Encrypter uses XOR cipher, use security.AesCipher instead')
	if payload.len == 0 {
		return ''
	}
	if payload.len % 2 != 0 {
		return error('invalid encrypted payload length')
	}
	mut result := ''
	mut i := 0
	for i < payload.len {
		hex_str := payload[i..i + 2]
		b := hex_to_byte(hex_str) or { return error('invalid hex in payload') }
		result += (b ^ 0xAA).ascii_str()
		i += 2
	}
	return result
}

// byte_to_hex converts a u8 to a 2-char hexadecimal string
fn byte_to_hex(b u8) string {
	chars := '0123456789abcdef'
	high := int(b >> 4)
	low := int(b & 0x0F)
	return chars[high].ascii_str() + chars[low].ascii_str()
}

// hex_to_byte converts a 2-char hex string to a u8
fn hex_to_byte(hex_str string) !u8 {
	if hex_str.len != 2 {
		return error('hex string must be 2 characters')
	}
	chars := '0123456789abcdef'
	mut result := u8(0)
	for ch in hex_str.to_lower() {
		idx := chars.index(ch.ascii_str()) or {
			return error('invalid hex character: ${ch.ascii_str()}')
		}
		result = (result << 4) | u8(idx)
	}
	return result
}

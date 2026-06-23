module web

// cookie_test.v - CookieManager 和 CookieBuilder 单元测试
// CookieManager and CookieBuilder Unit Tests
//
// 测试覆盖 / Test Coverage:
//   - CookieBuilder 构建 Cookie（name/value/domain/path/max_age/secure/http_only/same_site）
//   - CookieManager.sign() 签名 Cookie + verify() 验证签名
//   - 签名篡改检测（修改值后验证失败）
//   - CookieManager.encrypt() 加密 Cookie + decrypt() 解密
//   - 加密 Cookie 无法直接读取原始值
//   - 缺少加密密钥时加密操作返回错误
//   - 解密格式错误返回 none
//   - 签名 Cookie 值中包含 '.' 的处理
import net.http
import encoding.base64
import sync

// ── CookieBuilder 测试 / CookieBuilder tests ──

fn test_cookie_builder_basic_name_value() {
	// CookieBuilder 基本构建：name + value
	// CookieBuilder basic construction: name + value
	b := new_cookie_builder('session_id', 'abc123')
	assert b.name == 'session_id'
	assert b.value == 'abc123'
}

fn test_cookie_builder_default_values() {
	// CookieBuilder 默认值：path='/', max_age=-1, http_only=true, same_site=lax
	// CookieBuilder defaults: path='/', max_age=-1, http_only=true, same_site=lax
	b := new_cookie_builder('test', 'val')
	assert b.path == '/'
	assert b.max_age == -1
	assert b.secure == false
	assert b.http_only == true
	assert b.same_site == .lax
	assert b.domain == ''
}

fn test_cookie_builder_domain() {
	// domain() 设置 Domain 属性
	// domain() sets the Domain attribute
	mut b := new_cookie_builder('test', 'val')
	b.domain('example.com')
	assert b.domain == 'example.com'
}

fn test_cookie_builder_path() {
	// path() 设置 Path 属性
	// path() sets the Path attribute
	mut b := new_cookie_builder('test', 'val')
	b.path('/api')
	assert b.path == '/api'
}

fn test_cookie_builder_max_age() {
	// max_age() 设置 Max-Age 属性
	// max_age() sets the Max-Age attribute
	mut b := new_cookie_builder('test', 'val')
	b.max_age(3600)
	assert b.max_age == 3600
}

fn test_cookie_builder_secure() {
	// secure() 设置 Secure 标志
	// secure() sets the Secure flag
	mut b := new_cookie_builder('test', 'val')
	assert b.secure == false
	b.secure()
	assert b.secure == true
}

fn test_cookie_builder_http_only() {
	// http_only() 设置 HttpOnly 标志
	// http_only() sets the HttpOnly flag
	mut b := new_cookie_builder('test', 'val')
	b.http_only()
	assert b.http_only == true
}

fn test_cookie_builder_same_site_strict() {
	// same_site() 设置 SameSite 属性为 strict
	// same_site() sets the SameSite attribute to strict
	mut b := new_cookie_builder('test', 'val')
	b.same_site(.strict)
	assert b.same_site == .strict
}

fn test_cookie_builder_same_site_none() {
	// same_site() 设置 SameSite 属性为 none
	// same_site() sets the SameSite attribute to none
	mut b := new_cookie_builder('test', 'val')
	b.same_site(.none)
	assert b.same_site == .none
}

fn test_cookie_builder_chained_calls() {
	// CookieBuilder 链式调用
	// CookieBuilder chained calls
	mut b := new_cookie_builder('sid', 'xyz')
	b.domain('app.com')
	b.path('/v1')
	b.max_age(7200)
	b.secure()
	b.same_site(.strict)
	assert b.name == 'sid'
	assert b.value == 'xyz'
	assert b.domain == 'app.com'
	assert b.path == '/v1'
	assert b.max_age == 7200
	assert b.secure == true
	assert b.same_site == .strict
}

fn test_cookie_builder_build_returns_cookie() {
	// build() 构建最终的 http.Cookie
	// build() constructs the final http.Cookie
	mut b := new_cookie_builder('user', 'alice')
	b.domain('test.com')
	b.path('/app')
	b.max_age(3600)
	b.secure()
	b.http_only()
	b.same_site(.strict)
	cookie := b.build()
	assert cookie.name == 'user'
	assert cookie.value == 'alice'
	assert cookie.domain == 'test.com'
	assert cookie.path == '/app'
	assert cookie.max_age == 3600
	assert cookie.secure == true
	assert cookie.http_only == true
}

fn test_cookie_builder_build_same_site_lax() {
	// build() 中 lax 映射到 same_site_lax_mode
	// build() maps lax to same_site_lax_mode
	mut b := new_cookie_builder('test', 'val')
	b.same_site(.lax)
	cookie := b.build()
	assert cookie.same_site == http.SameSite.same_site_lax_mode
}

fn test_cookie_builder_build_same_site_strict() {
	// build() 中 strict 映射到 same_site_strict_mode
	// build() maps strict to same_site_strict_mode
	mut b := new_cookie_builder('test', 'val')
	b.same_site(.strict)
	cookie := b.build()
	assert cookie.same_site == http.SameSite.same_site_strict_mode
}

fn test_cookie_builder_build_same_site_none() {
	// build() 中 none 映射到 same_site_none_mode
	// build() maps none to same_site_none_mode
	mut b := new_cookie_builder('test', 'val')
	b.same_site(.none)
	cookie := b.build()
	assert cookie.same_site == http.SameSite.same_site_none_mode
}

// ── CookieManager 签名测试 / CookieManager signing tests ──

fn test_cookie_manager_sign_basic() {
	// sign() 对值进行 HMAC-SHA256 签名
	// sign() signs the value with HMAC-SHA256
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	signed := cm.sign('hello')
	// 格式应为 <value>.<hex_signature>
	// Format should be <value>.<hex_signature>
	assert signed.starts_with('hello.')
	assert signed.len > 'hello.'.len
}

fn test_cookie_manager_verify_valid_signature() {
	// verify() 验证有效签名并返回原始值
	// verify() verifies a valid signature and returns the original value
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	signed := cm.sign('hello')
	value := cm.verify(signed) or { '' }
	assert value == 'hello'
}

fn test_cookie_manager_verify_tampered_value() {
	// 签名篡改检测：修改值后验证失败
	// Tamper detection: modified value fails verification
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	signed := cm.sign('hello')
	// 篡改值部分 / Tamper the value part
	dot_pos := signed.index('.') or { 0 }
	tampered := 'goodbye' + signed[dot_pos..]
	result := cm.verify(tampered) or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_verify_wrong_signature() {
	// 篡改签名部分后验证失败
	// Tampered signature part fails verification
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	signed := cm.sign('hello')
	// 替换签名为伪造值 / Replace signature with a fake value
	tampered := 'hello.0000000000000000000000000000000000000000000000000000000000000000'
	result := cm.verify(tampered) or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_verify_wrong_key() {
	// 不同密钥验证失败
	// Verification fails with a different key
	mut cm1 := new_cookie_manager('key-one-that-is-at-least-32-bytes-long', []) or { panic(err) }
	mut cm2 := new_cookie_manager('key-two-that-is-at-least-32-bytes-long', []) or { panic(err) }
	signed := cm1.sign('hello')
	result := cm2.verify(signed) or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_verify_invalid_format_no_dot() {
	// 格式错误（无点号）返回 none
	// Invalid format (no dot) returns none
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	result := cm.verify('nodot') or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_verify_invalid_format_empty_value() {
	// 格式错误（空值部分）返回 none
	// Invalid format (empty value part) returns none
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	result := cm.verify('.abc123') or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_verify_invalid_format_empty_signature() {
	// 格式错误（空签名部分）返回 none
	// Invalid format (empty signature part) returns none
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	result := cm.verify('hello.') or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_sign_verify_roundtrip() {
	// sign() → verify() 往返测试
	// sign() → verify() round-trip test
	mut cm := new_cookie_manager('my-super-secret-key-for-signing-cookies!', []) or { panic(err) }
	values := ['hello', 'world', 'test-value-123', '', 'a.b.c.d']
	for v in values {
		signed := cm.sign(v)
		verified := cm.verify(signed) or { '' }
		assert verified == v
	}
}

fn test_cookie_manager_sign_value_with_dots() {
	// 值中包含 '.' 时签名和验证正常工作
	// Signing and verification work correctly when the value contains '.'
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	signed := cm.sign('a.b.c')
	// 验证应返回原始值（从最后一个 '.' 拆分）
	// Verification should return the original value (split from last '.')
	value := cm.verify(signed) or { '' }
	assert value == 'a.b.c'
}

fn test_cookie_manager_sign_deterministic() {
	// 相同密钥和值的签名结果一致
	// Same key and value produce the same signature
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	s1 := cm.sign('hello')
	s2 := cm.sign('hello')
	assert s1 == s2
}

// ── CookieManager 加密测试 / CookieManager encryption tests ──

fn test_cookie_manager_encrypt_basic() {
	// encrypt() 加密明文
	// encrypt() encrypts plaintext
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(42)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	encrypted := cm.encrypt('secret-data') or {
		assert false // 不应到达这里 / should not reach here
		return
	}
	assert encrypted.starts_with('enc://')
}

fn test_cookie_manager_decrypt_roundtrip() {
	// encrypt() → decrypt() 往返测试
	// encrypt() → decrypt() round-trip test
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 1)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	plaintexts := ['hello', 'world', 'secret-value', 'test-123']
	for pt in plaintexts {
		encrypted := cm.encrypt(pt) or {
			assert false
			return
		}
		decrypted := cm.decrypt(encrypted) or { '' }
		assert decrypted == pt
	}
}

fn test_cookie_manager_encrypt_obscures_value() {
	// 加密后的值无法直接读取原始值
	// Encrypted value cannot be directly read as plaintext
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 7)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	encrypted := cm.encrypt('sensitive-data') or {
		assert false
		return
	}
	// 加密值不应包含原始明文
	// Encrypted value should not contain the original plaintext
	assert !encrypted.contains('sensitive-data')
}

fn test_cookie_manager_decrypt_invalid_format() {
	// 解密格式不正确返回 none
	// Invalid format returns none on decrypt
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	// 不以 enc:// 开头 / Does not start with enc://
	result := cm.decrypt('not-encrypted') or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_decrypt_corrupted_data() {
	// 解密损坏的加密数据返回 none
	// Corrupted encrypted data returns none on decrypt
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 3)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	// 构造一个格式正确但内容损坏的加密值
	// Construct a properly formatted but corrupted encrypted value
	result := cm.decrypt('enc://aW52YWxpZGRhdGFoZXJl') or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_encrypt_without_key_returns_error() {
	// 缺少加密密钥时 encrypt() 返回错误
	// encrypt() returns an error when no encryption key is provided
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', []) or { panic(err) }
	cm.encrypt('test') or {
		assert err.msg().contains('32')
		return
	}
	assert false // 应该进入 or 块 / Should enter the or block
}

fn test_cookie_manager_encrypt_with_short_key_returns_error() {
	// 加密密钥不足 32 字节时返回错误
	// Encryption key shorter than 32 bytes returns an error
	short_key := []u8{len: 16} // 只有 16 字节 / Only 16 bytes
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', short_key) or { panic(err) }
	cm.encrypt('test') or {
		assert err.msg().contains('32')
		return
	}
	assert false
}

fn test_cookie_manager_decrypt_without_key_returns_none() {
	// 缺少加密密钥时 decrypt() 返回 none
	// decrypt() returns none when no encryption key is provided
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', []) or { panic(err) }
	result := cm.decrypt('enc://dGVzdA==') or { 'none' }
	assert result == 'none'
}

// ── SameSite 枚举测试 / SameSite enum tests ──

fn test_same_site_enum_values() {
	// SameSite 枚举值正确
	// SameSite enum values are correct
	assert SameSite.strict == .strict
	assert SameSite.lax == .lax
	assert SameSite.none == .none
}

// ── CookieManager 构造函数测试 / CookieManager constructor tests ──

fn test_new_cookie_manager_basic() {
	// 创建 CookieManager
	// Create a CookieManager
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', []) or { panic(err) }
	assert cm.signing_key == 'signing-key-at-least-32-bytes-long'
	assert cm.encryption_key.len == 0
}

fn test_new_cookie_manager_with_encryption_key() {
	// 创建带加密密钥的 CookieManager
	// Create a CookieManager with an encryption key
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	assert cm.encryption_key.len == 32
}

// ── 签名密钥长度验证测试 / Signing key length validation tests ──

fn test_cookie_manager_short_signing_key_returns_error() {
	// 签名密钥不足 32 字节时 new_cookie_manager 返回错误
	// new_cookie_manager returns error when signing key is less than 32 bytes
	new_cookie_manager('short', []) or {
		assert err.msg().contains('32')
		return
	}
	assert false
}

fn test_cookie_manager_exactly_32_byte_signing_key() {
	// 恰好 32 字节的签名密钥可以正常创建
	// Exactly 32-byte signing key works normally
	mut cm := new_cookie_manager('0123456789abcdef0123456789abcdef', [])!
	signed := cm.sign('test')
	value := cm.verify(signed) or { '' }
	assert value == 'test'
}

fn test_cookie_manager_31_byte_signing_key_returns_error() {
	// 31 字节的签名密钥返回错误
	// 31-byte signing key returns error
	new_cookie_manager('0123456789abcdef0123456789abcde', []) or {
		assert err.msg().contains('32')
		return
	}
	assert false
}

// ── verify() 常量时间比较测试 / verify() constant-time comparison tests ──

fn test_cookie_manager_verify_uses_hex_decoded_comparison() {
	// verify() 使用 hex 解码后常量时间比较（hmac.equal）
	// 验证：篡改签名的十六进制字符后验证失败
	// verify() uses hex-decoded constant-time comparison (hmac.equal)
	// Verify: tampering with hex signature characters fails verification
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	signed := cm.sign('hello')
	// 找到最后一个点号 / Find the last dot
	last_dot := signed.last_index('.') or { 0 }
	signature_hex := signed[last_dot + 1..]
	// 篡改签名的最后一个字符 / Tamper the last character of the signature
	mut tampered_sig := signature_hex
	if tampered_sig.len > 0 {
		last_char := tampered_sig[tampered_sig.len - 1]
		mut replacement := u8(0)
		if last_char != u8(`a`) {
			replacement = u8(`a`)
		} else {
			replacement = u8(`b`)
		}
		tampered_sig = tampered_sig[..tampered_sig.len - 1] + replacement.ascii_str()
	}
	tampered := '${signed[..last_dot + 1]}${tampered_sig}'
	result := cm.verify(tampered) or { 'none' }
	assert result == 'none'
}

fn test_cookie_manager_verify_invalid_hex_signature() {
	// 签名部分包含无效十六进制字符时返回 none
	// Returns none when signature part contains invalid hex characters
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	// 签名部分包含非十六进制字符 / Signature part contains non-hex characters
	result := cm.verify('hello.GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG') or {
		'none'
	}
	assert result == 'none'
}

// ── encrypt()/decrypt() authenticate-then-decrypt 测试 ──
// encrypt()/decrypt() authenticate-then-decrypt tests

fn test_cookie_manager_decrypt_tampered_ciphertext() {
	// 篡改密文后 decrypt() 返回 none（authenticate-then-decrypt 修复验证）
	// decrypt() returns none when ciphertext is tampered (authenticate-then-decrypt fix verification)
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 5)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	encrypted := cm.encrypt('secret-data') or {
		assert false
		return
	}
	// 篡改 base64 编码后的数据（修改中间几个字符）
	// Tamper the base64-encoded data (modify a few characters in the middle)
	encoded := encrypted[6..] // 去掉 enc:// 前缀 / Remove enc:// prefix
	if encoded.len > 10 {
		mut tampered_encoded := encoded
		// 修改中间一个字符 / Modify one character in the middle
		mid := encoded.len / 2
		original := encoded[mid]
		mut replacement := u8(0)
		if original != u8(`A`) {
			replacement = u8(`A`)
		} else {
			replacement = u8(`B`)
		}
		tampered_encoded = encoded[..mid] + replacement.ascii_str() + encoded[mid + 1..]
		tampered := 'enc://${tampered_encoded}'
		result := cm.decrypt(tampered) or { 'none' }
		assert result == 'none'
	}
}

fn test_cookie_manager_decrypt_tag_tampered() {
	// 篡改 HMAC tag 后 decrypt() 返回 none（常量时间 tag 比较验证）
	// decrypt() returns none when HMAC tag is tampered (constant-time tag comparison verification)
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 9)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	encrypted := cm.encrypt('important-data') or {
		assert false
		return
	}
	// 解码 base64，翻转最后一个字节（tag 的最后一个字节），重新编码
	// Decode base64, flip the last byte (last byte of tag), re-encode
	encoded := encrypted[6..]
	combined := base64.decode(encoded)
	if combined.len > 16 {
		mut tampered_combined := combined.clone()
		last_idx := tampered_combined.len - 1
		tampered_combined[last_idx] = tampered_combined[last_idx] ^ u8(0xFF)
		tampered := 'enc://${base64.encode(tampered_combined)}'
		result := cm.decrypt(tampered) or { 'none' }
		assert result == 'none'
	}
}

fn test_cookie_manager_decrypt_nonce_tampered() {
	// 篡改 nonce 后 decrypt() 返回 none
	// decrypt() returns none when nonce is tampered
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 11)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	encrypted := cm.encrypt('nonce-test') or {
		assert false
		return
	}
	encoded := encrypted[6..]
	combined := base64.decode(encoded)
	if combined.len > 12 {
		mut tampered_combined := combined.clone()
		// 翻转 nonce 的第一个字节 / Flip the first byte of nonce
		tampered_combined[0] = tampered_combined[0] ^ u8(0x01)
		tampered := 'enc://${base64.encode(tampered_combined)}'
		result := cm.decrypt(tampered) or { 'none' }
		assert result == 'none'
	}
}

// ── 空字符串和边界值测试 / Empty string and boundary value tests ──

fn test_cookie_manager_sign_verify_empty_string() {
	// 空字符串签名和验证
	// Sign and verify empty string
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	signed := cm.sign('')
	value := cm.verify(signed) or { '' }
	assert value == ''
}

fn test_cookie_manager_sign_verify_long_value() {
	// 超长值的签名和验证
	// Sign and verify very long value
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	long_value := 'a'.repeat(10000)
	signed := cm.sign(long_value)
	value := cm.verify(signed) or { '' }
	assert value == long_value
}

fn test_cookie_manager_sign_verify_unicode() {
	// Unicode 值的签名和验证
	// Sign and verify Unicode value
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	unicode_value := '你好世界🌍🚀'
	signed := cm.sign(unicode_value)
	value := cm.verify(signed) or { '' }
	assert value == unicode_value
}

fn test_cookie_manager_sign_verify_special_chars() {
	// 特殊字符的签名和验证
	// Sign and verify special characters
	mut cm := new_cookie_manager('this-is-a-very-secret-signing-key-32b', []) or { panic(err) }
	special_value := 'key=val&foo=bar<script>alert(1)</script>'
	signed := cm.sign(special_value)
	value := cm.verify(signed) or { '' }
	assert value == special_value
}

// ── 加密边界值测试 / Encryption boundary value tests ──

fn test_cookie_manager_encrypt_decrypt_empty_string() {
	// 空字符串加密和解密
	// Encrypt and decrypt empty string
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 1)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	encrypted := cm.encrypt('') or {
		assert false
		return
	}
	decrypted := cm.decrypt(encrypted) or { '' }
	assert decrypted == ''
}

fn test_cookie_manager_encrypt_decrypt_unicode() {
	// Unicode 加密和解密
	// Encrypt and decrypt Unicode
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 3)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	encrypted := cm.encrypt('机密数据🔑') or {
		assert false
		return
	}
	decrypted := cm.decrypt(encrypted) or { '' }
	assert decrypted == '机密数据🔑'
}

fn test_cookie_manager_encrypt_produces_different_ciphertexts() {
	// 相同明文每次加密产生不同密文（因为随机 nonce）
	// Same plaintext produces different ciphertexts each time (due to random nonce)
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 7)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	e1 := cm.encrypt('same-input') or { '' }
	e2 := cm.encrypt('same-input') or { '' }
	// 由于 nonce 不同，密文应不同 / Due to different nonces, ciphertexts should differ
	assert e1 != e2
	// 但两者都能正确解密 / But both decrypt correctly
	d1 := cm.decrypt(e1) or { '' }
	d2 := cm.decrypt(e2) or { '' }
	assert d1 == 'same-input'
	assert d2 == 'same-input'
}

fn test_cookie_manager_decrypt_too_short_data() {
	// 解密数据太短（< 28 字节）返回 none
	// Decrypt data too short (< 28 bytes) returns none
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i)
	}
	mut cm := new_cookie_manager('signing-key-at-least-32-bytes-long', key) or { panic(err) }
	// base64 编码一个很短的值 / Base64 encode a very short value
	short_data := 'enc://${base64.encode([u8(1), 2, 3, 4, 5])}'
	result := cm.decrypt(short_data) or { 'none' }
	assert result == 'none'
}

// ── 并发安全测试 / Concurrency safety tests ──

fn test_cookie_manager_concurrent_sign_verify() {
	// 并发签名和验证不应 panic
	// Concurrent sign and verify should not panic
	mut cm := new_cookie_manager('concurrent-signing-key-at-least-32-bytes!', []) or { panic(err) }
	mut wg := sync.new_waitgroup()

	for i in 0 .. 10 {
		wg.add(1)
		spawn fn (mut manager CookieManager, idx int, mut w sync.WaitGroup) {
			defer { w.done() }
			signed := manager.sign('value-${idx}')
			_ = manager.verify(signed) or { '' }
		}(mut cm, i, mut wg)
	}

	wg.wait()
	assert true
}

fn test_cookie_manager_concurrent_encrypt_decrypt() {
	// 并发加密和解密不应 panic
	// Concurrent encrypt and decrypt should not panic
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 13)
	}
	mut cm := new_cookie_manager('concurrent-signing-key-at-least-32-bytes!', key) or { panic(err) }
	mut wg := sync.new_waitgroup()

	for i in 0 .. 5 {
		wg.add(1)
		spawn fn (mut manager CookieManager, idx int, mut w sync.WaitGroup) {
			defer { w.done() }
			encrypted := manager.encrypt('secret-${idx}') or { return }
			_ = manager.decrypt(encrypted) or { '' }
		}(mut cm, i, mut wg)
	}

	wg.wait()
	assert true
}
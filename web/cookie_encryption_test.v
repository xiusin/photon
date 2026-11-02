// cookie_encryption_test.v — 加密 Cookie 必须是真的加密
//
// 旧实现是 XOR + HMAC：完整性有，机密性没有。同一密钥流反复使用，
// 两份密文异或就能看出明文之间的关系。这里断言的是密码学性质，
// 不是「函数返回了一个字符串」。
module web

import encoding.base64



fn new_test_cookie_manager() &CookieManager {
	key := crypto_rand_bytes(32)
	return new_cookie_manager('0123456789abcdef0123456789abcdef', key) or {
		panic('manager: ${err}')
	}
}

fn test_encrypt_decrypt_roundtrip() {
	mut cm := new_test_cookie_manager()
	for plain in ['', 'hello', '中文会话数据', 'a'.repeat(200)] {
		enc := cm.encrypt(plain)!
		assert enc.starts_with('enc://')
		assert enc != 'enc://' + plain
		assert cm.decrypt(enc)? == plain
	}
}

fn test_ciphertext_is_not_a_plaintext_permutation() {
	mut cm := new_test_cookie_manager()
	// 32 个相同字节。XOR 混淆只会把它变成「同一段密钥流重复几次」：
	// 密文里 12 字节的窗口反复出现。AES-GCM 的密文是均匀随机的，
	// 几乎不可能出现两个相同的窗口。窗口数由密文长度决定，随机数据下
	// 重复数为 0，这里放宽到 1 也给哈希碰撞留余量。
	plain := 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
	enc := cm.encrypt(plain)!
	raw := base64.decode(enc[6..])
	mut seen := map[string]int{}
	mut duplicates := 0
	mut windows := 0
	mut offset := 12 // skip nonce
	for offset + 12 <= raw.len - 16 { // skip trailing tag
		chunk := raw[offset..offset + 12].bytestr()
		count := seen[chunk] or { 0 }
		if count > 0 {
			duplicates++
		}
		seen[chunk] = count + 1
		windows++
		offset++
	}
	assert windows > 0
	assert duplicates == 0, '${duplicates}/${windows} repeating windows — ciphertext is not randomized'
	assert cm.decrypt(enc)? == plain
}

fn test_encrypt_uses_fresh_nonce() {
	mut cm := new_test_cookie_manager()
	a := cm.encrypt('same')!
	b := cm.encrypt('same')!
	assert a != b
	assert cm.decrypt(a)? == 'same'
	assert cm.decrypt(b)? == 'same'
}

fn test_tampered_ciphertext_is_rejected() {
	mut cm := new_test_cookie_manager()
	enc := cm.encrypt('sensitive')!
	mut bytes := enc.bytes()
	// 改密文里的一个字节：GCM 的认证标签必须拒绝它
	idx := bytes.len - 8
	bytes[idx] = if bytes[idx] == `A` { `B` } else { `A` }
	tampered := bytes.bytestr()
	assert cm.decrypt(tampered) == none
}

fn test_wrong_key_cannot_decrypt() {
	mut cm := new_test_cookie_manager()
	enc := cm.encrypt('secret')!
	key := crypto_rand_bytes(32)
	mut other := new_cookie_manager('ffffffffffffffffffffffffffffffff', key) or {
		panic('manager: ${err}')
	}
	assert other.decrypt(enc) == none
}

fn test_malformed_input_returns_none() {
	mut cm := new_test_cookie_manager()
	assert cm.decrypt('plain') == none
	assert cm.decrypt('enc://') == none
	assert cm.decrypt('enc://AAAA') == none
}

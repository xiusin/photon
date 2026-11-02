module web

// cookie.v - Cookie 增强（签名/加密/Builder）
//
// Cookie Enhancement: signed cookies (HMAC-SHA256), encrypted cookies (AES-256-GCM),
// and a fluent CookieBuilder API.
//
// Cookie 增强：签名 Cookie（HMAC-SHA256）、加密 Cookie（AES-256-GCM）
// 以及 Fluent API 的 CookieBuilder。
import veb
import net.http
import crypto.aes
import crypto.sha256
import crypto.hmac
import crypto.rand as crand
import encoding.hex
import encoding.base64
import sync

// ── SameSite 枚举 / SameSite Enum ──

// SameSite defines the SameSite attribute for cookies.
// SameSite 定义 Cookie 的 SameSite 属性。
pub enum SameSite {
	strict
	lax
	none
}

// ── CookieBuilder / Cookie Builder ──

// CookieBuilder provides a fluent API for constructing http.Cookie.
// CookieBuilder 提供 Fluent API 构建 Cookie。
@[heap]
pub struct CookieBuilder {
pub mut:
	name      string
	value     string
	domain    string
	path      string = '/'
	max_age   int    = -1
	secure    bool
	http_only bool     = true
	same_site SameSite = .lax
}

// new_cookie_builder creates a CookieBuilder with the given name and value.
// new_cookie_builder 创建带指定名称和值的 CookieBuilder。
pub fn new_cookie_builder(name string, value string) &CookieBuilder {
	return &CookieBuilder{
		name:  name
		value: value
	}
}

// domain sets the Domain attribute. Returns self for chaining.
// domain 设置 Domain 属性。返回自身以支持链式调用。
pub fn (mut b CookieBuilder) domain(d string) &CookieBuilder {
	b.domain = d
	return b
}

// path sets the Path attribute. Returns self for chaining.
// path 设置 Path 属性。返回自身以支持链式调用。
pub fn (mut b CookieBuilder) path(p string) &CookieBuilder {
	b.path = p
	return b
}

// secure sets the Secure flag to true. Returns self for chaining.
// secure 设置 Secure 标志为 true。返回自身以支持链式调用。
pub fn (mut b CookieBuilder) secure() &CookieBuilder {
	b.secure = true
	return b
}

// http_only sets the HttpOnly flag to true. Returns self for chaining.
// http_only 设置 HttpOnly 标志为 true。返回自身以支持链式调用。
pub fn (mut b CookieBuilder) http_only() &CookieBuilder {
	b.http_only = true
	return b
}

// same_site sets the SameSite attribute. Returns self for chaining.
// same_site 设置 SameSite 属性。返回自身以支持链式调用。
pub fn (mut b CookieBuilder) same_site(ss SameSite) &CookieBuilder {
	b.same_site = ss
	return b
}

// max_age sets the Max-Age attribute in seconds. Returns self for chaining.
// max_age 设置 Max-Age 属性（秒）。返回自身以支持链式调用。
pub fn (mut b CookieBuilder) max_age(seconds int) &CookieBuilder {
	b.max_age = seconds
	return b
}

// build constructs the final http.Cookie from the builder state.
// build 从 Builder 状态构建最终的 http.Cookie。
pub fn (b &CookieBuilder) build() http.Cookie {
	ss := match b.same_site {
		.strict { http.SameSite.same_site_strict_mode }
		.lax { http.SameSite.same_site_lax_mode }
		.none { http.SameSite.same_site_none_mode }
	}

	return http.Cookie{
		name:      b.name
		value:     b.value
		domain:    b.domain
		path:      b.path
		max_age:   b.max_age
		secure:    b.secure
		http_only: b.http_only
		same_site: ss
	}
}

// ── CookieManager / Cookie Manager ──

// CookieManager manages cookie signing and encryption operations.
// Thread-safe: signing_key and encryption_key are protected by sync.RwMutex.
//
// 锁策略说明：
//   - sign/verify/encrypt/decrypt 使用 rlock 读取密钥，因为密钥在运行时不变
//     （仅在初始化时设置），读多写零，RwMutex 允许并发读取。
//   - 如果未来支持密钥轮换，需使用 @lock 保护写入。
//
// CookieManager 管理 Cookie 的签名和加密操作。
// 线程安全：signing_key 和 encryption_key 通过 sync.RwMutex 保护。
//
// Lock strategy:
//   - sign/verify/encrypt/decrypt use rlock for key reads since keys are immutable
//     at runtime (set only during initialization). RwMutex allows concurrent reads.
//   - If key rotation is needed in the future, use @lock for writes.
@[heap]
pub struct CookieManager {
pub mut:
	signing_key    string // HMAC-SHA256 signing key (≥32 bytes) / HMAC-SHA256 签名密钥（≥32字节）
	encryption_key []u8   // AES-256-GCM encryption key (=32 bytes) / AES-256-GCM 加密密钥（=32字节）
mut:
	mu sync.RwMutex
}

// new_cookie_manager creates a CookieManager with the given signing key and
// optional encryption key. The signing key must be at least 32 bytes.
// The encryption key must be exactly 32 bytes if provided.
// Returns error if the signing key is too short.
//
// new_cookie_manager 使用给定的签名密钥和可选的加密密钥创建 CookieManager。
// 签名密钥至少 32 字节，加密密钥必须恰好 32 字节。
// 签名密钥过短时返回错误。
pub fn new_cookie_manager(signing_key string, encryption_key []u8) !&CookieManager {
	if signing_key.len < 32 {
		return error('signing key must be at least 32 bytes (256 bit) / 签名密钥至少需要 32 字节（256 位）')
	}
	return &CookieManager{
		signing_key:    signing_key
		encryption_key: encryption_key.clone()
	}
}

// ── Signed Cookie Operations / 签名 Cookie 操作 ──

// sign computes the HMAC-SHA256 signature for the given value.
// Format: <value>.<hex_hmac_signature>
// Returns the signed value string.
//
// sign 对给定值计算 HMAC-SHA256 签名。
// 格式：<value>.<hex_hmac_signature>
// 返回签名后的值字符串。
pub fn (mut cm CookieManager) sign(value string) string {
	cm.mu.rlock()
	key := cm.signing_key.clone()
	cm.mu.runlock()

	mac := hmac.new(key.bytes(), value.bytes(), sha256.sum, sha256.block_size)
	return '${value}.${hex.encode(mac)}'
}

// verify checks the HMAC-SHA256 signature and returns the original value.
// Returns none if the signature is invalid or the format is wrong.
// Does NOT panic on verification failure.
//
// verify 验证 HMAC-SHA256 签名并返回原始值。
// 签名无效或格式错误时返回 none。
// 验证失败不会 panic。
pub fn (mut cm CookieManager) verify(signed_value string) ?string {
	// Split from the last '.' to handle values that may contain '.'
	// 从最后一个 '.' 拆分，处理值中可能包含 '.' 的情况
	last_dot := signed_value.last_index('.') or { return none }
	if last_dot <= 0 || last_dot >= signed_value.len - 1 {
		return none
	}
	value := signed_value[..last_dot]
	signature := signed_value[last_dot + 1..]

	cm.mu.rlock()
	key := cm.signing_key.clone()
	cm.mu.runlock()

	expected_mac := hmac.new(key.bytes(), value.bytes(), sha256.sum, sha256.block_size)

	// Constant-time comparison to prevent timing attacks.
	// Compare hex-decoded bytes rather than hex strings to ensure
	// hmac.equal operates on fixed-width MAC bytes (32 bytes for SHA-256),
	// avoiding length-dependent short-circuit in string comparison.
	// 常量时间比较以防止时序攻击。
	// 比较十六进制解码后的字节而非十六进制字符串，确保 hmac.equal
	// 在固定宽度的 MAC 字节（SHA-256 为 32 字节）上操作，
	// 避免字符串比较中的长度依赖短路。
	signature_bytes := hex.decode(signature) or { return none }
	if !hmac.equal(signature_bytes, expected_mac) {
		return none
	}
	return value
}

// set_signed_cookie sets a signed cookie on the response.
// The cookie value is signed with HMAC-SHA256 to prevent tampering.
// Uses secure defaults: HttpOnly=true, SameSite=Lax, Path=/.
//
// set_signed_cookie 在响应上设置签名 Cookie。
// Cookie 值使用 HMAC-SHA256 签名以防止篡改。
// 使用安全默认值：HttpOnly=true, SameSite=Lax, Path=/。
pub fn (mut cm CookieManager) set_signed_cookie(mut ctx veb.Context, name string, value string) {
	signed_value := cm.sign(value)
	ctx.set_cookie(http.Cookie{
		name:      name
		value:     signed_value
		path:      '/'
		http_only: true
		same_site: http.SameSite.same_site_lax_mode
		secure:    true // 签名 Cookie 应通过 HTTPS 传输 / Signed cookies should be transmitted over HTTPS
	})
}

// get_signed_cookie retrieves and verifies a signed cookie.
// Returns the original value if the signature is valid, or none otherwise.
//
// get_signed_cookie 读取并验证签名 Cookie。
// 签名有效时返回原始值，否则返回 none。
pub fn (mut cm CookieManager) get_signed_cookie(ctx &veb.Context, name string) ?string {
	signed_value := ctx.get_cookie(name) or { return none }
	return cm.verify(signed_value)
}

// ── Encrypted Cookie Operations / 加密 Cookie 操作 ──

// encrypt encrypts the plaintext with AES-256-GCM.
// Format: enc://<base64(nonce[12] || ciphertext || tag[16])>
//
// 原来的实现是一段「占位符」：把明文与密钥、nonce 逐字节 XOR，再用
// HMAC-SHA256 做完整性校验，注释里也写着「等 V 支持 AES-GCM 再替换」。
// 问题是 XOR 用同一段密钥流反复覆盖同一个 key —— 两份用同一 nonce 的
// 密文一异或，明文之间的关系就直接暴露，而调用方看到的是
// `set_encrypted_cookie`，会以为数据真的被加密了。
//
// V 的 crypto.aes 早就有 AES-GCM（new_aes_gcm / encrypt / decrypt，带
// 认证标签），所以直接换成真算法：机密性 + 完整性都由 GCM 提供，
// 不再需要外挂 HMAC。密文格式（nonce || ct || tag）保持不变。
//
// encrypt encrypts plaintext with real AES-256-GCM. The previous version was
// XOR "obfuscation" + HMAC, which provided integrity but no confidentiality.
pub fn (mut cm CookieManager) encrypt(plaintext string) !string {
	cm.mu.rlock()
	key := cm.encryption_key.clone()
	cm.mu.runlock()

	if key.len != 32 {
		return error('cookie encryption key must be 32 bytes / Cookie 加密密钥必须为 32 字节')
	}

	gcm := aes.new_aes_gcm(key)!
	// nonce MUST be unique per encryption: reusing a nonce with the same key
	// destroys GCM's security guarantees.
	nonce := crand.read(gcm.nonce_size()) or {
		return error('nonce generation failed / nonce 生成失败')
	}
	sealed := gcm.encrypt(plaintext.bytes(), nonce, []u8{})!

	mut combined := []u8{cap: nonce.len + sealed.len}
	combined << nonce
	combined << sealed
	return 'enc://${base64.encode(combined)}'
}

// decrypt verifies and decrypts an AES-256-GCM cookie value.
// Returns none if the value is malformed or the authentication tag fails.
//
// decrypt 校验并解密 AES-256-GCM 加密的 Cookie 值。
// 格式不对或认证失败时返回 none（不 panic）。
pub fn (mut cm CookieManager) decrypt(encrypted string) ?string {
	if !encrypted.starts_with('enc://') {
		return none
	}
	encoded := encrypted[6..]
	combined := base64.decode(encoded)
	// 12 (nonce) + 16 (tag) 是下限：GCM 的空明文也会带一个 tag
	if combined.len < 28 {
		return none
	}

	cm.mu.rlock()
	key := cm.encryption_key.clone()
	cm.mu.runlock()
	if key.len != 32 {
		return none
	}

	gcm := aes.new_aes_gcm(key) or { return none }
	nonce_size := gcm.nonce_size()
	if combined.len < nonce_size + 16 {
		return none
	}
	nonce := combined[..nonce_size]
	sealed := combined[nonce_size..]

	plaintext := gcm.decrypt(sealed, nonce, []u8{}) or { return none }
	return plaintext.bytestr()
}

// set_encrypted_cookie sets an encrypted cookie on the response.
// The cookie value is encrypted with AES-256-GCM for confidentiality.
//
// set_encrypted_cookie 在响应上设置加密 Cookie。
// Cookie 值使用 AES-256-GCM 加密以保护机密性。
pub fn (mut cm CookieManager) set_encrypted_cookie(mut ctx veb.Context, name string, value string) !string {
	encrypted_value := cm.encrypt(value)!
	ctx.set_cookie(http.Cookie{
		name:      name
		value:     encrypted_value
		path:      '/'
		http_only: true
		secure:    true
		same_site: http.SameSite.same_site_lax_mode
	})
	return encrypted_value
}

// get_encrypted_cookie retrieves and decrypts an encrypted cookie.
// Returns the original plaintext value if decryption succeeds, or none otherwise.
//
// get_encrypted_cookie 读取并解密加密 Cookie。
// 解密成功时返回原始明文值，否则返回 none。
pub fn (mut cm CookieManager) get_encrypted_cookie(ctx &veb.Context, name string) ?string {
	encrypted_value := ctx.get_cookie(name) or { return none }
	return cm.decrypt(encrypted_value)
}

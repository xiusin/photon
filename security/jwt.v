module security

// jwt.v - JWT Token Management
//
// Implements JSON Web Token (JWT) creation, parsing, and validation.
// Uses HMAC-SHA256 signing via V's crypto module.
// Supports configurable expiration, issuer, audience, and custom claims.
import crypto.hmac
import crypto.sha256
import encoding.base64
import x.json2
import time

// JwtConfig configures JWT token behavior
pub struct JwtConfig {
pub:
	secret                         string
	issuer                         string = 'photon'
	audience                       string
	expiration_minutes             int = 60
	refresh_token_expiration_hours int = 168
	// clock_skew_seconds 是签发方与本方允许的时钟偏差。
	//
	// 多机部署里 NTP 同步误差几秒是常态。严格 `iat > now` 会把「快了几秒
	// 的那台机器签的令牌」判成「在未来签发」，而 `now > exp` 又会在过期
	// 边界上提前几秒拒掉合法令牌。两端各让 skew 秒。
	clock_skew_seconds             i64 = 30
}

// JwtClaims represents the claims in a JWT token
pub struct JwtClaims {
pub mut:
	sub         string
	iat         i64
	exp         i64
	iss         string
	aud         string
	jti         string
	roles       []string
	permissions []string
}

// JwtManager handles JWT operations
pub struct JwtManager {
pub mut:
	config JwtConfig
}

// new_jwt_manager creates a new JwtManager.
//
// An empty secret is accepted here and rejected at sign/verify time
// (see check_secret) — refusing the constructor outright would break the
// common "configure the manager in a struct literal, fill the secret from
// config in @[post_construct]" flow, but a manager that silently signs with
// an empty key is an open door: anyone can forge an admin token with
// `hmac.new('', ...)` and it validates cleanly.
pub fn new_jwt_manager(config JwtConfig) &JwtManager {
	return &JwtManager{
		config: config
	}
}

// check_secret refuses to sign or verify with an empty secret.
//
// An empty HMAC key is not a weak key, it is a *public* key: `hmac.new('',
// payload, sha256.sum, ...)` is one line of code. A manager built from a
// config that forgot to fill `secret` therefore validated any token an
// attacker cared to write — including `{"sub":"admin"}`.
//
// Only emptiness is rejected here on purpose. A short secret is a
// configuration weakness that belongs in a startup check with a warning, not
// in a hard failure on every request; rejecting it here would turn an
// existing deployment's short key into a total outage.
fn (jm &JwtManager) check_secret() ! {
	if jm.config.secret.len == 0 {
		return error('JWT secret is empty: refusing to sign or verify tokens / JWT 密钥为空，拒绝签发或校验令牌')
	}
}

// min_recommended_jwt_secret_len is the length reported by
// check_secret_strength(): HMAC-SHA256 gains nothing from a key shorter than
// its own 32-byte output, and a short key is brute-forceable offline against a
// single captured token.
pub const min_recommended_jwt_secret_len = 32

// check_secret_strength reports a weak secret without failing the caller.
// Call it once at startup (application context / @[post_construct]) and log
// the result.
pub fn (jm &JwtManager) check_secret_strength() ! {
	jm.check_secret()!
	if jm.config.secret.len < min_recommended_jwt_secret_len {
		return error('JWT secret is short (${jm.config.secret.len} < ${min_recommended_jwt_secret_len} bytes); use a random 32+ byte key in production / JWT 密钥过短，生产环境请使用 32 字节以上的随机密钥')
	}
}

// create_token creates a JWT access token for a user
pub fn (jm &JwtManager) create_token(username string, roles []string) !string {
	now := time.now().unix()
	claims := JwtClaims{
		sub:   username
		iat:   now
		exp:   now + i64(jm.config.expiration_minutes * 60)
		iss:   jm.config.issuer
		aud:   jm.config.audience
		jti:   generate_jti(username, now)
		roles: roles
	}
	return jm.encode(claims)
}

// create_refresh_token creates a long-lived refresh token
pub fn (jm &JwtManager) create_refresh_token(username string) !string {
	now := time.now().unix()
	claims := JwtClaims{
		sub: username
		iat: now
		exp: now + i64(jm.config.refresh_token_expiration_hours * 3600)
		iss: jm.config.issuer
		jti: generate_jti('refresh_${username}', now)
	}
	return jm.encode(claims)
}

// parse_token parses and validates a JWT token, returning claims
pub fn (jm &JwtManager) parse_token(token string) !JwtClaims {
	claims := jm.decode(token)!

	now := time.now().unix()
	skew := if jm.config.clock_skew_seconds > 0 { jm.config.clock_skew_seconds } else { 0 }

	// 先验字段存在性，再做数值比较。
	//
	// 反过来的话，缺 exp 的令牌先撞上 `0 < now`，报出「已过期」—— 排查者
	// 会去看服务器时钟，而真因是签发方少写了一个字段。exp / iat 缺失
	// （0）时任何基于比较的检查都没有意义，必须先明确拒绝。
	if claims.exp == 0 {
		return error('JWT token has no expiration claim')
	}
	if now > claims.exp + skew {
		return error('JWT token expired at ${claims.exp}')
	}
	if claims.iat > now + skew {
		return error('JWT token used before issued time')
	}
	if claims.iss.len > 0 && claims.iss != jm.config.issuer {
		return error('JWT issuer mismatch: expected ${jm.config.issuer}, got ${claims.iss}')
	}
	// Audience 校验：配置了 audience 就必须校验。
	// 之前 `aud` 只写不读 —— 给 A 服务签发的 token 可以原样拿去访问 B 服务，
	// 只要两边共享同一个 secret（多服务部署的常态），越权就这么发生了，
	// 而且校验全绿。
	if jm.config.audience.len > 0 {
		if claims.aud != jm.config.audience {
			return error('JWT audience mismatch: expected ${jm.config.audience}, got "${claims.aud}"')
		}
	}
	return claims
}

// validate_token validates a token and returns the username if valid
pub fn (jm &JwtManager) validate_token(token string) !string {
	claims := jm.parse_token(token)!
	return claims.sub
}

// has_role checks if the token contains a specific role
pub fn (jm &JwtManager) has_role(token string, role string) bool {
	claims := jm.parse_token(token) or { return false }
	for r in claims.roles {
		if r == role || r == 'ROLE_${role}' {
			return true
		}
	}
	return false
}

// has_any_role checks if the token contains any of the specified roles
pub fn (jm &JwtManager) has_any_role(token string, roles []string) bool {
	claims := jm.parse_token(token) or { return false }
	for required in roles {
		for user_role in claims.roles {
			if user_role == required || user_role == 'ROLE_${required}' {
				return true
			}
		}
	}
	return false
}

// encode encodes claims into a JWT token string (header.payload.signature)
fn (jm &JwtManager) encode(claims JwtClaims) !string {
	jm.check_secret()!
	header := '{"alg":"HS256","typ":"JWT"}'
	header_b64 := base64.url_encode(header.bytes())

	payload := json2.encode(claims)
	payload_b64 := base64.url_encode(payload.bytes())

	signing_input := '${header_b64}.${payload_b64}'
	signature := jm.hmac_sign(signing_input)
	signature_b64 := base64.url_encode(signature)

	return '${header_b64}.${payload_b64}.${signature_b64}'
}

// decode decodes a JWT token string into claims
fn (jm &JwtManager) decode(token string) !JwtClaims {
	jm.check_secret()!
	parts := token.split('.')
	if parts.len != 3 {
		return error('invalid JWT format: expected 3 parts, got ${parts.len}')
	}

	header_b64 := parts[0]
	payload_b64 := parts[1]
	signature_b64 := parts[2]

	// Verify signature
	signing_input := '${header_b64}.${payload_b64}'
	expected_sig := jm.hmac_sign(signing_input)
	expected_sig_b64 := base64.url_encode(expected_sig)

	if signature_b64 != expected_sig_b64 {
		return error('JWT signature verification failed')
	}

	// Decode payload
	payload_bytes := base64.url_decode(payload_b64)
	payload_str := payload_bytes.bytestr()

	return json2.decode[JwtClaims](payload_str)!
}

// hmac_sign creates an HMAC-SHA256 signature
fn (jm &JwtManager) hmac_sign(data string) []u8 {
	return hmac.new(jm.config.secret.bytes(), data.bytes(), sha256.sum, sha256.block_size)
}

// generate_jti creates a unique token ID
fn generate_jti(prefix string, timestamp i64) string {
	return '${prefix}_${timestamp}'
}

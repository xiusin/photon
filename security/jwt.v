module security

// jwt.v - JWT Token Management
//
// Implements JSON Web Token (JWT) creation, parsing, and validation.
// Uses HMAC-SHA256 signing via V's crypto module.
// Supports configurable expiration, issuer, audience, and custom claims.
import crypto.hmac
import crypto.sha256
import encoding.base64
import json2
import time

// JwtConfig configures JWT token behavior
pub struct JwtConfig {
pub:
	secret                         string
	issuer                         string = 'photon'
	audience                       string
	expiration_minutes             int = 60
	refresh_token_expiration_hours int = 168
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

// new_jwt_manager creates a new JwtManager
pub fn new_jwt_manager(config JwtConfig) &JwtManager {
	return &JwtManager{
		config: config
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
	if now > claims.exp {
		return error('JWT token expired at ${claims.exp}')
	}
	if claims.iat > now {
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
	// exp / iat 缺失（0）时上面的检查会失效：exp=0 永远小于 now → 拒绝，
	// iat=0 也永远不大于 now → 放行。这里显式拒绝没有 exp 的令牌，
	// 否则一个缺字段的 payload 就成了「永不过期的通行证」。
	if claims.exp == 0 {
		return error('JWT token has no expiration claim')
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

	return json2.decode[JwtClaims]( payload_str)!
}

// hmac_sign creates an HMAC-SHA256 signature
fn (jm &JwtManager) hmac_sign(data string) []u8 {
	return hmac.new(jm.config.secret.bytes(), data.bytes(), sha256.sum, sha256.block_size)
}

// generate_jti creates a unique token ID
fn generate_jti(prefix string, timestamp i64) string {
	return '${prefix}_${timestamp}'
}

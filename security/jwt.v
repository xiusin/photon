module security

// jwt.v - JWT Token Management
//
// Implements JSON Web Token (JWT) creation, parsing, and validation.
// Uses HMAC-SHA256 signing via V's crypto module.
// Supports configurable expiration, issuer, audience, and custom claims.

import time
import encoding.base64
import json

// JwtConfig configures JWT token behavior
pub struct JwtConfig {
pub:
	secret         string
	issuer         string = 'photon'
	audience       string
	expiration_minutes int = 60
	refresh_token_expiration_hours int = 168
}

// JwtClaims represents the claims in a JWT token
pub struct JwtClaims {
pub mut:
	sub       string
	iat       i64
	exp       i64
	iss       string
	aud       string
	jti       string
	roles     []string
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
		sub: username
		iat: now
		exp: now + i64(jm.config.expiration_minutes * 60)
		iss: jm.config.issuer
		aud: jm.config.audience
		jti: generate_jti(username, now)
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

	payload := json.encode(claims)
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

	return json.decode(JwtClaims, payload_str)!
}

// hmac_sign creates an HMAC-SHA256 signature
// FIXME: When V's crypto.hmac / crypto.sha256 modules stabilize,
// replace this custom implementation with:
//   import crypto.hmac
//   import crypto.sha256
//   return hmac.new(key, data, sha256.sum, sha256.block_size)
fn (jm &JwtManager) hmac_sign(data string) []u8 {
	// HMAC-SHA256 implementation using iterative hashing
	mut key := jm.config.secret.bytes()

	block_size := 64 // SHA256 block size
	if key.len > block_size {
		key = sha256_hash(key)
	}
	if key.len < block_size {
		mut padded := []u8{len: block_size}
		for i in 0 .. key.len {
			padded[i] = key[i]
		}
		unsafe { key = padded }
	}

	// Inner and outer padding
	mut inner_key := []u8{len: block_size}
	mut outer_key := []u8{len: block_size}
	for i in 0 .. block_size {
		inner_key[i] = key[i] ^ 0x36
		outer_key[i] = key[i] ^ 0x5c
	}

	// inner_hash = SHA256(inner_key || data)
	mut inner_input := []u8{cap: block_size + data.len}
	inner_input << inner_key
	inner_input << data.bytes()
	inner_hash := sha256_hash(inner_input)

	// result = SHA256(outer_key || inner_hash)
	mut outer_input := []u8{cap: block_size + 32}
	outer_input << outer_key
	outer_input << inner_hash

	return sha256_hash(outer_input)
}

// sha256_hash computes a SHA-256 hash of the input data
fn sha256_hash(data []u8) []u8 {
	// SHA-256 constants
	k := [
		u32(0x428a2f98), 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
		0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
		0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
		0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
		0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
		0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
		0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
		0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
		0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
		0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
		0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
		0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
		0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
		0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
		0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
		0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
	]

	// Initialize hash values
	mut h0 := u32(0x6a09e667)
	mut h1 := u32(0xbb67ae85)
	mut h2 := u32(0x3c6ef372)
	mut h3 := u32(0xa54ff53a)
	mut h4 := u32(0x510e527f)
	mut h5 := u32(0x9b05688c)
	mut h6 := u32(0x1f83d9ab)
	mut h7 := u32(0x5be0cd19)

	// Pre-processing: padding
	msg_len := data.len * 8 // length in bits
	mut padded := data.clone()
	padded << u8(0x80)
	for (padded.len * 8 + 64) % 512 != 0 {
		padded << u8(0)
	}
	// Append length as 64-bit big-endian
	for i := 0; i < 8; i++ {
		padded << u8((msg_len >> (56 - i * 8)) & 0xff)
	}

	// Process each 512-bit block
	for i := 0; i < padded.len; i += 64 {
		mut w := []u32{len: 64}
		for t := 0; t < 16; t++ {
			w[t] = u32(padded[i + t * 4]) << 24 |
				u32(padded[i + t * 4 + 1]) << 16 |
				u32(padded[i + t * 4 + 2]) << 8 |
				u32(padded[i + t * 4 + 3])
		}
		for t := 16; t < 64; t++ {
			s0 := right_rotate(w[t - 15], 7) ^ right_rotate(w[t - 15], 18) ^ (w[t - 15] >> 3)
			s1 := right_rotate(w[t - 2], 17) ^ right_rotate(w[t - 2], 19) ^ (w[t - 2] >> 10)
			w[t] = w[t - 16] + s0 + w[t - 7] + s1
		}

		mut a := h0
		mut b := h1
		mut c := h2
		mut d := h3
		mut e := h4
		mut f := h5
		mut g := h6
		mut h := h7

		for t := 0; t < 64; t++ {
			s1 := right_rotate(e, 6) ^ right_rotate(e, 11) ^ right_rotate(e, 25)
			ch := (e & f) ^ (~e & g)
			temp1 := h + s1 + ch + k[t] + w[t]
			s0 := right_rotate(a, 2) ^ right_rotate(a, 13) ^ right_rotate(a, 22)
			maj := (a & b) ^ (a & c) ^ (b & c)
			temp2 := s0 + maj

			h = g
			g = f
			f = e
			e = d + temp1
			d = c
			c = b
			b = a
			a = temp1 + temp2
		}

		h0 += a
		h1 += b
		h2 += c
		h3 += d
		h4 += e
		h5 += f
		h6 += g
		h7 += h
	}

	// Output
	mut result := []u8{len: 32}
	put_u32(mut result, 0, h0)
	put_u32(mut result, 4, h1)
	put_u32(mut result, 8, h2)
	put_u32(mut result, 12, h3)
	put_u32(mut result, 16, h4)
	put_u32(mut result, 20, h5)
	put_u32(mut result, 24, h6)
	put_u32(mut result, 28, h7)
	return result
}

fn right_rotate(x u32, n int) u32 {
	return (x >> n) | (x << (32 - n))
}

fn put_u32(mut buf []u8, pos int, val u32) {
	buf[pos] = u8(val >> 24)
	buf[pos + 1] = u8((val >> 16) & 0xff)
	buf[pos + 2] = u8((val >> 8) & 0xff)
	buf[pos + 3] = u8(val & 0xff)
}

// generate_jti creates a unique token ID
fn generate_jti(prefix string, timestamp i64) string {
	return '${prefix}_${timestamp}'
}

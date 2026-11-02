// jwt_alg_test.v — 令牌头部的 alg 必须被真正拒绝，而不是「碰巧签名不匹配」
module security

import crypto.hmac
import crypto.sha256
import encoding.base64
import time

fn b64(s string) string {
	return base64.url_encode(s.bytes())
}

fn make_header(alg string) string {
	return b64('{"alg":"${alg}","typ":"JWT"}')
}

fn make_claims(sub string) string {
	return b64('{"sub":"${sub}","exp":${time.now().unix() + 3600}}')
}

fn test_alg_none_is_rejected_explicitly() {
	jm := new_jwt_manager(JwtConfig{
		secret: '0123456789abcdef0123456789abcdef'
	})
	token := '${make_header('none')}.${make_claims('admin')}.'
	if _ := jm.parse_token(token) {
		assert false, 'alg:none token must never verify'
	} else {
		assert err.msg().contains('unsupported JWT algorithm'), 'got: ${err.msg()}'
	}
}

fn test_hs512_header_is_rejected_not_silently_downgraded() {
	jm := new_jwt_manager(JwtConfig{
		secret: '0123456789abcdef0123456789abcdef'
	})
	// 用 HS256 计算签名，但头部声明 HS512：不能让它通过
	header := make_header('HS512')
	payload := make_claims('admin')
	sig := hmac.new(jm.config.secret.bytes(), '${header}.${payload}'.bytes(), sha256.sum,
		sha256.block_size)
	token := '${header}.${payload}.${b64(sig.bytestr())}'
	if _ := jm.parse_token(token) {
		assert false, 'algorithm confusion: header said HS512 but signature was HS256'
	} else {
		assert err.msg().contains('unsupported JWT algorithm')
	}
}

fn test_valid_hs256_token_still_works() {
	jm := new_jwt_manager(JwtConfig{
		secret: '0123456789abcdef0123456789abcdef'
	})
	token := jm.create_token('alice', ['ADMIN'])!
	claims := jm.parse_token(token)!
	assert claims.sub == 'alice'
	assert claims.roles == ['ADMIN']

	// 客户端/中间件重新编码时，base64 的尾部填充可能被加上或去掉：
	// 签名比的是字节，不是 base64 文本，两种形态都必须通过。
	parts := token.split('.')
	padded := '${parts[0]}.${parts[1]}.${parts[2]}'
	assert jm.parse_token(padded)!.sub == 'alice'
}

fn test_tampered_signature_is_rejected() {
	jm := new_jwt_manager(JwtConfig{
		secret: '0123456789abcdef0123456789abcdef'
	})
	token := jm.create_token('alice', [])!
	parts := token.split('.')
	// 翻转签名里的一个字节
	mut sig := base64.url_decode(parts[2])
	sig[0] = if sig[0] == `A` { `B` } else { `A` }
	tampered := '${parts[0]}.${parts[1]}.${base64.url_encode(sig)}'
	if _ := jm.parse_token(tampered) {
		assert false, 'tampered signature must be rejected'
	} else {
		assert err.msg().contains('signature')
	}
}

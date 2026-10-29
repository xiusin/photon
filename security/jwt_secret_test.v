module security

import crypto.hmac
import crypto.sha256
import encoding.base64

// 空 secret 不是「弱密钥」，是公开密钥：`hmac.new('', payload, ...)` 只需要
// 一行代码。配置忘了填 secret 时，任何人都能签出 `{"sub":"admin"}` 并通过校验。

fn forge_with_secret(secret string, payload string) string {
	header := base64.url_encode('{"alg":"HS256","typ":"JWT"}'.bytes())
	body := base64.url_encode(payload.bytes())
	signing_input := '${header}.${body}'
	signature := hmac.new(secret.bytes(), signing_input.bytes(), sha256.sum, sha256.block_size)
	return '${signing_input}.${base64.url_encode(signature)}'
}

fn test_empty_secret_cannot_validate_forged_token() {
	jm := new_jwt_manager(JwtConfig{}) // 配置里没填 secret
	forged := forge_with_secret('', '{"sub":"admin","exp":9999999999,"iss":"photon"}')

	jm.validate_token(forged) or {
		assert err.msg().contains('secret is empty')
		return
	}
	assert false, 'a token signed with an empty secret must not validate'
}

fn test_empty_secret_cannot_issue_tokens() {
	jm := new_jwt_manager(JwtConfig{})
	jm.create_token('alice', []) or {
		assert err.msg().contains('secret is empty')
		return
	}
	assert false, 'signing with an empty secret must be refused'
}

fn test_real_secret_rejects_forged_token() {
	jm := new_jwt_manager(JwtConfig{
		secret: 'a-real-secret-that-nobody-knows'
	})
	forged := forge_with_secret('', '{"sub":"admin","exp":9999999999,"iss":"photon"}')
	if _ := jm.validate_token(forged) {
		assert false, 'a token signed with a different key must not validate'
	}
	// 正常签发的令牌照旧可用
	tok := jm.create_token('alice', [])!
	assert jm.validate_token(tok)! == 'alice'
}

fn test_short_secret_still_works_but_is_reported() {
	// 短密钥是配置弱点，不是「立刻全线中断」的理由：签发/校验照旧，
	// 通过 check_secret_strength() 在启动时报告。
	jm := new_jwt_manager(JwtConfig{
		secret: 'short'
	})
	tok := jm.create_token('bob', [])!
	assert jm.validate_token(tok)! == 'bob'
	mut was_weak := false
	jm.check_secret_strength() or { was_weak = true }
	assert was_weak, 'a 5-byte secret must be reported as weak'

	strong := new_jwt_manager(JwtConfig{
		secret: '0123456789abcdef0123456789abcdef'
	})
	strong.check_secret_strength()!
}

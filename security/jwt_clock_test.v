module security

// jwt_clock_test.v - 时间相关声明的校验顺序与时钟偏移
//
// 校验如果先按数值比较、后判「字段是否存在」，缺失的字段会先撞上
// 「0 < now」这条看似合理的比较，报出完全相反的原因；而严格相等比较
// 又让多机部署里几秒的系统时钟偏差把合法令牌判成「还没生效」。
import time

fn sign_claims(secret string, claims JwtClaims) string {
	return JwtManager{
		config: JwtConfig{
			secret: secret
		}
	}.encode(claims) or { panic(err) }
}

fn test_missing_exp_reports_missing_not_expired() {
	jm := new_jwt_manager(JwtConfig{
		secret: 'test-key'
	})
	// exp 缺省是 0：不该报成「已过期」，那会把人引向排查时钟
	tok := sign_claims('test-key', JwtClaims{
		sub: 'alice'
	})
	jm.parse_token(tok) or {
		assert err.msg().contains('no expiration claim')
		return
	}
	assert false, 'a token without exp must be rejected'
}

fn test_future_exp_is_accepted() {
	jm := new_jwt_manager(JwtConfig{
		secret: 'test-key'
	})
	tok := sign_claims('test-key', JwtClaims{
		sub: 'alice'
		exp: time.now().unix() + 3600
	})
	claims := jm.parse_token(tok) or {
		assert false, 'valid token rejected: ${err}'
		return
	}
	assert claims.sub == 'alice'
}

fn test_expired_token_rejected() {
	jm := new_jwt_manager(JwtConfig{
		secret: 'test-key'
	})
	tok := sign_claims('test-key', JwtClaims{
		sub: 'alice'
		exp: time.now().unix() - 3600
	})
	if _ := jm.parse_token(tok) {
		assert false, 'expired token must be rejected'
	}
}

fn test_small_clock_skew_in_iat_is_tolerated() {
	jm := new_jwt_manager(JwtConfig{
		secret: 'test-key'
	})
	// 签发方时钟快几秒是部署常态；严格 `iat > now` 会把它判成
	// 「令牌在未来签发」，而这通常报给用户的就是一个 401
	tok := sign_claims('test-key', JwtClaims{
		sub:  'alice'
		exp:  time.now().unix() + 3600
		iat:  time.now().unix() + 3
	})
	claims := jm.parse_token(tok) or {
		assert false, 'token signed slightly in the future was rejected: ${err}'
		return
	}
	assert claims.sub == 'alice'
}

fn test_clearly_future_iat_rejected() {
	jm := new_jwt_manager(JwtConfig{
		secret: 'test-key'
	})
	tok := sign_claims('test-key', JwtClaims{
		sub: 'alice'
		exp: time.now().unix() + 7200
		iat: time.now().unix() + 3600
	})
	if _ := jm.parse_token(tok) {
		assert false, 'token issued an hour in the future must be rejected'
	}
}

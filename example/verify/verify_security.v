module main

// verify_security.v — JWT / 密码哈希 / CSRF / RBAC 验证

import security

fn verify_security(mut v Verifier) {
	v.section('安全 — JWT / 密码哈希 / CSRF / RBAC')

	// ── 1) JWT 创建 / 解析 / 校验 / 角色 ──
	jm := security.new_jwt_manager(security.JwtConfig{
		secret:             'verify-secret-key-at-least-32-bytes-long!!'
		expiration_minutes: 60
	})
	token := jm.create_token('alice', ['USER', 'ADMIN']) or {
		v.check('jwt.create_token', false)
		return
	}
	v.check('jwt token 非空', token.len > 0)

	claims := jm.parse_token(token) or {
		v.check('jwt.parse_token', false)
		return
	}
	v.check('jwt claims.sub == alice', claims.sub == 'alice')
	v.check('jwt claims.roles 含 ADMIN', 'ADMIN' in claims.roles)
	v.check('jwt.validate_token 返回 subject', (jm.validate_token(token) or { '' }) == 'alice')
	v.check('jwt.has_role(ADMIN)', jm.has_role(token, 'ADMIN'))
	v.check('jwt.has_role(GUEST)=false', !jm.has_role(token, 'GUEST'))
	v.check('jwt 篡改 token 校验失败', (jm.validate_token(token + 'x') or { 'INVALID' }) == 'INVALID')

	// ── 2) 密码哈希（BcryptHasher: make/check）──
	hasher := security.BcryptHasher{
		rounds: 10
	}
	hash := hasher.make('s3cret-pw')
	v.check('bcrypt make 产生哈希', hash.len > 0 && hash != 's3cret-pw')
	v.check('bcrypt check 正确密码', hasher.check('s3cret-pw', hash))
	v.check('bcrypt check 错误密码=false', !hasher.check('wrong-pw', hash))

	// Spring 风格 PasswordEncoder（encode/matches，带 {id} 前缀）
	encoder := security.new_bcrypt_password_encoder()
	enc := encoder.encode('pw123') or {
		v.check('password_encoder.encode', false)
		return
	}
	v.check('encoder 带 {bcrypt} 前缀', enc.starts_with('{bcrypt}'))
	v.check('encoder.matches 正确', encoder.matches('pw123', enc) or { false })

	// ── 3) CSRF 令牌生成与校验 ──
	mut csrf := security.new_csrf_manager(security.CsrfConfig{})
	csrf_token := csrf.generate()
	v.check('csrf.generate 非空', csrf_token.len > 0)
	v.check('csrf POST 需要校验', csrf.is_csrf_required('POST'))
	v.check('csrf GET 不需要校验', !csrf.is_csrf_required('GET'))
	csrf.validate(csrf_token, csrf_token) or {
		v.check('csrf.validate 相同令牌通过', false)
		return
	}
	v.check('csrf.validate 相同令牌通过', true)
	mut mismatch := false
	csrf.validate('aaa', 'bbb') or {
		mismatch = true
	}
	v.check('csrf.validate 不同令牌失败', mismatch)

	// ── 4) RBAC 角色层级 ──
	mut rh := security.build_default_hierarchy()
	v.check('RBAC: ADMIN 继承 USER', rh.has_role(['ADMIN'], 'USER'))
	v.check('RBAC: USER 不具备 ADMIN', !rh.has_role(['USER'], 'ADMIN'))
	v.check('RBAC: has_any_role', rh.has_any_role(['USER'], ['ADMIN', 'USER']))

	adm := security.new_access_manager(rh)
	v.check('AccessDecisionManager.decide (ADMIN 访问 USER 资源)', adm.decide(['ADMIN'],
		['USER'], []))
	v.check('AccessDecisionManager.decide 拒绝 (GUEST 访问 ADMIN 资源)', !adm.decide(['GUEST'],
		['ADMIN'], []))
}

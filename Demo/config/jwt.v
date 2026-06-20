module main

// config/jwt.v — JWT 认证配置
//
// 定义 JWT 密钥、过期时间、签发者等配置。
// 生产环境强制校验密钥非空且非默认值。

// JwtConfigBlock JWT 认证配置块
pub struct JwtConfigBlock {
pub:
	secret             string
	expiration_minutes int
	refresh_hours      int
	issuer             string
}

// default_jwt_config 返回 JWT 默认配置
pub fn default_jwt_config(profile string) JwtConfigBlock {
	secret := env_or('JWT_SECRET', 'photonblog-default-jwt-secret-change-in-production-32chars')

	return JwtConfigBlock{
		secret: secret
		expiration_minutes: env_or_int('JWT_TTL', 60)
		refresh_hours: env_or_int('JWT_REFRESH_HOURS', 24)
		issuer: env_or('JWT_ISSUER', 'PhotonBlog')
	}
}

// validate_jwt_secret 生产环境校验 JWT 密钥
// 若 profile 为 prod 且密钥为空或默认值，返回错误
pub fn validate_jwt_secret(profile string, secret string) ! {
	if profile != 'prod' {
		return
	}
	if secret.len == 0 {
		return error('生产环境必须设置 JWT_SECRET 环境变量（至少 32 字符的随机字符串）')
	}
	if secret == 'photonblog-default-jwt-secret-change-in-production-32chars' {
		return error('生产环境禁止使用默认 JWT_SECRET，请通过 .env 或环境变量设置自定义密钥')
	}
	if secret.len < 32 {
		return error('生产环境 JWT_SECRET 长度不足，至少需要 32 字符')
	}
}

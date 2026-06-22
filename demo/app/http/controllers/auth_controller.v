module controllers

import json

import veb
import photon.web
import photon.security
import models
import app.http
import app.http.resources

// AuthController — 认证控制器，处理注册/登录/刷新/资料/登出
pub struct AuthController {
	BaseController
}

// post_auth_register POST /api/v1/auth/register — 用户注册（触发 user.registered 事件）
pub fn (c &AuthController) post_auth_register(mut ctx http.Context) veb.Result {
	// 校验请求体
	dto := web.bind_json[models.CreateUserDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	// 哈希密码
	hasher := security.BcryptHasher{}
	hashed_password := hasher.make(dto.password)

	// 调用服务层注册（触发 user.registered 事件）
	mut user_svc := c.bootstrap.user_svc
	user, _ := user_svc.register(dto, hashed_password) or {
		return ctx.send_bad_request(err.msg())
	}

	// 返回用户信息（通过 UserResource 脱敏）
	return ctx.send_data(resources.new_user_resource(&user).to_json())
}

// post_auth_login POST /api/v1/auth/login — 用户登录，返回 JWT
pub fn (c &AuthController) post_auth_login(mut ctx http.Context) veb.Result {
	// 校验请求体
	dto := web.bind_json[models.LoginDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return c.do_login(mut ctx, dto)
}

// do_login 执行登录逻辑（内部辅助方法）
fn (c &AuthController) do_login(mut ctx http.Context, dto models.LoginDto) veb.Result {
	// 调用认证服务验证凭据并生成 JWT
	mut auth_svc := c.bootstrap.auth_svc
	token, roles := auth_svc.authenticate(dto.username, dto.password) or {
		return ctx.send_unauthorized(err.msg())
	}

	// 查询用户信息
	user_svc := c.bootstrap.user_svc
	user := user_svc.find_by_username(dto.username) or {
		return ctx.send_unauthorized('user not found / 用户不存在')
	}

	// 构建登录响应
	resp := models.LoginResponseDto{
		access_token:  token
		token_type:    'Bearer'
		expires_in:    3600
		refresh_token: ''
		user: models.UserProfileDto{
			id:       user.id
			username: user.username
			nickname: user.nickname
			avatar:   user.avatar
			email:    user.email
			role:     user.role
			status:   user.status
			created:  user.created_at.str()
		}
	}

	return ctx.send_data(json.encode(resp))
}

// post_auth_refresh POST /api/v1/auth/refresh — 刷新访问令牌
pub fn (c &AuthController) post_auth_refresh(mut ctx http.Context) veb.Result {
	// 校验请求体
	dto := web.bind_json[http.RefreshTokenDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}

	// 验证旧 token 并生成新 token
	mut auth_svc := c.bootstrap.auth_svc
	username := auth_svc.validate_token(dto.refresh_token) or {
		return ctx.send_unauthorized('invalid refresh token / 无效的刷新令牌: ${err}')
	}

	// 生成新的 access token
	jwt_mgr := c.bootstrap.jwt_mgr
	access_token := jwt_mgr.create_token(username, []) or {
		return ctx.send_internal_error('failed to generate token / 令牌生成失败: ${err}')
	}

	resp := http.TokenResponseDto{
		access_token:  access_token
		refresh_token: dto.refresh_token
	}
	return ctx.send_data(json.encode(resp))
}

// get_auth_profile GET /api/v1/auth/profile — 获取当前用户信息（需 JWT）
pub fn (c &AuthController) get_auth_profile(mut ctx http.Context) veb.Result {
	// JWT 认证
	username, _ := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}

	// 查询用户信息
	user_svc := c.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_not_found('user not found / 用户不存在: ${username}')
	}

	// 返回用户信息（通过 UserResource 脱敏，隐藏 password/version）
	return ctx.send_data(resources.new_user_resource(&user).to_json())
}

// post_auth_logout POST /api/v1/auth/logout — 登出（客户端清除 token）
pub fn (c &AuthController) post_auth_logout(mut ctx http.Context) veb.Result {
	// JWT 认证（可选，即使 token 过期也允许登出）
	_, _ = c.middleware_registry.authenticate(mut ctx.Context) or {
		// 即使认证失败也返回成功（客户端应清除 token）
		return ctx.send_data(json.encode(http.MessageDto{message: 'logged out / 已登出'}))
	}

	// 返回成功（JWT 无状态，服务端无需额外处理，客户端清除 token 即可）
	return ctx.send_data(json.encode(http.MessageDto{message: 'logged out / 已登出'}))
}
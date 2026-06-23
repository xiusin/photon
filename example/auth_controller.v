module main

// auth_controller.v — 认证控制器（独立分层控制器）
//
// API 前缀：/api/v1/auth
import veb

// AuthController — 认证接口
pub struct AuthController {
pub mut:
	auth_service &AuthService       = unsafe { nil }
	user_service &UserService       = unsafe { nil }
	middleware   &MiddlewareManager = unsafe { nil }
}

// new_auth_controller 构造控制器并注入依赖
pub fn new_auth_controller(auth_svc &AuthService, user_svc &UserService, mw &MiddlewareManager) &AuthController {
	return unsafe {
		&AuthController{
			auth_service: auth_svc
			user_service: user_svc
			middleware:   mw
		}
	}
}

// login POST /api/v1/auth/login — 用户登录
pub fn (mut c AuthController) login(mut ctx Context) veb.Result {
	username := ctx.query['username'] or { ctx.form['username'] or { '' } }
	password := ctx.query['password'] or { ctx.form['password'] or { '' } }
	if username.len == 0 || password.len == 0 {
		return ctx.json_error(400, 'username and password required')
	}
	req := LoginRequest{
		username: username
		password: password
	}
	resp := c.auth_service.login(req) or { return ctx.json_error(401, err.msg()) }
	return ctx.json_response(200, '${resp}')
}

// register POST /api/v1/auth/register — 用户注册
pub fn (mut c AuthController) register(mut ctx Context) veb.Result {
	username := ctx.query['username'] or { ctx.form['username'] or { '' } }
	email := ctx.query['email'] or { ctx.form['email'] or { '' } }
	password := ctx.query['password'] or { ctx.form['password'] or { '' } }
	nickname := ctx.query['nickname'] or { ctx.form['nickname'] or { '' } }
	if username.len == 0 || email.len == 0 || password.len == 0 {
		return ctx.json_error(400, 'username, email, password required')
	}
	req := CreateUserRequest{
		username: username
		email:    email
		password: password
		nickname: nickname
	}
	user := c.user_service.create(req) or { return ctx.json_error(409, err.msg()) }
	_ = user
	return ctx.json_success('registration successful, please login')
}

// profile GET /api/v1/auth/profile — 获取用户信息（JWT）
pub fn (c &AuthController) profile(mut ctx Context) veb.Result {
	username, _ := c.middleware.apply_auth(mut ctx.Context) or {
		return ctx.json_error(401, err.msg())
	}
	profile := c.auth_service.get_profile(username) or { return ctx.json_error(404, err.msg()) }
	return ctx.json_response(200, '${profile}')
}

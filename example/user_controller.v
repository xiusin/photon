module main

// user_controller.v — 用户管理控制器（独立分层控制器）
//
// API 前缀：/api/v1/users（全部需要 ADMIN 角色）
import veb
import time

// UserController — 用户管理接口
pub struct UserController {
pub mut:
	user_service &UserService       = unsafe { nil }
	middleware   &MiddlewareManager = unsafe { nil }
}

// new_user_controller 构造控制器并注入依赖
pub fn new_user_controller(user_svc &UserService, mw &MiddlewareManager) &UserController {
	return unsafe {
		&UserController{
			user_service: user_svc
			middleware:   mw
		}
	}
}

// index GET /api/v1/users — 用户列表（分页）
pub fn (mut c UserController) index(mut ctx Context) veb.Result {
	c.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
	// 限流
	mut ip := '-'
	if ctx.conn != unsafe { nil } {
		addr := ctx.conn.peer_ip() or { return ctx.text('') }
		ip = addr.str()
	}
	c.middleware.apply_rate_limit(ip) or { return ctx.json_error(429, err.msg()) }
	// 查询参数
	page := ctx.query['page'] or { '1' }
	page_size := ctx.query['page_size'] or { '20' }
	keyword := ctx.query['keyword'] or { '' }
	status_str := ctx.query['status'] or { '0' }
	role := ctx.query['role'] or { '' }
	query := UserListQuery{
		page:      page.int()
		page_size: page_size.int()
		keyword:   keyword
		status:    status_str.int()
		role:      role
	}
	users, total := c.user_service.list(query)
	return ctx.json({
		'code':      '200'
		'message':   'OK'
		'data':      json_data(users)
		'total':     '${total}'
		'page':      '${query.page}'
		'page_size': '${query.page_size}'
	})
}

// show GET /api/v1/users/:id — 用户详情
pub fn (c &UserController) show(mut ctx Context) veb.Result {
	c.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
	id_str := ctx.query['id'] or { '' }
	if id_str.len == 0 {
		return ctx.json_error(400, 'missing user ID')
	}
	id := id_str.int()
	user := c.user_service.get_by_id(id) or { return ctx.json_error(404, err.msg()) }
	return ctx.json_response(200, '${UserProfile{
		id:       user.id
		username: user.username
		nickname: user.nickname
		avatar:   user.avatar
		email:    user.email
		role:     user.role
		status:   user.status
		created:  time.unix(user.created_at).format_ss()
	}}')
}

// create POST /api/v1/users — 创建用户
pub fn (mut c UserController) create(mut ctx Context) veb.Result {
	c.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
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
	return ctx.json_response(201, '${UserProfile{
		id:       user.id
		username: user.username
		nickname: user.nickname
		email:    user.email
		role:     user.role
		status:   user.status
		created:  time.unix(user.created_at).format_ss()
	}}')
}

// update PUT /api/v1/users/:id — 更新用户
pub fn (mut c UserController) update(mut ctx Context) veb.Result {
	c.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
	id_str := ctx.query['id'] or { '' }
	if id_str.len == 0 {
		return ctx.json_error(400, 'missing user ID')
	}
	uid := id_str.int()
	email := ctx.query['email'] or { ctx.form['email'] or { '' } }
	nickname := ctx.query['nickname'] or { ctx.form['nickname'] or { '' } }
	avatar := ctx.query['avatar'] or { ctx.form['avatar'] or { '' } }
	req := UpdateUserRequest{
		email:    email
		nickname: nickname
		avatar:   avatar
	}
	user := c.user_service.update(uid, req) or { return ctx.json_error(404, err.msg()) }
	return ctx.json_response(200, '${UserProfile{
		id:       user.id
		username: user.username
		nickname: user.nickname
		email:    user.email
		role:     user.role
		status:   user.status
		created:  time.unix(user.created_at).format_ss()
	}}')
}

// destroy DELETE /api/v1/users/:id — 删除用户
pub fn (mut c UserController) destroy(mut ctx Context) veb.Result {
	c.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
	id_str := ctx.query['id'] or { '' }
	if id_str.len == 0 {
		return ctx.json_error(400, 'missing user ID')
	}
	id := id_str.int()
	c.user_service.delete(id) or { return ctx.json_error(404, err.msg()) }
	return ctx.json_success('user deleted')
}

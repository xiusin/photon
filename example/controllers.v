module main

// controllers.v — Web 控制器层
//
// 注解驱动路由：
//   @[get]    @['/path']  → GET    /path
//   @[post]   @['/path']  → POST   /path
//   @[put]    @['/path']  → PUT    /path
//   @[delete] @['/path']  → DELETE /path
//
// 约定路由（无需注解）：方法返回 veb.Result → GET /${方法名}
// 生命周期钩子：before_request / after_request 自动调用
//
// 注意：注解必须是真正的 V 属性 @[attr]，不是注释。
import veb
import time

// ═══════════════════════════════════════════════════════════
// HomeController — 首页 & 系统信息
// ═══════════════════════════════════════════════════════════

@['/'; get]
pub fn (mut app App) index(mut ctx Context) veb.Result {
	return ctx.json({
		'app':       'Photon API Server'
		'version':   '0.4.0'
		'uptime':    '${time.ticks() - app.start_time}ms'
		'requests':  '${app.req_count}'
		'endpoints': '/health /ping /stats /api/v1/users /api/v1/auth/login /api/v1/auth/profile'
	})
}

@['/health'; get]
pub fn (mut app App) health(mut ctx Context) veb.Result {
	return ctx.json({
		'status':    'UP'
		'version':   '0.4.0'
		'uptime_ms': '${time.ticks() - app.start_time}'
		'timestamp': '${time.now().unix()}'
	})
}

@['/ping'; get]
pub fn (mut app App) ping(mut ctx Context) veb.Result {
	return ctx.text('pong')
}

@['/stats'; get]
pub fn (mut app App) stats(mut ctx Context) veb.Result {
	active_users := app.user_service.count()
	return ctx.json({
		'requests':     '${app.req_count}'
		'uptime_ms':    '${time.ticks() - app.start_time}'
		'active_users': '${active_users}'
		'start_time':   time.unix(app.start_time / 1000).format_ss()
	})
}

@['/cache'; get]
pub fn (mut app App) cache_demo(mut ctx Context) veb.Result {
	key := ctx.query['key'] or { 'default' }
	if app.cache_service != unsafe { nil } {
		if val := app.cache_service.get(key) {
			return ctx.json({
				'source': 'cache'
				'key':    key
				'value':  val
			})
		}
		value := 'computed_${time.ticks()}'
		app.cache_service.set(key, value, 30) or {
			return ctx.server_error('cache write failed: ${err}')
		}
		return ctx.json({
			'source': 'computed'
			'key':    key
			'value':  value
		})
	}
	return ctx.server_error('cache not initialized')
}

@['/request-info'; get]
pub fn (mut app App) request_info(mut ctx Context) veb.Result {
	method := ctx.req.method.str()
	path := ctx.req.url
	host := ctx.req.host
	ua := ctx.req.user_agent
	mut ip := '-'
	if ctx.conn != unsafe { nil } {
		addr := ctx.conn.peer_ip() or { return ctx.text('') }
		ip = addr.str()
	}
	return ctx.json({
		'method':     method
		'path':       path
		'host':       host
		'user-agent': ua
		'ip':         ip
		'time':       time.now().format_ss()
	})
}

// ═══════════════════════════════════════════════════════════
// AuthController — 认证接口
// ═══════════════════════════════════════════════════════════
// API 前缀：/api/v1/auth

@['/api/v1/auth/login'; post]
pub fn (mut app App) post_login(mut ctx Context) veb.Result {
	// 从 query/form 参数读取
	username := ctx.query['username'] or { ctx.form['username'] or { '' } }
	password := ctx.query['password'] or { ctx.form['password'] or { '' } }
	if username.len == 0 || password.len == 0 {
		return ctx.json_error(400, 'username and password required')
	}
	mut req := LoginRequest{
		username: username
		password: password
	}
	resp := app.auth_service.login(req) or { return ctx.json_error(401, err.msg()) }
	return ctx.json_response(200, '${resp}')
}

@['/api/v1/auth/register'; post]
pub fn (mut app App) post_register(mut ctx Context) veb.Result {
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
	user := app.user_service.create(req) or { return ctx.json_error(409, err.msg()) }
	_ = user
	return ctx.json_success('registration successful, please login')
}

@['/api/v1/auth/profile'; get]
pub fn (mut app App) get_profile(mut ctx Context) veb.Result {
	username, _ := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.json_error(401, err.msg())
	}
	profile := app.auth_service.get_profile(username) or { return ctx.json_error(404, err.msg()) }
	return ctx.json_response(200, '${profile}')
}

// ═══════════════════════════════════════════════════════════
// UserController — 用户管理接口
// ═══════════════════════════════════════════════════════════
// API 前缀：/api/v1/users

@['/api/v1/users'; get]
pub fn (mut app App) get_users(mut ctx Context) veb.Result {
	// required
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
	// rate limit
	mut ip := '-'
	if ctx.conn != unsafe { nil } {
		addr := ctx.conn.peer_ip() or { return ctx.text('') }
		ip = addr.str()
	}
	app.middleware.apply_rate_limit(ip) or { return ctx.json_error(429, err.msg()) }
	// 解析查询参数
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
	users, total := app.user_service.list(query)
	return ctx.json({
		'code':      '200'
		'message':   'OK'
		'data':      json_data(users)
		'total':     '${total}'
		'page':      '${query.page}'
		'page_size': '${query.page_size}'
	})
}

@['/api/v1/users/:id'; get]
pub fn (mut app App) get_user(mut ctx Context) veb.Result {
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
	id_str := ctx.query['id'] or { '' }
	if id_str.len == 0 {
		return ctx.json_error(400, 'missing user ID')
	}
	id := id_str.int()
	user := app.user_service.get_by_id(id) or { return ctx.json_error(404, err.msg()) }
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

@['/api/v1/users'; post]
pub fn (mut app App) post_user(mut ctx Context) veb.Result {
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
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
	user := app.user_service.create(req) or { return ctx.json_error(409, err.msg()) }
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

@['/api/v1/users/:id'; put]
pub fn (mut app App) put_user(mut ctx Context) veb.Result {
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
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
	user := app.user_service.update(uid, req) or { return ctx.json_error(404, err.msg()) }
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

@['/api/v1/users/:id'; delete]
pub fn (mut app App) delete_user(mut ctx Context) veb.Result {
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or { return ctx.json_error(403, err.msg()) }
	id_str := ctx.query['id'] or { '' }
	if id_str.len == 0 {
		return ctx.json_error(400, 'missing user ID')
	}
	id := id_str.int()
	app.user_service.delete(id) or { return ctx.json_error(404, err.msg()) }
	return ctx.json_success('user deleted')
}

// ═══════════════════════════════════════════════════════════
// JSON 响应辅助方法
// ═══════════════════════════════════════════════════════════

// json_success 返回成功 JSON
pub fn (mut ctx Context) json_success(message string) veb.Result {
	return ctx.json({
		'code':    '200'
		'message': message
	})
}

// json_error 返回错误 JSON
pub fn (mut ctx Context) json_error(code int, message string) veb.Result {
	return ctx.json({
		'code':    '${code}'
		'message': message
	})
}

// json_response 返回带数据的 JSON
pub fn (mut ctx Context) json_response(code int, data string) veb.Result {
	return ctx.json({
		'code': '${code}'
		'data': data
	})
}

// json_data 将数组转为 JSON 字符串
fn json_data[T](items []T) string {
	if items.len == 0 {
		return '[]'
	}
	mut result := '['
	for i, item in items {
		if i > 0 {
			result += ','
		}
		result += '${item}'
	}
	result += ']'
	return result
}

// ═══════════════════════════════════════════════════════════
// ApiDocController — API 文档路由（thin wrapper → apidoc.ApidocHandler）
// ═══════════════════════════════════════════════════════════

@["/__docs"; get]
pub fn (mut app App) api_docs_index(mut ctx Context) veb.Result {
	return app.apidoc_handler.serve_index(mut ctx.Context)
}

@["/__docs/static/:file"; get]
pub fn (mut app App) api_docs_static(mut ctx Context, file string) veb.Result {
	return app.apidoc_handler.serve_static_file(mut ctx.Context, file)
}

@["/__docs/api/entries"; get]
pub fn (mut app App) api_docs_entries(mut ctx Context) veb.Result {
	return app.apidoc_handler.serve_entries(mut ctx.Context)
}

@["/__docs/api/entries/:id"; get]
pub fn (mut app App) api_docs_entry_get(mut ctx Context, id string) veb.Result {
	return app.apidoc_handler.serve_entry(mut ctx.Context, id)
}

@["/__docs/api/entries/:id"; put]
pub fn (mut app App) api_docs_entry_put(mut ctx Context, id string) veb.Result {
	return app.apidoc_handler.serve_entry(mut ctx.Context, id)
}

@["/__docs/api/entries/:id"; delete]
pub fn (mut app App) api_docs_entry_delete(mut ctx Context, id string) veb.Result {
	return app.apidoc_handler.serve_entry(mut ctx.Context, id)
}

@["/__docs/api/export"; get]
pub fn (mut app App) api_docs_export(mut ctx Context) veb.Result {
	return app.apidoc_handler.serve_export(mut ctx.Context)
}

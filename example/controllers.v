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
import apidoc
import os

// ═══════════════════════════════════════════════════════════
// HomeController — 首页 & 系统信息
// ═══════════════════════════════════════════════════════════

@[get]
@['/']
pub fn (mut app App) index(mut ctx Context) veb.Result {
	return ctx.json({
		'app':       'Photon API Server'
		'version':   '0.4.0'
		'uptime':    '${time.ticks() - app.start_time}ms'
		'requests':  '${app.req_count}'
		'endpoints': '/health /ping /stats /api/v1/users /api/v1/auth/login /api/v1/auth/profile'
	})
}

@[get]
@['/health']
pub fn (mut app App) health(mut ctx Context) veb.Result {
	return ctx.json({
		'status':    'UP'
		'version':   '0.4.0'
		'uptime_ms': '${time.ticks() - app.start_time}'
		'timestamp': '${time.now().unix()}'
	})
}

@[get]
@['/ping']
pub fn (mut app App) ping(mut ctx Context) veb.Result {
	return ctx.text('pong')
}

@[get]
@['/stats']
pub fn (mut app App) stats(mut ctx Context) veb.Result {
	active_users := app.services.user_service.count()
	return ctx.json({
		'requests':     '${app.req_count}'
		'uptime_ms':    '${time.ticks() - app.start_time}'
		'active_users': '${active_users}'
		'start_time':   time.unix(app.start_time / 1000).format_ss()
	})
}

@[get]
@['/cache']
pub fn (mut app App) cache_demo(mut ctx Context) veb.Result {
	key := ctx.query['key'] or { 'default' }
	if app.services.cache_service != unsafe { nil } {
		if val := app.services.cache_service.get(key) {
			return ctx.json({'source': 'cache', 'key': key, 'value': val})
		}
		value := 'computed_${time.ticks()}'
		app.services.cache_service.set(key, value, 30) or {
			return ctx.server_error('cache write failed: ${err}')
		}
		return ctx.json({'source': 'computed', 'key': key, 'value': value})
	}
	return ctx.server_error('cache not initialized')
}

@[get]
@['/request-info']
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

@[post]
@['/api/v1/auth/login']
pub fn (mut app App) post_login(mut ctx Context) veb.Result {
	// 从 query/form 参数读取
	username := ctx.query['username'] or { ctx.form['username'] or { '' } }
	password := ctx.query['password'] or { ctx.form['password'] or { '' } }
	if username.len == 0 || password.len == 0 {
		return ctx.json_error(400, 'username and password required')
	}
	mut req := LoginRequest{username: username, password: password}
	resp := app.services.auth_service.login(req) or {
		return ctx.json_error(401, err.msg())
	}
	return ctx.json_response(200, '${resp}')
}

@[post]
@['/api/v1/auth/register']
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
		email: email
		password: password
		nickname: nickname
	}
	user := app.services.user_service.create(req) or {
		return ctx.json_error(409, err.msg())
	}
	_ = user
	return ctx.json_success('registration successful, please login')
}

@[get]
@['/api/v1/auth/profile']
pub fn (mut app App) get_profile(mut ctx Context) veb.Result {
	username, _ := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.json_error(401, err.msg())
	}
	profile := app.services.auth_service.get_profile(username) or {
		return ctx.json_error(404, err.msg())
	}
	return ctx.json_response(200, '${profile}')
}

// ═══════════════════════════════════════════════════════════
// UserController — 用户管理接口
// ═══════════════════════════════════════════════════════════
// API 前缀：/api/v1/users

@[get]
@['/api/v1/users']
pub fn (mut app App) get_users(mut ctx Context) veb.Result {
	// required
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or {
		return ctx.json_error(403, err.msg())
	}
	// rate limit
	mut ip := '-'
	if ctx.conn != unsafe { nil } {
		addr := ctx.conn.peer_ip() or { return ctx.text('') }
		ip = addr.str()
	}
	app.middleware.apply_rate_limit(ip) or {
		return ctx.json_error(429, err.msg())
	}
	// 解析查询参数
	page := ctx.query['page'] or { '1' }
	page_size := ctx.query['page_size'] or { '20' }
	keyword := ctx.query['keyword'] or { '' }
	status_str := ctx.query['status'] or { '0' }
	role := ctx.query['role'] or { '' }
	query := UserListQuery{
		page: page.int()
		page_size: page_size.int()
		keyword: keyword
		status: status_str.int()
		role: role
	}
	users, total := app.services.user_service.list(query)
	return ctx.json({
		'code':    '200'
		'message': 'OK'
		'data':    json_data(users)
		'total':   '${total}'
		'page':    '${query.page}'
		'page_size': '${query.page_size}'
	})
}

@[get]
@['/api/v1/users/:id']
pub fn (mut app App) get_user(mut ctx Context) veb.Result {
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or {
		return ctx.json_error(403, err.msg())
	}
	id_str := ctx.query['id'] or { '' }
	if id_str.len == 0 {
		return ctx.json_error(400, 'missing user ID')
	}
	id := id_str.int()
	user := app.services.user_service.get_by_id(id) or {
		return ctx.json_error(404, err.msg())
	}
	return ctx.json_response(200, '${UserProfile{
		id: user.id
		username: user.username
		nickname: user.nickname
		avatar: user.avatar
		email: user.email
		role: user.role
		status: user.status
		created: time.unix(user.created_at).format_ss()
	}}')
}

@[post]
@['/api/v1/users']
pub fn (mut app App) post_user(mut ctx Context) veb.Result {
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or {
		return ctx.json_error(403, err.msg())
	}
	username := ctx.query['username'] or { ctx.form['username'] or { '' } }
	email := ctx.query['email'] or { ctx.form['email'] or { '' } }
	password := ctx.query['password'] or { ctx.form['password'] or { '' } }
	nickname := ctx.query['nickname'] or { ctx.form['nickname'] or { '' } }
	if username.len == 0 || email.len == 0 || password.len == 0 {
		return ctx.json_error(400, 'username, email, password required')
	}
	req := CreateUserRequest{username: username, email: email, password: password, nickname: nickname}
	user := app.services.user_service.create(req) or {
		return ctx.json_error(409, err.msg())
	}
	return ctx.json_response(201, '${UserProfile{
		id: user.id
		username: user.username
		nickname: user.nickname
		email: user.email
		role: user.role
		status: user.status
		created: time.unix(user.created_at).format_ss()
	}}')
}

@[put]
@['/api/v1/users/:id']
pub fn (mut app App) put_user(mut ctx Context) veb.Result {
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or {
		return ctx.json_error(403, err.msg())
	}
	id_str := ctx.query['id'] or { '' }
	if id_str.len == 0 {
		return ctx.json_error(400, 'missing user ID')
	}
	id := id_str.int()
	email := ctx.query['email'] or { ctx.form['email'] or { '' } }
	nickname := ctx.query['nickname'] or { ctx.form['nickname'] or { '' } }
	avatar := ctx.query['avatar'] or { ctx.form['avatar'] or { '' } }
	req := UpdateUserRequest{email: email, nickname: nickname, avatar: avatar}
	user := app.services.user_service.update(id, req) or {
		return ctx.json_error(404, err.msg())
	}
	return ctx.json_response(200, '${UserProfile{
		id: user.id
		username: user.username
		nickname: user.nickname
		email: user.email
		role: user.role
		status: user.status
		created: time.unix(user.created_at).format_ss()
	}}')
}

@[delete]
@['/api/v1/users/:id']
pub fn (mut app App) delete_user(mut ctx Context) veb.Result {
	app.middleware.apply_role(mut ctx.Context, 'ADMIN') or {
		return ctx.json_error(403, err.msg())
	}
	id_str := ctx.query['id'] or { '' }
	if id_str.len == 0 {
		return ctx.json_error(400, 'missing user ID')
	}
	id := id_str.int()
	app.services.user_service.delete(id) or {
		return ctx.json_error(404, err.msg())
	}
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
		'code':    '${code}'
		'data':    data
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
// DocController — API 文档自动生成路由
// ═══════════════════════════════════════════════════════════

@[get]
@['/__docs']
pub fn (mut app App) api_docs_index(mut ctx Context) veb.Result {
	html_path := 'apidoc/static/index.html'
	html := os.read_file(html_path) or {
		return ctx.text('API Documentation UI not found (expected at ${html_path})')
	}
	ctx.set_content_type('text/html; charset=utf-8')
	return ctx.text(html)
}

@[get]
@['/__docs/static/:file']
pub fn (mut app App) api_docs_static(mut ctx Context) veb.Result {
	filename := ctx.query['file'] or { '' }
	if filename.len == 0 {
		return ctx.json_error(400, 'missing filename')
	}
	// sanitize: 只允许字母数字 . / _
	safe_chars := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-'
	for ch in filename {
		if ch !in safe_chars.bytes() {
			return ctx.json_error(400, 'invalid filename')
		}
	}
	file_path := 'apidoc/static/${filename}'
	content := os.read_file(file_path) or {
		return ctx.json_error(404, 'static file not found')
	}
	// 根据扩展名设置 Content-Type
	if filename.ends_with('.css') {
		ctx.set_content_type('text/css; charset=utf-8')
	} else if filename.ends_with('.js') {
		ctx.set_content_type('application/javascript; charset=utf-8')
	} else if filename.ends_with('.html') {
		ctx.set_content_type('text/html; charset=utf-8')
	} else if filename.ends_with('.json') {
		ctx.set_content_type('application/json; charset=utf-8')
	} else if filename.ends_with('.png') {
		ctx.set_content_type('image/png')
	} else if filename.ends_with('.svg') {
		ctx.set_content_type('image/svg+xml')
	} else if filename.ends_with('.ico') {
		ctx.set_content_type('image/x-icon')
	} else {
		ctx.set_content_type('text/plain; charset=utf-8')
	}
	return ctx.text(content)
}

// get_entries 获取所有文档条目
@[get]
@['/__docs/api/entries']
pub fn (mut app App) api_docs_get_entries(mut ctx Context) veb.Result {
	entries := app.doc_store.get_entries()
	// 手动构建 JSON 响应（避免 V 泛型与 &ApiDocEntry 的 C 代码生成 bug）
	mut items_str := '['
	for i, e in entries {
		if i > 0 { items_str += ',' }
		items_str += e.to_json()
	}
	items_str += ']'
	return ctx.text(apidoc.encode_response(0, 'OK', items_str))
}

// get_entry 获取单条文档
@[get]
@['/__docs/api/entries/:id']
pub fn (mut app App) api_docs_get_entry(mut ctx Context) veb.Result {
	id := ctx.query['id'] or { return ctx.text(apidoc.api_error(400, 'missing id')) }
	entry := app.doc_store.get_entry(id) or {
		return ctx.text(apidoc.api_error(404, err.msg()))
	}
	return ctx.text(apidoc.encode_response(0, 'OK', entry.to_json()))
}

// update_entry 更新文档条目（编辑/锁定）
@[put]
@['/__docs/api/entries/:id']
pub fn (mut app App) api_docs_update_entry(mut ctx Context) veb.Result {
	id := ctx.query['id'] or { return ctx.text(apidoc.api_error(400, 'missing id')) }
	body := ctx.req.data
	if body.len == 0 {
		return ctx.text(apidoc.api_error(400, 'empty request body'))
	}

	entry := app.doc_store.get_entry(id) or {
		return ctx.text(apidoc.api_error(404, err.msg()))
	}

	// 解析变更
	mut changes := parse_update_body(body)
	// 简单字段更新 — 全部在 unsafe 中完成（entry 是 &ApiDocEntry 经过 map 取得）
	unsafe {
		if changes['summary'] != '' {
			entry.summary = changes['summary']
		}
		if changes['group'] != '' {
			entry.group = changes['group']
		}
		if changes['locked'] == 'true' || changes['locked'] == 'false' {
			entry.locked = changes['locked'] == 'true'
		}
		if changes['is_hidden'] == 'true' || changes['is_hidden'] == 'false' {
			entry.is_hidden = changes['is_hidden'] == 'true'
		}
	}
	// 参数编辑
	if changes['editParam.location'] != '' {
		loc := changes['editParam.location']
		name := changes['editParam.name']
		field := changes['editParam.field']
		value := changes['editParam.value']
		for i := 0; i < entry.parameters.len; i++ {
			if entry.parameters[i].name == name && entry.parameters[i].location == loc {
				unsafe {
					if field == 'description' {
						entry.parameters[i].description = value
					}
				}
				break
			}
		}
	}
	if changes['toggleParamLock.location'] != '' {
		loc := changes['toggleParamLock.location']
		name := changes['toggleParamLock.name']
		for i := 0; i < entry.parameters.len; i++ {
			if entry.parameters[i].name == name && entry.parameters[i].location == loc {
				unsafe { entry.parameters[i].locked = !entry.parameters[i].locked }
				break
			}
		}
	}
	// 请求头锁定切换
	if changes['toggleHeaderLock.name'] != '' {
		name := changes['toggleHeaderLock.name']
		for i := 0; i < entry.headers.len; i++ {
			if entry.headers[i].name == name {
				unsafe { entry.headers[i].locked = !entry.headers[i].locked }
				break
			}
		}
	}
	// 响应属性编辑
	if changes['editRespProp.path'] != '' {
		prop_path := changes['editRespProp.path']
		field := changes['editRespProp.field']
		value := changes['editRespProp.value']
		for i := 0; i < entry.response.properties.len; i++ {
			if entry.response.properties[i].path == prop_path {
				unsafe {
					if field == 'description' {
						entry.response.properties[i].description = value
					}
				}
				break
			}
		}
	}
	if changes['toggleRespPropLock.path'] != '' {
		prop_path := changes['toggleRespPropLock.path']
		for i := 0; i < entry.response.properties.len; i++ {
			if entry.response.properties[i].path == prop_path {
				unsafe { entry.response.properties[i].locked = !entry.response.properties[i].locked }
				break
			}
		}
	}

	app.doc_store.update_entry(id, entry) or {
		return ctx.text(apidoc.api_error(500, err.msg()))
	}
	return ctx.text(apidoc.encode_response(0, 'OK', '{}'))
}

// delete_entry 删除文档条目
@[delete]
@['/__docs/api/entries/:id']
pub fn (mut app App) api_docs_delete_entry(mut ctx Context) veb.Result {
	id := ctx.query['id'] or { return ctx.text(apidoc.api_error(400, 'missing id')) }
	app.doc_store.delete_entry(id) or {
		return ctx.text(apidoc.api_error(500, err.msg()))
	}
	return ctx.text(apidoc.encode_response(0, 'deleted', '{}'))
}

// parse_update_body 简化版 JSON 解析（从请求体提取字段）
fn parse_update_body(body string) map[string]string {
	mut result := map[string]string{}
	// 简单 key-value 解析，仅用于已知字段
	mut pos := 0
	for pos < body.len {
		// 跳空白
		for pos < body.len && (body[pos] == ` ` || body[pos] == `\n` || body[pos] == `\t` || body[pos] == `\r` || body[pos] == `{` || body[pos] == `}` || body[pos] == `"`) {
			if body[pos] == `"` || body[pos] == `{` || body[pos] == `}` {
				pos++
				continue
			}
			pos++
		}
		if pos >= body.len {
			break
		}
		// 找 key
		key_start := pos
		for pos < body.len && body[pos] != `:` && body[pos] != `\n` && body[pos] != `,` && body[pos] != ` ` && body[pos] != `\t` {
			pos++
		}
		if pos >= body.len {
			break
		}
		key := body[key_start..pos]
		// 跳 :
		for pos < body.len && (body[pos] == `:` || body[pos] == ` ` || body[pos] == `\t`) {
			pos++
		}
		if pos >= body.len {
			break
		}
		// 找 value（简单字符串或字面值）
		if body[pos] == `"` {
			pos++ // 跳过起始引号
			val_start := pos
			for pos < body.len && body[pos] != `"` {
				if body[pos] == `\\` {
					pos += 2
				} else {
					pos++
				}
			}
			result[key.trim_space()] = body[val_start..pos]
			pos++ // 跳过结束引号
		} else if body[pos] == `{` || body[pos] == `[` {
			// 嵌套对象 — 跳过，只记录标记
			mut depth := 1
			pos++
			for pos < body.len && depth > 0 {
				if body[pos] == `{` || body[pos] == `[` {
					depth++
				} else if body[pos] == `}` || body[pos] == `]` {
					depth--
				}
				pos++
			}
			result[key.trim_space()] = 'nested'
		} else {
			// 字面值
			val_start := pos
			for pos < body.len && body[pos] != `,` && body[pos] != `\n` && body[pos] != `\r` && body[pos] != `}` {
				pos++
			}
			result[key.trim_space()] = body[val_start..pos].trim_space()
		}
	}
	return result
}

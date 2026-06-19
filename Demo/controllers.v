module main

// controllers.v — PhotonBlog Web 控制器层
//
// 注解驱动路由（veb 框架）：
//   @[get]    @['/path']           → GET    /path
//   @[post]   @['/path']           → POST   /path
//   @[put]    @['/path']           → PUT    /path
//   @[delete] @['/path']           → DELETE /path
//
// 路径参数通过方法参数传递：@['/api/v1/users/:id'] → fn ...(mut ctx Context, id string)
//
// 统一响应格式：
//   {"success":bool,"code":int,"message":string,"data":...,"timestamp":i64}
//
// 认证流程：
//   1. app.middleware.apply_auth(mut ctx.Context) → (username, roles)
//   2. app.middleware.apply_role(['ADMIN'], roles) → 通过或抛错
//
// 控制器清单（27 个端点）：
//   Task 12: 系统      — index / health / ping / stats
//   Task 13: 认证      — register / login / refresh / profile / logout
//   Task 14: 用户管理  — list / get / create / update / delete（需 ADMIN）
//   Task 15: 文章      — list / get / create / update / delete（公开 / EDITOR+ / ADMIN）
//   Task 16: 评论      — list / create / delete
//   Task 17: 分类&标签 — categories list/create + tags list/create
//   Task 18: 文件上传  — avatar / image / file access

import veb
import json
import time
import net.http
import photon.web

// ═══════════════════════════════════════════════════════════
// 统一响应辅助函数
// ═══════════════════════════════════════════════════════════

// ok_resp 构建成功响应 JSON 字符串
// data_json 必须是合法的 JSON 值（对象、数组、字符串、null 等）
fn ok_resp(data_json string) string {
	ts := time.now().unix()
	return '{"success":true,"code":200,"message":"OK","data":' + data_json + ',"timestamp":' +
		ts.str() + '}'
}

// err_resp 构建错误响应 JSON 字符串
fn err_resp(code int, message string) string {
	ts := time.now().unix()
	msg_json := json.encode(message)
	return '{"success":false,"code":' + code.str() + ',"message":' + msg_json + ',"timestamp":' +
		ts.str() + '}'
}

// send_ok 发送成功 JSON 响应（HTTP 200）
fn (mut ctx Context) send_ok(data_json string) veb.Result {
	return ctx.send_response_to_client('application/json', ok_resp(data_json))
}

// send_err 发送错误 JSON 响应，附带 HTTP 状态码
fn (mut ctx Context) send_err(status http.Status, code int, message string) veb.Result {
	ctx.res.set_status(status)
	return ctx.send_response_to_client('application/json', err_resp(code, message))
}

// parse_body 解析 JSON 请求体到指定类型，失败时返回错误
// 调用方使用 or 块处理错误（空体或解析失败）
fn (mut ctx Context) parse_body[T]() !T {
	// veb 框架中，JSON body 通过 ctx.req.data 获取
	// 但某些情况下 req.data 为空，需要回退到 form 参数
	body := ctx.req.data
	if body.len > 0 {
		return json.decode(T, body) or { error('invalid JSON: ${err}') }
	}
	return error('empty body / 请求体为空')
}

// parse_body_or_form 解析 JSON body，失败时从 form 参数构建
// 这是为了兼容 veb 框架中 ctx.req.data 可能为空的情况
fn (mut ctx Context) parse_body_or_form[T](form_builder fn (mut ctx Context) !T) !T {
	body := ctx.req.data
	if body.len > 0 {
		return json.decode(T, body) or { form_builder(mut ctx) }
	}
	return form_builder(mut ctx)
}

// form_builder 函数：从 ctx.form 参数构建 DTO，作为 JSON body 解析失败时的回退

fn build_create_user_dto(mut ctx Context) !CreateUserDto {
	return CreateUserDto{
		username: ctx.form['username'] or { '' }
		email: ctx.form['email'] or { '' }
		password: ctx.form['password'] or { '' }
		nickname: ctx.form['nickname'] or { '' }
		role: ctx.form['role'] or { 'USER' }
	}
}

fn build_login_dto(mut ctx Context) !LoginDto {
	return LoginDto{
		username: ctx.form['username'] or { '' }
		password: ctx.form['password'] or { '' }
	}
}

fn build_update_user_dto(mut ctx Context) !UpdateUserDto {
	return UpdateUserDto{
		email: ctx.form['email'] or { '' }
		nickname: ctx.form['nickname'] or { '' }
		avatar: ctx.form['avatar'] or { '' }
		status: (ctx.form['status'] or { '0' }).int()
		role: ctx.form['role'] or { '' }
	}
}

fn build_create_post_dto(mut ctx Context) !CreatePostDto {
	return CreatePostDto{
		title: ctx.form['title'] or { '' }
		content: ctx.form['content'] or { '' }
		summary: ctx.form['summary'] or { '' }
		author_id: (ctx.form['author_id'] or { '0' }).int()
		category_id: (ctx.form['category_id'] or { '0' }).int()
		status: ctx.form['status'] or { 'draft' }
	}
}

fn build_update_post_dto(mut ctx Context) !UpdatePostDto {
	return UpdatePostDto{
		title: ctx.form['title'] or { '' }
		content: ctx.form['content'] or { '' }
		summary: ctx.form['summary'] or { '' }
		category_id: (ctx.form['category_id'] or { '0' }).int()
		status: ctx.form['status'] or { '' }
	}
}

fn build_create_category_dto(mut ctx Context) !CreateCategoryDto {
	return CreateCategoryDto{
		name: ctx.form['name'] or { '' }
		slug: ctx.form['slug'] or { '' }
		description: ctx.form['description'] or { '' }
	}
}

fn build_create_tag_dto(mut ctx Context) !CreateTagDto {
	return CreateTagDto{
		name: ctx.form['name'] or { '' }
		slug: ctx.form['slug'] or { '' }
	}
}

// ═══════════════════════════════════════════════════════════
// Task 12: 系统控制器 — 首页 & 系统信息
// ═══════════════════════════════════════════════════════════

// index GET / — 应用信息与端点列表
@[get]
@['/']
pub fn (mut app App) index(mut ctx Context) veb.Result {
	uptime_ms := time.ticks() - app.start_time
	data := '{"app":"${app.bootstrap.cfg.app.name}","version":"${app.bootstrap.cfg.app.version}","profile":"${app.bootstrap.cfg.profile}","uptime_ms":${uptime_ms},"requests":${app.req_count},"endpoints":["/health","/ping","/stats","/api/v1/auth/register","/api/v1/auth/login","/api/v1/auth/refresh","/api/v1/auth/profile","/api/v1/auth/logout","/api/v1/users","/api/v1/posts","/api/v1/posts/:id/comments","/api/v1/categories","/api/v1/tags","/api/v1/uploads/avatar","/api/v1/uploads/image"]}'
	return ctx.send_ok(data)
}

// health GET /health — 健康检查（状态/版本/uptime/时间戳）
@[get]
@['/health']
pub fn (mut app App) health(mut ctx Context) veb.Result {
	uptime_ms := time.ticks() - app.start_time
	data := '{"status":"UP","version":"${app.bootstrap.cfg.app.version}","uptime_ms":${uptime_ms},"timestamp":${time.now().unix()}}'
	return ctx.send_ok(data)
}

// ping GET /ping — 连通性测试，返回 'pong'
@[get]
@['/ping']
pub fn (mut app App) ping(mut ctx Context) veb.Result {
	return ctx.text('pong')
}

// stats GET /stats — 服务器统计（请求数/用户数/文章数/评论数）
@[get]
@['/stats']
pub fn (mut app App) stats(mut ctx Context) veb.Result {
	uptime_ms := time.ticks() - app.start_time

	// 通过 StatsService 获取博客统计（带缓存）
	mut stats_svc := app.bootstrap.stats_svc
	blog_stats := stats_svc.get_blog_stats() or {
		// 统计服务失败时返回基础信息
		return ctx.send_ok('{"requests":${app.req_count},"uptime_ms":${uptime_ms},"user_count":0,"post_count":0,"comment_count":0,"timestamp":${time.now().unix()}}')
	}

	data := '{"requests":${app.req_count},"uptime_ms":${uptime_ms},"user_count":${blog_stats.user_count},"post_count":${blog_stats.post_count},"published_count":${blog_stats.published_count},"draft_count":${blog_stats.draft_count},"comment_count":${blog_stats.comment_count},"aggregated_at":${blog_stats.aggregated_at}}'
	return ctx.send_ok(data)
}

// ═══════════════════════════════════════════════════════════
// Task 13: 认证控制器 — 注册/登录/刷新/资料/登出
// ═══════════════════════════════════════════════════════════

// post_auth_register POST /api/v1/auth/register — 用户注册（触发 user.registered 事件）
@[post]
@['/api/v1/auth/register']
pub fn (mut app App) post_auth_register(mut ctx Context) veb.Result {
	// 解析请求体
	dto := ctx.parse_body_or_form[CreateUserDto](build_create_user_dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}
	return app.do_register(mut ctx, dto)
}

// do_register 执行注册逻辑（内部辅助方法）
fn (mut app App) do_register(mut ctx Context, dto CreateUserDto) veb.Result {
	// 校验必填字段
	if dto.username.len == 0 || dto.email.len == 0 || dto.password.len == 0 {
		return ctx.send_err(.bad_request, 400, 'username, email, password required / 用户名、邮箱、密码为必填项')
	}

	// 调用服务层注册（触发 user.registered 事件）
	mut user_svc := app.bootstrap.user_svc
	user, _ := user_svc.register(dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}

	// 返回用户信息（脱敏）
	profile := user_svc.to_profile_dto(&user)
	return ctx.send_ok(json.encode(profile))
}

// post_auth_login POST /api/v1/auth/login — 用户登录，返回 JWT
@[post]
@['/api/v1/auth/login']
pub fn (mut app App) post_auth_login(mut ctx Context) veb.Result {
	// 解析请求体
	dto := ctx.parse_body_or_form[LoginDto](build_login_dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}
	return app.do_login(mut ctx, dto)
}

// do_login 执行登录逻辑（内部辅助方法）
fn (mut app App) do_login(mut ctx Context, dto LoginDto) veb.Result {
	// 校验必填字段
	if dto.username.len == 0 || dto.password.len == 0 {
		return ctx.send_err(.bad_request, 400, 'username and password required / 用户名和密码为必填项')
	}

	// 调用服务层登录
	mut user_svc := app.bootstrap.user_svc
	user := user_svc.login(dto) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}

	// 构建登录响应（生成 JWT 令牌）
	mut auth_svc := app.bootstrap.auth_svc
	resp := auth_svc.build_login_response(&user) or {
		return ctx.send_err(.internal_server_error, 500, 'failed to generate token / 令牌生成失败: ${err}')
	}

	return ctx.send_ok(json.encode(resp))
}

// post_auth_refresh POST /api/v1/auth/refresh — 刷新访问令牌
@[post]
@['/api/v1/auth/refresh']
pub fn (mut app App) post_auth_refresh(mut ctx Context) veb.Result {
	// 从请求体或表单获取 refresh_token
	mut refresh_token := ctx.form['refresh_token'] or { '' }
	if refresh_token.len == 0 {
		// 尝试从 JSON 请求体解析
		body := ctx.req.data
		if body.len > 0 {
			// 简单解析 JSON 中的 refresh_token 字段
			refresh_token = extract_json_field(body, 'refresh_token')
		}
	}

	if refresh_token.len == 0 {
		return ctx.send_err(.bad_request, 400, 'refresh_token required / 缺少 refresh_token')
	}

	// 调用服务层刷新令牌
	mut auth_svc := app.bootstrap.auth_svc
	access_token, new_refresh_token := auth_svc.refresh_token(refresh_token) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}

	data := '{"access_token":"${access_token}","refresh_token":"${new_refresh_token}","token_type":"Bearer","expires_in":3600}'
	return ctx.send_ok(data)
}

// get_auth_profile GET /api/v1/auth/profile — 获取当前用户信息（需 JWT）
@[get]
@['/api/v1/auth/profile']
pub fn (mut app App) get_auth_profile(mut ctx Context) veb.Result {
	// JWT 认证
	username, _ := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}

	// 查询用户信息
	user_svc := app.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_err(.not_found, 404, 'user not found / 用户不存在: ${username}')
	}

	// 返回用户信息（脱敏）
	profile := user_svc.to_profile_dto(&user)
	return ctx.send_ok(json.encode(profile))
}

// post_auth_logout POST /api/v1/auth/logout — 登出（客户端清除 token）
@[post]
@['/api/v1/auth/logout']
pub fn (mut app App) post_auth_logout(mut ctx Context) veb.Result {
	// JWT 认证（可选，即使 token 过期也允许登出）
	_, _ = app.middleware.apply_auth(mut ctx.Context) or {
		// 即使认证失败也返回成功（客户端应清除 token）
		return ctx.send_ok('{"message":"logged out / 已登出"}')
	}

	// 返回成功（JWT 无状态，服务端无需额外处理，客户端清除 token 即可）
	return ctx.send_ok('{"message":"logged out / 已登出"}')
}

// ═══════════════════════════════════════════════════════════
// Task 14: 用户管理控制器 — CRUD（均需 ADMIN）
// ═══════════════════════════════════════════════════════════

// get_users GET /api/v1/users — 用户分页列表（需 ADMIN，支持 keyword/status/role 过滤）
@[get]
@['/api/v1/users']
pub fn (mut app App) get_users(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	// 解析查询参数
	page_str := ctx.query['page'] or { '1' }
	page_size_str := ctx.query['page_size'] or { '20' }
	keyword := ctx.query['keyword'] or { '' }
	status_str := ctx.query['status'] or { '0' }
	role_filter := ctx.query['role'] or { '' }

	mut page := page_str.int()
	mut page_size := page_size_str.int()
	if page < 1 {
		page = 1
	}
	if page_size < 1 || page_size > 100 {
		page_size = 20
	}
	status_filter := status_str.int()

	// 查询所有用户
	mut user_svc := app.bootstrap.user_svc
	users := user_svc.find_all() or {
		return ctx.send_err(.internal_server_error, 500, 'failed to fetch users / 获取用户列表失败: ${err}')
	}

	// 过滤
	mut filtered := []UserProfileDto{}
	for u in users {
		if keyword.len > 0 && !u.username.contains(keyword) && !u.email.contains(keyword) {
			continue
		}
		if status_filter != 0 && u.status != status_filter {
			continue
		}
		if role_filter.len > 0 && u.role != role_filter {
			continue
		}
		filtered << user_svc.to_profile_dto(&u)
	}

	// 分页
	total := filtered.len
	start := (page - 1) * page_size
	end := if start + page_size > total { total } else { start + page_size }
	mut paged := []UserProfileDto{}
	if start < total {
		paged = filtered[start..end].clone()
	}

	data := '{"items":${json.encode(paged)},"total":${total},"page":${page},"page_size":${page_size},"has_more":${end < total}}'
	return ctx.send_ok(data)
}

// get_user GET /api/v1/users/:id — 用户详情（需 ADMIN）
@[get]
@['/api/v1/users/:id']
pub fn (mut app App) get_user(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid user id / 无效的用户 ID')
	}

	mut user_svc := app.bootstrap.user_svc
	user := user_svc.find_by_id(user_id) or {
		return ctx.send_err(.not_found, 404, 'user not found / 用户不存在: ${id}')
	}

	profile := user_svc.to_profile_dto(&user)
	return ctx.send_ok(json.encode(profile))
}

// post_user POST /api/v1/users — 创建用户（需 ADMIN）
@[post]
@['/api/v1/users']
pub fn (mut app App) post_user(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	// 解析请求体
	dto := ctx.parse_body_or_form[CreateUserDto](build_create_user_dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}
	return app.do_admin_create_user(mut ctx, dto)
}

// do_admin_create_user 管理员创建用户（内部辅助方法）
fn (mut app App) do_admin_create_user(mut ctx Context, dto CreateUserDto) veb.Result {
	if dto.username.len == 0 || dto.email.len == 0 || dto.password.len == 0 {
		return ctx.send_err(.bad_request, 400, 'username, email, password required / 用户名、邮箱、密码为必填项')
	}

	mut user_svc := app.bootstrap.user_svc
	user, _ := user_svc.register(dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}

	profile := user_svc.to_profile_dto(&user)
	ctx.res.set_status(.created)
	return ctx.send_response_to_client('application/json', ok_resp(json.encode(profile)))
}

// put_user PUT /api/v1/users/:id — 更新用户（需 ADMIN）
@[put]
@['/api/v1/users/:id']
pub fn (mut app App) put_user(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid user id / 无效的用户 ID')
	}

	// 解析请求体
	dto := ctx.parse_body_or_form[UpdateUserDto](build_update_user_dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}
	return app.do_update_user(mut ctx, user_id, dto)
}

// do_update_user 执行用户更新（内部辅助方法）
fn (mut app App) do_update_user(mut ctx Context, user_id int, dto UpdateUserDto) veb.Result {
	mut user_svc := app.bootstrap.user_svc
	user := user_svc.update(user_id, dto) or {
		return ctx.send_err(.not_found, 404, err.msg())
	}

	profile := user_svc.to_profile_dto(&user)
	return ctx.send_ok(json.encode(profile))
}

// delete_user DELETE /api/v1/users/:id — 删除用户（需 ADMIN，软删除）
@[delete]
@['/api/v1/users/:id']
pub fn (mut app App) delete_user(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid user id / 无效的用户 ID')
	}

	user_svc := app.bootstrap.user_svc
	user_svc.delete(user_id) or {
		return ctx.send_err(.not_found, 404, err.msg())
	}

	return ctx.send_ok('{"message":"user deleted / 用户已删除"}')
}

// ═══════════════════════════════════════════════════════════
// Task 15: 文章控制器 — CRUD（公开 / EDITOR+ / ADMIN）
// ═══════════════════════════════════════════════════════════

// get_posts GET /api/v1/posts — 文章分页列表（公开，支持 category/tag/keyword/status 过滤 + 排序）
@[get]
@['/api/v1/posts']
pub fn (mut app App) get_posts(mut ctx Context) veb.Result {
	// 解析查询参数
	page_str := ctx.query['page'] or { '1' }
	page_size_str := ctx.query['page_size'] or { '20' }
	category := ctx.query['category'] or { '' }
	tag := ctx.query['tag'] or { '' }
	keyword := ctx.query['keyword'] or { '' }
	status := ctx.query['status'] or { 'published' }
	sort := ctx.query['sort'] or { 'created_at_desc' }

	mut page := page_str.int()
	mut page_size := page_size_str.int()
	if page < 1 {
		page = 1
	}
	if page_size < 1 || page_size > 100 {
		page_size = 20
	}

	// 查询文章
	mut post_svc := app.bootstrap.post_svc
	mut posts := []Post{}

	if status == 'published' {
		posts = post_svc.find_published() or {
			return ctx.send_err(.internal_server_error, 500, 'failed to fetch posts / 获取文章列表失败: ${err}')
		}
	} else {
		posts = post_svc.find_all() or {
			return ctx.send_err(.internal_server_error, 500, 'failed to fetch posts / 获取文章列表失败: ${err}')
		}
	}

	// 按状态过滤
	if status.len > 0 && status != 'all' {
		mut filtered := []Post{}
		for p in posts {
			if p.status == status {
				filtered << p
			}
		}
		posts = filtered.clone()
	}

	// 按分类过滤
	if category.len > 0 {
		category_id := category.int()
		if category_id > 0 {
			mut filtered := []Post{}
			for p in posts {
				if p.category_id == category_id {
					filtered << p
				}
			}
			posts = filtered.clone()
		}
	}

	// 按标签过滤
	if tag.len > 0 {
		tag_svc := app.bootstrap.tag_svc
		tag_id := tag.int()
		if tag_id > 0 {
			post_ids := tag_svc.find_post_ids_by_tag(tag_id) or { []int{} }
			mut filtered := []Post{}
			for p in posts {
				if p.id in post_ids {
					filtered << p
				}
			}
			posts = filtered.clone()
		}
	}

	// 按关键词过滤
	if keyword.len > 0 {
		mut filtered := []Post{}
		for p in posts {
			if p.title.contains(keyword) || p.summary.contains(keyword) || p.content.contains(keyword) {
				filtered << p
			}
		}
		posts = filtered.clone()
	}

	// 排序
	if sort == 'created_at_asc' {
		// 按创建时间升序（简单冒泡排序，文章数不多时可用）
		mut sorted := posts.clone()
		for i in 0 .. sorted.len {
			for j in i + 1 .. sorted.len {
				if sorted[i].created_at > sorted[j].created_at {
					tmp := sorted[i]
					sorted[i] = sorted[j]
					sorted[j] = tmp
				}
			}
		}
		posts = sorted.clone()
	} else if sort == 'views_desc' {
		// 按浏览量降序
		mut sorted := posts.clone()
		for i in 0 .. sorted.len {
			for j in i + 1 .. sorted.len {
				if sorted[i].views < sorted[j].views {
					tmp := sorted[i]
					sorted[i] = sorted[j]
					sorted[j] = tmp
				}
			}
		}
		posts = sorted.clone()
	}
	// 默认 created_at_desc — 数据库已按时间倒序返回，无需额外排序

	// 分页
	total := posts.len
	start := (page - 1) * page_size
	end := if start + page_size > total { total } else { start + page_size }
	mut paged := []Post{}
	if start < total {
		paged = posts[start..end].clone()
	}

	data := '{"items":${json.encode(paged)},"total":${total},"page":${page},"page_size":${page_size},"has_more":${end < total}}'
	return ctx.send_ok(data)
}

// get_post GET /api/v1/posts/:id — 文章详情（公开，自增 views，缓存命中）
@[get]
@['/api/v1/posts/:id']
pub fn (mut app App) get_post(mut ctx Context, id string) veb.Result {
	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid post id / 无效的文章 ID')
	}

	mut post_svc := app.bootstrap.post_svc
	post := post_svc.find_by_id(post_id) or {
		return ctx.send_err(.not_found, 404, 'post not found / 文章不存在: ${id}')
	}

	// 异步自增浏览量（不阻塞响应）
	go post_svc.increment_views(post_id)

	return ctx.send_ok(json.encode(post))
}

// post_post POST /api/v1/posts — 创建文章（需 EDITOR+，触发 post.published 事件）
@[post]
@['/api/v1/posts']
pub fn (mut app App) post_post(mut ctx Context) veb.Result {
	// 认证 + 角色校验（EDITOR+ 包含 ADMIN）
	username, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	// 获取当前用户 ID（作为作者）
	user_svc := app.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_err(.unauthorized, 401, 'user not found / 用户不存在')
	}

	// 解析请求体 — 先尝试从 form 参数获取，再尝试 JSON body
	// veb 框架中 req.data 可能为空，form 参数更可靠
	title := ctx.form['title'] or { '' }
	content := ctx.form['content'] or { '' }
	mut dto := CreatePostDto{
		title: title
		content: content
		summary: ctx.form['summary'] or { '' }
		author_id: user.id
		category_id: (ctx.form['category_id'] or { '0' }).int()
		status: ctx.form['status'] or { 'draft' }
	}

	// 如果 form 参数为空，尝试解析 JSON body
	if dto.title.len == 0 || dto.content.len == 0 {
		body := ctx.req.data
		if body.len > 0 {
			json_dto := json.decode(CreatePostDto, body) or {
				return ctx.send_err(.bad_request, 400, 'invalid JSON: ${err}')
			}
			if json_dto.title.len > 0 {
				dto = CreatePostDto{
					...json_dto
					author_id: user.id
				}
			}
		}
	}

	return app.do_create_post(mut ctx, dto)
}

// do_create_post 执行文章创建（内部辅助方法）
fn (mut app App) do_create_post(mut ctx Context, dto CreatePostDto) veb.Result {
	if dto.title.len == 0 || dto.content.len == 0 {
		return ctx.send_err(.bad_request, 400, 'title and content required / 标题和内容为必填项')
	}

	mut post_svc := app.bootstrap.post_svc
	post := post_svc.create(dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}

	ctx.res.set_status(.created)
	return ctx.send_response_to_client('application/json', ok_resp(json.encode(post)))
}

// put_post PUT /api/v1/posts/:id — 更新文章（需 EDITOR+，清除缓存）
@[put]
@['/api/v1/posts/:id']
pub fn (mut app App) put_post(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid post id / 无效的文章 ID')
	}

	// 解析请求体
	dto := ctx.parse_body_or_form[UpdatePostDto](build_update_post_dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}
	return app.do_update_post(mut ctx, post_id, dto)
}

// do_update_post 执行文章更新（内部辅助方法）
fn (mut app App) do_update_post(mut ctx Context, post_id int, dto UpdatePostDto) veb.Result {
	mut post_svc := app.bootstrap.post_svc
	post := post_svc.update(post_id, dto) or {
		return ctx.send_err(.not_found, 404, err.msg())
	}

	return ctx.send_ok(json.encode(post))
}

// delete_post DELETE /api/v1/posts/:id — 删除文章（需 ADMIN）
@[delete]
@['/api/v1/posts/:id']
pub fn (mut app App) delete_post(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid post id / 无效的文章 ID')
	}

	mut post_svc := app.bootstrap.post_svc
	post_svc.delete(post_id) or {
		return ctx.send_err(.not_found, 404, err.msg())
	}

	return ctx.send_ok('{"message":"post deleted / 文章已删除"}')
}

// ═══════════════════════════════════════════════════════════
// Task 16: 评论控制器 — 列表/创建/删除
// ═══════════════════════════════════════════════════════════

// get_post_comments GET /api/v1/posts/:id/comments — 文章评论列表（公开，支持嵌套）
@[get]
@['/api/v1/posts/:id/comments']
pub fn (mut app App) get_post_comments(mut ctx Context, id string) veb.Result {
	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid post id / 无效的文章 ID')
	}

	comment_svc := app.bootstrap.comment_svc
	comments := comment_svc.find_by_post(post_id) or {
		return ctx.send_err(.internal_server_error, 500, 'failed to fetch comments / 获取评论失败: ${err}')
	}

	// 构建嵌套评论结构（顶层评论 + 子评论）
	mut top_level := []Comment{}
	mut replies_map := map[int][]Comment{}
	for c in comments {
		if c.parent_id == 0 {
			top_level << c
		} else {
			mut existing := replies_map[c.parent_id] or { []Comment{} }
			existing << c
			replies_map[c.parent_id] = existing
		}
	}

	// 构建带 replies 的 JSON
	mut items_json := []string{}
	for c in top_level {
		replies := replies_map[c.id] or { []Comment{} }
		item_json := '{"comment":${json.encode(c)},"replies":${json.encode(replies)}}'
		items_json << item_json
	}

	items_str := if items_json.len > 0 { items_json.join(',') } else { '' }
	data := '{"items":[${items_str}],"total":${comments.len}}'
	return ctx.send_ok(data)
}

// post_post_comment POST /api/v1/posts/:id/comments — 创建评论（需 USER+，触发 comment.posted 事件）
@[post]
@['/api/v1/posts/:id/comments']
pub fn (mut app App) post_post_comment(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验（USER+ 包含 EDITOR 和 ADMIN）
	username, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['USER', 'EDITOR', 'ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid post id / 无效的文章 ID')
	}

	// 获取当前用户 ID
	user_svc := app.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_err(.unauthorized, 401, 'user not found / 用户不存在')
	}

	// 解析请求体
	mut content := ''
	mut parent_id := 0

	body := ctx.req.data
	if body.len > 0 {
		dto := json.decode(CreateCommentDto, body) or {
			return ctx.send_err(.bad_request, 400, 'invalid request body / 无效的请求体: ${err}')
		}
		content = dto.content
		parent_id = dto.parent_id
	} else {
		content = ctx.form['content'] or { '' }
		parent_id = (ctx.form['parent_id'] or { '0' }).int()
	}

	if content.len == 0 {
		return ctx.send_err(.bad_request, 400, 'content required / 评论内容为必填项')
	}

	// 构建评论 DTO
	dto := CreateCommentDto{
		post_id: post_id
		user_id: user.id
		content: content
		parent_id: parent_id
	}

	mut comment_svc := app.bootstrap.comment_svc
	comment := comment_svc.create(dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}

	ctx.res.set_status(.created)
	return ctx.send_response_to_client('application/json', ok_resp(json.encode(comment)))
}

// delete_comment DELETE /api/v1/comments/:id — 删除评论（需 ADMIN 或作者本人）
@[delete]
@['/api/v1/comments/:id']
pub fn (mut app App) delete_comment(mut ctx Context, id string) veb.Result {
	// 认证（必须登录）
	username, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}

	comment_id := id.int()
	if comment_id <= 0 {
		return ctx.send_err(.bad_request, 400, 'invalid comment id / 无效的评论 ID')
	}

	// 查询评论以检查所有权
	mut comment_svc := app.bootstrap.comment_svc
	comment := comment_svc.find_by_id(comment_id) or {
		return ctx.send_err(.not_found, 404, 'comment not found / 评论不存在: ${id}')
	}

	// 获取当前用户
	user_svc := app.bootstrap.user_svc
	current_user := user_svc.find_by_username(username) or {
		return ctx.send_err(.unauthorized, 401, 'user not found / 用户不存在')
	}

	// 权限校验：ADMIN 或评论作者本人
	is_admin := 'ADMIN' in roles
	is_owner := comment.user_id == current_user.id
	if !is_admin && !is_owner {
		return ctx.send_err(.forbidden, 403, 'permission denied — only admin or comment owner can delete / 权限不足，仅管理员或评论作者可删除')
	}

	// 执行删除（软删除，标记为 deleted 状态）
	comment_svc.delete(comment_id) or {
		return ctx.send_err(.internal_server_error, 500, err.msg())
	}

	return ctx.send_ok('{"message":"comment deleted / 评论已删除"}')
}

// ═══════════════════════════════════════════════════════════
// Task 17: 分类与标签控制器
// ═══════════════════════════════════════════════════════════

// get_categories GET /api/v1/categories — 分类列表（公开）
@[get]
@['/api/v1/categories']
pub fn (mut app App) get_categories(mut ctx Context) veb.Result {
	mut category_svc := app.bootstrap.category_svc
	categories := category_svc.find_all() or {
		return ctx.send_err(.internal_server_error, 500, 'failed to fetch categories / 获取分类列表失败: ${err}')
	}

	return ctx.send_ok(json.encode(categories))
}

// post_category POST /api/v1/categories — 创建分类（需 ADMIN）
@[post]
@['/api/v1/categories']
pub fn (mut app App) post_category(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	// 解析请求体
	dto := ctx.parse_body_or_form[CreateCategoryDto](build_create_category_dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}
	return app.do_create_category(mut ctx, dto)
}

// do_create_category 执行分类创建（内部辅助方法）
fn (mut app App) do_create_category(mut ctx Context, dto CreateCategoryDto) veb.Result {
	if dto.name.len == 0 {
		return ctx.send_err(.bad_request, 400, 'category name required / 分类名称为必填项')
	}

	mut category_svc := app.bootstrap.category_svc
	category := category_svc.create(dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}

	ctx.res.set_status(.created)
	return ctx.send_response_to_client('application/json', ok_resp(json.encode(category)))
}

// get_tags GET /api/v1/tags — 标签列表（公开）
@[get]
@['/api/v1/tags']
pub fn (mut app App) get_tags(mut ctx Context) veb.Result {
	mut tag_svc := app.bootstrap.tag_svc
	tags := tag_svc.find_all() or {
		return ctx.send_err(.internal_server_error, 500, 'failed to fetch tags / 获取标签列表失败: ${err}')
	}

	return ctx.send_ok(json.encode(tags))
}

// post_tag POST /api/v1/tags — 创建标签（需 EDITOR+）
@[post]
@['/api/v1/tags']
pub fn (mut app App) post_tag(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	// 解析请求体
	dto := ctx.parse_body_or_form[CreateTagDto](build_create_tag_dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}
	return app.do_create_tag(mut ctx, dto)
}

// do_create_tag 执行标签创建（内部辅助方法）
fn (mut app App) do_create_tag(mut ctx Context, dto CreateTagDto) veb.Result {
	if dto.name.len == 0 {
		return ctx.send_err(.bad_request, 400, 'tag name required / 标签名称为必填项')
	}

	mut tag_svc := app.bootstrap.tag_svc
	tag := tag_svc.create(dto) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}

	ctx.res.set_status(.created)
	return ctx.send_response_to_client('application/json', ok_resp(json.encode(tag)))
}

// ═══════════════════════════════════════════════════════════
// Task 18: 文件上传控制器 — 头像/配图/文件访问
// ═══════════════════════════════════════════════════════════

// post_upload_avatar POST /api/v1/uploads/avatar — 头像上传（需 USER+，限制 2MB，.jpg/.png）
@[post]
@['/api/v1/uploads/avatar']
pub fn (mut app App) post_upload_avatar(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['USER', 'EDITOR', 'ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	// 从 multipart 表单获取文件
	files := ctx.files['file'] or {
		return ctx.send_err(.bad_request, 400, 'no file uploaded / 未上传文件')
	}
	if files.len == 0 {
		return ctx.send_err(.bad_request, 400, 'no file uploaded / 未上传文件')
	}

	file := files[0]
	if file.data.len == 0 {
		return ctx.send_err(.bad_request, 400, 'empty file / 文件为空')
	}

	// 调用上传服务（内部校验大小与扩展名）
	mut upload_svc := app.bootstrap.upload_svc
	result := upload_svc.upload_avatar(file.filename, file.data.bytes()) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}

	// 构建响应数据
	data := '{"original_name":"${result.original_name}","stored_name":"${result.stored_name}","path":"${result.path}","size":${result.size},"extension":"${result.extension}","mime_type":"${result.mime_type}","hash":"${result.hash}","url":"/api/v1/uploads/${result.stored_name}"}'
	return ctx.send_ok(data)
}

// post_upload_image POST /api/v1/uploads/image — 文章配图上传（需 EDITOR+，限制 5MB）
@[post]
@['/api/v1/uploads/image']
pub fn (mut app App) post_upload_image(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware.apply_auth(mut ctx.Context) or {
		return ctx.send_err(.unauthorized, 401, err.msg())
	}
	app.middleware.apply_role(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_err(.forbidden, 403, err.msg())
	}

	// 从 multipart 表单获取文件
	files := ctx.files['file'] or {
		return ctx.send_err(.bad_request, 400, 'no file uploaded / 未上传文件')
	}
	if files.len == 0 {
		return ctx.send_err(.bad_request, 400, 'no file uploaded / 未上传文件')
	}

	file := files[0]
	if file.data.len == 0 {
		return ctx.send_err(.bad_request, 400, 'empty file / 文件为空')
	}

	// 调用上传服务（内部校验大小与扩展名）
	mut upload_svc := app.bootstrap.upload_svc
	result := upload_svc.upload_image(file.filename, file.data.bytes()) or {
		return ctx.send_err(.bad_request, 400, err.msg())
	}

	// 构建响应数据
	data := '{"original_name":"${result.original_name}","stored_name":"${result.stored_name}","path":"${result.path}","size":${result.size},"extension":"${result.extension}","mime_type":"${result.mime_type}","hash":"${result.hash}","url":"/api/v1/uploads/${result.stored_name}"}'
	return ctx.send_ok(data)
}

// get_upload_file GET /api/v1/uploads/:file — 访问已上传文件
@[get]
@['/api/v1/uploads/:file']
pub fn (mut app App) get_upload_file(mut ctx Context, file string) veb.Result {
	if file.len == 0 {
		return ctx.send_err(.bad_request, 400, 'file name required / 文件名为必填项')
	}

	// 安全检查：防止路径遍历攻击
	if file.contains('..') || file.contains('/') || file.contains('\\') {
		return ctx.send_err(.bad_request, 400, 'invalid file name / 无效的文件名')
	}

	// 读取文件内容
	upload_svc := app.bootstrap.upload_svc
	content := upload_svc.get_file(file) or {
		return ctx.send_err(.not_found, 404, 'file not found / 文件不存在: ${file}')
	}

	// 根据扩展名推断 MIME 类型
	mime_type := web.guess_mime_type(file)

	// 直接返回文件内容（不使用统一 JSON 封装）
	return ctx.send_response_to_client(mime_type, content)
}

// ═══════════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════════

// extract_json_field 从 JSON 字符串中简单提取指定字段的字符串值
// 仅用于简单场景（如提取 refresh_token），不处理嵌套对象
fn extract_json_field(json_str string, field string) string {
	// 查找 "field":"value" 模式
	search_key := '"${field}":"'
	start_idx := json_str.index(search_key) or { return '' }
	value_start := start_idx + search_key.len
	// 查找结束引号
	mut end_idx := value_start
	for end_idx < json_str.len {
		if json_str[end_idx] == `"` {
			break
		}
		if json_str[end_idx] == `\\` && end_idx + 1 < json_str.len {
			end_idx += 2
			continue
		}
		end_idx++
	}
	if end_idx > value_start && end_idx <= json_str.len {
		return json_str[value_start..end_idx]
	}
	return ''
}

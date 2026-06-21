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
// 统一响应格式（通过 web.Result + Context.send_result 发送）：
//   {"success":bool,"code":int,"message":string,"data":...,"timestamp":i64,"path":""}
//
// 认证流程：
//   1. app.middleware_registry.authenticate(mut ctx.Context) → (username, roles)
//   2. app.middleware_registry.authorize(['ADMIN'], roles) → 通过或抛错
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
import os
import photon.web
import photon.security
import models
import app.http.resources

// ═══════════════════════════════════════════════════════════
// 请求体解析与校验
// ═══════════════════════════════════════════════════════════
//
// 所有 DTO 校验通过 Context.validate_json[T]() 完成（见 app/Http/Kernel.v）。
// 该方法基于 web.validate_body[T]，自动解析 JSON 请求体并应用 @[validate] 规则。
// 校验失败时返回错误，调用方用 or 块返回 422 响应。
//
// 用法：
//   dto := ctx.validate_json[CreateUserDto]() or {
//       return ctx.send_result(web.fail(422, err.msg()))
//   }

// ═══════════════════════════════════════════════════════════
// Task 12: 系统控制器 — 首页 & 系统信息
// ═══════════════════════════════════════════════════════════

// AppInfoDto 首页应用信息
struct AppInfoDto {
	app         string
	version     string
	profile     string
	uptime_ms   i64
	requests    int
	endpoints   []string
}

// HealthDto 健康检查响应
struct HealthDto {
	status    string
	version   string
	uptime_ms i64
	timestamp i64
}

// BasicStatsDto 基础统计（统计服务失败时的回退）
struct BasicStatsDto {
	requests     int
	uptime_ms    i64
	user_count   int
	post_count   int
	comment_count int
	timestamp    i64
}

// BlogStatsDto 博客统计
struct BlogStatsDto {
	requests        int
	uptime_ms       i64
	user_count      int
	post_count      int
	published_count int
	draft_count     int
	comment_count   int
	aggregated_at   i64
}

// index GET / — 应用信息与端点列表
@[get]
@['/']
pub fn (mut app App) index(mut ctx Context) veb.Result {
	uptime_ms := time.ticks() - app.start_time
	info := AppInfoDto{
		app:       app.bootstrap.cfg.app.name
		version:   app.bootstrap.cfg.app.version
		profile:   app.bootstrap.cfg.profile
		uptime_ms: uptime_ms
		requests:  app.req_count
		endpoints: ['/health', '/ping', '/stats', '/api/v1/auth/register', '/api/v1/auth/login',
			'/api/v1/auth/refresh', '/api/v1/auth/profile', '/api/v1/auth/logout', '/api/v1/users',
			'/api/v1/posts', '/api/v1/posts/:id/comments', '/api/v1/categories', '/api/v1/tags',
			'/api/v1/uploads/avatar', '/api/v1/uploads/image', '/__docs']
	}
	return ctx.send_data(json.encode(info))
}

// ═══════════════════════════════════════════════════════════
// API 文档面板（apidoc 模块，非生产环境启用）
// ═══════════════════════════════════════════════════════════

// docs_index GET /__docs — API 文档交互式面板
@[get]
@['/__docs']
pub fn (mut app App) docs_index(mut ctx Context) veb.Result {
	if isnil(app.apidoc_handler) {
		return ctx.send_result(web.fail(404, 'API docs not available in production / 生产环境未启用 API 文档'))
	}
	mut h := app.apidoc_handler
	return h.serve_index(mut ctx.Context)
}

// docs_static GET /__docs/static/:file — API 文档静态资源
@[get]
@['/__docs/static/:file']
pub fn (mut app App) docs_static(mut ctx Context, file string) veb.Result {
	if isnil(app.apidoc_handler) {
		return ctx.send_result(web.fail(404, 'API docs not available in production'))
	}
	mut h := app.apidoc_handler
	return h.serve_static_file(mut ctx.Context, file)
}

// docs_entries GET /__docs/api/entries — 所有已记录的 API 端点
@[get]
@['/__docs/api/entries']
pub fn (mut app App) docs_entries(mut ctx Context) veb.Result {
	if isnil(app.apidoc_handler) {
		return ctx.send_result(web.fail(404, 'API docs not available in production'))
	}
	mut h := app.apidoc_handler
	return h.serve_entries(mut ctx.Context)
}

// docs_export GET /__docs/api/export — 导出 OpenAPI 3.0 JSON
@[get]
@['/__docs/api/export']
pub fn (mut app App) docs_export(mut ctx Context) veb.Result {
	if isnil(app.apidoc_handler) {
		return ctx.send_result(web.fail(404, 'API docs not available in production'))
	}
	mut h := app.apidoc_handler
	return h.serve_export(mut ctx.Context)
}

// health GET /health — 健康检查（状态/版本/uptime/时间戳）
@[get]
@['/health']
pub fn (mut app App) health(mut ctx Context) veb.Result {
	uptime_ms := time.ticks() - app.start_time
	data := HealthDto{
		status:    'UP'
		version:   app.bootstrap.cfg.app.version
		uptime_ms: uptime_ms
		timestamp: time.now().unix()
	}
	return ctx.send_data(json.encode(data))
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
		basic := BasicStatsDto{
			requests:      app.req_count
			uptime_ms:     uptime_ms
			user_count:    0
			post_count:    0
			comment_count: 0
			timestamp:     time.now().unix()
		}
		return ctx.send_data(json.encode(basic))
	}

	data := BlogStatsDto{
		requests:        app.req_count
		uptime_ms:       uptime_ms
		user_count:      blog_stats.user_count
		post_count:      blog_stats.post_count
		published_count: blog_stats.published_count
		draft_count:     blog_stats.draft_count
		comment_count:   blog_stats.comment_count
		aggregated_at:   blog_stats.aggregated_at
	}
	return ctx.send_data(json.encode(data))
}

// ═══════════════════════════════════════════════════════════
// Task 13: 认证控制器 — 注册/登录/刷新/资料/登出
// ═══════════════════════════════════════════════════════════

// post_auth_register POST /api/v1/auth/register — 用户注册（触发 user.registered 事件）
@[post]
@['/api/v1/auth/register']
pub fn (mut app App) post_auth_register(mut ctx Context) veb.Result {
	// 校验请求体
	dto := web.bind_json[models.CreateUserDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	// 哈希密码
	hasher := security.BcryptHasher{}
	hashed_password := hasher.make(dto.password)

	// 调用服务层注册（触发 user.registered 事件）
	mut user_svc := app.bootstrap.user_svc
	user, _ := user_svc.register(dto, hashed_password) or {
		return ctx.send_bad_request(err.msg())
	}

	// 返回用户信息（通过 UserResource 脱敏）
	return ctx.send_data(resources.new_user_resource(&user).to_json())
}

// post_auth_login POST /api/v1/auth/login — 用户登录，返回 JWT
@[post]
@['/api/v1/auth/login']
pub fn (mut app App) post_auth_login(mut ctx Context) veb.Result {
	// 校验请求体
	dto := web.bind_json[models.LoginDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return do_login(mut app, mut ctx, dto)
}

// do_login 执行登录逻辑（内部辅助方法）
fn do_login(mut app App, mut ctx Context, dto models.LoginDto) veb.Result {
	// 调用认证服务验证凭据并生成 JWT
	mut auth_svc := app.bootstrap.auth_svc
	token, roles := auth_svc.authenticate(dto.username, dto.password) or {
		return ctx.send_unauthorized(err.msg())
	}

	// 查询用户信息
	user_svc := app.bootstrap.user_svc
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

// RefreshTokenDto 刷新令牌请求
struct RefreshTokenDto {
	refresh_token string @[required; validate: 'required']
}

// TokenResponseDto 令牌响应
struct TokenResponseDto {
	access_token  string
	refresh_token string
	token_type    string = 'Bearer'
	expires_in    int    = 3600
}

// post_auth_refresh POST /api/v1/auth/refresh — 刷新访问令牌
@[post]
@['/api/v1/auth/refresh']
pub fn (mut app App) post_auth_refresh(mut ctx Context) veb.Result {
	// 校验请求体
	dto := web.bind_json[RefreshTokenDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}

	// 验证旧 token 并生成新 token
	mut auth_svc := app.bootstrap.auth_svc
	username := auth_svc.validate_token(dto.refresh_token) or {
		return ctx.send_unauthorized('invalid refresh token / 无效的刷新令牌: ${err}')
	}

	// 生成新的 access token
	jwt_mgr := app.bootstrap.jwt_mgr
	access_token := jwt_mgr.create_token(username, []) or {
		return ctx.send_internal_error('failed to generate token / 令牌生成失败: ${err}')
	}

	resp := TokenResponseDto{
		access_token:  access_token
		refresh_token: dto.refresh_token
	}
	return ctx.send_data(json.encode(resp))
}

// get_auth_profile GET /api/v1/auth/profile — 获取当前用户信息（需 JWT）
@[get]
@['/api/v1/auth/profile']
pub fn (mut app App) get_auth_profile(mut ctx Context) veb.Result {
	// JWT 认证
	username, _ := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}

	// 查询用户信息
	user_svc := app.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_not_found('user not found / 用户不存在: ${username}')
	}

	// 返回用户信息（通过 UserResource 脱敏，隐藏 password/version）
	return ctx.send_data(resources.new_user_resource(&user).to_json())
}

// MessageDto 通用消息响应
struct MessageDto {
	message string
}

// post_auth_logout POST /api/v1/auth/logout — 登出（客户端清除 token）
@[post]
@['/api/v1/auth/logout']
pub fn (mut app App) post_auth_logout(mut ctx Context) veb.Result {
	// JWT 认证（可选，即使 token 过期也允许登出）
	_, _ = app.middleware_registry.authenticate(mut ctx.Context) or {
		// 即使认证失败也返回成功（客户端应清除 token）
		return ctx.send_data(json.encode(MessageDto{message: 'logged out / 已登出'}))
	}

	// 返回成功（JWT 无状态，服务端无需额外处理，客户端清除 token 即可）
	return ctx.send_data(json.encode(MessageDto{message: 'logged out / 已登出'}))
}

// ═══════════════════════════════════════════════════════════
// Task 14: 用户管理控制器 — CRUD（均需 ADMIN）
// ═══════════════════════════════════════════════════════════

// get_users GET /api/v1/users — 用户分页列表（需 ADMIN，支持 keyword/status/role 过滤）
@[get]
@['/api/v1/users']
pub fn (mut app App) get_users(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
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

	// 构建过滤条件（SubTask 12.3：过滤下沉到 SQL）
	filter := models.UserFilter{
		keyword: keyword
		status:  status_filter
		role:    role_filter
	}

	// 调用仓储层过滤查询（过滤/分页全部在 SQL 完成）
	user_repo := app.bootstrap.user_repo
	users, total := user_repo.find_with_filters(filter, 'id_asc', page, page_size) or {
		return ctx.send_internal_error('failed to fetch users / 获取用户列表失败: ${err}')
	}

	// 转换为 UserResource 集合
	mut res_list := []resources.UserResource{}
	for u in users {
		res_list << resources.new_user_resource(&u)
	}

	// 使用 web.page 构建分页响应（含 pagination 元数据）
	page_result := web.page(json.encode(res_list), page, page_size, total)
	return ctx.send_page_result(page_result)
}

// get_user GET /api/v1/users/:id — 用户详情（需 ADMIN）
@[get]
@['/api/v1/users/:id']
pub fn (mut app App) get_user(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_bad_request('invalid user id / 无效的用户 ID')
	}

	mut user_svc := app.bootstrap.user_svc
	user := user_svc.find_by_id(user_id) or {
		return ctx.send_not_found('user not found / 用户不存在: ${id}')
	}

	return ctx.send_data(resources.new_user_resource(&user).to_json())
}

// post_user POST /api/v1/users — 创建用户（需 ADMIN）
@[post]
@['/api/v1/users']
pub fn (mut app App) post_user(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 校验请求体
	dto := web.bind_json[models.CreateUserDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return do_admin_create_user(mut app, mut ctx, dto)
}

// do_admin_create_user 管理员创建用户（内部辅助方法）
fn do_admin_create_user(mut app App, mut ctx Context, dto models.CreateUserDto) veb.Result {
	// 哈希密码
	hasher := security.BcryptHasher{}
	hashed_password := hasher.make(dto.password)

	mut user_svc := app.bootstrap.user_svc
	user, _ := user_svc.register(dto, hashed_password) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_user_resource(&user).to_json())
}

// put_user PUT /api/v1/users/:id — 更新用户（需 ADMIN）
@[put]
@['/api/v1/users/:id']
pub fn (mut app App) put_user(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_bad_request('invalid user id / 无效的用户 ID')
	}

	// 校验请求体
	dto := web.bind_json[models.UpdateUserDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return do_update_user(mut app, mut ctx, user_id, dto)
}

// do_update_user 执行用户更新（内部辅助方法）
fn do_update_user(mut app App, mut ctx Context, user_id int, dto models.UpdateUserDto) veb.Result {
	mut user_svc := app.bootstrap.user_svc
	user := user_svc.update_profile(user_id, dto) or {
		return ctx.send_not_found(err.msg())
	}

	return ctx.send_data(resources.new_user_resource(&user).to_json())
}

// delete_user DELETE /api/v1/users/:id — 删除用户（需 ADMIN，软删除）
@[delete]
@['/api/v1/users/:id']
pub fn (mut app App) delete_user(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_bad_request('invalid user id / 无效的用户 ID')
	}

	// 软删除（SubTask 12.4：设置 status = -1，而非物理删除）
	mut user_repo := app.bootstrap.user_repo
	user_repo.soft_delete(user_id) or {
		return ctx.send_not_found(err.msg())
	}

	return ctx.send_data(json.encode(MessageDto{message: 'user deleted / 用户已删除'}))
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

	// 构建过滤条件（SubTask 12.2：过滤下沉到 SQL）
	filter := models.PostFilter{
		keyword:     keyword
		status:      status
		category_id: if category.len > 0 { category.int() } else { 0 }
		tag_id:      if tag.len > 0 { tag.int() } else { 0 }
	}

	// 调用仓储层过滤查询（过滤/排序/分页全部在 SQL 完成）
	post_repo := app.bootstrap.post_repo
	posts, total := post_repo.find_with_filters(filter, sort, page, page_size) or {
		return ctx.send_internal_error('failed to fetch posts / 获取文章列表失败: ${err}')
	}

	// 转换为 PostResource 集合（加载作者与分类关联）
	mut user_svc := app.bootstrap.user_svc
	mut category_svc := app.bootstrap.category_svc
	mut res_list := []resources.PostResource{}
	for p in posts {
		post_author := user_svc.find_by_id(p.author_id) or { models.User{} }
		post_category := category_svc.find_by_id(p.category_id) or { models.Category{} }
		res_list << resources.new_post_resource_with_relations(&p, &post_author,
			&post_category, []models.Tag{})
	}

	// 使用 web.page 构建分页响应（含 pagination 元数据）
	page_result := web.page(json.encode(res_list), page, page_size, total)
	return ctx.send_page_result(page_result)
}

// get_post GET /api/v1/posts/:id — 文章详情（公开，自增 views，缓存命中）
@[get]
@['/api/v1/posts/:id']
pub fn (mut app App) get_post(mut ctx Context, id string) veb.Result {
	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	mut post_svc := app.bootstrap.post_svc
	post := post_svc.find_by_id(post_id) or {
		return ctx.send_not_found('post not found / 文章不存在: ${id}')
	}

	// 自增浏览量（同步执行：共享单个 sqlite 连接，禁止用 go 协程并发访问，
	// 否则与请求处理线程并发 prepare/exec 会导致 SQLite 崩溃）
	post_svc.increment_views(post_id) or {
		app.bootstrap.log.error('[get_post] increment_views failed: ${err}')
	}

	// 加载关联：作者与分类
	mut user_svc := app.bootstrap.user_svc
	mut category_svc := app.bootstrap.category_svc
	author := user_svc.find_by_id(post.author_id) or { models.User{} }
	category := category_svc.find_by_id(post.category_id) or { models.Category{} }
	return ctx.send_data(resources.new_post_resource_with_relations(&post, &author, &category,
		[]models.Tag{}).to_json())
}

// post_post POST /api/v1/posts — 创建文章（需 EDITOR+，触发 post.published 事件）
@[post]
@['/api/v1/posts']
pub fn (mut app App) post_post(mut ctx Context) veb.Result {
	// 认证 + 角色校验（EDITOR+ 包含 ADMIN）
	username, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 获取当前用户 ID（作为作者）
	user_svc := app.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_unauthorized('user not found / 用户不存在')
	}

	// 校验请求体
	mut dto := web.bind_json[models.CreatePostDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	// 注入作者 ID（由控制器从 JWT 设置，非客户端输入）
	dto.author_id = user.id

	return do_create_post(mut app, mut ctx, dto)
}

// do_create_post 执行文章创建（内部辅助方法）
fn do_create_post(mut app App, mut ctx Context, dto models.CreatePostDto) veb.Result {
	mut post_svc := app.bootstrap.post_svc
	post, _ := post_svc.create(dto, dto.author_id) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_post_resource(&post).to_json())
}

// put_post PUT /api/v1/posts/:id — 更新文章（需 EDITOR+，清除缓存）
@[put]
@['/api/v1/posts/:id']
pub fn (mut app App) put_post(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	// 校验请求体
	dto := web.bind_json[models.UpdatePostDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return do_update_post(mut app, mut ctx, post_id, dto)
}

// do_update_post 执行文章更新（内部辅助方法）
fn do_update_post(mut app App, mut ctx Context, post_id int, dto models.UpdatePostDto) veb.Result {
	mut post_svc := app.bootstrap.post_svc
	post, _ := post_svc.update(post_id, dto) or {
		return ctx.send_not_found(err.msg())
	}

	return ctx.send_data(resources.new_post_resource(&post).to_json())
}

// delete_post DELETE /api/v1/posts/:id — 删除文章（需 ADMIN）
@[delete]
@['/api/v1/posts/:id']
pub fn (mut app App) delete_post(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	// 软删除（SubTask 12.4：设置 status = 'archived'，而非物理删除）
	mut post_repo := app.bootstrap.post_repo
	post_repo.soft_delete(post_id) or {
		return ctx.send_not_found(err.msg())
	}

	return ctx.send_data(json.encode(MessageDto{message: 'post deleted / 文章已删除'}))
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
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	comment_svc := app.bootstrap.comment_svc
	comments := comment_svc.find_by_post(post_id) or {
		return ctx.send_internal_error('failed to fetch comments / 获取评论失败: ${err}')
	}

	// 构建嵌套评论结构（顶层评论 + 子评论）
	mut top_level := []models.Comment{}
	mut replies_map := map[int][]models.Comment{}
	for c in comments {
		if c.parent_id == 0 {
			top_level << c
		} else {
			mut existing := replies_map[c.parent_id] or { []models.Comment{} }
			existing << c
			replies_map[c.parent_id] = existing
		}
	}

	// 构建带 replies 的 Resource 列表
	mut items := []resources.CommentResource{}
	for c in top_level {
		replies := replies_map[c.id] or { []models.Comment{} }
		mut reply_resources := []resources.CommentResource{}
		for r in replies {
			reply_resources << resources.new_comment_resource(&r)
		}
		items << resources.new_comment_resource_with_replies(&c, unsafe { nil }, reply_resources)
	}

	// 使用 web.page 构建分页响应（评论一次性返回，分页元数据标识总数）
	page_result := web.page(json.encode(items), 1, items.len, items.len)
	return ctx.send_page_result(page_result)
}

// post_post_comment POST /api/v1/posts/:id/comments — 创建评论（需 USER+，触发 comment.posted 事件）
@[post]
@['/api/v1/posts/:id/comments']
pub fn (mut app App) post_post_comment(mut ctx Context, id string) veb.Result {
	// 认证 + 角色校验（USER+ 包含 EDITOR 和 ADMIN）
	username, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['USER', 'EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	// 获取当前用户 ID
	user_svc := app.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_unauthorized('user not found / 用户不存在')
	}

	// 校验请求体
	mut dto := web.bind_json[models.CreateCommentDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	// 注入 post_id 与 user_id（由控制器设置，非客户端输入）
	dto.post_id = post_id
	dto.user_id = user.id

	mut comment_svc := app.bootstrap.comment_svc
	comment, _ := comment_svc.create(dto, user.id) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_comment_resource(&comment).to_json())
}

// delete_comment DELETE /api/v1/comments/:id — 删除评论（需 ADMIN 或作者本人）
@[delete]
@['/api/v1/comments/:id']
pub fn (mut app App) delete_comment(mut ctx Context, id string) veb.Result {
	// 认证（必须登录）
	username, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}

	comment_id := id.int()
	if comment_id <= 0 {
		return ctx.send_bad_request('invalid comment id / 无效的评论 ID')
	}

	// 查询评论以检查所有权
	mut comment_svc := app.bootstrap.comment_svc
	comment := comment_svc.find_by_id(comment_id) or {
		return ctx.send_not_found('comment not found / 评论不存在: ${id}')
	}

	// 获取当前用户
	user_svc := app.bootstrap.user_svc
	current_user := user_svc.find_by_username(username) or {
		return ctx.send_unauthorized('user not found / 用户不存在')
	}

	// 权限校验：ADMIN 或评论作者本人
	is_admin := 'ADMIN' in roles
	is_owner := comment.user_id == current_user.id
	if !is_admin && !is_owner {
		return ctx.send_forbidden('permission denied — only admin or comment owner can delete / 权限不足，仅管理员或评论作者可删除')
	}

	// 执行软删除（SubTask 12.4：设置 status = 'deleted'）
	mut comment_repo := app.bootstrap.comment_repo
	comment_repo.soft_delete(comment_id) or {
		return ctx.send_internal_error(err.msg())
	}

	return ctx.send_data(json.encode(MessageDto{message: 'comment deleted / 评论已删除'}))
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
		return ctx.send_internal_error('failed to fetch categories / 获取分类列表失败: ${err}')
	}

	// 转换为 CategoryResource 集合
	mut res_list := []resources.CategoryResource{}
	for c in categories {
		res_list << resources.new_category_resource(&c)
	}

	// 使用 web.page 构建分页响应
	page_result := web.page(json.encode(res_list), 1, res_list.len, res_list.len)
	return ctx.send_page_result(page_result)
}

// post_category POST /api/v1/categories — 创建分类（需 ADMIN）
@[post]
@['/api/v1/categories']
pub fn (mut app App) post_category(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 校验请求体
	dto := web.bind_json[models.CreateCategoryDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return do_create_category(mut app, mut ctx, dto)
}

// do_create_category 执行分类创建（内部辅助方法）
fn do_create_category(mut app App, mut ctx Context, dto models.CreateCategoryDto) veb.Result {
	mut category_svc := app.bootstrap.category_svc
	category, _ := category_svc.create(dto) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_category_resource(&category).to_json())
}

// get_tags GET /api/v1/tags — 标签列表（公开）
@[get]
@['/api/v1/tags']
pub fn (mut app App) get_tags(mut ctx Context) veb.Result {
	mut tag_svc := app.bootstrap.tag_svc
	tags := tag_svc.find_all() or {
		return ctx.send_internal_error('failed to fetch tags / 获取标签列表失败: ${err}')
	}

	// 转换为 TagResource 集合
	mut res_list := []resources.TagResource{}
	for t in tags {
		res_list << resources.new_tag_resource(&t)
	}

	// 使用 web.page 构建分页响应
	page_result := web.page(json.encode(res_list), 1, res_list.len, res_list.len)
	return ctx.send_page_result(page_result)
}

// post_tag POST /api/v1/tags — 创建标签（需 EDITOR+）
@[post]
@['/api/v1/tags']
pub fn (mut app App) post_tag(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 校验请求体
	dto := web.bind_json[models.CreateTagDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return do_create_tag(mut app, mut ctx, dto)
}

// do_create_tag 执行标签创建（内部辅助方法）
fn do_create_tag(mut app App, mut ctx Context, dto models.CreateTagDto) veb.Result {
	mut tag_svc := app.bootstrap.tag_svc
	tag, _ := tag_svc.create(dto) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_tag_resource(&tag).to_json())
}

// ═══════════════════════════════════════════════════════════
// Task 18: 文件上传控制器 — 头像/配图/文件访问
// ═══════════════════════════════════════════════════════════

// UploadResponseDto 文件上传响应
struct UploadResponseDto {
	original_name string
	stored_name   string
	path          string
	size          int
	extension     string
	mime_type     string
	hash          string
	url           string
}

// post_upload_avatar POST /api/v1/uploads/avatar — 头像上传（需 USER+，限制 2MB，.jpg/.png）
@[post]
@['/api/v1/uploads/avatar']
pub fn (mut app App) post_upload_avatar(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['USER', 'EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 从 multipart 表单获取文件
	files := ctx.files['file'] or {
		return ctx.send_bad_request('no file uploaded / 未上传文件')
	}
	if files.len == 0 {
		return ctx.send_bad_request('no file uploaded / 未上传文件')
	}

	file := files[0]
	if file.data.len == 0 {
		return ctx.send_bad_request('empty file / 文件为空')
	}

	// 调用上传服务
	mut upload_svc := app.bootstrap.upload_svc
	stored_name, _ := upload_svc.upload(file.filename, file.data.bytes()) or {
		return ctx.send_bad_request(err.msg())
	}

	// 构建响应数据
	resp := UploadResponseDto{
		original_name: file.filename
		stored_name:   stored_name
		path:          '/uploads/${stored_name}'
		size:          file.data.len
		extension:     file.filename.all_after_last('.')
		mime_type:     file.filename.all_after_last('.')
		hash:          ''
		url:           '/api/v1/uploads/${stored_name}'
	}
	return ctx.send_data(json.encode(resp))
}

// post_upload_image POST /api/v1/uploads/image — 文章配图上传（需 EDITOR+，限制 5MB）
@[post]
@['/api/v1/uploads/image']
pub fn (mut app App) post_upload_image(mut ctx Context) veb.Result {
	// 认证 + 角色校验
	_, roles := app.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	app.middleware_registry.authorize(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 从 multipart 表单获取文件
	files := ctx.files['file'] or {
		return ctx.send_bad_request('no file uploaded / 未上传文件')
	}
	if files.len == 0 {
		return ctx.send_bad_request('no file uploaded / 未上传文件')
	}

	file := files[0]
	if file.data.len == 0 {
		return ctx.send_bad_request('empty file / 文件为空')
	}

	// 调用上传服务
	mut upload_svc := app.bootstrap.upload_svc
	stored_name, _ := upload_svc.upload(file.filename, file.data.bytes()) or {
		return ctx.send_bad_request(err.msg())
	}

	// 构建响应数据
	resp := UploadResponseDto{
		original_name: file.filename
		stored_name:   stored_name
		path:          '/uploads/${stored_name}'
		size:          file.data.len
		extension:     file.filename.all_after_last('.')
		mime_type:     file.filename.all_after_last('.')
		hash:          ''
		url:           '/api/v1/uploads/${stored_name}'
	}
	return ctx.send_data(json.encode(resp))
}

// get_upload_file GET /api/v1/uploads/:file — 访问已上传文件
@[get]
@['/api/v1/uploads/:file']
pub fn (mut app App) get_upload_file(mut ctx Context, file string) veb.Result {
	if file.len == 0 {
		return ctx.send_bad_request('file name required / 文件名为必填项')
	}

	// 安全检查：防止路径遍历攻击
	if file.contains('..') || file.contains('/') || file.contains('\\') {
		return ctx.send_bad_request('invalid file name / 无效的文件名')
	}

	// 读取文件内容
	content := os.read_file('uploads/${file}') or {
		return ctx.send_not_found('file not found / 文件不存在: ${file}')
	}

	// 根据扩展名推断 MIME 类型
	mime_type := web.guess_mime_type(file)

	// 直接返回文件内容（不使用统一 JSON 封装）
	return ctx.send_response_to_client(mime_type, content)
}

module main

// services.v — PhotonBlog 业务服务层
//
// 实现 8 个核心业务服务，采用构造器注入依赖（Constructor Injection）。
// 所有服务通过指针持有依赖组件，由 Bootstrap 在启动时装配。
//
// 服务清单：
//   1. UserService     — 用户注册/登录/CRUD/密码管理（依赖 UserRepository + BcryptHasher + EventBus）
//   2. AuthService     — JWT 令牌生成/验证/刷新 + 角色校验（依赖 JwtManager + UserService + RoleHierarchy）
//   3. PostService     — 文章 CRUD + 缓存 + 分布式锁 + 事件（依赖 PostRepository + CacheManager + LockManager + EventBus）
//   4. CommentService  — 评论 CRUD + 嵌套评论 + 事件（依赖 CommentRepository + EventBus）
//   5. CategoryService — 分类 CRUD（依赖 CategoryRepository）
//   6. TagService      — 标签 CRUD + 文章-标签关联（依赖 TagRepository）
//   7. StatsService    — 统计聚合（带缓存，依赖各 Repository + CacheManager）
//   8. UploadService   — 文件上传（头像/配图，依赖 StorageManager + UploadHandler）
//
// 设计原则：
//   - 构造器注入：所有依赖通过 new_xxx_service() 构造函数注入
//   - 事件驱动：状态变更后通过 EventBus 分发领域事件
//   - 缓存策略：PostService/StatsService 使用 CacheManager 缓存热点数据
//   - 锁策略：PostService 使用 LockManager 防止并发更新冲突
//   - 错误处理：使用 V 的 `!` 错误传播，错误信息中英文双语

import photon.core
import photon.cache
import photon.locking
import photon.security
import photon.storage
import photon.logger
import photon.web
import photon.http
import json
import os
import time

// ═══════════════════════════════════════════════════════════
// BlogStats — 博客统计聚合数据
// ═══════════════════════════════════════════════════════════

pub struct BlogStats {
pub:
	user_count      int
	post_count      int
	published_count int
	draft_count     int
	comment_count   int
	aggregated_at   i64
}

// ═══════════════════════════════════════════════════════════
// GithubUser — GitHub API 用户响应（用于获取头像 URL）
// ═══════════════════════════════════════════════════════════

pub struct GithubUser {
pub:
	login      string
	avatar_url string
	html_url   string
	name       string
}

// fetch_github_avatar 通过 GitHub API 获取指定用户的头像 URL
// 使用 photon.http.RestTemplate 调用 https://api.github.com/users/{username}
// 配置 5s 超时 + 3 次指数退避重试，失败不阻塞注册（调用方处理错误）
pub fn fetch_github_avatar(username string) !string {
	rt := http.new_rest_template().
		set_base_url('https://api.github.com').
		set_default_header('Accept', 'application/vnd.github.v3+json').
		set_default_header('User-Agent', 'PhotonBlog').
		set_connect_timeout(5000).   // 5s 连接超时
		set_read_timeout(5000).      // 5s 读取超时
		set_retry(3, 200)            // 3 次重试，200ms 基础退避

	github_user := rt.get_for_object[GithubUser]('/users/${username}', {})!
	return github_user.avatar_url
}

// ═══════════════════════════════════════════════════════════
// UserService — 用户业务逻辑
// ═══════════════════════════════════════════════════════════

pub struct UserService {
pub:
	repo      &UserRepository
	hasher    security.BcryptHasher
	event_bus &core.EventBus
	logger    &logger.Logger
}

// new_user_service 创建用户服务，注入仓储、事件总线和日志
pub fn new_user_service(repo &UserRepository, event_bus &core.EventBus, log &logger.Logger) &UserService {
	return unsafe {
		&UserService{
			repo:      repo
			hasher:    security.BcryptHasher{}
			event_bus: event_bus
			logger:    log
		}
	}
}

// register 注册新用户：校验唯一性 → 哈希密码 → （可选）获取 GitHub 头像 → 事务持久化 → 分发 user.registered 事件
// 返回 (创建的用户, 欢迎消息)
@[transactional]
pub fn (mut s UserService) register(dto CreateUserDto) !(User, string) {
	// 校验用户名唯一性（事务前只读检查）
	if s.repo.exists_by_username(dto.username) {
		return error('用户名已存在 / username already exists: ${dto.username}')
	}
	// 校验邮箱唯一性
	if s.repo.exists_by_email(dto.email) {
		return error('邮箱已被注册 / email already registered: ${dto.email}')
	}

	// 哈希密码
	hashed := s.hasher.make(dto.password)

	// 若提供 GitHub 用户名，调用 GitHub API 获取头像 URL（事务外 HTTP 调用，不占用 DB 事务）
	mut avatar_url := ''
	if dto.github.len > 0 {
		avatar_url = fetch_github_avatar(dto.github) or {
			s.logger.warn('[UserService] 获取 GitHub 头像失败 / failed to fetch github avatar for "${dto.github}": ${err}')
			''
		}
		if avatar_url.len > 0 {
			s.logger.info('[UserService] 已获取 GitHub 头像 / fetched github avatar for "${dto.github}": ${avatar_url}')
		}
	}

	// 构建用户实体
	mut user := User{
		username: dto.username
		email:    dto.email
		password: hashed
		nickname: if dto.nickname.len > 0 { dto.nickname } else { dto.username }
		avatar:   avatar_url
		status:   1
		role:     dto.role
	}

	// 事务保证：用户持久化原子性（为未来多步操作如初始化统计预留事务边界）
	mut tx := begin_transaction(s.repo.db)!
	defer {
		tx.auto_rollback()
	}

	// 持久化（OrmAdapter 自动调用 touch() 设置时间戳与版本号）
	mut repo := s.repo
	user = repo.save(mut user)!

	tx.commit()!

	s.logger.info('[UserService] 用户注册成功: id=${user.id} username=${user.username}')

	// 事务后副作用：分发 user.registered 事件（触发欢迎邮件 + 统计缓存失效）
	// 放在 commit 之后，避免事件监听器失败导致事务回滚（邮件发送等副作用不可回滚）
	mut bus := s.event_bus
	event := core.new_event_with_data(event_user_registered, user.username, {
		'user_id':  user.id.str()
		'username': user.username
		'email':    user.email
	})
	bus.dispatch(event)

	return user, '注册成功 / registration successful'
}

// login 用户登录：校验凭证 → 分发 user.logged_in 事件
pub fn (mut s UserService) login(dto LoginDto) !User {
	user := s.repo.find_by_username(dto.username) or {
		return error('用户名或密码错误 / invalid username or password')
	}

	// 校验密码
	if !s.hasher.check(dto.password, user.password) {
		return error('用户名或密码错误 / invalid username or password')
	}

	// 校验账户状态
	if user.status != 1 {
		return error('账户已被禁用 / account has been disabled')
	}

	s.logger.info('[UserService] 用户登录成功: id=${user.id} username=${user.username}')

	// 分发 user.logged_in 事件
	mut bus := s.event_bus
	event := core.new_event_with_data(event_user_logged_in, user.username, {
		'user_id':  user.id.str()
		'username': user.username
	})
	bus.dispatch(event)

	return user
}

// find_by_id 按 ID 查询用户
pub fn (mut s UserService) find_by_id(id int) !User {
	mut repo := s.repo
	return repo.find_by_id(id)!
}

// find_by_username 按用户名查询用户
pub fn (s &UserService) find_by_username(username string) !User {
	return s.repo.find_by_username(username)!
}

// find_all 查询所有用户
pub fn (mut s UserService) find_all() ![]User {
	mut repo := s.repo
	return repo.find_all()!
}

// update 更新用户信息
pub fn (mut s UserService) update(id int, dto UpdateUserDto) !User {
	mut repo := s.repo
	mut user := repo.find_by_id(id)!

	// 按需更新字段（空值跳过）
	if dto.email.len > 0 {
		if dto.email != user.email && s.repo.exists_by_email(dto.email) {
			return error('邮箱已被注册 / email already registered: ${dto.email}')
		}
		user.email = dto.email
	}
	if dto.nickname.len > 0 {
		user.nickname = dto.nickname
	}
	if dto.avatar.len > 0 {
		user.avatar = dto.avatar
	}
	if dto.status != 0 {
		user.status = dto.status
	}
	if dto.role.len > 0 {
		user.role = dto.role
	}

	user = repo.update(mut user)!
	s.logger.info('[UserService] 用户更新成功: id=${user.id}')
	return user
}

// delete 删除用户
pub fn (s &UserService) delete(id int) ! {
	s.repo.delete_by_id(id)!
	s.logger.info('[UserService] 用户删除成功: id=${id}')
}

// change_password 修改密码：校验旧密码 → 哈希新密码 → 更新
pub fn (mut s UserService) change_password(id int, old_password string, new_password string) ! {
	mut repo := s.repo
	mut user := repo.find_by_id(id)!

	// 校验旧密码
	if !s.hasher.check(old_password, user.password) {
		return error('旧密码不正确 / old password is incorrect')
	}

	// 哈希新密码并更新
	user.password = s.hasher.make(new_password)
	user = repo.update(mut user)!

	s.logger.info('[UserService] 密码修改成功: id=${user.id}')
}

// verify_password 校验密码（不抛错，返回布尔值）
pub fn (s &UserService) verify_password(password string, hash string) bool {
	return s.hasher.check(password, hash)
}

// to_profile_dto 将 User 实体转换为 UserProfileDto（脱敏，不含密码）
pub fn (s &UserService) to_profile_dto(u &User) UserProfileDto {
	return UserProfileDto{
		id:       u.id
		username: u.username
		nickname: u.nickname
		avatar:   u.avatar
		email:    u.email
		role:     u.role
		status:   u.status
		created:  u.created_at.str()
	}
}

// ═══════════════════════════════════════════════════════════
// AuthService — 认证授权服务
// ═══════════════════════════════════════════════════════════

pub struct AuthService {
pub:
	jwt_manager    &security.JwtManager
	user_service   &UserService
	role_hierarchy &security.RoleHierarchy
	logger         &logger.Logger
}

// new_auth_service 创建认证服务，注入 JWT 管理器、用户服务和角色层级
pub fn new_auth_service(jwt_mgr &security.JwtManager, user_svc &UserService, role_h &security.RoleHierarchy, log &logger.Logger) &AuthService {
	return unsafe {
		&AuthService{
			jwt_manager:    jwt_mgr
			user_service:   user_svc
			role_hierarchy: role_h
			logger:         log
		}
	}
}

// generate_token 为用户生成 JWT 访问令牌 + 刷新令牌
// 返回 (access_token, refresh_token)
pub fn (s &AuthService) generate_token(user &User) !(string, string) {
	roles := [user.role]
	access_token := s.jwt_manager.create_token(user.username, roles)!
	refresh_token := s.jwt_manager.create_refresh_token(user.username)!
	s.logger.info('[AuthService] 生成令牌: username=${user.username} roles=${roles}')
	return access_token, refresh_token
}

// validate_token 验证访问令牌，返回用户名
pub fn (s &AuthService) validate_token(token string) !string {
	return s.jwt_manager.validate_token(token)!
}

// parse_token 解析令牌，返回完整的 Claims
pub fn (s &AuthService) parse_token(token string) !security.JwtClaims {
	return s.jwt_manager.parse_token(token)!
}

// refresh_token 使用刷新令牌获取新的访问令牌 + 刷新令牌
// 返回 (new_access_token, new_refresh_token)
pub fn (mut s AuthService) refresh_token(refresh_token string) !(string, string) {
	// 解析刷新令牌获取用户名
	claims := s.jwt_manager.parse_token(refresh_token)!
	username := claims.sub

	// 查询用户获取当前角色
	user := s.user_service.find_by_username(username) or {
		return error('用户不存在 / user not found: ${username}')
	}

	// 校验账户状态
	if user.status != 1 {
		return error('账户已被禁用 / account has been disabled')
	}

	// 生成新令牌
	roles := [user.role]
	new_access := s.jwt_manager.create_token(username, roles)!
	new_refresh := s.jwt_manager.create_refresh_token(username)!

	s.logger.info('[AuthService] 刷新令牌: username=${username}')
	return new_access, new_refresh
}

// has_role 检查令牌是否包含指定角色
pub fn (s &AuthService) has_role(token string, role string) bool {
	return s.jwt_manager.has_role(token, role)
}

// has_any_role 检查令牌是否包含任一指定角色
pub fn (s &AuthService) has_any_role(token string, roles []string) bool {
	return s.jwt_manager.has_any_role(token, roles)
}

// check_permission 基于角色层级检查用户是否拥有所需角色
// 例如：ADMIN 继承 MODERATOR > USER > GUEST
pub fn (s &AuthService) check_permission(user_roles []string, required_role string) bool {
	return s.role_hierarchy.has_role(user_roles, required_role)
}

// check_any_permission 基于角色层级检查用户是否拥有任一所需角色
pub fn (s &AuthService) check_any_permission(user_roles []string, required_roles []string) bool {
	return s.role_hierarchy.has_any_role(user_roles, required_roles)
}

// build_login_response 构建登录响应 DTO（令牌 + 用户信息）
pub fn (mut s AuthService) build_login_response(user &User) !LoginResponseDto {
	access_token, refresh_token := s.generate_token(user)!
	return LoginResponseDto{
		access_token:  access_token
		token_type:    'Bearer'
		expires_in:    3600
		refresh_token: refresh_token
		user:          s.user_service.to_profile_dto(user)
	}
}

// ═══════════════════════════════════════════════════════════
// PostService — 文章业务逻辑（带缓存 + 锁）
// ═══════════════════════════════════════════════════════════

pub struct PostService {
pub:
	repo      &PostRepository
	cache     &cache.CacheManager
	lock_mgr  &locking.LockManager
	event_bus &core.EventBus
	logger    &logger.Logger
}

// new_post_service 创建文章服务，注入仓储、缓存、锁、事件总线和日志
pub fn new_post_service(repo &PostRepository, cm &cache.CacheManager, lm &locking.LockManager, bus &core.EventBus, log &logger.Logger) &PostService {
	return unsafe {
		&PostService{
			repo:      repo
			cache:     cm
			lock_mgr:  lm
			event_bus: bus
			logger:    log
		}
	}
}

// create 创建文章：持久化 → 若为 published 状态则分发 post.published 事件
@[transactional]
pub fn (mut s PostService) create(dto CreatePostDto) !Post {
	mut post := Post{
		title:       dto.title
		content:     dto.content
		summary:     dto.summary
		author_id:   dto.author_id
		category_id: dto.category_id
		status:      dto.status
		views:       0
	}

	// 事务保证：持久化失败则回滚（单写操作事务，为未来多步扩展预留原子性边界）
	mut tx := begin_transaction(s.repo.db)!
	defer {
		tx.auto_rollback()
	}

	mut repo := s.repo
	post = repo.save(mut post)!

	tx.commit()!

	s.logger.info('[PostService] 文章创建成功: id=${post.id} title="${post.title}" status=${post.status}')

	// 事务后副作用：事件分发（非 DB 操作，放在 commit 之后避免事务内副作用不可回滚）
	if post.status == 'published' {
		s.dispatch_published_event(post)
	}

	return post
}

// find_by_id 查询文章详情（带缓存 + Singleflight 削峰）
// 缓存策略：使用 CacheManager.get_or_load 内置 Singleflight 防止缓存击穿，
// TTL 1 小时。缓存损坏时删除脏键并回源。
pub fn (mut s PostService) find_by_id(id int) !Post {
	cache_key := 'posts:${id}'
	mut cm := s.cache
	repo := s.repo

	// get_or_load 内部使用 Singleflight 合并并发回源请求
	cached := cm.get_or_load(cache_key, 3600, fn [repo, id] () !string {
		mut r := repo
		post := r.find_by_id(id)!
		return json.encode(post)
	})!

	// 解码缓存，失败则删除损坏缓存并回源
	post := json.decode(Post, cached) or {
		cm.delete(cache_key) or {}
		mut r := repo
		return r.find_by_id(id)!
	}

	return post
}

// find_all 查询所有文章
pub fn (mut s PostService) find_all() ![]Post {
	mut repo := s.repo
	return repo.find_all()!
}

// find_published 查询所有已发布文章（带缓存 + Singleflight 削峰）
pub fn (mut s PostService) find_published() ![]Post {
	cache_key := 'posts:published'
	mut cm := s.cache
	repo := s.repo

	// get_or_load 内部使用 Singleflight 合并并发回源请求
	cached := cm.get_or_load(cache_key, 3600, fn [repo] () !string {
		mut r := repo
		posts := r.find_published()!
		return json.encode(posts)
	})!

	// 解码缓存，失败则删除损坏缓存并回源
	posts := json.decode([]Post, cached) or {
		cm.delete(cache_key) or {}
		mut r := repo
		return r.find_published()!
	}

	return posts
}

// find_by_author 查询某作者的所有文章
pub fn (s &PostService) find_by_author(author_id int) ![]Post {
	return s.repo.find_by_author(author_id)!
}

// find_by_category 查询某分类下的所有文章
pub fn (s &PostService) find_by_category(category_id int) ![]Post {
	return s.repo.find_by_category(category_id)!
}

// update 更新文章：LockGuard 加锁 → 事务更新 → TaggedCache 失效 → 分发 post.updated 事件
@[transactional]
pub fn (mut s PostService) update(id int, dto UpdatePostDto) !Post {
	// 使用 LockGuard RAII 防止并发更新冲突（defer 保证释放）
	mut lm := s.lock_mgr
	guard := locking.new_lock_guard(mut lm, 'post:update:${id}')
	defer {
		guard.unlock()
	}

	// 事务保证：更新失败则回滚
	mut tx := begin_transaction(s.repo.db)!
	defer {
		tx.auto_rollback()
	}

	mut repo := s.repo
	mut post := repo.find_by_id(id)!

	was_published := post.status == 'published'

	// 按需更新字段
	if dto.title.len > 0 {
		post.title = dto.title
	}
	if dto.content.len > 0 {
		post.content = dto.content
	}
	if dto.summary.len > 0 {
		post.summary = dto.summary
	}
	if dto.category_id != 0 {
		post.category_id = dto.category_id
	}
	if dto.status.len > 0 {
		post.status = dto.status
	}

	post = repo.update(mut post)!

	tx.commit()!

	// 事务后副作用：TaggedCache 批量失效 'posts' 标签下所有缓存键
	flush_cache_tag(s.cache, 'posts')

	s.logger.info('[PostService] 文章更新成功: id=${post.id}')

	// 分发 post.updated 事件
	mut bus := s.event_bus
	event := core.new_event_with_data(event_post_updated, post.id.str(), {
		'post_id': post.id.str()
		'title':   post.title
	})
	bus.dispatch(event)

	// 若从非发布状态变为发布状态，分发 post.published 事件
	if !was_published && post.status == 'published' {
		s.dispatch_published_event(post)
	}

	return post
}

// delete 删除文章：LockGuard 加锁 → 事务删除 → TaggedCache 失效
@[transactional]
pub fn (mut s PostService) delete(id int) ! {
	// 使用 LockGuard RAII 防止并发删除冲突
	mut lm := s.lock_mgr
	guard := locking.new_lock_guard(mut lm, 'post:delete:${id}')
	defer {
		guard.unlock()
	}

	// 事务保证：删除失败则回滚
	mut tx := begin_transaction(s.repo.db)!
	defer {
		tx.auto_rollback()
	}

	s.repo.delete_by_id(id)!

	tx.commit()!

	// 事务后副作用：TaggedCache 批量失效 'posts' 标签下所有缓存键
	flush_cache_tag(s.cache, 'posts')

	s.logger.info('[PostService] 文章删除成功: id=${id}')
}

// increment_views 文章浏览数自增（LockGuard 防止并发竞争）
pub fn (mut s PostService) increment_views(id int) ! {
	mut lm := s.lock_mgr
	guard := locking.new_lock_guard(mut lm, 'post:views:${id}')
	defer {
		guard.unlock()
	}

	s.repo.increment_views(id)!
}

// publish 发布文章：LockGuard 加锁 → 更新状态 → TaggedCache 失效 → 分发 post.published 事件
pub fn (mut s PostService) publish(id int) !Post {
	// 使用 LockGuard 防止并发发布冲突
	mut lm := s.lock_mgr
	guard := locking.new_lock_guard(mut lm, 'post:publish:${id}')
	defer {
		guard.unlock()
	}

	mut repo := s.repo
	mut post := repo.find_by_id(id)!

	if post.status == 'published' {
		return post // 已发布，幂等返回
	}

	post.status = 'published'
	post = repo.update(mut post)!

	// TaggedCache 批量失效 'posts' 标签下所有缓存键
	flush_cache_tag(s.cache, 'posts')

	s.logger.info('[PostService] 文章发布成功: id=${post.id} title="${post.title}"')

	// 分发 post.published 事件
	s.dispatch_published_event(post)

	return post
}

// count_by_status 按状态统计文章数
pub fn (s &PostService) count_by_status(status string) !int {
	return s.repo.count_by_status(status)!
}

// dispatch_published_event 分发文章发布事件（内部辅助方法）
fn (mut s PostService) dispatch_published_event(post Post) {
	mut bus := s.event_bus
	event := core.new_event_with_data(event_post_published, post.title, {
		'post_id': post.id.str()
		'title':   post.title
	})
	bus.dispatch(event)
}

// ═══════════════════════════════════════════════════════════
// CommentService — 评论业务逻辑
// ═══════════════════════════════════════════════════════════

pub struct CommentService {
pub:
	repo      &CommentRepository
	event_bus &core.EventBus
	logger    &logger.Logger
}

// new_comment_service 创建评论服务，注入仓储、事件总线和日志
pub fn new_comment_service(repo &CommentRepository, bus &core.EventBus, log &logger.Logger) &CommentService {
	return unsafe {
		&CommentService{
			repo:      repo
			event_bus: bus
			logger:    log
		}
	}
}

// create 创建评论：事务持久化评论 + 更新文章活动时间 → 分发 comment.posted 事件
@[transactional]
pub fn (mut s CommentService) create(dto CreateCommentDto) !Comment {
	mut comment := Comment{
		post_id:   dto.post_id
		user_id:   dto.user_id
		content:   dto.content
		parent_id: dto.parent_id
		status:    'visible'
	}

	// 事务保证：评论创建 + 文章活动时间更新原子性
	// 任一步骤失败则整体回滚（评论不会孤立存在）
	mut tx := begin_transaction(s.repo.db)!
	defer {
		tx.auto_rollback()
	}

	mut repo := s.repo
	comment = repo.save(mut comment)!

	// 第二步：更新文章的 updated_at 时间戳，标记文章有新活动
	// 若此步失败，评论创建也会回滚（原子性保证）
	repo.touch_post(comment.post_id)!

	tx.commit()!

	s.logger.info('[CommentService] 评论创建成功: id=${comment.id} post_id=${comment.post_id} user_id=${comment.user_id}')

	// 事务后副作用：事件分发（非 DB 操作，放在 commit 之后）
	mut bus := s.event_bus
	event := core.new_event_with_data(event_comment_posted, comment.content, {
		'comment_id': comment.id.str()
		'post_id':    comment.post_id.str()
		'user_id':    comment.user_id.str()
		'content':    comment.content
	})
	bus.dispatch(event)

	return comment
}

// find_by_id 查询评论详情
pub fn (mut s CommentService) find_by_id(id int) !Comment {
	mut repo := s.repo
	return repo.find_by_id(id)!
}

// find_by_post 查询某文章的所有评论
pub fn (s &CommentService) find_by_post(post_id int) ![]Comment {
	return s.repo.find_by_post(post_id)!
}

// find_replies 查询某评论的子评论（嵌套评论）
pub fn (s &CommentService) find_replies(parent_id int) ![]Comment {
	return s.repo.find_by_parent(parent_id)!
}

// delete 删除评论（标记为 deleted 状态，软删除）
pub fn (mut s CommentService) delete(id int) ! {
	mut repo := s.repo
	mut comment := repo.find_by_id(id)!
	comment.status = 'deleted'
	comment = repo.update(mut comment)!

	s.logger.info('[CommentService] 评论删除成功: id=${comment.id}')
}

// count_by_post 统计某文章的评论数
pub fn (s &CommentService) count_by_post(post_id int) !int {
	return s.repo.count_by_post(post_id)!
}

// ═══════════════════════════════════════════════════════════
// CategoryService — 分类业务逻辑
// ═══════════════════════════════════════════════════════════

pub struct CategoryService {
pub:
	repo   &CategoryRepository
	logger &logger.Logger
}

// new_category_service 创建分类服务
pub fn new_category_service(repo &CategoryRepository, log &logger.Logger) &CategoryService {
	return unsafe {
		&CategoryService{
			repo:   repo
			logger: log
		}
	}
}

// create 创建分类：自动生成 slug（若未提供）→ 校验唯一性 → 持久化
pub fn (mut s CategoryService) create(dto CreateCategoryDto) !Category {
	// 生成 slug（若未提供，从 name 生成）
	mut slug := dto.slug
	if slug.len == 0 {
		slug = generate_slug(dto.name)
	}

	// 校验 slug 唯一性
	if s.repo.exists_by_slug(slug) {
		return error('分类 slug 已存在 / category slug already exists: ${slug}')
	}

	mut category := Category{
		name:        dto.name
		slug:        slug
		description: dto.description
	}

	mut repo := s.repo
	category = repo.save(mut category)!

	s.logger.info('[CategoryService] 分类创建成功: id=${category.id} name="${category.name}"')
	return category
}

// find_by_id 查询分类详情
pub fn (mut s CategoryService) find_by_id(id int) !Category {
	mut repo := s.repo
	return repo.find_by_id(id)!
}

// find_all 查询所有分类
pub fn (mut s CategoryService) find_all() ![]Category {
	mut repo := s.repo
	return repo.find_all()!
}

// find_by_slug 按 slug 查询分类
pub fn (s &CategoryService) find_by_slug(slug string) !Category {
	return s.repo.find_by_slug(slug)!
}

// update 更新分类
pub fn (mut s CategoryService) update(id int, dto CreateCategoryDto) !Category {
	mut repo := s.repo
	mut category := repo.find_by_id(id)!

	if dto.name.len > 0 {
		category.name = dto.name
	}
	if dto.slug.len > 0 {
		if dto.slug != category.slug && s.repo.exists_by_slug(dto.slug) {
			return error('分类 slug 已存在 / category slug already exists: ${dto.slug}')
		}
		category.slug = dto.slug
	}
	if dto.description.len > 0 {
		category.description = dto.description
	}

	category = repo.update(mut category)!

	s.logger.info('[CategoryService] 分类更新成功: id=${category.id}')
	return category
}

// delete 删除分类
pub fn (s &CategoryService) delete(id int) ! {
	s.repo.delete_by_id(id)!
	s.logger.info('[CategoryService] 分类删除成功: id=${id}')
}

// ═══════════════════════════════════════════════════════════
// TagService — 标签业务逻辑
// ═══════════════════════════════════════════════════════════

pub struct TagService {
pub:
	repo   &TagRepository
	logger &logger.Logger
}

// new_tag_service 创建标签服务
pub fn new_tag_service(repo &TagRepository, log &logger.Logger) &TagService {
	return unsafe {
		&TagService{
			repo:   repo
			logger: log
		}
	}
}

// create 创建标签：自动生成 slug → 校验唯一性 → 持久化
pub fn (mut s TagService) create(dto CreateTagDto) !Tag {
	// 生成 slug
	mut slug := dto.slug
	if slug.len == 0 {
		slug = generate_slug(dto.name)
	}

	// 校验 slug 唯一性
	if s.repo.exists_by_slug(slug) {
		return error('标签 slug 已存在 / tag slug already exists: ${slug}')
	}

	mut tag := Tag{
		name: dto.name
		slug: slug
	}

	mut repo := s.repo
	tag = repo.save(mut tag)!

	s.logger.info('[TagService] 标签创建成功: id=${tag.id} name="${tag.name}"')
	return tag
}

// find_by_id 查询标签详情
pub fn (mut s TagService) find_by_id(id int) !Tag {
	mut repo := s.repo
	return repo.find_by_id(id)!
}

// find_all 查询所有标签
pub fn (mut s TagService) find_all() ![]Tag {
	mut repo := s.repo
	return repo.find_all()!
}

// find_by_slug 按 slug 查询标签
pub fn (s &TagService) find_by_slug(slug string) !Tag {
	return s.repo.find_by_slug(slug)!
}

// update 更新标签
pub fn (mut s TagService) update(id int, dto CreateTagDto) !Tag {
	mut repo := s.repo
	mut tag := repo.find_by_id(id)!

	if dto.name.len > 0 {
		tag.name = dto.name
	}
	if dto.slug.len > 0 {
		if dto.slug != tag.slug && s.repo.exists_by_slug(dto.slug) {
			return error('标签 slug 已存在 / tag slug already exists: ${dto.slug}')
		}
		tag.slug = dto.slug
	}

	tag = repo.update(mut tag)!

	s.logger.info('[TagService] 标签更新成功: id=${tag.id}')
	return tag
}

// delete 删除标签
pub fn (s &TagService) delete(id int) ! {
	s.repo.delete_by_id(id)!
	s.logger.info('[TagService] 标签删除成功: id=${id}')
}

// attach_tag 为文章添加标签
pub fn (s &TagService) attach_tag(post_id int, tag_id int) ! {
	s.repo.attach_tag(post_id, tag_id)!
	s.logger.info('[TagService] 标签关联: post_id=${post_id} tag_id=${tag_id}')
}

// detach_tag 移除文章的标签关联
pub fn (s &TagService) detach_tag(post_id int, tag_id int) ! {
	s.repo.detach_tag(post_id, tag_id)!
	s.logger.info('[TagService] 标签解除关联: post_id=${post_id} tag_id=${tag_id}')
}

// find_tags_by_post 查询文章的所有标签
pub fn (s &TagService) find_tags_by_post(post_id int) ![]Tag {
	return s.repo.find_tags_by_post(post_id)!
}

// find_post_ids_by_tag 查询带有某标签的所有文章 ID
pub fn (s &TagService) find_post_ids_by_tag(tag_id int) ![]int {
	return s.repo.find_post_ids_by_tag(tag_id)!
}

// ═══════════════════════════════════════════════════════════
// StatsService — 统计聚合服务（带缓存）
// ═══════════════════════════════════════════════════════════

pub struct StatsService {
pub:
	user_repo    &UserRepository
	post_repo    &PostRepository
	comment_repo &CommentRepository
	cache        &cache.CacheManager
	lock_mgr     &locking.LockManager
	logger       &logger.Logger
}

// new_stats_service 创建统计服务，注入各仓储、缓存和锁管理器
pub fn new_stats_service(user_repo &UserRepository, post_repo &PostRepository, comment_repo &CommentRepository, cm &cache.CacheManager, lm &locking.LockManager, log &logger.Logger) &StatsService {
	return unsafe {
		&StatsService{
			user_repo:    user_repo
			post_repo:    post_repo
			comment_repo: comment_repo
			cache:        cm
			lock_mgr:     lm
			logger:       log
		}
	}
}

// get_blog_stats 获取博客综合统计（带缓存 + Singleflight 削峰，TTL 1 小时）
// 缓存未命中时从各仓储实时聚合
pub fn (mut s StatsService) get_blog_stats() !BlogStats {
	cache_key := 'stats:blog'
	mut cm := s.cache

	// get_or_load 内部使用 Singleflight 合并并发回源请求
	cached := cm.get_or_load(cache_key, 3600, fn [s] () !string {
		stats := s.aggregate_stats()!
		return json.encode(stats)
	})!

	// 解码缓存，失败则删除损坏缓存并回源
	stats := json.decode(BlogStats, cached) or {
		cm.delete(cache_key) or {}
		return s.aggregate_stats()!
	}

	return stats
}

// aggregate_stats 实时聚合统计数据（LockGuard 防止并发重复聚合）
pub fn (s &StatsService) aggregate_stats() !BlogStats {
	// 使用 LockGuard 防止并发聚合（统计聚合涉及多次 DB 查询，避免重复计算）
	mut lm := s.lock_mgr
	guard := locking.new_lock_guard(mut lm, 'stats:aggregate')
	defer {
		guard.unlock()
	}

	user_count := s.user_repo.count() or {
		s.logger.error('[StatsService] 用户计数失败: ${err}')
		0
	}
	post_count := s.post_repo.count() or {
		s.logger.error('[StatsService] 文章计数失败: ${err}')
		0
	}
	published_count := s.post_repo.count_by_status('published') or {
		s.logger.error('[StatsService] 已发布文章计数失败: ${err}')
		0
	}
	draft_count := s.post_repo.count_by_status('draft') or {
		s.logger.error('[StatsService] 草稿文章计数失败: ${err}')
		0
	}
	comment_count := s.comment_repo.count() or {
		s.logger.error('[StatsService] 评论计数失败: ${err}')
		0
	}

	return BlogStats{
		user_count:      user_count
		post_count:      post_count
		published_count: published_count
		draft_count:     draft_count
		comment_count:   comment_count
		aggregated_at:   time.now().unix()
	}
}

// get_user_count 获取用户数（带缓存 + Singleflight）
pub fn (mut s StatsService) get_user_count() !int {
	cache_key := 'stats:user_count'
	mut cm := s.cache
	user_repo := s.user_repo

	cached := cm.get_or_load(cache_key, 3600, fn [user_repo] () !string {
		count := user_repo.count() or { 0 }
		return count.str()
	})!

	return cached.int()
}

// get_post_count 获取文章数（带缓存 + Singleflight）
pub fn (mut s StatsService) get_post_count() !int {
	cache_key := 'stats:post_count'
	mut cm := s.cache
	post_repo := s.post_repo

	cached := cm.get_or_load(cache_key, 3600, fn [post_repo] () !string {
		count := post_repo.count() or { 0 }
		return count.str()
	})!

	return cached.int()
}

// get_comment_count 获取评论数（带缓存 + Singleflight）
pub fn (mut s StatsService) get_comment_count() !int {
	cache_key := 'stats:comment_count'
	mut cm := s.cache
	comment_repo := s.comment_repo

	cached := cm.get_or_load(cache_key, 3600, fn [comment_repo] () !string {
		count := comment_repo.count() or { 0 }
		return count.str()
	})!

	return cached.int()
}

// invalidate_cache 失效所有统计缓存（TaggedCache 批量失效 'stats' 标签）
pub fn (mut s StatsService) invalidate_cache() ! {
	flush_cache_tag(s.cache, 'stats')
	s.logger.info('[StatsService] 统计缓存已失效')
}

// ═══════════════════════════════════════════════════════════
// UploadService — 文件上传服务
// ═══════════════════════════════════════════════════════════

pub struct UploadService {
pub:
	storage   &storage.StorageManager
	handler   &web.UploadHandler
	base_path string
	logger    &logger.Logger
}

// new_upload_service 创建上传服务，注入存储管理器、上传处理器和基础路径
pub fn new_upload_service(sm &storage.StorageManager, handler &web.UploadHandler, base_path string, log &logger.Logger) &UploadService {
	return unsafe {
		&UploadService{
			storage:   sm
			handler:   handler
			base_path: base_path
			logger:    log
		}
	}
}

// upload_avatar 上传头像：限制 2MB，仅支持 jpg/jpeg/png
pub fn (mut s UploadService) upload_avatar(name string, data []u8) !web.UploadResult {
	// 头像规格：2MB，jpg/jpeg/png
	max_avatar_size := 2 * 1024 * 1024
	if data.len > max_avatar_size {
		return error('头像大小超过限制 / avatar exceeds max size (2MB)')
	}

	ext := os.file_ext(name).to_lower()
	if ext !in ['.jpg', '.jpeg', '.png'] {
		return error('头像格式不支持 / avatar format not supported (only jpg/jpeg/png)')
	}

	dest_dir := os.join_path(s.base_path, 'avatars')
	mut handler := s.handler
	result := handler.handle_bytes(name, data, dest_dir)!

	s.logger.info('[UploadService] 头像上传成功: ${result.stored_name} (${result.size} bytes)')
	return result
}

// upload_image 上传文章配图：限制 5MB，支持 jpg/jpeg/png/gif/webp
pub fn (mut s UploadService) upload_image(name string, data []u8) !web.UploadResult {
	// 配图规格：5MB，jpg/jpeg/png/gif/webp
	max_image_size := 5 * 1024 * 1024
	if data.len > max_image_size {
		return error('图片大小超过限制 / image exceeds max size (5MB)')
	}

	ext := os.file_ext(name).to_lower()
	if ext !in ['.jpg', '.jpeg', '.png', '.gif', '.webp'] {
		return error('图片格式不支持 / image format not supported (only jpg/jpeg/png/gif/webp)')
	}

	dest_dir := os.join_path(s.base_path, 'images')
	mut handler := s.handler
	result := handler.handle_bytes(name, data, dest_dir)!

	s.logger.info('[UploadService] 图片上传成功: ${result.stored_name} (${result.size} bytes)')
	return result
}

// upload 通用文件上传（使用配置的允许扩展名）
pub fn (mut s UploadService) upload(name string, data []u8, sub_dir string) !web.UploadResult {
	dest_dir := os.join_path(s.base_path, sub_dir)
	mut handler := s.handler
	result := handler.handle_bytes(name, data, dest_dir)!

	s.logger.info('[UploadService] 文件上传成功: ${result.stored_name} (${result.size} bytes)')
	return result
}

// get_file 读取已上传的文件内容
pub fn (s &UploadService) get_file(path string) !string {
	disk := s.storage.disk('local')!
	return disk.read(path)!
}

// file_exists 检查文件是否存在
pub fn (s &UploadService) file_exists(path string) bool {
	disk := s.storage.disk('local') or { return false }
	return disk.exists(path)
}

// file_url 获取文件的访问 URL
pub fn (s &UploadService) file_url(path string) string {
	disk := s.storage.disk('local') or { return '/storage/${path}' }
	return disk.url(path)
}

// file_size 获取文件大小
pub fn (s &UploadService) file_size(path string) !i64 {
	disk := s.storage.disk('local')!
	return disk.size(path)!
}

// delete_file 删除已上传的文件
pub fn (s &UploadService) delete_file(path string) ! {
	disk := s.storage.disk('local')!
	// Storage 接口的 delete 需要 mut 接收者，通过 unsafe 获取可变引用
	unsafe {
		mut d := disk
		d.delete(path)!
	}
	s.logger.info('[UploadService] 文件删除成功: ${path}')
}

// ═══════════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════════

// generate_slug 已迁移至 helpers.v

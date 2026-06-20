module services

// services.v — PhotonBlog 服务层
//
// 实现业务逻辑，协调仓储层（Repository）与基础设施（Cache / Security / Mailer / EventBus）。
// 每个服务对应一个领域：用户、认证、文章、评论、分类、标签、统计、上传。

import photon.orm as phorm
import photon.cache
import photon.security
import photon.logger
import json
import time
import models
import repositories
import util

// ═══════════════════════════════════════════════════════════
// UserService — 用户服务
// ═══════════════════════════════════════════════════════════

pub struct UserService {
pub mut:
	repo  &repositories.UserRepository
	cache &cache.CacheManager
	log   &logger.Logger
}

pub fn new_user_service(repo &repositories.UserRepository, cache_mgr &cache.CacheManager, log &logger.Logger) &UserService {
	return &UserService{
		repo: repo
		cache: cache_mgr
		log: log
	}
}

// register 注册新用户
pub fn (mut s UserService) register(dto models.CreateUserDto, hashed_password string) !(models.User, string) {
	if s.repo.exists_by_username(dto.username) {
		return error('username already taken / 用户名已存在')
	}
	if s.repo.exists_by_email(dto.email) {
		return error('email already registered / 邮箱已注册')
	}

	now := time.now().unix()
	mut user := models.User{
		BaseEntity: phorm.BaseEntity{created_at: now, updated_at: now, version: 1}
		username: dto.username
		email:    dto.email
		password: hashed_password
		nickname: dto.nickname
		status:   1
		role:     dto.role
	}

	mut repo := unsafe { s.repo }
	saved := repo.save(mut user) or {
		return error('user save failed / 用户保存失败: ${err}')
	}

	// 缓存失效
	util.flush_cache_tag(s.cache, 'users')

	s.log.info('[UserService] user registered: ${saved.username} (id=${saved.id})')
	return saved, 'user registered successfully / 用户注册成功'
}

// login 用户登录
pub fn (s &UserService) login(dto models.LoginDto, hasher &security.BcryptHasher) !(models.User, string) {
	user := s.repo.find_by_username(dto.username) or {
		return error('invalid credentials / 用户名或密码错误')
	}

	if user.status != 1 {
		return error('account disabled / 账户已禁用')
	}

	if !hasher.check(dto.password, user.password) {
		return error('invalid credentials / 用户名或密码错误')
	}

	s.log.info('[UserService] user logged in: ${user.username}')
	return user, 'login successful / 登录成功'
}

// find_by_id 根据 ID 查询用户（带缓存）
pub fn (mut s UserService) find_by_id(id int) !models.User {
	cache_key := 'user:${id}'
	cached := s.cache.get(cache_key) or { '' }
	if cached.len > 0 {
		return json.decode(models.User, cached)!
	}

	user := s.repo.find_by_id(id)!
	s.cache.set(cache_key, json.encode(user), 300) or {}
	return user
}

// find_by_username 根据用户名查询用户
pub fn (s &UserService) find_by_username(username string) !models.User {
	return s.repo.find_by_username(username)!
}

// update_profile 更新用户资料
pub fn (mut s UserService) update_profile(id int, dto models.UpdateUserDto) !models.User {
	mut user := s.repo.find_by_id(id)!

	if dto.nickname.len > 0 {
		user.nickname = dto.nickname
	}
	if dto.avatar.len > 0 {
		user.avatar = dto.avatar
	}
	if dto.email.len > 0 {
		if dto.email != user.email && s.repo.exists_by_email(dto.email) {
			return error('email already registered / 邮箱已注册')
		}
		user.email = dto.email
	}
	user.updated_at = time.now().unix()

	mut repo := unsafe { s.repo }
	updated := repo.update(mut user) or {
		return error('user update failed / 用户更新失败: ${err}')
	}

	// 缓存失效
	s.cache.delete('user:${id}') or {}
	util.flush_cache_tag(s.cache, 'users')

	return updated
}

// change_password 修改密码
pub fn (mut s UserService) change_password(id int, old_password string, new_password string, hasher &security.BcryptHasher) ! {
	user := s.repo.find_by_id(id)!

	if !hasher.check(old_password, user.password) {
		return error('current password incorrect / 当前密码错误')
	}

	hashed := hasher.make(new_password)

	mut u := user
	u.password = hashed
	u.updated_at = time.now().unix()

	mut repo := unsafe { s.repo }
	repo.update(mut u) or {
		return error('password update failed / 密码更新失败: ${err}')
	}

	s.cache.delete('user:${id}') or {}
}

// delete 删除用户
pub fn (mut s UserService) delete(id int) ! {
	s.repo.delete_by_id(id)!
	s.cache.delete('user:${id}') or {}
	util.flush_cache_tag(s.cache, 'users')
}

// list 列表查询（带过滤/排序/分页）
pub fn (s &UserService) list(filter models.UserFilter, sort string, page int, page_size int) !([]models.User, int) {
	return s.repo.find_with_filters(filter, sort, page, page_size)!
}

// count 统计用户总数
pub fn (s &UserService) count() !int {
	return s.repo.count()!
}

// ═══════════════════════════════════════════════════════════
// AuthService — 认证服务
// ═══════════════════════════════════════════════════════════

pub struct AuthService {
pub mut:
	user_repo &repositories.UserRepository
	hasher    &security.BcryptHasher
	jwt       &security.JwtManager
	cache     &cache.CacheManager
	logger    &logger.Logger
}

pub fn new_auth_service(user_repo &repositories.UserRepository, hasher &security.BcryptHasher, jwt &security.JwtManager, cache_mgr &cache.CacheManager, log &logger.Logger) &AuthService {
	return &AuthService{
		user_repo: user_repo
		hasher:    hasher
		jwt:       jwt
		cache:     cache_mgr
		logger:    log
	}
}

// authenticate 验证用户名密码，返回 JWT token
pub fn (s &AuthService) authenticate(username string, password string) !(string, []string) {
	user := s.user_repo.find_by_username(username) or {
		return error('invalid credentials / 用户名或密码错误')
	}

	if user.status != 1 {
		return error('account disabled / 账户已禁用')
	}

	hasher := unsafe { s.hasher }
	if !hasher.check(password, user.password) {
		return error('invalid credentials / 用户名或密码错误')
	}

	roles := if user.role.len > 0 { [user.role] } else { []string{} }
	jwt_mgr := unsafe { s.jwt }
	token := jwt_mgr.create_token(user.username, roles)!

	s.logger.info('[AuthService] user authenticated: ${user.username}')
	return token, roles
}

// validate_token 验证 JWT token，返回用户名
pub fn (mut s AuthService) validate_token(token string) !string {
	// 检查黑名单
	blacklist_key := 'jwt:blacklist:${token}'
	blacklisted := s.cache.get(blacklist_key) or { '' }
	if blacklisted.len > 0 {
		return error('token revoked / 令牌已撤销')
	}

	jwt_mgr := unsafe { s.jwt }
	username := jwt_mgr.validate_token(token)!
	return username
}

// parse_token 解析 JWT token，返回完整 claims
pub fn (s &AuthService) parse_token(token string) !security.JwtClaims {
	jwt_mgr := unsafe { s.jwt }
	return jwt_mgr.parse_token(token)!
}

// logout 将 token 加入黑名单
pub fn (mut s AuthService) logout(token string) ! {
	jwt_mgr := unsafe { s.jwt }
	claims := jwt_mgr.parse_token(token)!

	// 将 token 加入黑名单，TTL = token 剩余有效期
	remaining := claims.exp - time.now().unix()
	if remaining > 0 {
		s.cache.set('jwt:blacklist:${token}', '1', int(remaining)) or {}
	}

	s.logger.info('[AuthService] user logged out: ${claims.sub}')
}

// register_auth 注册新用户（认证服务版本）
pub fn (s &AuthService) register(username string, email string, password string, role string) !(models.User, string) {
	if s.user_repo.exists_by_username(username) {
		return error('username already taken / 用户名已存在')
	}
	if s.user_repo.exists_by_email(email) {
		return error('email already registered / 邮箱已注册')
	}

	hasher := unsafe { s.hasher }
	hashed := hasher.make(password)

	now := time.now().unix()
	mut user := models.User{
		BaseEntity: phorm.BaseEntity{created_at: now, updated_at: now, version: 1}
		username: username
		email:    email
		password: hashed
		status:   1
		role:     role
	}

	mut repo := unsafe { s.user_repo }
	saved := repo.save(mut user) or {
		return error('user save failed / 用户保存失败: ${err}')
	}

	s.logger.info('[AuthService] user registered: ${saved.username}')
	return saved, 'user registered successfully / 用户注册成功'
}

// ═══════════════════════════════════════════════════════════
// PostService — 文章服务
// ═══════════════════════════════════════════════════════════

pub struct PostService {
pub mut:
	repo          &repositories.PostRepository
	user_repo     &repositories.UserRepository
	category_repo &repositories.CategoryRepository
	tag_repo      &repositories.TagRepository
	cache         &cache.CacheManager
	log           &logger.Logger
}

pub fn new_post_service(repo &repositories.PostRepository, user_repo &repositories.UserRepository, category_repo &repositories.CategoryRepository, tag_repo &repositories.TagRepository, cache_mgr &cache.CacheManager, log &logger.Logger) &PostService {
	return &PostService{
		repo:          repo
		user_repo:     user_repo
		category_repo: category_repo
		tag_repo:      tag_repo
		cache:         cache_mgr
		log:           log
	}
}

// create 创建文章
pub fn (mut s PostService) create(dto models.CreatePostDto, author_id int) !(models.Post, string) {
	category := s.category_repo.find_by_id(dto.category_id) or {
		return error('category not found / 分类不存在: id=${dto.category_id}')
	}

	now := time.now().unix()
	mut post := models.Post{
		BaseEntity: phorm.BaseEntity{created_at: now, updated_at: now, version: 1}
		title:       dto.title
		content:     dto.content
		summary:     dto.summary
		author_id:   author_id
		category_id: category.id
		status:      dto.status
	}

	mut repo := unsafe { s.repo }
	saved := repo.save(mut post) or {
		return error('post save failed / 文章保存失败: ${err}')
	}

	// 关联标签
	if dto.tag_ids.len > 0 {
		for tag_id in dto.tag_ids {
			s.tag_repo.attach_tag(saved.id, tag_id) or {
				s.log.error('[PostService] failed to attach tag ${tag_id} to post ${saved.id}: ${err}')
			}
		}
	}

	util.flush_cache_tag(s.cache, 'posts')
	s.log.info('[PostService] post created: ${saved.title} (id=${saved.id})')
	return saved, 'post created successfully / 文章创建成功'
}

// find_by_id 根据 ID 查询文章（带缓存）
pub fn (mut s PostService) find_by_id(id int) !models.Post {
	cache_key := 'post:${id}'
	cached := s.cache.get(cache_key) or { '' }
	if cached.len > 0 {
		return json.decode(models.Post, cached)!
	}

	post := s.repo.find_by_id(id)!
	s.cache.set(cache_key, json.encode(post), 300) or {}
	return post
}

// update 更新文章
pub fn (mut s PostService) update(id int, dto models.UpdatePostDto) !(models.Post, string) {
	mut post := s.repo.find_by_id(id)!

	if dto.title.len > 0 {
		post.title = dto.title
	}
	if dto.content.len > 0 {
		post.content = dto.content
	}
	if dto.summary.len > 0 {
		post.summary = dto.summary
	}
	if dto.category_id > 0 {
		post.category_id = dto.category_id
	}
	if dto.status.len > 0 {
		post.status = dto.status
	}
	post.updated_at = time.now().unix()

	mut repo := unsafe { s.repo }
	updated := repo.update(mut post) or {
		return error('post update failed / 文章更新失败: ${err}')
	}

	// 更新标签关联
	if dto.tag_ids.len > 0 {
		// 先移除所有旧标签
		old_tags := s.tag_repo.find_tags_by_post(id) or { []models.Tag{} }
		for tag in old_tags {
			s.tag_repo.detach_tag(id, tag.id) or {}
		}
		// 再添加新标签
		for tag_id in dto.tag_ids {
			s.tag_repo.attach_tag(id, tag_id) or {}
		}
	}

	s.cache.delete('post:${id}') or {}
	util.flush_cache_tag(s.cache, 'posts')

	s.log.info('[PostService] post updated: ${updated.title} (id=${updated.id})')
	return updated, 'post updated successfully / 文章更新成功'
}

// delete 删除文章
pub fn (mut s PostService) delete(id int) ! {
	s.repo.delete_by_id(id)!
	s.cache.delete('post:${id}') or {}
	util.flush_cache_tag(s.cache, 'posts')
	s.log.info('[PostService] post deleted: id=${id}')
}

// list 列表查询（带过滤/排序/分页）
pub fn (s &PostService) list(filter models.PostFilter, sort string, page int, page_size int) !([]models.Post, int) {
	return s.repo.find_with_filters(filter, sort, page, page_size)!
}

// find_published 查询已发布文章
pub fn (s &PostService) find_published() ![]models.Post {
	return s.repo.find_published()!
}

// find_by_author 查询作者的文章
pub fn (s &PostService) find_by_author(author_id int) ![]models.Post {
	return s.repo.find_by_author(author_id)!
}

// increment_views 增加文章浏览量
pub fn (s &PostService) increment_views(id int) ! {
	s.repo.increment_views(id)!
}

// count_by_status 按状态统计文章数
pub fn (s &PostService) count_by_status(status string) !int {
	return s.repo.count_by_status(status)!
}

// count 统计文章总数
pub fn (s &PostService) count() !int {
	return s.repo.count()!
}

// find_post_with_relations 查询文章及关联数据
pub fn (mut s PostService) find_post_with_relations(id int) !(models.Post, models.User, models.Category, []models.Tag) {
	post := s.repo.find_by_id(id)!

	mut author := models.User{}
	if post.author_id > 0 {
		author = s.user_repo.find_by_id(post.author_id) or { models.User{} }
	}

	mut category := models.Category{}
	if post.category_id > 0 {
		category = s.category_repo.find_by_id(post.category_id) or { models.Category{} }
	}

	tags := s.tag_repo.find_tags_by_post(id) or { []models.Tag{} }

	return post, author, category, tags
}

// ═══════════════════════════════════════════════════════════
// CommentService — 评论服务
// ═══════════════════════════════════════════════════════════

pub struct CommentService {
pub mut:
	repo      &repositories.CommentRepository
	post_repo &repositories.PostRepository
	user_repo &repositories.UserRepository
	cache     &cache.CacheManager
	log       &logger.Logger
}

pub fn new_comment_service(repo &repositories.CommentRepository, post_repo &repositories.PostRepository, user_repo &repositories.UserRepository, cache_mgr &cache.CacheManager, log &logger.Logger) &CommentService {
	return &CommentService{
		repo:      repo
		post_repo: post_repo
		user_repo: user_repo
		cache:     cache_mgr
		log:       log
	}
}

// create 创建评论
pub fn (mut s CommentService) create(dto models.CreateCommentDto, user_id int) !(models.Comment, string) {
	// 验证文章存在
	post := s.post_repo.find_by_id(dto.post_id) or {
		return error('post not found / 文章不存在: id=${dto.post_id}')
	}

	now := time.now().unix()
	mut comment := models.Comment{
		BaseEntity: phorm.BaseEntity{created_at: now, updated_at: now, version: 1}
		post_id:   post.id
		user_id:   user_id
		content:   dto.content
		parent_id: dto.parent_id
		status:    'visible'
	}

	mut repo := unsafe { s.repo }
	saved := repo.save(mut comment) or {
		return error('comment save failed / 评论保存失败: ${err}')
	}

	// 触摸文章更新时间
	s.repo.touch_post(post.id) or {
		s.log.error('[CommentService] failed to touch post ${post.id}: ${err}')
	}

	util.flush_cache_tag(s.cache, 'comments')
	s.log.info('[CommentService] comment created: post_id=${saved.post_id} user_id=${saved.user_id}')
	return saved, 'comment created successfully / 评论创建成功'
}

// find_by_post 查询文章的评论
pub fn (s &CommentService) find_by_post(post_id int) ![]models.Comment {
	return s.repo.find_by_post(post_id)!
}

// find_by_id 根据 ID 查询评论
pub fn (s &CommentService) find_by_id(id int) !models.Comment {
	return s.repo.find_by_id(id)!
}

// delete 删除评论
pub fn (mut s CommentService) delete(id int) ! {
	s.repo.delete_by_id(id)!
	util.flush_cache_tag(s.cache, 'comments')
	s.log.info('[CommentService] comment deleted: id=${id}')
}

// list 列表查询（带过滤/排序/分页）
pub fn (s &CommentService) list(filter models.CommentFilter, sort string, page int, page_size int) !([]models.Comment, int) {
	return s.repo.find_with_filters(filter, sort, page, page_size)!
}

// count_by_post 统计文章评论数
pub fn (s &CommentService) count_by_post(post_id int) !int {
	return s.repo.count_by_post(post_id)!
}

// count 统计评论总数
pub fn (s &CommentService) count() !int {
	return s.repo.count()!
}

// ═══════════════════════════════════════════════════════════
// CategoryService — 分类服务
// ═══════════════════════════════════════════════════════════

pub struct CategoryService {
pub mut:
	repo      &repositories.CategoryRepository
	post_repo &repositories.PostRepository
	cache     &cache.CacheManager
	log       &logger.Logger
}

pub fn new_category_service(repo &repositories.CategoryRepository, post_repo &repositories.PostRepository, cache_mgr &cache.CacheManager, log &logger.Logger) &CategoryService {
	return &CategoryService{repo: repo, post_repo: post_repo, cache: cache_mgr, log: log}
}

// create 创建分类
pub fn (mut s CategoryService) create(dto models.CreateCategoryDto) !(models.Category, string) {
	slug := util.generate_slug(dto.name)
	if s.repo.exists_by_slug(slug) {
		return error('category slug already exists / 分类别名已存在: ${slug}')
	}

	now := time.now().unix()
	mut category := models.Category{
		BaseEntity: phorm.BaseEntity{created_at: now, updated_at: now, version: 1}
		name:        dto.name
		slug:        slug
		description: dto.description
	}

	mut repo := unsafe { s.repo }
	saved := repo.save(mut category) or {
		return error('category save failed / 分类保存失败: ${err}')
	}

	util.flush_cache_tag(s.cache, 'categories')
	s.log.info('[CategoryService] category created: ${saved.name} (id=${saved.id})')
	return saved, 'category created successfully / 分类创建成功'
}

// find_all 查询所有分类
pub fn (s &CategoryService) find_all() ![]models.Category {
	return s.repo.find_all()!
}

// find_by_id 根据 ID 查询分类
pub fn (s &CategoryService) find_by_id(id int) !models.Category {
	return s.repo.find_by_id(id)!
}

// update 更新分类
pub fn (mut s CategoryService) update(id int, dto models.CreateCategoryDto) !(models.Category, string) {
	mut category := s.repo.find_by_id(id)!

	category.name = dto.name
	category.slug = util.generate_slug(dto.name)
	category.description = dto.description
	category.updated_at = time.now().unix()

	mut repo := unsafe { s.repo }
	updated := repo.update(mut category) or {
		return error('category update failed / 分类更新失败: ${err}')
	}

	util.flush_cache_tag(s.cache, 'categories')
	s.log.info('[CategoryService] category updated: ${updated.name} (id=${updated.id})')
	return updated, 'category updated successfully / 分类更新成功'
}

// delete 删除分类
pub fn (mut s CategoryService) delete(id int) ! {
	s.repo.delete_by_id(id)!
	util.flush_cache_tag(s.cache, 'categories')
	s.log.info('[CategoryService] category deleted: id=${id}')
}

// count 统计分类总数
pub fn (s &CategoryService) count() !int {
	return s.repo.count()!
}

// ═══════════════════════════════════════════════════════════
// TagService — 标签服务
// ═══════════════════════════════════════════════════════════

pub struct TagService {
pub mut:
	repo  &repositories.TagRepository
	cache &cache.CacheManager
	log   &logger.Logger
}

pub fn new_tag_service(repo &repositories.TagRepository, cache_mgr &cache.CacheManager, log &logger.Logger) &TagService {
	return &TagService{repo: repo, cache: cache_mgr, log: log}
}

// create 创建标签
pub fn (mut s TagService) create(dto models.CreateTagDto) !(models.Tag, string) {
	slug := util.generate_slug(dto.name)
	if s.repo.exists_by_slug(slug) {
		return error('tag slug already exists / 标签别名已存在: ${slug}')
	}

	now := time.now().unix()
	mut tag := models.Tag{
		BaseEntity: phorm.BaseEntity{created_at: now, updated_at: now, version: 1}
		name: dto.name
		slug: slug
	}

	mut repo := unsafe { s.repo }
	saved := repo.save(mut tag) or {
		return error('tag save failed / 标签保存失败: ${err}')
	}

	util.flush_cache_tag(s.cache, 'tags')
	s.log.info('[TagService] tag created: ${saved.name} (id=${saved.id})')
	return saved, 'tag created successfully / 标签创建成功'
}

// find_all 查询所有标签
pub fn (s &TagService) find_all() ![]models.Tag {
	return s.repo.find_all()!
}

// find_by_id 根据 ID 查询标签
pub fn (s &TagService) find_by_id(id int) !models.Tag {
	return s.repo.find_by_id(id)!
}

// delete 删除标签
pub fn (mut s TagService) delete(id int) ! {
	s.repo.delete_by_id(id)!
	util.flush_cache_tag(s.cache, 'tags')
	s.log.info('[TagService] tag deleted: id=${id}')
}

// count 统计标签总数
pub fn (s &TagService) count() !int {
	return s.repo.count()!
}

// ═══════════════════════════════════════════════════════════
// StatsService — 统计服务
// ═══════════════════════════════════════════════════════════

pub struct StatsService {
pub mut:
	user_repo     &repositories.UserRepository
	post_repo     &repositories.PostRepository
	comment_repo  &repositories.CommentRepository
	category_repo &repositories.CategoryRepository
	tag_repo      &repositories.TagRepository
	cache         &cache.CacheManager
	log           &logger.Logger
}

pub fn new_stats_service(user_repo &repositories.UserRepository, post_repo &repositories.PostRepository, comment_repo &repositories.CommentRepository, category_repo &repositories.CategoryRepository, tag_repo &repositories.TagRepository, cache_mgr &cache.CacheManager, log &logger.Logger) &StatsService {
	return &StatsService{
		user_repo:     user_repo
		post_repo:     post_repo
		comment_repo:  comment_repo
		category_repo: category_repo
		tag_repo:      tag_repo
		cache:         cache_mgr
		log:           log
	}
}

// get_blog_stats 获取博客统计（带缓存）
pub fn (mut s StatsService) get_blog_stats() !models.BlogStats {
	cache_key := 'stats:blog'
	cached := s.cache.get(cache_key) or { '' }
	if cached.len > 0 {
		return json.decode(models.BlogStats, cached)!
	}

	stats := s.aggregate_stats() or {
		return error('stats aggregation failed / 统计聚合失败: ${err}')
	}

	stats_json := json.encode(stats)
	s.cache.set(cache_key, stats_json, 3600) or {}

	return stats
}

// aggregate_stats 聚合统计数据
pub fn (s &StatsService) aggregate_stats() !models.BlogStats {
	user_count := s.user_repo.count() or { 0 }
	post_count := s.post_repo.count() or { 0 }
	published_count := s.post_repo.count_by_status('published') or { 0 }
	draft_count := s.post_repo.count_by_status('draft') or { 0 }
	comment_count := s.comment_repo.count() or { 0 }
	tag_count := s.tag_repo.count() or { 0 }
	category_count := s.category_repo.count() or { 0 }

	return models.BlogStats{
		user_count:      user_count
		post_count:      post_count
		published_count: published_count
		draft_count:     draft_count
		comment_count:   comment_count
		tag_count:       tag_count
		category_count:  category_count
	}
}

// ═══════════════════════════════════════════════════════════
// UploadService — 上传服务
// ═══════════════════════════════════════════════════════════

pub struct UploadService {
pub mut:
	log &logger.Logger
}

pub fn new_upload_service(log &logger.Logger) &UploadService {
	return &UploadService{log: log}
}

// upload 处理文件上传（占位实现）
pub fn (s &UploadService) upload(filename string, data []u8) !(string, string) {
	s.log.info('[UploadService] file uploaded: ${filename} (${data.len} bytes)')
	return filename, 'file uploaded successfully / 文件上传成功'
}

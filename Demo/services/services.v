module services

import photon.orm as phorm
import photon.security
import photon.mailer
import photon.cache
import json
import time
import net.http
import models
import repositories
import config
import util

// ═══════════════════════════════════════════════════════════
// Event name constants
// ═══════════════════════════════════════════════════════════

pub const event_user_registered = 'user.registered'
pub const event_user_logged_in  = 'user.logged_in'
pub const event_post_published  = 'post.published'
pub const event_post_updated    = 'post.updated'
pub const event_comment_posted  = 'comment.posted'

// ═══════════════════════════════════════════════════════════
// UserService
// ═══════════════════════════════════════════════════════════

pub struct UserService {
pub mut:
	user_repo &repositories.UserRepository = unsafe { nil }
	cache_mgr cache.CacheManager
	event_bus phorm.EventBus
}

pub fn new_user_service(repo &repositories.UserRepository, cm cache.CacheManager, eb phorm.EventBus) &UserService {
	return &UserService{
		user_repo: repo
		cache_mgr: cm
		event_bus: eb
	}
}

pub fn (s &UserService) find_by_id(id int) !models.User {
	key := 'user:${id}'
	return util.cache_remember[models.User](s.cache_mgr, key, 300, fn () !models.User {
		return s.user_repo.find_active(id)!
	})!
}

pub fn (s &UserService) find_by_username(username string) !models.User {
	return s.user_repo.find_by_username(username)!
}

pub fn (s &UserService) list_users(query models.UserListQueryDto) ![]models.User {
	mut repo := unsafe { mut s.user_repo }
	return repo.find_with_filters(models.UserFilter{
		keyword: query.keyword
		status: query.status
		role: query.role
	})!
}

pub fn (s &UserService) create_user(dto models.CreateUserDto) !models.User {
	// Check uniqueness
	s.user_repo.find_by_username(dto.username) or {}
	s.user_repo.find_by_email(dto.email) or {}

	mut user := models.User{
		username: dto.username
		email: dto.email
		password: security.hash_password(dto.password)
		nickname: dto.nickname
		role: dto.role
		status: 1
	}
	if dto.github.len > 0 {
		user.avatar = s.fetch_github_avatar(dto.github) or { '' }
	}
	s.user_repo.create(mut user)!
	s.event_bus.publish(event_user_registered, user)
	return user, true
}

pub fn (s &UserService) update_user(id int, dto models.UpdateUserDto) !models.User {
	mut user := s.user_repo.find_by_id(id)!
	if dto.email.len > 0 {
		user.email = dto.email
	}
	if dto.nickname.len > 0 {
		user.nickname = dto.nickname
	}
	if dto.avatar.len > 0 {
		user.avatar = dto.avatar
	}
	if dto.status > 0 {
		user.status = dto.status
	}
	if dto.role.len > 0 {
		user.role = dto.role
	}
	user.updated_at = time.now()
	s.user_repo.update(user)!
	util.flush_cache_tag(s.cache_mgr, 'user')
	return user
}

pub fn (s &UserService) delete_user(id int) ! {
	s.user_repo.soft_delete(id)!
	util.flush_cache_tag(s.cache_mgr, 'user')
}

pub fn (s &UserService) user_profile(id int) !models.UserProfileDto {
	user := s.find_by_id(id)!
	return models.UserProfileDto{
		id: user.id
		username: user.username
		nickname: user.nickname
		avatar: user.avatar
		email: user.email
		role: user.role
		status: user.status
		created: user.created_at.format_rfc3339()
	}
}

pub fn (s &UserService) fetch_github_avatar(github string) !string {
	resp := http.get('https://api.github.com/users/${github}')!
	gh_user := json.decode(models.GithubUser, resp.body)!
	return gh_user.avatar_url
}

// ═══════════════════════════════════════════════════════════
// AuthService
// ═══════════════════════════════════════════════════════════

pub struct AuthService {
pub mut:
	user_repo  &repositories.UserRepository = unsafe { nil }
	jwt_config config.JwtConfigBlock
	role_mgr   security.RoleManager
}

pub fn new_auth_service(repo &repositories.UserRepository, jwt_cfg config.JwtConfigBlock, rm security.RoleManager) &AuthService {
	return &AuthService{
		user_repo: repo
		jwt_config: jwt_cfg
		role_mgr: rm
	}
}

pub fn (s &AuthService) login(dto models.LoginDto) !models.LoginResponseDto {
	user := s.user_repo.find_by_username(dto.username)!
	if user.status != 1 {
		return error('Account is disabled')
	}
	if !security.verify_password(dto.password, user.password) {
		return error('Invalid credentials')
	}
	token := security.generate_jwt(user.id, user.role, s.jwt_config.secret, s.jwt_config.ttl)
	return models.LoginResponseDto{
		access_token: token
		token_type: 'Bearer'
		expires_in: s.jwt_config.ttl
		refresh_token: security.generate_refresh_token(user.id, s.jwt_config.secret)
		user: models.UserProfileDto{
			id: user.id
			username: user.username
			nickname: user.nickname
			avatar: user.avatar
			email: user.email
			role: user.role
			status: user.status
			created: user.created_at.format_rfc3339()
		}
	}
}

pub fn (s &AuthService) validate_token(token string) !(int, string) {
	return security.validate_jwt(token, s.jwt_config.secret)
}

pub fn (s &AuthService) authenticate(token string) !(int, string) {
	return s.validate_token(token)
}

pub fn (s &AuthService) authorize(required_roles []string, user_roles []string) bool {
	return s.role_mgr.check_access(required_roles, user_roles)
}

pub fn (s &AuthService) refresh_token(refresh_token_str string) !string {
	user_id := security.validate_refresh_token(refresh_token_str, s.jwt_config.secret)
	user := s.user_repo.find_by_id(user_id)!
	return security.generate_jwt(user.id, user.role, s.jwt_config.secret, s.jwt_config.ttl)
}

// ═══════════════════════════════════════════════════════════
// PostService
// ═══════════════════════════════════════════════════════════

pub struct PostService {
pub mut:
	post_repo    &repositories.PostRepository = unsafe { nil }
	comment_repo &repositories.CommentRepository = unsafe { nil }
	cache_mgr    cache.CacheManager
	event_bus    phorm.EventBus
}

pub fn new_post_service(pr &repositories.PostRepository, cr &repositories.CommentRepository, cm cache.CacheManager, eb phorm.EventBus) &PostService {
	return &PostService{
		post_repo: pr
		comment_repo: cr
		cache_mgr: cm
		event_bus: eb
	}
}

pub fn (s &PostService) find_by_id(id int) !models.Post {
	key := 'post:${id}'
	return util.cache_remember[models.Post](s.cache_mgr, key, 600, fn () !models.Post {
		return s.post_repo.find_published(id)!
	})!
}

pub fn (s &PostService) list_posts(query models.PostListQueryDto) ![]models.Post {
	mut repo := unsafe { mut s.post_repo }
	return repo.find_with_filters(models.PostFilter{
		keyword: query.keyword
		status: if query.status == 'all' { '' } else { query.status }
	})!
}

pub fn (s &PostService) create_post(dto models.CreatePostDto) !models.Post {
	mut post := models.Post{
		title: dto.title
		content: dto.content
		summary: dto.summary
		author_id: dto.author_id
		category_id: dto.category_id
		status: dto.status
	}
	s.post_repo.create(mut post)!
	if post.status == 'published' {
		s.event_bus.publish(event_post_published, post)
	}
	return post
}

pub fn (s &PostService) update_post(id int, dto models.UpdatePostDto) !models.Post {
	mut post := s.post_repo.find_by_id(id)!
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
	was_draft := post.status == 'draft'
	if dto.status.len > 0 {
		post.status = dto.status
	}
	post.updated_at = time.now()
	s.post_repo.update(post)!
	util.flush_cache_tag(s.cache_mgr, 'post')
	if was_draft && post.status == 'published' {
		s.event_bus.publish(event_post_published, post)
	} else {
		s.event_bus.publish(event_post_updated, post)
	}
	return post
}

pub fn (s &PostService) delete_post(id int) ! {
	s.post_repo.soft_delete(id)!
	util.flush_cache_tag(s.cache_mgr, 'post')
}

pub fn (s &PostService) increment_views(id int) ! {
	s.post_repo.increment_views(id)!
}

// ═══════════════════════════════════════════════════════════
// CommentService
// ═══════════════════════════════════════════════════════════

pub struct CommentService {
pub mut:
	comment_repo &repositories.CommentRepository = unsafe { nil }
	event_bus    phorm.EventBus
}

pub fn new_comment_service(cr &repositories.CommentRepository, eb phorm.EventBus) &CommentService {
	return &CommentService{
		comment_repo: cr
		event_bus: eb
	}
}

pub fn (s &CommentService) list_by_post(post_id int) ![]models.Comment {
	return s.comment_repo.by_post(post_id)!
}

pub fn (s &CommentService) create_comment(dto models.CreateCommentDto) !models.Comment {
	mut comment := models.Comment{
		post_id: dto.post_id
		user_id: dto.user_id
		content: dto.content
		parent_id: dto.parent_id
		status: 'visible'
	}
	s.comment_repo.create(mut comment)!
	s.event_bus.publish(event_comment_posted, comment)
	return comment
}

pub fn (s &CommentService) delete_comment(id int) ! {
	s.comment_repo.soft_delete(id)!
}

// ═══════════════════════════════════════════════════════════
// CategoryService
// ═══════════════════════════════════════════════════════════

pub struct CategoryService {
pub mut:
	category_repo &repositories.CategoryRepository = unsafe { nil }
}

pub fn new_category_service(cr &repositories.CategoryRepository) &CategoryService {
	return &CategoryService{
		category_repo: cr
	}
}

pub fn (s &CategoryService) list_categories() ![]models.Category {
	return s.category_repo.all_ordered()!
}

pub fn (s &CategoryService) create_category(dto models.CreateCategoryDto) !models.Category {
	mut category := models.Category{
		name: dto.name
		slug: if dto.slug.len > 0 { dto.slug } else { util.generate_slug(dto.name) }
		description: dto.description
	}
	s.category_repo.create(mut category)!
	return category
}

pub fn (s &CategoryService) find_by_slug(slug string) !models.Category {
	return s.category_repo.find_by_slug(slug)!
}

// ═══════════════════════════════════════════════════════════
// TagService
// ═══════════════════════════════════════════════════════════

pub struct TagService {
pub mut:
	tag_repo &repositories.TagRepository = unsafe { nil }
}

pub fn new_tag_service(tr &repositories.TagRepository) &TagService {
	return &TagService{
		tag_repo: tr
	}
}

pub fn (s &TagService) list_tags() ![]models.Tag {
	return s.tag_repo.all_ordered()!
}

pub fn (s &TagService) create_tag(dto models.CreateTagDto) !models.Tag {
	mut tag := models.Tag{
		name: dto.name
		slug: if dto.slug.len > 0 { dto.slug } else { util.generate_slug(dto.name) }
	}
	s.tag_repo.create(mut tag)!
	return tag
}

pub fn (s &TagService) tags_for_post(post_id int) ![]models.Tag {
	return s.tag_repo.find_by_post(post_id)!
}

// ═══════════════════════════════════════════════════════════
// StatsService
// ═══════════════════════════════════════════════════════════

pub struct StatsService {
pub mut:
	user_repo    &repositories.UserRepository = unsafe { nil }
	post_repo    &repositories.PostRepository = unsafe { nil }
	comment_repo &repositories.CommentRepository = unsafe { nil }
}

pub fn new_stats_service(ur &repositories.UserRepository, pr &repositories.PostRepository, cr &repositories.CommentRepository) &StatsService {
	return &StatsService{
		user_repo: ur
		post_repo: pr
		comment_repo: cr
	}
}

pub fn (s &StatsService) blog_stats() !models.BlogStats {
	return models.BlogStats{
		user_count: s.user_repo.count()!
		post_count: s.post_repo.count()!
		published_count: s.post_repo.count_by_status('published')!
		draft_count: s.post_repo.count_by_status('draft')!
		comment_count: s.comment_repo.count()!
		aggregated_at: util.now_unix()
	}
}

// ═══════════════════════════════════════════════════════════
// UploadService
// ═══════════════════════════════════════════════════════════

pub struct UploadService {
pub mut:
	storage_cfg config.StorageConfigBlock
}

pub fn new_upload_service(cfg config.StorageConfigBlock) &UploadService {
	return &UploadService{
		storage_cfg: cfg
	}
}

pub fn (s &UploadService) upload_path(filename string) string {
	return '${s.storage_cfg.base_path}/${filename}'
}

// ═══════════════════════════════════════════════════════════
// Email functions
// ═══════════════════════════════════════════════════════════

pub fn send_welcome_email(m mailer.Mailer, user models.User) ! {
	msg := mailer.Message{
		from: 'noreply@photonblog.dev'
		to: [user.email]
		subject: 'Welcome to PhotonBlog, ${user.nickname}!'
		body: 'Hello ${user.nickname},\n\nWelcome to PhotonBlog! Your account has been created successfully.\n\nBest regards,\nPhotonBlog Team'
	}
	m.send(msg)!
}

pub fn send_comment_notification(m mailer.Mailer, post models.Post, comment models.Comment, user models.User) ! {
	msg := mailer.Message{
		from: 'noreply@photonblog.dev'
		to: [user.email]
		subject: 'New comment on "${post.title}"'
		body: 'Hello ${user.nickname},\n\nA new comment has been posted on your article "${post.title}":\n\n${comment.content}\n\nBest regards,\nPhotonBlog Team'
	}
	m.send(msg)!
}

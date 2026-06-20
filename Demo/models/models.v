module models

import photon.orm as phorm

// ═══════════════════════════════════════════════════════════
// User Entity
// ═══════════════════════════════════════════════════════════

@[table: 'users']
pub struct User {
	phorm.BaseEntity
pub mut:
	username string
	email    string
	password string @[skip]
	nickname string
	avatar   string
	status   int = 1
	role     string = 'USER'
}

pub fn (u &User) table_name() string {
	return 'users'
}

// ═══════════════════════════════════════════════════════════
// Post Entity
// ═══════════════════════════════════════════════════════════

@[table: 'posts']
pub struct Post {
	phorm.BaseEntity
pub mut:
	title       string
	content     string
	summary     string
	author_id   int
	category_id int
	status      string = 'draft'
	views       int
}

pub fn (p &Post) table_name() string {
	return 'posts'
}

// ═══════════════════════════════════════════════════════════
// Comment Entity
// ═══════════════════════════════════════════════════════════

@[table: 'comments']
pub struct Comment {
	phorm.BaseEntity
pub mut:
	post_id   int
	user_id   int
	content   string
	parent_id int
	status    string = 'visible'
}

pub fn (c &Comment) table_name() string {
	return 'comments'
}

// ═══════════════════════════════════════════════════════════
// Category Entity
// ═══════════════════════════════════════════════════════════

@[table: 'categories']
pub struct Category {
	phorm.BaseEntity
pub mut:
	name        string
	slug        string
	description string
}

pub fn (c &Category) table_name() string {
	return 'categories'
}

// ═══════════════════════════════════════════════════════════
// Tag Entity
// ═══════════════════════════════════════════════════════════

@[table: 'tags']
pub struct Tag {
	phorm.BaseEntity
pub mut:
	name string
	slug string
}

pub fn (t &Tag) table_name() string {
	return 'tags'
}

// ═══════════════════════════════════════════════════════════
// PostTag Entity
// ═══════════════════════════════════════════════════════════

@[table: 'post_tags']
pub struct PostTag {
	phorm.BaseEntity
pub mut:
	post_id int
	tag_id  int
}

pub fn (pt &PostTag) table_name() string {
	return 'post_tags'
}

// ═══════════════════════════════════════════════════════════
// DTOs
// ═══════════════════════════════════════════════════════════

pub struct CreateUserDto {
pub:
	username string @[required; validate: 'required|min_len:3|max_len:32|alpha_num']
	email    string @[required; validate: 'required|email']
	password string @[required; validate: 'required|min_len:6|max_len:128']
	nickname string @[validate: 'max_len:64']
	role     string = 'USER' @[validate: 'in:USER,EDITOR,ADMIN']
	github   string
}

pub struct UpdateUserDto {
pub:
	email    string @[validate: 'email']
	nickname string @[validate: 'max_len:64']
	avatar   string
	status   int    @[validate: 'between:0,2']
	role     string @[validate: 'in:USER,EDITOR,ADMIN']
}

pub struct LoginDto {
pub:
	username string @[required; validate: 'required']
	password string @[required; validate: 'required']
}

pub struct LoginResponseDto {
pub:
	access_token  string
	token_type    string = 'Bearer'
	expires_in    int
	refresh_token string
	user          UserProfileDto
}

pub struct UserProfileDto {
pub:
	id       int
	username string
	nickname string
	avatar   string
	email    string
	role     string
	status   int
	created  string
}

pub struct UserListQueryDto {
pub:
	page      int    = 1
	page_size int    = 20
	keyword   string
	status    int
	role      string
}

pub mut struct CreatePostDto {
pub:
	title       string @[required; validate: 'required|min_len:1|max_len:255']
	content     string @[required; validate: 'required']
	summary     string @[validate: 'max_len:500']
	author_id   int
	category_id int
	status      string = 'draft' @[validate: 'in:draft,published,archived']
}

pub struct UpdatePostDto {
pub:
	title       string @[validate: 'max_len:255']
	content     string
	summary     string @[validate: 'max_len:500']
	category_id int
	status      string @[validate: 'in:draft,published,archived']
}

pub struct PostListQueryDto {
pub:
	page       int    = 1
	page_size  int    = 20
	category   string
	tag        string
	keyword    string
	status     string = 'published' @[validate: 'in:all,published,draft,archived']
	sort       string = 'created_at_desc' @[validate: 'in:created_at_desc,created_at_asc,views_desc']
}

pub mut struct CreateCommentDto {
pub:
	post_id   int
	user_id   int
	content   string @[required; validate: 'required|min_len:1|max_len:2000']
	parent_id int
}

pub struct CommentListQueryDto {
pub:
	post_id   int
	page      int = 1
	page_size int = 20
}

pub struct CreateCategoryDto {
pub:
	name        string @[required; validate: 'required|min_len:1|max_len:100']
	slug        string @[validate: 'max_len:128']
	description string @[validate: 'max_len:500']
}

pub struct CreateTagDto {
pub:
	name string @[required; validate: 'required|min_len:1|max_len:50']
	slug string @[validate: 'max_len:128']
}

// ═══════════════════════════════════════════════════════════
// Health & Stats
// ═══════════════════════════════════════════════════════════

pub struct HealthStatusDto {
pub:
	status    string = 'UP'
	version   string
	uptime_ms i64
	timestamp i64
}

pub struct ServerStatsDto {
pub:
	requests      int
	uptime_ms     i64
	active_users  int
	post_count    int
	comment_count int
	cache_hits    int
	cache_misses  int
}

pub struct BlogStats {
pub:
	user_count      int
	post_count      int
	published_count int
	draft_count     int
	comment_count   int
	aggregated_at   i64
}

pub struct GithubUser {
pub:
	login      string
	avatar_url string
	html_url   string
	name       string
}

// ═══════════════════════════════════════════════════════════
// Filter types
// ═══════════════════════════════════════════════════════════

pub struct PostFilter {
pub:
	keyword     string
	status      string
	category_id int
	tag_id      int
}

pub struct UserFilter {
pub:
	keyword string
	status  int
	role    string
}

pub struct CommentFilter {
pub:
	post_id int
	status  string
}

pub enum SortDirection {
	asc
	desc
}

pub struct SortSpec {
pub:
	field     string
	direction SortDirection
}

pub fn parse_sort_spec(sort string) SortSpec {
	parts := sort.split('_')
	if parts.len < 2 {
		return SortSpec{field: 'id', direction: .desc}
	}
	dir := parts[parts.len - 1]
	field := parts[0..parts.len - 1].join('_')
	return SortSpec{
		field:     field
		direction: if dir == 'asc' { .asc } else { .desc }
	}
}

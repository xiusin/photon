module main

// models.v — PhotonBlog 实体模型与 DTO
//
// 分层结构：Entity（持久化）→ DTO（传输）
// 所有实体嵌入 photon.orm.BaseEntity，获得 id/created_at/updated_at/version
// 字段及 touch() 自动时间戳管理。
//
// V ORM 注意事项：
//   - 每个实体使用 @[table: '...'] 属性声明对应的数据库表名
//   - 跨模块嵌入 phorm.BaseEntity 后，V ORM 的 sql where 子句无法直接
//     引用嵌入字段（如 id），因此仓储层使用原生 SQL 进行 id 相关查询

import photon.orm as phorm

// ═══════════════════════════════════════════════════════════
// User Entity — 用户实体
// ═══════════════════════════════════════════════════════════

@[table: 'users']
pub struct User {
	phorm.BaseEntity
pub mut:
	username string
	email    string
	password string // bcrypt hash
	nickname string
	avatar   string
	status   int = 1 // 1=active, 0=disabled, -1=deleted
	role     string = 'USER' // USER | EDITOR | ADMIN
}

pub fn (u &User) table_name() string {
	return 'users'
}

// ═══════════════════════════════════════════════════════════
// Post Entity — 文章实体
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
	status      string = 'draft' // draft | published | archived
	views       int = 0
}

pub fn (p &Post) table_name() string {
	return 'posts'
}

// ═══════════════════════════════════════════════════════════
// Comment Entity — 评论实体
// ═══════════════════════════════════════════════════════════

@[table: 'comments']
pub struct Comment {
	phorm.BaseEntity
pub mut:
	post_id   int
	user_id   int
	content   string
	parent_id int = 0 // 0 = top-level comment
	status    string = 'visible' // visible | hidden | deleted
}

pub fn (c &Comment) table_name() string {
	return 'comments'
}

// ═══════════════════════════════════════════════════════════
// Category Entity — 分类实体
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
// Tag Entity — 标签实体
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
// PostTag Entity — 文章-标签关联表
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
// DTO — 数据传输对象
// ═══════════════════════════════════════════════════════════

// CreateUserDto — 创建用户请求
pub struct CreateUserDto {
pub:
	username string @[required]
	email    string @[required]
	password string @[required]
	nickname string
	role     string = 'USER'
	github   string // 可选：GitHub 用户名，提供后自动获取头像 URL
}

// UpdateUserDto — 更新用户请求
pub struct UpdateUserDto {
pub:
	email    string
	nickname string
	avatar   string
	status   int
	role     string
}

// LoginDto — 登录请求
pub struct LoginDto {
pub:
	username string @[required]
	password string @[required]
}

// LoginResponseDto — 登录响应
pub struct LoginResponseDto {
pub:
	access_token  string
	token_type    string = 'Bearer'
	expires_in    int
	refresh_token string
	user          UserProfileDto
}

// UserProfileDto — 用户公开信息
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

// UserListQueryDto — 用户列表查询参数
pub struct UserListQueryDto {
pub:
	page      int    = 1
	page_size int    = 20
	keyword   string
	status    int
	role      string
}

// CreatePostDto — 创建文章请求
pub struct CreatePostDto {
pub:
	title       string @[required]
	content     string @[required]
	summary     string
	author_id   int
	category_id int
	status      string = 'draft'
}

// UpdatePostDto — 更新文章请求
pub struct UpdatePostDto {
pub:
	title       string
	content     string
	summary     string
	category_id int
	status      string
}

// PostListQueryDto — 文章列表查询参数
pub struct PostListQueryDto {
pub:
	page       int    = 1
	page_size  int    = 20
	category   string
	tag        string
	keyword    string
	status     string = 'published'
	sort       string = 'created_at_desc'
}

// CreateCommentDto — 创建评论请求
pub struct CreateCommentDto {
pub:
	post_id   int
	user_id   int
	content   string @[required]
	parent_id int
}

// CommentListQueryDto — 评论列表查询参数
pub struct CommentListQueryDto {
pub:
	post_id   int
	page      int = 1
	page_size int = 20
}

// CreateCategoryDto — 创建分类请求
pub struct CreateCategoryDto {
pub:
	name        string @[required]
	slug        string
	description string
}

// CreateTagDto — 创建标签请求
pub struct CreateTagDto {
pub:
	name string @[required]
	slug string
}

// ═══════════════════════════════════════════════════════════
// API 统一响应封装
// ═══════════════════════════════════════════════════════════

// ApiResponseDto — 统一 API 响应格式
pub struct ApiResponseDto {
pub:
	success   bool   = true
	code      int    = 200
	message   string = 'OK'
	data      string
	timestamp i64
}

// success_response 创建成功响应
pub fn success_response(data string) ApiResponseDto {
	return ApiResponseDto{
		success:   true
		code:      200
		message:   'OK'
		data:      data
		timestamp: 0
	}
}

// error_response 创建错误响应
pub fn error_response(code int, message string) ApiResponseDto {
	return ApiResponseDto{
		success:   false
		code:      code
		message:   message
		data:      ''
		timestamp: 0
	}
}

// ═══════════════════════════════════════════════════════════
// Health & Stats 模型
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
	requests     int
	uptime_ms    i64
	active_users int
	post_count   int
	comment_count int
	cache_hits   int
	cache_misses int
}

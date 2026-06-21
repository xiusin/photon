module models

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
	password string @[skip] // bcrypt hash — 不序列化到 JSON（SubTask 10.7）
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
//
// 验证规则使用 @[validate: '...'] 注解，由 web.validate_body[T] 在运行时校验。
// 支持的规则：required|min:N|max:N|min_len:N|max_len:N|email|url|alpha|alpha_num|
//             numeric|in:A,B,C|not_in:A,B,C|regex:PATTERN|between:MIN,MAX|integer|boolean
// ═══════════════════════════════════════════════════════════

// CreateUserDto — 创建用户请求
pub struct CreateUserDto {
pub:
	username string @[required; validate: 'required|min_len:3|max_len:32|alpha_num']
	email    string @[required; validate: 'required|email']
	password string @[required; validate: 'required|min_len:6|max_len:128']
	nickname string @[validate: 'max_len:64']
	role     string = 'USER' @[validate: 'in:USER,EDITOR,ADMIN']
	github   string // 可选：GitHub 用户名，提供后自动获取头像 URL
}

// UpdateUserDto — 更新用户请求
pub struct UpdateUserDto {
pub:
	email    string @[validate: 'email']
	nickname string @[validate: 'max_len:64']
	avatar   string
	status   int    @[validate: 'between:0,2']
	role     string @[validate: 'in:USER,EDITOR,ADMIN']
}

// LoginDto — 登录请求
pub struct LoginDto {
pub:
	username string @[required; validate: 'required']
	password string @[required; validate: 'required']
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
// 注：author_id 由控制器从 JWT 注入，不参与客户端校验
pub struct CreatePostDto {
pub mut:
	title       string @[required; validate: 'required|min_len:1|max_len:255']
	content     string @[required; validate: 'required']
	summary     string @[validate: 'max_len:500']
	author_id   int
	category_id int
	status      string = 'draft' @[validate: 'in:draft,published,archived']
}

// UpdatePostDto — 更新文章请求
pub struct UpdatePostDto {
pub:
	title       string @[validate: 'max_len:255']
	content     string
	summary     string @[validate: 'max_len:500']
	category_id int
	status      string @[validate: 'in:draft,published,archived']
}

// PostListQueryDto — 文章列表查询参数
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

// CreateCommentDto — 创建评论请求
// 注：post_id 与 user_id 由控制器注入，不参与客户端校验
pub struct CreateCommentDto {
pub mut:
	post_id   int
	user_id   int
	content   string @[required; validate: 'required|min_len:1|max_len:2000']
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
	name        string @[required; validate: 'required|min_len:1|max_len:100']
	slug        string @[validate: 'max_len:128']
	description string @[validate: 'max_len:500']
}

// CreateTagDto — 创建标签请求
pub struct CreateTagDto {
pub:
	name string @[required; validate: 'required|min_len:1|max_len:50']
	slug string @[validate: 'max_len:128']
}

// ═══════════════════════════════════════════════════════════
// API 统一响应封装
// ═══════════════════════════════════════════════════════════
// 注：统一响应已迁移至 photon.web.Result（web/result.v）
// 使用 web.success() / web.fail() / web.page() 等函数构建响应
// 通过 Context.send_result() 发送（见 app/Http/Kernel.v）

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

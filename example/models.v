module main

// models.v — 数据模型 & DTO（Data Transfer Object）
//
// 分层结构：Entity（持久化）→ DTO（传输）→ VO（展示）
// 遵循"显式优于隐式"原则，每个模型职责清晰。

import orm

// ═══════════════════════════════════════════════════════════
// User Entity — 用户实体（ORM 映射模型）
// ═══════════════════════════════════════════════════════════

pub struct User {
	orm.BaseEntity
pub mut:
	username string
	email    string
	password string // bcrypt hash
	nickname string
	avatar   string
	status   int = 1 // 1=active, 0=disabled, -1=deleted
	role     string = 'USER' // USER | MODERATOR | ADMIN
}

// ═══════════════════════════════════════════════════════════
// User DTO — 用户数据传输对象
// ═══════════════════════════════════════════════════════════

// CreateUserRequest — 创建用户请求
pub struct CreateUserRequest {
	username string @[required]
	email    string @[required]
	password string @[required]
	nickname string
}

// UpdateUserRequest — 更新用户请求
pub struct UpdateUserRequest {
	email    string
	nickname string
	avatar   string
}

// LoginRequest — 登录请求
pub struct LoginRequest {
	username string @[required]
	password string @[required]
}

// LoginResponse — 登录响应（JWT token）
pub struct LoginResponse {
	access_token  string
	token_type    string = 'Bearer'
	expires_in    int
	refresh_token string
	user          UserProfile
}

// UserProfile — 用户公开信息（VO）
pub struct UserProfile {
	id       int
	username string
	nickname string
	avatar   string
	email    string
	role     string
	status   int
	created  string
}

// UserListQuery — 用户列表查询参数
pub struct UserListQuery {
	page     int    = 1
	page_size int   = 20
	keyword  string
	status   int
	role     string
}

// ═══════════════════════════════════════════════════════════
// API 统一响应封装
// ═══════════════════════════════════════════════════════════

// ApiResponse — 统一 API 响应格式
pub struct ApiResponse {
pub:
	code    int         = 200
	message string      = 'OK'
	data    map[string]string
}

// success 创建成功响应
pub fn success(data map[string]string) ApiResponse {
	return ApiResponse{
		code: 200
		message: 'OK'
		data: data
	}
}

// error_ 创建错误响应（下划线后缀避免与 V 关键字冲突）
pub fn error_(code int, message string) ApiResponse {
	return ApiResponse{
		code: code
		message: message
		data: map[string]string{}
	}
}

// ═══════════════════════════════════════════════════════════
// Health & Stats 模型
// ═══════════════════════════════════════════════════════════

pub struct HealthStatus {
	status    string = 'UP'
	version   string
	uptime_ms i64
	timestamp i64
}

pub struct ServerStats {
	requests    int
	uptime_ms   i64
	active_users int
	cache_hits  int
	cache_misses int
}

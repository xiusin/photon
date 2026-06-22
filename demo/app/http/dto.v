module http

// dto.v — 共享 DTO 结构体
//
// 集中定义所有控制器共用的数据传输对象（DTO），
// 避免在多个控制器文件中重复定义。
// 从 controller_dto.v 迁移至 app/http/ 目录（module http），
// 控制器通过 http.AppInfoDto 等方式引用。

// ═══════════════════════════════════════════════════════════
// 系统相关 DTO
// ═══════════════════════════════════════════════════════════

// AppInfoDto 首页应用信息
pub struct AppInfoDto {
pub:
	app       string
	version   string
	profile   string
	uptime_ms i64
	requests  int
	endpoints []string
}

// HealthDto 健康检查响应
pub struct HealthDto {
pub:
	status    string
	version   string
	uptime_ms i64
	timestamp i64
}

// BasicStatsDto 基础统计（统计服务失败时的回退）
pub struct BasicStatsDto {
pub:
	requests      int
	uptime_ms     i64
	user_count    int
	post_count    int
	comment_count int
	timestamp     i64
}

// BlogStatsDto 博客统计
pub struct BlogStatsDto {
pub:
	requests        int
	uptime_ms       i64
	user_count      int
	post_count      int
	published_count int
	draft_count     int
	comment_count   int
	aggregated_at   i64
}

// ═══════════════════════════════════════════════════════════
// 认证相关 DTO
// ═══════════════════════════════════════════════════════════

// RefreshTokenDto 刷新令牌请求
pub struct RefreshTokenDto {
pub:
	refresh_token string @[required; validate: 'required']
}

// TokenResponseDto 令牌响应
pub struct TokenResponseDto {
pub:
	access_token  string
	refresh_token string
	token_type    string = 'Bearer'
	expires_in    int    = 3600
}

// ═══════════════════════════════════════════════════════════
// 通用 DTO
// ═══════════════════════════════════════════════════════════

// MessageDto 通用消息响应
pub struct MessageDto {
pub:
	message string
}

// ═══════════════════════════════════════════════════════════
// 上传相关 DTO
// ═══════════════════════════════════════════════════════════

// UploadResponseDto 文件上传响应
pub struct UploadResponseDto {
pub:
	original_name string
	stored_name   string
	path          string
	size          int
	extension     string
	mime_type     string
	hash          string
	url           string
}
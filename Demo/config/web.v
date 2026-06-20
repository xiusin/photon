module config

// config/web.v — Web 配置
//
// 定义 CORS 跨域、限流等 Web 层配置。

// WebConfig Web 层配置
pub struct WebConfig {
pub:
	cors_allowed_origins   string
	cors_allowed_methods   string
	cors_allowed_headers   string
	rate_limit_max_requests int
	rate_limit_window_secs  int
}

// default_web_config 返回 Web 默认配置
pub fn default_web_config() WebConfig {
	return WebConfig{
		cors_allowed_origins: env_or('WEB_CORS_ALLOWED_ORIGINS', '*')
		cors_allowed_methods: env_or('WEB_CORS_ALLOWED_METHODS', 'GET,POST,PUT,DELETE,OPTIONS')
		cors_allowed_headers: env_or('WEB_CORS_ALLOWED_HEADERS', 'Content-Type,Authorization,X-Requested-With')
		rate_limit_max_requests: env_or_int('WEB_RATE_LIMIT_MAX_REQUESTS', 60)
		rate_limit_window_secs: env_or_int('WEB_RATE_LIMIT_WINDOW_SECS', 60)
	}
}

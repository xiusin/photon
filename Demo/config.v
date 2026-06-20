module main

// config.v — PhotonBlog 配置系统入口
//
// 基于 Photon config 模块 + .env 文件实现多源配置加载：
//   1. .env 文件          — 基础环境变量（由 main.v 通过 load_env_file 加载）
//   2. .env.<profile>     — profile 特定覆盖（由 main.v 加载）
//   3. config/*.v         — 按关注点拆分的默认配置结构
//   4. os.getenv()        — 系统环境变量（最高优先级）
//
// 支持 dev / prod / test 三套 profile，所有配置项均有默认值。
// 生产环境强制校验 JWT 密钥。

import os

// ═══════════════════════════════════════════════════════════
// 配置根结构
// ═══════════════════════════════════════════════════════════

// AppConfig 应用配置根结构
pub struct AppConfig {
pub:
	app      AppConfigBlock
	server   ServerConfig
	database DatabaseConfig
	jwt      JwtConfigBlock
	cache    CacheConfigBlock
	mail     MailConfigBlock
	storage  StorageConfigBlock
	logging  LoggingConfig
	web      WebConfig
	auth     AuthConfig
	profile  string
	debug    bool
	log_level string
}

// ServerConfig HTTP 服务器配置
pub struct ServerConfig {
pub:
	host string
	port int
}

// ═══════════════════════════════════════════════════════════
// 环境变量辅助函数
// ═══════════════════════════════════════════════════════════

// env_or 读取环境变量，不存在时返回默认值
pub fn env_or(key string, default_val string) string {
	val := os.getenv(key)
	if val == '' {
		return default_val
	}
	return val
}

// env_or_int 读取环境变量为 int，不存在或无效时返回默认值
pub fn env_or_int(key string, default_val int) int {
	val := os.getenv(key)
	if val == '' {
		return default_val
	}
	return val.int()
}

// env_or_bool 读取环境变量为 bool，不存在时返回默认值
pub fn env_or_bool(key string, default_val bool) bool {
	val := os.getenv(key)
	if val == '' {
		return default_val
	}
	return val in ['true', '1', 'yes', 'on', 'True', 'TRUE']
}

// ═══════════════════════════════════════════════════════════
// 服务器配置
// ═══════════════════════════════════════════════════════════

// default_server_config 返回指定 profile 的服务器默认配置
pub fn default_server_config(profile string) ServerConfig {
	mut port := env_or_int('APP_SERVER_PORT', 8080)
	mut host := env_or('APP_SERVER_HOST', '0.0.0.0')

	match profile {
		'prod' {
			port = env_or_int('APP_SERVER_PORT', 80)
		}
		'test' {
			port = env_or_int('APP_SERVER_PORT', 0)
			host = env_or('APP_SERVER_HOST', '127.0.0.1')
		}
		else {
			port = env_or_int('APP_SERVER_PORT', 8080)
		}
	}

	return ServerConfig{
		host: host
		port: port
	}
}

// ═══════════════════════════════════════════════════════════
// 配置加载入口
// ═══════════════════════════════════════════════════════════

// load_config 加载应用配置
//
// 加载顺序（后者覆盖前者）：
//   1. config/*.v 的 default_*() 函数 — 默认值（已读取 os.getenv）
//   2. profile 特定覆盖
//
// .env 文件应由 main.v 在调用此函数前通过 load_env_file() 加载到环境变量。
//
// profile 取值：'dev' | 'prod' | 'test'
pub fn load_config(profile string) !AppConfig {
	// 从 config/*.v 构建各配置块（内部已读取环境变量）
	app_block := default_app_config(profile)
	server := default_server_config(profile)
	database := default_database_config(profile)
	jwt := default_jwt_config(profile)
	cache := default_cache_config()
	mail := default_mail_config(profile)
	storage := default_storage_config()
	logging := default_logging_config(profile)
	web := default_web_config()
	auth := default_auth_config()

	// debug 与 log_level 由 profile 决定（兼容旧字段）
	mut debug := env_or_bool('APP_DEBUG', true)
	mut log_level := logging.level

	match profile {
		'prod' {
			debug = env_or_bool('APP_DEBUG', false)
		}
		'test' {
			debug = env_or_bool('APP_DEBUG', true)
		}
		else {
			debug = env_or_bool('APP_DEBUG', true)
		}
	}

	cfg := AppConfig{
		profile: profile
		debug: debug
		log_level: log_level
		app: app_block
		server: server
		database: database
		jwt: jwt
		cache: cache
		mail: mail
		storage: storage
		logging: logging
		web: web
		auth: auth
	}

	// 生产环境校验 JWT 密钥
	validate_jwt_secret(profile, cfg.jwt.secret)!

	return cfg
}

// load_config_with_env 加载配置并自动加载 .env 文件
//
// 此函数会先加载 .env 和 .env.<profile> 文件到环境变量，再调用 load_config。
// 适用于非 main.v 入口（如测试）需要自动加载 .env 的场景。
pub fn load_config_with_env(profile string) !AppConfig {
	// 加载基础 .env
	load_env_file('.env')

	// 加载 profile 特定 .env
	match profile {
		'dev' {
			load_env_file('.env.dev')
		}
		'prod' {
			load_env_file('.env.prod')
		}
		'test' {
			load_env_file('.env.testing')
		}
		else {}
	}

	return load_config(profile)!
}

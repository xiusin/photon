module config

import util

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

// load_config 加载应用配置
pub fn load_config(profile string) !AppConfig {
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

	validate_jwt_secret(profile, cfg.jwt.secret)!

	return cfg
}

// load_config_with_env 加载配置并自动加载 .env 文件
pub fn load_config_with_env(profile string) !AppConfig {
	util.load_env_file('.env')

	match profile {
		'dev' {
			util.load_env_file('.env.dev')
		}
		'prod' {
			util.load_env_file('.env.prod')
		}
		'test' {
			util.load_env_file('.env.testing')
		}
		else {}
	}

	return load_config(profile)!
}

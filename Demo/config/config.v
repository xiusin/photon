module config

// config/config.v — 应用配置聚合
//
// AppConfig 是所有配置块的聚合结构，由 load_config() 根据 profile 装配。
// 各配置块定义在 config/ 目录下的独立文件中（app/database/cache/jwt/logging/mail/storage/web/server/auth）。
//
// 用法：
//   cfg := load_config('dev')!
//   println(cfg.app.name)
//   println(cfg.database.path)

// AppConfig 应用配置聚合（所有配置块的统一入口）
pub struct AppConfig {
pub:
	profile  string
	app      AppConfigBlock
	debug    bool
	log_level string
	database DatabaseConfig
	server   ServerConfig
	cache    CacheConfigBlock
	mail     MailConfigBlock
	jwt      JwtConfigBlock
	storage  StorageConfigBlock
	web      WebConfig
	log      LoggingConfig
	auth     AuthConfig
}

// load_config 根据 profile 加载完整应用配置
//
// 装配流程：
//   1. 读取各配置块默认值（从环境变量覆盖）
//   2. 根据 profile 调整特定配置
//   3. 生产环境校验 JWT 密钥
//   4. 返回聚合的 AppConfig
pub fn load_config(profile string) !AppConfig {
	app_cfg := default_app_config(profile)
	db_cfg := default_database_config(profile)
	cache_cfg := default_cache_config()
	jwt_cfg := default_jwt_config(profile)
	logging_cfg := default_logging_config(profile)
	mail_cfg := default_mail_config(profile)
	storage_cfg := default_storage_config()
	web_cfg := default_web_config()
	server_cfg := default_server_config(profile)
	auth_cfg := default_auth_config()

	// 生产环境校验 JWT 密钥
	validate_jwt_secret(profile, jwt_cfg.secret)!

	// debug 与 log_level 从 logging 配置派生
	debug := profile != 'prod'

	return AppConfig{
		profile:   profile
		app:       app_cfg
		debug:     debug
		log_level: logging_cfg.level
		database:  db_cfg
		server:    server_cfg
		cache:     cache_cfg
		mail:      mail_cfg
		jwt:       jwt_cfg
		storage:   storage_cfg
		web:       web_cfg
		log:       logging_cfg
		auth:      auth_cfg
	}
}

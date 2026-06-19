module main

// config.v — PhotonBlog 配置系统
//
// 基于 Photon config 模块实现多源配置加载：
//   1. MapConfigSource  — 内置默认值 + profile 特定覆盖
//   2. EnvConfigSource  — APP_* 前缀环境变量
//   3. 显式环境变量映射 — 将 APP_* 下划线键转换为点号键覆盖
//
// 支持 dev / prod / test 三套 profile，所有配置项均有默认值。

import config
import os

// ═══════════════════════════════════════════════════════════
// 配置结构定义
// ═══════════════════════════════════════════════════════════

// AppConfig 应用配置根结构
pub struct AppConfig {
pub:
	app       AppConfigBlock
	server    ServerConfig
	database  DatabaseConfig
	jwt       JwtConfigBlock
	cache     CacheConfigBlock
	mail      MailConfigBlock
	storage   StorageConfigBlock
	profile   string
	debug     bool
	log_level string
}

// AppConfigBlock 应用元信息配置块
pub struct AppConfigBlock {
pub:
	name    string
	version string
	env     string
}

// ServerConfig HTTP 服务器配置
pub struct ServerConfig {
pub:
	host string
	port int
}

// DatabaseConfig 数据库配置
pub struct DatabaseConfig {
pub:
	driver    string
	path      string
	max_conns int
}

// JwtConfigBlock JWT 认证配置块
pub struct JwtConfigBlock {
pub:
	secret             string
	expiration_minutes int
	refresh_hours      int
	issuer             string
}

// CacheConfigBlock 缓存配置块
pub struct CacheConfigBlock {
pub:
	driver string
	ttl    int
	prefix string
}

// MailConfigBlock 邮件配置块
pub struct MailConfigBlock {
pub:
	driver    string
	host      string
	port      int
	username  string
	password  string
	from      string
	from_name string
}

// StorageConfigBlock 文件存储配置块
pub struct StorageConfigBlock {
pub:
	driver      string
	base_path   string
	max_size    int
	allowed_ext []string
}

// ═══════════════════════════════════════════════════════════
// 默认配置生成
// ═══════════════════════════════════════════════════════════

// default_config_for 返回指定 profile 的默认配置 map（点号键）
fn default_config_for(profile string) map[string]string {
	mut data := {
		// App
		'app.name':    'PhotonBlog'
		'app.version': '0.1.0'
		'app.env':     profile
		'app.debug':   'true'
		// Server
		'server.host': '0.0.0.0'
		'server.port': '8080'
		// Database
		'database.driver':    'sqlite'
		'database.path':      ':memory:'
		'database.max_conns': '10'
		// JWT
		'jwt.secret':             'photonblog-default-jwt-secret-change-in-production-32chars'
		'jwt.expiration_minutes': '60'
		'jwt.refresh_hours':      '24'
		'jwt.issuer':             'PhotonBlog'
		// Cache
		'cache.driver': 'memory'
		'cache.ttl':    '3600'
		'cache.prefix': 'photonblog:'
		// Mail
		'mail.driver':    'log'
		'mail.host':      'localhost'
		'mail.port':      '587'
		'mail.username':  ''
		'mail.password':  ''
		'mail.from':      'noreply@photonblog.dev'
		'mail.from_name': 'PhotonBlog'
		// Storage
		'storage.driver':      'local'
		'storage.base_path':   './storage/uploads'
		'storage.max_size':    '5242880'
		'storage.allowed_ext': 'jpg,jpeg,png,gif,webp'
		// Log
		'log.level': 'debug'
	}

	// Profile 特定覆盖
	match profile {
		'dev' {
			data['app.debug'] = 'true'
			data['log.level'] = 'debug'
			data['database.path'] = ':memory:'
			data['server.port'] = '8080'
			data['mail.driver'] = 'log'
		}
		'prod' {
			data['app.debug'] = 'false'
			data['log.level'] = 'info'
			data['database.path'] = './photonblog.db'
			data['server.port'] = '80'
			data['mail.driver'] = 'smtp'
		}
		'test' {
			data['app.debug'] = 'true'
			data['log.level'] = 'error'
			data['database.path'] = ':memory:'
			data['server.port'] = '0'
			data['mail.driver'] = 'log'
		}
		else {
			// 未知 profile 回退到 dev 行为
			data['app.debug'] = 'true'
			data['log.level'] = 'debug'
			data['database.path'] = ':memory:'
			data['server.port'] = '8080'
		}
	}

	return data
}

// ═══════════════════════════════════════════════════════════
// 环境变量覆盖
// ═══════════════════════════════════════════════════════════

// env_overrides 读取 APP_* 环境变量并映射为点号配置键
//
// EnvConfigSource 会将 APP_SERVER_PORT 转换为 server_port（下划线小写），
// 而 MapConfigSource 使用 server.port（点号）。此函数建立显式映射，
// 确保 APP_* 环境变量能正确覆盖点号键的配置值。
fn env_overrides() map[string]string {
	mut result := map[string]string{}

	mapping := {
		'APP_NAME':                   'app.name'
		'APP_VERSION':                'app.version'
		'APP_DEBUG':                  'app.debug'
		'APP_LOG_LEVEL':              'log.level'
		'APP_SERVER_HOST':            'server.host'
		'APP_SERVER_PORT':            'server.port'
		'APP_DATABASE_DRIVER':        'database.driver'
		'APP_DATABASE_PATH':          'database.path'
		'APP_DATABASE_MAX_CONNS':     'database.max_conns'
		'APP_JWT_SECRET':             'jwt.secret'
		'APP_JWT_EXPIRATION_MINUTES': 'jwt.expiration_minutes'
		'APP_JWT_REFRESH_HOURS':      'jwt.refresh_hours'
		'APP_JWT_ISSUER':             'jwt.issuer'
		'APP_CACHE_DRIVER':           'cache.driver'
		'APP_CACHE_TTL':              'cache.ttl'
		'APP_CACHE_PREFIX':           'cache.prefix'
		'APP_MAIL_DRIVER':            'mail.driver'
		'APP_MAIL_HOST':              'mail.host'
		'APP_MAIL_PORT':              'mail.port'
		'APP_MAIL_USERNAME':          'mail.username'
		'APP_MAIL_PASSWORD':          'mail.password'
		'APP_MAIL_FROM':              'mail.from'
		'APP_MAIL_FROM_NAME':         'mail.from_name'
		'APP_STORAGE_DRIVER':         'storage.driver'
		'APP_STORAGE_BASE_PATH':      'storage.base_path'
		'APP_STORAGE_MAX_SIZE':       'storage.max_size'
		'APP_STORAGE_ALLOWED_EXT':    'storage.allowed_ext'
	}

	for env_key, cfg_key in mapping {
		val := os.getenv(env_key)
		if val != '' {
			result[cfg_key] = val
		}
	}

	return result
}

// ═══════════════════════════════════════════════════════════
// 配置加载入口
// ═══════════════════════════════════════════════════════════

// load_config 加载应用配置
//
// 加载顺序（后者覆盖前者）：
//   1. MapConfigSource — 默认值 + profile 特定值
//   2. EnvConfigSource — APP_* 前缀环境变量（下划线键）
//   3. 显式环境变量映射 — APP_* 转换为点号键覆盖
//
// profile 取值：'dev' | 'prod' | 'test'
pub fn load_config(profile string) !AppConfig {
	mut cfg := config.new()
	cfg.set_profile([profile])

	// 1. MapConfigSource — 默认值 + profile 覆盖
	cfg.add_source(config.MapConfigSource{
		data: default_config_for(profile)
	})

	// 2. EnvConfigSource — APP_* 前缀环境变量
	cfg.add_source(config.EnvConfigSource{
		prefix: 'APP_'
	})

	// 加载所有配置源
	cfg.load() or {
		return error('config load failed: ${err}')
	}

	// 3. 显式环境变量覆盖（APP_* → 点号键）
	for key, val in env_overrides() {
		cfg.set(key, val)
	}

	// 解析 storage.allowed_ext 为字符串数组
	allowed_ext_str := cfg.get_or('storage.allowed_ext', 'jpg,jpeg,png,gif,webp')
	allowed_ext := allowed_ext_str.split(',').map(it.trim_space()).filter(it.len > 0)

	// 构建 AppConfig 结构体
	return AppConfig{
		profile: profile
		debug: cfg.get_bool_or('app.debug', false)
		log_level: cfg.get_or('log.level', 'debug')
		app: AppConfigBlock{
			name: cfg.get_or('app.name', 'PhotonBlog')
			version: cfg.get_or('app.version', '0.1.0')
			env: cfg.get_or('app.env', profile)
		}
		server: ServerConfig{
			host: cfg.get_or('server.host', '0.0.0.0')
			port: cfg.get_int_or('server.port', 8080)
		}
		database: DatabaseConfig{
			driver: cfg.get_or('database.driver', 'sqlite')
			path: cfg.get_or('database.path', ':memory:')
			max_conns: cfg.get_int_or('database.max_conns', 10)
		}
		jwt: JwtConfigBlock{
			secret: cfg.get_or('jwt.secret', 'photonblog-default-jwt-secret-change-in-production-32chars')
			expiration_minutes: cfg.get_int_or('jwt.expiration_minutes', 60)
			refresh_hours: cfg.get_int_or('jwt.refresh_hours', 24)
			issuer: cfg.get_or('jwt.issuer', 'PhotonBlog')
		}
		cache: CacheConfigBlock{
			driver: cfg.get_or('cache.driver', 'memory')
			ttl: cfg.get_int_or('cache.ttl', 3600)
			prefix: cfg.get_or('cache.prefix', 'photonblog:')
		}
		mail: MailConfigBlock{
			driver: cfg.get_or('mail.driver', 'log')
			host: cfg.get_or('mail.host', 'localhost')
			port: cfg.get_int_or('mail.port', 587)
			username: cfg.get_or('mail.username', '')
			password: cfg.get_or('mail.password', '')
			from: cfg.get_or('mail.from', 'noreply@photonblog.dev')
			from_name: cfg.get_or('mail.from_name', 'PhotonBlog')
		}
		storage: StorageConfigBlock{
			driver: cfg.get_or('storage.driver', 'local')
			base_path: cfg.get_or('storage.base_path', './storage/uploads')
			max_size: cfg.get_int_or('storage.max_size', 5242880)
			allowed_ext: allowed_ext
		}
	}
}

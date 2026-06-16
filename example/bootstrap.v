module main

// bootstrap.v — 应用初始化（Spring Boot 式 Bootstrap）
//
// 职责：服务注册、配置加载、模块初始化、依赖装配。
// 相当于 Spring Boot 的 @SpringBootApplication 启动逻辑。

import config
import logger
import cache
import apidoc

// ═══════════════════════════════════════════════════════════
// 应用配置结构
// ═══════════════════════════════════════════════════════════

pub struct AppConfig {
pub:
	app_name    string
	app_version string
	server_port int
	jwt_secret  string
	jwt_expiry  int
	cache_ttl   int
	profile     string
	debug       bool
}

// ═══════════════════════════════════════════════════════════
// Application Bootstrap — 装配所有组件
// ═══════════════════════════════════════════════════════════

pub struct Bootstrap {
pub:
	log_       &logger.Logger
	cfg        &config.Config
	app_cfg    AppConfig
	services   &ServiceRegistry
	middleware  &MiddlewareManager
}

// new_bootstrap 创建并运行 Bootstrap
pub fn new_bootstrap() !&Bootstrap {
	// ── 1. Configuration 配置加载 ──
	mut cfg := config.new()
	cfg.set_profile(['dev'])
	cfg.add_source(config.MapConfigSource{
		data: {
			'app.name':       'PhotonAPI'
			'app.version':    '0.4.0'
			'server.port':    '8080'
			'jwt.secret':     'your-256-bit-secret-key-here-min-32-chars!!'
			'jwt.expiration': '60'
			'cache.ttl':      '3600'
			'app.debug':      'true'
		}
	})
	cfg.load() or {
		return error('config load failed: ${err}')
	}

	// ── 2. Environment 环境检测 ──
	is_prod := cfg.get_or('profile', 'dev') == 'production'

	// ── 3. Logger 日志初始化 ──
	mut log_ := logger.new()
	if is_prod {
		log_.set_level(.info)
		log_.set_colored(false)
	} else {
		log_.set_level(.debug)
		log_.set_colored(true)
	}
	log_.put('app', cfg.get_or('app.name', 'Photon'))
	log_.info('═══ Photon Application Bootstrap ═══')
	log_.info('Profile: ${cfg.get_or('profile', 'dev')}')

	// ── 4. AppConfig 构建 ──
	app_cfg := AppConfig{
		app_name:    cfg.get_or('app.name', 'PhotonAPI')
		app_version: cfg.get_or('app.version', '0.4.0')
		server_port: cfg.get_int_or('server.port', 8080)
		jwt_secret:  cfg.get_or('jwt.secret', 'default-secret-change-me-in-production!!')
		jwt_expiry:  cfg.get_int_or('jwt.expiration', 60)
		cache_ttl:   cfg.get_int_or('cache.ttl', 3600)
		profile:     cfg.get_or('profile', 'dev')
		debug:       cfg.get_or('app.debug', 'true') == 'true'
	}
	log_.info('Config loaded — app=${app_cfg.app_name} v${app_cfg.app_version}')

	// ── 5. Cache 缓存初始化 ──
	mut cache_mgr := cache.new_cache_manager()
	unsafe {
		cache_mgr.register('default', cache.new_memory_cache('default'))
	}
	cache_mgr.set('app:name', app_cfg.app_name, 0)!
	cache_mgr.set('app:version', app_cfg.app_version, 0)!
	log_.info('Cache initialized — memory driver "default"')

	// ── 6. Services 服务注册 ──
	user_svc := new_user_service(log_)
	jwt_config := JWTConfig{
		secret: app_cfg.jwt_secret
		expiration_minutes: app_cfg.jwt_expiry
	}
	auth_svc := new_auth_service(log_, user_svc, jwt_config)
	health_svc := new_health_service()
	cache_svc := new_cache_service(cache_mgr)

	services := &ServiceRegistry{
		user_service: user_svc
		auth_service: auth_svc
		health_service: health_svc
		cache_service: cache_svc
	}
	log_.info('Services registered — UserService, AuthService, HealthService, CacheService')

	// ── 7. Middleware 中间件注册 ──
	mw := new_middleware_manager(log_, auth_svc)
	log_.info('Middleware initialized — RequestLog, CORS, Auth, RateLimit')

	log_.info('Bootstrap complete — ${app_cfg.app_name} v${app_cfg.app_version} ready')
	return &Bootstrap{
		log_: log_
		cfg: cfg
		app_cfg: app_cfg
		services: services
		middleware: mw
	}
}

// print_banner 打印启动横幅
pub fn (b &Bootstrap) print_banner() {
	println('')
	println('╔══════════════════════════════════════════════════════════╗')
	println('║                                                          ║')
	println('║   Photon Framework — Enterprise API Server               ║')
	println('║   ${b.app_cfg.app_name} v${b.app_cfg.app_version}                      ')
	println('║                                                          ║')
	println('╚══════════════════════════════════════════════════════════╝')
	println('')
}

// print_routes 打印所有 API 端点
pub fn (b &Bootstrap) print_routes() {
	println('  Available API Endpoints:')
	println('  ───────────────────────────────────────────────────────────')
	println('  ${'METHOD':-8s} ${'PATH':-40s} ${'AUTH':-12s} ${'DESCRIPTION'}')
	println('  ───────────────────────────────────────────────────────────')
	println('  ${'GET':-8s} ${'/':-40s} ${'-':-12s} API 信息')
	println('  ${'GET':-8s} ${'/health':-40s} ${'-':-12s} 健康检查')
	println('  ${'GET':-8s} ${'/ping':-40s} ${'-':-12s} 连通性测试')
	println('  ${'GET':-8s} ${'/stats':-40s} ${'-':-12s} 服务器统计')
	println('  ${'GET':-8s} ${'/cache':-40s} ${'-':-12s} 缓存演示 (?key=xxx)')
	println('  ${'GET':-8s} ${'/request-info':-40s} ${'-':-12s} 请求信息回显')
	println('')
	println('  ${'POST':-8s} ${'/api/v1/auth/login':-40s} ${'-':-12s} 用户登录')
	println('  ${'POST':-8s} ${'/api/v1/auth/register':-40s} ${'-':-12s} 用户注册')
	println('  ${'GET':-8s}  ${'/api/v1/auth/profile':-40s} ${'JWT':-12s} 获取用户信息')
	println('')
	println('  ${'GET':-8s}  ${'/api/v1/users':-40s} ${'ADMIN':-12s} 用户列表 (分页)')
	println('  ${'GET':-8s}  ${'/api/v1/users/:id':-40s} ${'ADMIN':-12s} 用户详情')
	println('  ${'POST':-8s} ${'/api/v1/users':-40s} ${'ADMIN':-12s} 创建用户')
	println('  ${'PUT':-8s}  ${'/api/v1/users/:id':-40s} ${'ADMIN':-12s} 更新用户')
	println('  ${'DELETE':-8s} ${'/api/v1/users/:id':-40s} ${'ADMIN':-12s} 删除用户')
	println('  ───────────────────────────────────────────────────────────')
}

// init_api_doc 初始化 API 文档自动生成模块
pub fn (b &Bootstrap) init_api_doc() !(&apidoc.ApiDocStore, &apidoc.Collector) {
	b.log_.info('Initializing API Documentation module...')
	store, coll := apidoc.init('data/apidoc')!
	b.log_.info('API Documentation ready — /__docs')
	return store, coll
}

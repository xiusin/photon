module main

// bootstrap.v — 应用初始化（Spring Boot 式 Bootstrap，DI 容器驱动）
//
// 职责：通过 ApplicationContext 注册所有 Bean（配置、日志、缓存、服务、中间件）。
// 相当于 Spring Boot 的 @SpringBootApplication 启动逻辑。
//
// 与旧版手动装配的区别：
//   - 旧版：Bootstrap 结构体持有所有组件引用，手动 new_xxx() 链式装配
//   - 新版：所有组件注册到 ApplicationContext，由容器统一管理生命周期
//           main.v 通过 ctx.resolve_typed[T]() 获取 Bean
import logger
import cache
import orm
import core

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
// bootstrap — 装配所有组件到 ApplicationContext
// ═══════════════════════════════════════════════════════════

// bootstrap 加载配置、初始化各模块，并将所有 Bean 注册到 DI 容器。
// 注册顺序：Environment 属性 → Logger → AppConfig → CacheRegistry →
//           TransactionManager → UserService → AuthService →
//           HealthService → CacheService → MiddlewareManager
//
// 注意：本示例采用显式 register_instance 注册预构建单例（P0 7.1 显式模式）。
// 待框架注解自动扫描（@[component]/@[service]）就绪后，可切换为声明式注册。
pub fn bootstrap(mut ctx core.ApplicationContext) ! {
	// ── 1. Environment 配置属性 ──
	ctx.set_profiles(['dev'])
	ctx.set_property('app.name', 'PhotonAPI')
	ctx.set_property('app.version', '0.4.0')
	ctx.set_property('server.port', '8080')
	ctx.set_property('jwt.secret', 'your-256-bit-secret-key-here-min-32-chars!!')
	ctx.set_property('jwt.expiration', '60')
	ctx.set_property('cache.ttl', '3600')
	ctx.set_property('app.debug', 'true')

	// ── 2. Logger 日志初始化 ──
	mut log_ := logger.new()
	log_.set_level(.debug)
	log_.set_colored(true)
	log_.put('app', 'PhotonAPI')
	log_.info('═══ Photon Application Bootstrap (DI Container) ═══')
	log_.info('Profile: dev')
	ctx.register_instance('Logger', log_)!

	// ── 3. AppConfig 构建（从 Environment 属性绑定） ──
	app_cfg := &AppConfig{
		app_name:    ctx.get_property_or('app.name', 'PhotonAPI')
		app_version: ctx.get_property_or('app.version', '0.4.0')
		server_port: ctx.get_property_or('server.port', '8080').int()
		jwt_secret:  ctx.get_property_or('jwt.secret', 'default-secret-change-me-in-production!!')
		jwt_expiry:  ctx.get_property_or('jwt.expiration', '60').int()
		cache_ttl:   ctx.get_property_or('cache.ttl', '3600').int()
		profile:     ctx.get_property_or('profile', 'dev')
		debug:       ctx.get_property_or('app.debug', 'true') == 'true'
	}
	ctx.register_instance('AppConfig', app_cfg)!
	log_.info('Config loaded — app=${app_cfg.app_name} v${app_cfg.app_version}')

	// ── 4. Cache 缓存初始化 ──
	mut cache_mgr := cache.new_cache_registry()
	unsafe {
		cache_mgr.register('default', cache.new_memory_cache('default'))
	}
	cache_mgr.set('app:name', app_cfg.app_name, 0)!
	cache_mgr.set('app:version', app_cfg.app_version, 0)!
	ctx.register_instance('CacheRegistry', cache_mgr)!
	log_.info('Cache initialized — memory driver "default"')

	// ── 5. TransactionManager 事务管理器（@[transactional] 依赖） ──
	tm := orm.new_transaction_manager()
	ctx.register_instance('TransactionManager', tm)!

	// ── 6. Services 服务注册 ──
	user_svc := new_user_service(log_, tm)
	ctx.register_instance('UserService', user_svc)!

	jwt_config := JWTConfig{
		secret:             app_cfg.jwt_secret
		expiration_minutes: app_cfg.jwt_expiry
	}
	auth_svc := new_auth_service(log_, user_svc, jwt_config)
	ctx.register_instance('AuthService', auth_svc)!

	health_svc := new_health_service()
	ctx.register_instance('HealthService', health_svc)!

	cache_svc := new_cache_service(cache_mgr)
	ctx.register_instance('CacheService', cache_svc)!
	log_.info('Services registered — UserService, AuthService, HealthService, CacheService')

	// ── 7. Middleware 中间件注册 ──
	mw := new_middleware_manager(log_, auth_svc)
	ctx.register_instance('MiddlewareManager', mw)!
	log_.info('Middleware initialized — RequestLog, CORS, Auth, RateLimit')

	log_.info('Bootstrap complete — ${app_cfg.app_name} v${app_cfg.app_version} ready')
}

// print_banner 打印启动横幅
pub fn print_banner(app_cfg &AppConfig) {
	println('')
	println('╔══════════════════════════════════════════════════════════╗')
	println('║                                                          ║')
	println('║   Photon Framework — Enterprise API Server               ║')
	println('║   ${app_cfg.app_name} v${app_cfg.app_version}                      ')
	println('║                                                          ║')
	println('╚══════════════════════════════════════════════════════════╝')
	println('')
}

// print_routes 打印所有 API 端点
pub fn print_routes() {
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

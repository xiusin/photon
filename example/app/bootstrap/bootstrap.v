module bootstrap

// bootstrap.v — 应用初始化（Spring Boot 式 Bootstrap，DI 容器驱动）
//
// 职责：通过 ApplicationContext 注册所有 Bean（配置、日志、缓存、服务、中间件）。
// 相当于 Spring Boot 的 @SpringBootApplication 启动逻辑。
//
// 与旧版手动装配的区别：
//   - 旧版：Bootstrap 结构体持有所有组件引用，手动 new_xxx() 链式装配
//   - 新版：所有组件注册到 ApplicationContext，由容器统一管理生命周期
//           main.v 通过 ctx.resolve_typed[T]() 获取 Bean
import app.runtime
import app.services
import app.middleware
import photon.logger
import photon.cache
import photon.orm
import photon.core

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
// 注册顺序：Environment 属性 → 启动时刻冻结 → Logger → AppConfig →
//           CacheRegistry → TransactionManager → 各 Service → MiddlewareManager
//
// 运行时值（进程启动时刻、PID）在 refresh 之前先写进 Environment，
// 之后由 ProcessRuntime 这个 Bean 通过 @[value] 绑定读走 —— 这样启动代码里
// 不再有 start_time 穿参，需要 uptime 的地方 @[autowired] 注入即可。
pub fn bootstrap(mut ctx core.ApplicationContext, start_time i64, start_tick i64) ! {
	// ── 1. 冻结进程启动时刻 ──
	// 必须在 refresh 之前：ProcessRuntime 的 @[value] 字段在 refresh 期间绑定，
	// 读的就是此刻的属性表。放在这里，属性与 Bean 的注册顺序也统一了。
	//
	// 直接调 core 而不是转一手 app.runtime：V 0.5.2 下别的模块一旦在函数签名里
	// 写了 `mut ctx core.ApplicationContext`，checker 会把它报成 unknown type，
	// 连带 core/scanner.v 的 comptime 扫描一起误判。属性键也只该有一处定义。
	core.freeze_start_moment_props(mut ctx, start_time, start_tick)

	// ── 2. Environment 配置属性 ──
	ctx.set_profiles(['dev'])
	ctx.set_property('app.name', 'PhotonAPI')
	ctx.set_property('app.version', '0.4.0')
	ctx.set_property('server.port', '8080')
	ctx.set_property('jwt.secret', 'your-256-bit-secret-key-here-min-32-chars!!')
	ctx.set_property('jwt.expiration', '60')
	ctx.set_property('cache.ttl', '3600')
	ctx.set_property('app.debug', 'true')

	// ── 3. Logger 日志初始化 ──
	mut log_ := logger.new()
	log_.set_level(.debug)
	log_.set_colored(true)
	log_.put('app', 'PhotonAPI')
	log_.info('═══ Photon Application Bootstrap (DI Container) ═══')
	log_.info('Profile: dev')
	ctx.register_instance('Logger', log_)!

	// ── 4. AppConfig 构建（从 Environment 属性绑定） ──
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

	// ── 5. Cache 缓存初始化 ──
	mut cache_mgr := cache.new_cache_registry()
	unsafe {
		cache_mgr.register('default', cache.new_memory_cache('default'))
	}
	cache_mgr.set('app:name', app_cfg.app_name, 0)!
	cache_mgr.set('app:version', app_cfg.app_version, 0)!
	ctx.register_instance('CacheRegistry', cache_mgr)!
	log_.info('Cache initialized — memory driver "default"')

	// ── 6. TransactionManager 事务管理器（@[transactional] 依赖） ──
	tm := orm.new_transaction_manager()
	ctx.register_instance('TransactionManager', tm)!

	// ── 7. Services 服务注册 ──
	user_svc := services.new_user_service(log_, tm)
	ctx.register_instance('UserService', user_svc)!

	jwt_config := services.JWTConfig{
		secret:             app_cfg.jwt_secret
		expiration_minutes: app_cfg.jwt_expiry
	}
	auth_svc := services.new_auth_service(log_, user_svc, jwt_config)
	ctx.register_instance('AuthService', auth_svc)!

	cache_svc := services.new_cache_service(cache_mgr)
	ctx.register_instance('CacheService', cache_svc)!
	log_.info('Services registered — UserService, AuthService, HealthService, CacheService')

	// ── 7.1 运行时值 Bean（ProcessRuntime） ──
	// 启动时刻不在这里「传」给谁：定义 + @[value] 绑定交给容器，
	// 控制器与 HealthService 各自 @[autowired] 拿到它。
	//
	// 手写定义而不走 @[service] + scan_and_register[T]：V 0.5.2 下别的模块调
	// 核心的泛型 comptime 入口会让 core/scanner.v 的 `$for` 产物解析失败
	// （`definition of ast.SelectorExpr ... unknown`，main 分支同样复现）。
	// 定义内容和扫描结果等价 —— 就是结构体上那几个 @[value] 的字面键。
	mut runtime_def := core.new_bean_definition('ProcessRuntime')
	runtime_def.value_bindings = [
		core.ValueBinding{
			field_name: 'start_time'
			expr:       'app.start.time'
		},
		core.ValueBinding{
			field_name: 'start_tick'
			expr:       'app.start.tick'
		},
		core.ValueBinding{
			field_name: 'pid'
			expr:       'app.pid'
		},
	]
	ctx.register(runtime_def)!
	ctx.register_factory('ProcessRuntime', &runtime.ProcessRuntimeFactory{})!

	// ── 8. Middleware 中间件注册 ──
	mw := middleware.new_middleware_manager(log_, auth_svc)
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

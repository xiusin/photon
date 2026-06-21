module providers

// providers/app_service_provider.v — 应用基础服务提供者
//
// 注册应用级基础设施组件：Logger、Mailer、Scheduler、LockManager。
// 这些组件无外部依赖，是最先注册的基础服务。
//
// Laravel 等价：App\Providers\AppServiceProvider
// Spring 等价：@Configuration 类中的 @Bean 方法

import photon.core
import photon.logger
import photon.mailer
import photon.ticker
import photon.locking

pub struct AppServiceProvider {
	ctx &BootContext
}

// new_app_provider 创建应用基础服务提供者
pub fn new_app_provider(ctx &BootContext) &AppServiceProvider {
	return &AppServiceProvider{
		ctx: ctx
	}
}

// register 注册应用级基础设施
pub fn (sp &AppServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	mut ctx := unsafe { sp.ctx }
	cfg := ctx.cfg

	// ── Logger ──
	mut log := logger.new_with_level(if cfg.debug { .debug } else { .info })
	log.set_colored(cfg.debug)
	if !cfg.debug {
		log.use_json()
	}
	log.put('app', cfg.app.name)
	log.put('profile', cfg.profile)
	log.info('═══ PhotonBlog Bootstrap (ServiceProvider) ═══')
	log.info('Profile: ${cfg.profile}')
	log.info('Debug: ${cfg.debug}')
	ctx.log = log

	// ── Mailer ──
	mailer_inst := if cfg.mail.driver == 'log' {
		mailer.new_log_mailer()
	} else {
		mailer.new_mailer(mailer.SmtpConfig{
			host:      cfg.mail.host
			port:      cfg.mail.port
			username:  cfg.mail.username
			password:  cfg.mail.password
			from_name: cfg.mail.from_name
		})
	}
	ctx.mailer_inst = mailer_inst
	log.info('Mailer initialized — driver=${cfg.mail.driver}')

	// ── Scheduler ──
	scheduler := ticker.new_task_scheduler()
	ctx.scheduler = scheduler
	log.info('Scheduler initialized')

	// ── LockManager ──
	lock_mgr := locking.new_lock_manager()
	ctx.lock_mgr = lock_mgr
	log.info('LockManager initialized — local mutex driver')

	// 注册到 ApplicationContext
	app_ctx.register_instance('Logger', unsafe { voidptr(ctx.log) })!
	app_ctx.register_instance('Mailer', unsafe { voidptr(ctx.mailer_inst) })!
	app_ctx.register_instance('Scheduler', unsafe { voidptr(ctx.scheduler) })!
	app_ctx.register_instance('LockManager', unsafe { voidptr(ctx.lock_mgr) })!
}

// boot 应用基础服务无需启动后初始化
pub fn (sp &AppServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
}

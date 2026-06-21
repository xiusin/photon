module providers

// providers/queue_service_provider.v — 队列服务提供者
//
// register() 阶段创建 QueueWorker，boot() 阶段初始化 Job 全局依赖并注册 Job 工厂
// （依赖 Mailer/Cache/Repository，需等待 RepositoryServiceProvider 注册完成）。
//
// Laravel 等价：App\Providers\QueueServiceProvider
// Spring 等价：@EnableAsync + TaskExecutor

import photon.core
import photon.queue

pub struct QueueServiceProvider {
	ctx &BootContext
}

// new_queue_provider 创建队列服务提供者
pub fn new_queue_provider(ctx &BootContext) &QueueServiceProvider {
	return &QueueServiceProvider{
		ctx: ctx
	}
}

// register 创建 QueueWorker
pub fn (sp &QueueServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	mut ctx := unsafe { sp.ctx }
	log := ctx.log

	worker := queue.new_worker()
	ctx.worker = worker
	log.info('QueueWorker initialized')

	app_ctx.register_instance('QueueWorker', unsafe { voidptr(worker) })!
}

// boot 初始化 Job 全局依赖并注册 Job 工厂
pub fn (sp &QueueServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
	log := sp.ctx.log

	mailer_inst := sp.ctx.mailer_inst
	cache_mgr := sp.ctx.cache_mgr
	worker := sp.ctx.worker
	user_repo := sp.ctx.user_repo
	post_repo := sp.ctx.post_repo
	comment_repo := sp.ctx.comment_repo

	init_job_globals(mailer_inst, cache_mgr, log, user_repo, post_repo, comment_repo)
	log.info('Job globals initialized')

	register_jobs(worker)
	log.info('Job factories registered')
}

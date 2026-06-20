module bootstrap

// bootstrap/bootstrap_struct.v — Bootstrap 聚合结构体
//
// Bootstrap 是应用启动后的组件聚合容器，由 AppKernel.to_bootstrap() 构造。
// 持有全部基础设施、仓储与服务的引用，供 main.v、commands.v、seeders 等使用。
//
// 设计动机：
//   BootContext 是 Provider 装配阶段的共享可变状态（pub mut），
//   Bootstrap 是装配完成后的只读快照（pub），避免后续代码误写。

import photon.core
import photon.cache
import photon.locking
import photon.storage
import photon.mailer
import photon.ticker
import photon.logger
import photon.security
import photon.queue
import photon.orm as phorm
import photon.web
import config
import repositories
import services

@[heap]
pub struct Bootstrap {
pub:
	cfg            config.AppConfig
	log            &logger.Logger
	app_context    &core.ApplicationContext
	event_bus      &core.EventBus
	cache_mgr      &cache.CacheManager
	orm_mgr        &phorm.OrmManager
	lock_mgr       &locking.LockManager
	storage_mgr    &storage.StorageManager
	mailer_inst    &mailer.Mailer
	scheduler      &ticker.Scheduler
	jwt_mgr        &security.JwtManager
	role_hierarchy &security.RoleHierarchy
	csrf_mgr       &security.CsrfManager
	worker         &queue.QueueWorker
	upload_handler &web.UploadHandler
	// ── 仓储 ──
	user_repo     &repositories.UserRepository
	post_repo     &repositories.PostRepository
	comment_repo  &repositories.CommentRepository
	category_repo &repositories.CategoryRepository
	tag_repo      &repositories.TagRepository
	// ── 服务 ──
	user_svc     &services.UserService
	auth_svc     &services.AuthService
	post_svc     &services.PostService
	comment_svc  &services.CommentService
	category_svc &services.CategoryService
	tag_svc      &services.TagService
	stats_svc    &services.StatsService
	upload_svc   &services.UploadService
}

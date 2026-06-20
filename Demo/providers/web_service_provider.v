module providers

// providers/web_service_provider.v — Web 基础设施服务提供者
//
// 注册 StorageManager 与 UploadHandler，提供文件存储与上传能力。
// MiddlewareGroupRegistry 在 main.v 中创建（需 AuthService 与 RoleHierarchy，
// 这两者由 AuthServiceProvider 在 boot 阶段创建）。
//
// Laravel 等价：App\Providers\RouteServiceProvider + Storage 配置
// Spring 等价：MultipartResolver + ResourceHandlerRegistry

import photon.core
import photon.storage
import photon.web
import os

pub struct WebServiceProvider {
	ctx &BootContext
}

// new_web_provider 创建 Web 基础设施服务提供者
pub fn new_web_provider(ctx &BootContext) &WebServiceProvider {
	return &WebServiceProvider{
		ctx: ctx
	}
}

// register 创建 StorageManager 与 UploadHandler
pub fn (sp &WebServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	cfg := sp.ctx.cfg
	log := sp.ctx.log

	// ── StorageManager ──
	storage_mgr := storage.new_manager()
	if !os.exists(cfg.storage.base_path) {
		os.mkdir_all(cfg.storage.base_path)!
	}
	unsafe {
		storage_mgr.register('local', storage.new_local_adapter(cfg.storage.base_path))
	}
	sp.ctx.storage_mgr = storage_mgr
	log.info('StorageManager initialized — local driver (${cfg.storage.base_path})')

	// ── UploadHandler ──
	upload_handler := web.new_upload_handler()
	unsafe {
		upload_handler.max_size = cfg.storage.max_size
		upload_handler.allowed_extensions = cfg.storage.allowed_ext.clone()
	}
	sp.ctx.upload_handler = upload_handler
	log.info('UploadHandler initialized — max_size=${cfg.storage.max_size}')

	app_ctx.register_instance('StorageManager', unsafe { voidptr(storage_mgr) })!
	app_ctx.register_instance('UploadHandler', unsafe { voidptr(upload_handler) })!
}

// boot Web 基础设施无需启动后初始化
pub fn (sp &WebServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
}

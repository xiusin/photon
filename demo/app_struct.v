module main

// app_struct.v — PhotonBlog Web 应用结构（veb 集成）
//
// 定义 App 全局应用结构（嵌入 veb.Context + veb.Middleware[http.Context]）。
// Context 请求级上下文已迁移至 app/http/context.v（module http）。
// veb 框架在每次请求前自动调用 http.Context.before_request()
// 完成请求计数；完整的中间件链（CORS/RequestId/日志/限流）在 main() 中通过 use() 注册，
// 由 MiddlewareGroupRegistry.apply_api_group() 统一编排。

import veb
import sync
import photon.apidoc
import bootstrap
import app.http.middleware
import app.http
import app.http.controllers

// ═══════════════════════════════════════════════════════════
// App — 全局应用结构
// ═══════════════════════════════════════════════════════════

pub struct App {
	veb.Context
	veb.Middleware[http.Context]
pub mut:
	start_time          i64
	req_count           int
	req_mu              &sync.Mutex = unsafe { nil }
	bootstrap           &bootstrap.Bootstrap = unsafe { nil }
	middleware_registry &middleware.MiddlewareGroupRegistry = unsafe { nil }
	http_kernel         &http.HttpKernel = unsafe { nil }
	apidoc_handler      &apidoc.ApidocHandler = unsafe { nil }
	// Laravel 风格控制器实例
	system_ctrl         &controllers.SystemController = unsafe { nil }
	auth_ctrl           &controllers.AuthController = unsafe { nil }
	user_ctrl           &controllers.UserController = unsafe { nil }
	post_ctrl           &controllers.PostController = unsafe { nil }
	comment_ctrl        &controllers.CommentController = unsafe { nil }
	category_ctrl       &controllers.CategoryController = unsafe { nil }
	tag_ctrl            &controllers.TagController = unsafe { nil }
	upload_ctrl         &controllers.UploadController = unsafe { nil }
}
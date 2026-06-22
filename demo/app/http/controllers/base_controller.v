module controllers

import bootstrap
import app.http.middleware

// BaseController — 控制器基类，提供共享依赖
//
// 所有具体控制器嵌入 BaseController，通过 bootstrap 访问服务层，
// 通过 middleware_registry 访问认证/授权中间件。
pub struct BaseController {
pub:
	bootstrap           &bootstrap.Bootstrap = unsafe { nil }
	middleware_registry &middleware.MiddlewareGroupRegistry = unsafe { nil }
}
module routes

// routes/web.v — Web 路由定义与中间件组配置
//
// Web 路由（无 API 前缀）：
//   GET /        — 应用信息（名称、版本、运行时间）
//   GET /health  — 健康检查（数据库/缓存连通性）
//   GET /ping    — 连通性测试（返回 pong）
//   GET /stats   — 博客统计（用户/文章/评论数）
//
// 中间件组：
//   web — CORS + RequestId + RequestLog
//
// 注：实际路由由 controllers.v 中的 veb 注解定义，
//     本文件提供路由元数据与中间件组配置。

// WebRouteGroup Web 路由组元数据
pub struct WebRouteGroup {
pub:
	path        string
	middleware  []string
	description string
}

// web_route_groups 返回全部 Web 路由组定义
pub fn web_route_groups() []WebRouteGroup {
	return [
		WebRouteGroup{
			path: '/'
			middleware: ['web']
			description: '应用信息'
		},
		WebRouteGroup{
			path: '/health'
			middleware: ['web']
			description: '健康检查'
		},
		WebRouteGroup{
			path: '/ping'
			middleware: ['web']
			description: '连通性测试'
		},
		WebRouteGroup{
			path: '/stats'
			middleware: ['web']
			description: '博客统计'
		},
	]
}

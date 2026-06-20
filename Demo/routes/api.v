module main

// routes/api.v — API 路由定义与中间件组配置
//
// API 路由分组（/api/v1 前缀）：
//   认证    POST   /api/v1/auth/register     注册
//         POST   /api/v1/auth/login        登录
//         POST   /api/v1/auth/refresh      刷新令牌
//         GET    /api/v1/auth/profile      用户信息（JWT）
//
//   用户    GET    /api/v1/users             列表（ADMIN）
//         GET    /api/v1/users/:id         详情（ADMIN）
//         POST   /api/v1/users             创建（ADMIN）
//         PUT    /api/v1/users/:id         更新（ADMIN）
//         DELETE /api/v1/users/:id         删除（ADMIN）
//
//   文章    GET    /api/v1/posts             列表（公开）
//         GET    /api/v1/posts/:id         详情（公开）
//         POST   /api/v1/posts             创建（JWT）
//         PUT    /api/v1/posts/:id         更新（JWT）
//         DELETE /api/v1/posts/:id         删除（JWT）
//         PATCH  /api/v1/posts/:id/publish 发布（JWT）
//
//   评论    GET    /api/v1/posts/:id/comments 列表（公开）
//         POST   /api/v1/comments          创建（JWT）
//         DELETE /api/v1/comments/:id      删除（JWT）
//
//   分类    GET    /api/v1/categories        列表（公开）
//         POST   /api/v1/categories        创建（EDITOR+）
//
//   标签    GET    /api/v1/tags              列表（公开）
//         POST   /api/v1/tags              创建（EDITOR+）
//
//   上传    POST   /api/v1/upload/avatar     头像（JWT）
//         POST   /api/v1/upload/image       配图（JWT）
//
// 中间件组：
//   api    — CORS + RequestId + RequestLog + RateLimit
//   auth   — JwtAuth
//   admin  — auth + RoleAuth[ADMIN]
//   editor — auth + RoleAuth[EDITOR, ADMIN]
//
// 注：实际路由由 controllers.v 中的 veb 注解定义（@[get]/@[post] 等），
//     本文件提供路由元数据与中间件组配置，供 Task 9 中间件组注册使用。

// ApiRouteGroup API 路由组元数据
pub struct ApiRouteGroup {
pub:
	prefix      string
	middleware  []string
	description string
}

// api_route_groups 返回全部 API 路由组定义
pub fn api_route_groups() []ApiRouteGroup {
	return [
		ApiRouteGroup{
			prefix: '/api/v1/auth'
			middleware: ['api']
			description: '认证接口（注册/登录/刷新/个人信息）'
		},
		ApiRouteGroup{
			prefix: '/api/v1/users'
			middleware: ['api', 'admin']
			description: '用户管理（需 ADMIN 角色）'
		},
		ApiRouteGroup{
			prefix: '/api/v1/posts'
			middleware: ['api']
			description: '文章管理（公开读取，JWT 写入）'
		},
		ApiRouteGroup{
			prefix: '/api/v1/comments'
			middleware: ['api', 'auth']
			description: '评论管理（JWT 写入）'
		},
		ApiRouteGroup{
			prefix: '/api/v1/categories'
			middleware: ['api']
			description: '分类管理（公开读取，EDITOR+ 写入）'
		},
		ApiRouteGroup{
			prefix: '/api/v1/tags'
			middleware: ['api']
			description: '标签管理（公开读取，EDITOR+ 写入）'
		},
		ApiRouteGroup{
			prefix: '/api/v1/upload'
			middleware: ['api', 'auth']
			description: '文件上传（JWT）'
		},
	]
}

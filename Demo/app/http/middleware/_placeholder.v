// app/Http/Middleware/ — 中间件目录占位
//
// 中间件结构体和注册表定义已迁移至项目根目录：
//   - middleware_defs.v    — 中间件结构体（CorsMiddleware, RequestIdMiddleware 等）
//   - middleware_registry.v — MiddlewareGroupRegistry 中间件组注册表
//
// 原因：V 语言不支持子目录中的 module main 文件，
// 而中间件需要引用 Context 类型（定义在 module main 中），
// 因此必须在 module main（即项目根目录）中定义。
//
// Laravel 等价：app/Http/Middleware/
// 目录结构保留以维持 Laravel 风格的组织方式。
module middleware

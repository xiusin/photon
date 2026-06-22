module controllers

// app/http/controllers/_README.v — 控制器目录说明
//
// 注意：控制器方法（App 结构体的 veb 路由方法）必须定义在 module main 中，
// 因为 V 语言 veb 框架的路由注解（@[get]/@[post] 等）要求方法在 App 所在的 module 中。
// 因此控制器文件位于项目根目录（controllers.v），而非此目录。
//
// Laravel 等价：app/Http/Controllers/
// V 语言约束：module main → 根目录
//
// 控制器文件：
//   controllers.v — 所有控制器方法（合并自 controller_*.v）
//
// DTO 结构体：
//   app/http/dto.v — 共享 DTO（AppInfoDto/HealthDto/MessageDto 等，module http）

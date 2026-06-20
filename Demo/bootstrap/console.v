module bootstrap

// bootstrap/console.v — 控制台输出工具
//
// 从 bootstrap.v 迁移的 print_banner / print_routes 方法。
// print_routes 改为从 web.scan_controller[App]() 实际扫描结果生成，
// 移除原硬编码路由表，确保路由信息与实际注册一致。

import photon.web

// print_banner 打印启动横幅
pub fn (b &Bootstrap) print_banner() {
	println('')
	println('╔══════════════════════════════════════════════════════════╗')
	println('║                                                          ║')
	println('║   PhotonBlog — Enterprise Blog/CMS Platform              ║')
	println('║   Powered by Photon Framework                            ║')
	println('║                                                          ║')
	println('║   App:      ${b.cfg.app.name:-44s} ║')
	println('║   Version:  v${b.cfg.app.version:-43s} ║')
	println('║   Profile:  ${b.cfg.profile:-44s} ║')
	println('║   Env:      ${b.cfg.app.env:-44s} ║')
	println('║                                                          ║')
	println('╚══════════════════════════════════════════════════════════╝')
	println('')
}

// print_routes 打印路由表（接收从 main 模块扫描的路由列表）
// 注：App 类型在 module main 中定义，无法跨模块引用，
// 因此路由扫描由 main.v 调用 web.scan_controller[App]() 完成，
// 结果传递给本函数打印。
pub fn print_routes(routes []web.RouteInfo) {
	web.print_routes(routes)
}

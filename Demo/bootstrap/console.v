module bootstrap

// bootstrap/console.v — 控制台输出工具
//
// 从 bootstrap.v 迁移的 print_banner / print_routes 方法。
// print_routes 改为接收路由列表参数，由调用方（module main）
// 执行 web.scan_controller[App]() 后传入，避免子模块引用 App 类型。

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

// print_routes 打印路由表（接收路由列表，由调用方扫描控制器后传入）
pub fn (b &Bootstrap) print_routes(routes []web.RouteInfo) {
	web.print_routes(routes)
}

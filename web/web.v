module web

// web.v — Photon Web Module 核心（Spring WebMvc 等价）
//
// 架构概述：
//
//   1. WebModule（可嵌入结构体）
//      嵌入到 App 中，提供路由分发能力。
//      before_request 中调用 WebModule.handle_request()。
//
//   2. Controller（接口）
//      每个控制器是一个独立的 struct，通过 @[controller] 和 @[get/post] 注解。
//      mount_controller[T]() 编译期扫描并生成闭包处理器。
//
//   3. Router（路由注册表）
//      以 RouteHandler 闭包形式存储所有路由。
//      dispatch_with_chain() 匹配 URL 路径并执行对应闭包，
//      同时执行全局中间件链和路由级中间件。
//
//   4. MiddlewareChain（中间件链）
//      前置中间件在 handler 之前执行，后置中间件在 handler 之后执行。
//      支持压缩、CORS、认证、限流等横切关注点。
//
// 深度集成 veb 原生能力：
//   - 真正的 gzip/zstd 响应压缩（后置中间件）
//   - 请求体 gzip/zstd 解压（前置中间件）
//   - 静态文件服务（ResourceHandlerRegistry 集成）
//     · 预压缩文件自动检测（.gz / .zst 零拷贝）
//     · 即时压缩 + 磁盘缓存
//     · Markdown 内容协商
//   - SSE 长连接支持（veb.sse 桥接）
//   - 完整 CORS preflight 验证（veb.CorsOptions 桥接）
//   - Host 级路由隔离
//   - BeforeAcceptApp 启动前钩子
//
// 使用示例（example/main.v）：
//
//   module main
//
//   pub struct App {
//       veb.Context
//       web.WebModule               // ← 嵌入 WebModule
//   }
//
//   pub struct Context {
//       veb.Context
//       app &App                    // ← App 反向引用
//   }
//
//   // 覆写 veb.Context.before_request()
//   pub fn (mut ctx Context) before_request() {
//       ctx.app.WebModule.handle_request(unsafe { voidptr(&ctx) }) // 分发到控制器
//   }
//
//   pub fn main() {
//       mut app := &App{...}
//       app.WebModule.mount(&user_controller, '/api/v1')
//       // 注册中间件
//       app.WebModule.use(web.request_id_middleware)
//       app.WebModule.use_after(web.compression_auto_after_middleware)
//       // 启用静态文件压缩
//       app.WebModule.enable_static_compression(max_size: 2_000_000)
//       veb.run_at[App, Context](mut app)
//   }
import veb
import os

// WebModule — 可嵌入的 Web 模块
// 嵌入到 App 中，提供路由分发、控制器挂载、中间件链能力。
//
// 字段说明：
//   router:  路由注册表，存储所有路由定义
//   chain:   全局中间件链，前置+后置中间件
//   resources: 静态资源注册表，用于静态文件服务
//
// 用法：
//   pub struct App {
//       veb.Context
//       web.WebModule
//   }
pub struct WebModule {
pub mut:
	router    &RouteRegistry
	chain     &MiddlewareChain
	resources ResourceHandlerRegistry
}

// init_web_module 初始化 WebModule
pub fn init_web_module() WebModule {
	return WebModule{
		router:    new_route_registry()
		chain:     new_chain()
		resources: new_resource_handler_registry()
	}
}

// ============================================================
// 中间件链（全局中间件注册）
// ============================================================

// use 注册全局前置中间件。
// 前置中间件在所有路由 handler 之前执行。
// 返回 false 可短路（handler 不会执行）。
//
// 用法：
//   app.WebModule.use(web.request_id_middleware)
//   app.WebModule.use(web.auth_middleware)
pub fn (mut wm WebModule) use(mw MiddlewareFunc) {
	wm.chain.use(mw)
}

// use_after 注册全局后置中间件。
// 后置中间件在所有路由 handler 之后执行。
// 适用于响应压缩、安全头注入等响应变换场景。
//
// 用法：
//   app.WebModule.use_after(web.compression_auto_after_middleware)
pub fn (mut wm WebModule) use_after(mw MiddlewareFunc) {
	wm.chain.use_after(mw)
}

// ============================================================
// 控制器挂载
// ============================================================

// register 注册控制器（实现 Controller 接口的 struct）
// 用法：
//   app.WebModule.register(&UserController{user_service: svc})
pub fn (mut wm WebModule) register(controller Controller) {
	controller.register_routes(mut wm.router)
}

// mount 是 register 的别名（保持 API 一致性）
pub fn (mut wm WebModule) mount(controller Controller) {
	wm.register(controller)
}

// ============================================================
// 路由分发（在 Context.before_request 中调用）
// ============================================================

// handle_request 从路由表中匹配并执行处理器，同时执行中间件链。
// 返回 true 表示已匹配并处理，false 表示无匹配。
// 若已处理，ctx.done 会被设置为 true（由 ctx.text() 等触发）
//
// 执行顺序：
//   1. 静态资源检查（ResourceHandlerRegistry）
//      · Markdown 内容协商（如果启用）
//      · 预压缩文件检测（.gz / .zst 零拷贝）
//      · 即时压缩 + 磁盘缓存
//   2. 全局前置中间件 → 路由前置中间件 → handler → 路由后置中间件 → 全局后置中间件
//
// ctx_ptr 是指向自定义 Context 的 voidptr 指针
// 因为所有 Context 类型都嵌入 veb.Context 作为第一个字段，
// 所以可以安全地将 ctx_ptr 转换为 &veb.Context 以读取 req.url 和 req.method
//
// 用法：
//   pub fn (mut ctx Context) before_request() {
//       if ctx.app.WebModule.handle_request(unsafe { voidptr(&ctx) }) {
//           return  // 已处理
//       }
//       // 未匹配，veb 会自动处理 404
//   }
pub fn (mut wm WebModule) handle_request(ctx_ptr voidptr) bool {
	mut ctx := unsafe { &veb.Context(ctx_ptr) }
	mut path := ctx.req.url

	// 剥离查询字符串，仅保留路径部分用于路由匹配
	// Strip query string for route matching
	if qmark := path.index('?') {
		path = path[..qmark]
	}

	method := ctx.req.method.str()

	// 1. 静态资源检查（在路由匹配之前）
	if wm.resources.mappings.len > 0 {
		accept_header := ctx.req.header.get(.accept) or { '' }
		accept_encoding := ctx.req.header.get(.accept_encoding) or { '' }

		// 1a. Markdown 内容协商
		if file_path := wm.resources.resolve_with_negotiation(path, accept_header) {
			wm.serve_static_with_compression(mut ctx, file_path, accept_encoding)
			return true
		}

		// 1b. 常规文件解析
		if file_path := wm.resources.resolve(path) {
			wm.serve_static_with_compression(mut ctx, file_path, accept_encoding)
			return true
		}
	}

	// 2. 路由匹配 + 中间件执行
	// 提取 Host 头用于 host 级路由匹配
	host := ctx.req.header.get(.host) or { '' }
	// 去除端口号
	host_clean := if colon := host.index(':') { host[..colon] } else { host }

	return wm.router.dispatch_with_chain(method, path, host_clean, ctx_ptr, wm.chain)
}

// serve_static_with_compression 智能提供静态文件服务。
// 优先使用预压缩文件（零拷贝），回退到即时压缩，最后是原始文件。
//
// 桥接 veb.Context.serve_precompressed_file() + serve_compressed_static() 逻辑。
fn (wm &WebModule) serve_static_with_compression(mut ctx veb.Context, file_path string, accept_encoding string) {
	// 如果启用了压缩配置
	if wm.resources.compression.enable || wm.resources.compression.enable_gzip_only || wm.resources.compression.enable_zstd_only {
		// 1. 尝试预压缩文件（.gz / .zst 已存在）
		if compressed_path, encoding := wm.resources.resolve_precompressed(file_path, accept_encoding) {
			ext := os.file_ext(file_path).to_lower()
			mime_type := veb_mime_type(ext)
			ctx.res.header.set(.content_encoding, encoding)
			ctx.res.header.set(.vary, 'Accept-Encoding')
			compressed_size := os.file_size(compressed_path)
			ctx.res.header.set(.content_length, compressed_size.str())
			ctx.send_response_to_client(mime_type, '')
			return
		}

		// 2. 尝试即时压缩 + 磁盘缓存
		if compressed_path, encoding := wm.resources.compress_and_cache(file_path, accept_encoding) {
			ext := os.file_ext(file_path).to_lower()
			mime_type := veb_mime_type(ext)
			ctx.res.header.set(.content_encoding, encoding)
			ctx.res.header.set(.vary, 'Accept-Encoding')
			compressed_size := os.file_size(compressed_path)
			ctx.res.header.set(.content_length, compressed_size.str())
			ctx.send_response_to_client(mime_type, '')
			return
		}
	}

	// 3. 原始文件（无压缩）
	ctx.file(file_path)
}

// veb_mime_type 根据文件扩展名返回 MIME 类型。
// 桥接 veb.mime_types 常量。
fn veb_mime_type(ext string) string {
	match ext {
		'.css' { return 'text/css' }
		'.js' { return 'text/javascript' }
		'.json' { return 'application/json' }
		'.html', '.htm' { return 'text/html' }
		'.xml' { return 'application/xml' }
		'.txt' { return 'text/plain' }
		'.md' { return 'text/markdown' }
		'.png' { return 'image/png' }
		'.jpg', '.jpeg' { return 'image/jpeg' }
		'.gif' { return 'image/gif' }
		'.svg' { return 'image/svg+xml' }
		'.ico' { return 'image/vnd.microsoft.icon' }
		'.webp' { return 'image/webp' }
		'.woff' { return 'font/woff' }
		'.woff2' { return 'font/woff2' }
		'.ttf' { return 'font/ttf' }
		'.otf' { return 'font/otf' }
		'.pdf' { return 'application/pdf' }
		'.zip' { return 'application/zip' }
		'.gz' { return 'application/gzip' }
		'.zst' { return 'application/zstd' }
		'.mp4' { return 'video/mp4' }
		'.webm' { return 'video/webm' }
		'.mp3' { return 'audio/mpeg' }
		'.wasm' { return 'application/wasm' }
		else { return 'application/octet-stream' }
	}
}

// ============================================================
// 手动注册路由（无需控制器结构体）
// ============================================================

// get 注册 GET 路由
pub fn (mut wm WebModule) get(path string, handler RouteHandler) {
	wm.router.get(path, handler)
}

// post 注册 POST 路由
pub fn (mut wm WebModule) post(path string, handler RouteHandler) {
	wm.router.post(path, handler)
}

// put 注册 PUT 路由
pub fn (mut wm WebModule) put(path string, handler RouteHandler) {
	wm.router.put(path, handler)
}

// delete 注册 DELETE 路由
pub fn (mut wm WebModule) delete(path string, handler RouteHandler) {
	wm.router.delete(path, handler)
}

// patch 注册 PATCH 路由
pub fn (mut wm WebModule) patch(path string, handler RouteHandler) {
	wm.router.patch(path, handler)
}

// group 创建路由组
pub fn (mut wm WebModule) group(prefix string, cb fn (mut sub RouteRegistry)) {
	wm.router.group(prefix, cb)
}

// ============================================================
// 静态文件服务（ResourceHandlerRegistry 集成）
// ============================================================

// add_resource_handler 注册静态资源映射。
// 将 URL pattern 映射到文件系统目录。
//
// Spring 等价：ResourceHandlerRegistry.addResourceHandler()
//
// 用法：
//   app.WebModule.add_resource_handler('/static/**', './public')
//   // 访问 /static/css/main.css → 读取 ./public/css/main.css
pub fn (mut wm WebModule) add_resource_handler(pattern string, locations ...string) {
	wm.resources.add_mapping(pattern, ...locations)
}

// enable_static_compression 启用静态文件自动压缩。
// 桥接 veb.StaticHandler 的 enable_static_compression / enable_static_gzip / enable_static_zstd。
//
// 压缩策略：
//   - 优先查找 .zst / .gz 预压缩文件（零拷贝）
//   - 未找到则即时压缩并缓存到磁盘
//   - zstd 优先（更好的压缩比），gzip 回退
//
// 用法：
//   app.WebModule.enable_static_compression(enable: true, max_size: 2_000_000)
//   app.WebModule.enable_static_compression(enable_gzip_only: true)
pub fn (mut wm WebModule) enable_static_compression(config StaticCompressionConfig) {
	wm.resources.set_compression(config)
}

// enable_markdown_negotiation 启用 Markdown 内容协商。
// 当客户端发送 Accept: text/markdown 时，自动返回 .md 文件。
//
// 桥接 veb.StaticHandler.enable_markdown_negotiation。
//
// 用法：
//   app.WebModule.enable_markdown_negotiation()
pub fn (mut wm WebModule) enable_markdown_negotiation() {
	old := wm.resources.compression
	wm.resources.set_compression(StaticCompressionConfig{
		enable: old.enable
		enable_gzip_only: old.enable_gzip_only
		enable_zstd_only: old.enable_zstd_only
		max_size: old.max_size
		enable_markdown_negotiation: true
	})
}

// serve_static_file 直接通过 veb.Context 提供静态文件服务。
// 自动检测 Content-Type，支持 sendfile 零拷贝。
//
// 用法（在路由 handler 中）：
//   r.get('/download/:file', fn [wm] (ctx_ptr voidptr, params map[string]string) veb.Result {
//       ctx := unsafe { &veb.Context(ctx_ptr) }
//       return wm.serve_static_file(ctx, './files/${params['file']}')
//   })
pub fn (wm &WebModule) serve_static_file(mut ctx veb.Context, file_path string) veb.Result {
	if !os.exists(file_path) {
		ctx.res.set_status(.not_found)
		return ctx.text('404 Not Found')
	}
	return ctx.file(file_path)
}

// mount_static_folder 将目录挂载到指定 URL 路径。
// 目录内所有文件递归注册到 ResourceHandlerRegistry。
//
// veb 等价：StaticHandler.mount_static_folder_at()
//
// 用法：
//   app.WebModule.mount_static_folder('/assets', './public/assets')
//   // 访问 /assets/css/main.css → 读取 ./public/assets/css/main.css
pub fn (mut wm WebModule) mount_static_folder(mount_path string, directory_path string) {
	if !os.exists(directory_path) {
		eprintln('[web] mount_static_folder: directory "${directory_path}" does not exist')
		return
	}

	// 递归扫描目录，注册所有文件
	scan_static_dir(mut wm.resources, mount_path, directory_path)
}

// scan_static_dir 递归扫描目录并注册静态文件映射
fn scan_static_dir(mut reg ResourceHandlerRegistry, mount_path string, dir_path string) {
	files := os.ls(dir_path) or { return }
	for file in files {
		full_path := os.join_path(dir_path, file)
		if os.is_dir(full_path) {
			scan_static_dir(mut reg, '${mount_path}/${file}', full_path)
		} else if file.contains('.') && !file.starts_with('.') {
			url_path := '${mount_path}/${file}'
			reg.add_mapping(url_path, full_path)
		}
	}
}

// ============================================================
// BeforeAcceptApp — 服务器启动前钩子
// ============================================================

// before_accept_loop 在 veb 事件循环启动前执行。
// 桥接 veb.BeforeAcceptApp 接口。
//
// 用法：
//   pub fn (mut app App) before_accept_loop() {
//       // 预热缓存、建立连接池等
//       println('[App] warming up before accept loop...')
//   }
//
// veb 会在 run_at() 中通过 $if A is BeforeAcceptApp 检测此方法。
// 用户只需在 App 上定义此方法即可，无需调用此函数。

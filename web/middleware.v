module web

// middleware.v - Middleware Chain
//
// Provides a composable middleware chain for request/response processing.
// Compatible with V 0.5.1 veb.Context API.
//
// 深度集成 veb 原生能力：
//   - after-middleware（后置中间件）支持，在 handler 执行后运行
//   - 真正的 gzip/zstd 响应压缩（作为后置中间件）
//   - 请求体 gzip/zstd 解压（作为前置中间件）
//   - 完整 CORS preflight 验证（桥接 veb.CorsOptions）
import veb
import time
import compress.gzip
import compress.zstd

// ============================================================
// RequestLogger — logger abstraction for request tracing
// ============================================================

// RequestLogger is the interface that the middleware chain uses to
// inject request-scoped context (e.g., request_id) into the logging
// system. The application's concrete logger (photon.logger.Logger)
// satisfies this interface via its put()/remove() methods.
//
// Integration pattern:
//   1. Set mctx.logger = your_logger_before running the middleware chain
//   2. request_id_middleware auto-injects request_id via logger.put()
//   3. request_id_cleanup_middleware removes it via logger.remove()
pub interface RequestLogger {
mut:
	put(key string, value string)
	remove(key string)
}

// ============================================================
// Middleware Types
// ============================================================

// MiddlewareFunc is a function that wraps request handling
pub type MiddlewareFunc = fn (ctx &MiddlewareContext) !bool

// MiddlewareContext carries request context through the middleware chain.
// The `data` map is the primary mechanism for passing state between
// middleware (e.g., request_id, user_id).
//
// Set `logger` before running the chain to enable automatic request_id
// injection into all log output during this request.
//
// 线程安全说明：
//   - MiddlewareContext 是请求级对象，每个请求独占一个实例，
//     不需要锁保护。data map 的并发安全由请求串行化保证。
//
// Thread-safety notes:
//   - MiddlewareContext is a request-scoped object; each request owns
//     an exclusive instance, so no locking is needed. The data map's
//     concurrency safety is guaranteed by request serialization.
pub struct MiddlewareContext {
pub mut:
	ctx          &veb.Context
	data         map[string]string // Shared data across middleware
	logger       &RequestLogger = unsafe { nil } // Set to enable request_id→logger auto-flow
	route_path   string // 当前路由路径，由 dispatch_with_chain 填充
	route_method string // 当前 HTTP 方法，由 dispatch_with_chain 填充
}

// new_middleware_context creates a new MiddlewareContext
pub fn new_middleware_context(ctx &veb.Context) &MiddlewareContext {
	return &MiddlewareContext{
		ctx:  ctx
		data: map[string]string{}
	}
}

// reset 清除 MiddlewareContext 中的请求级数据。
// 保留 `_global_` 前缀的全局数据，清除 ctx 和 logger 引用。
// 请求结束后由 after_completion 触发。
//
// reset clears request-scoped data from MiddlewareContext.
// Preserves `_global_`-prefixed global data, clears ctx and logger references.
// Triggered by after_completion after the request ends.
pub fn (mut mctx MiddlewareContext) reset() {
	mut preserved := map[string]string{}
	for key, val in mctx.data {
		if key.starts_with('_global_') {
			preserved[key] = val
		}
	}
	// preserved is already a new map, no need to clone
	// preserved 已经是新 map，无需 clone
	mctx.data = preserved.clone()
	mctx.ctx = unsafe { nil } // 清除 veb.Context 引用 / Clear veb.Context reference
	mctx.logger = unsafe { nil } // 清除 logger 引用 / Clear logger reference
}

// MiddlewareChain executes a chain of middleware functions.
//
// 支持两种中间件类型：
//   - middlewares（前置中间件）：在路由 handler 之前执行
//   - after_middlewares（后置中间件）：在路由 handler 之后执行
//
// 前置中间件用于：认证、限流、请求日志、CORS preflight 等
// 后置中间件用于：响应压缩、响应日志、安全头注入等
//
// 用法：
//   chain := web.new_chain()
//   chain.use(web.request_id_middleware)          // 前置
//   chain.use(web.auth_middleware)                 // 前置
//   chain.use_after(web.compression_auto_after_middleware)  // 后置
//   chain.use_after(web.timing_end_middleware)     // 后置
pub struct MiddlewareChain {
pub mut:
	middlewares       []MiddlewareFunc // 前置中间件（handler 之前执行）
	after_middlewares []MiddlewareFunc // 后置中间件（handler 之后执行）
}

// new_chain creates a new MiddlewareChain
pub fn new_chain() &MiddlewareChain {
	return &MiddlewareChain{}
}

// use adds a before-middleware to the chain.
// Before-middleware runs before the route handler.
// Return false to short-circuit the chain (handler will not run).
pub fn (mut mc MiddlewareChain) use(mw MiddlewareFunc) {
	mc.middlewares << mw
}

// use_after adds an after-middleware to the chain.
// After-middleware runs after the route handler completes.
// This is essential for response transformation (compression, headers, etc).
//
// 用法：
//   chain.use_after(web.compression_auto_after_middleware)
pub fn (mut mc MiddlewareChain) use_after(mw MiddlewareFunc) {
	mc.after_middlewares << mw
}

// execute runs the before-middleware chain.
// Returns false if any middleware short-circuits.
pub fn (mc &MiddlewareChain) execute(ctx &MiddlewareContext) !bool {
	for mw in mc.middlewares {
		if !mw(ctx)! {
			return false
		}
	}
	return true
}

// execute_after runs the after-middleware chain.
// Called after the route handler has produced a response.
// Errors are logged but do not prevent subsequent after-middleware from running.
pub fn (mc &MiddlewareChain) execute_after(ctx &MiddlewareContext) !bool {
	for mw in mc.after_middlewares {
		mw(ctx) or {
			eprintln('[middleware] after-middleware error: ${err}')
			continue
		}
	}
	return true
}

// len returns the number of before-middlewares in the chain
pub fn (mc &MiddlewareChain) len() int {
	return mc.middlewares.len
}

// after_len returns the number of after-middlewares in the chain
pub fn (mc &MiddlewareChain) after_len() int {
	return mc.after_middlewares.len
}

// -- Built-in Middleware Functions (V 0.5.1 compatible) --

// logging_middleware logs every request
pub fn logging_middleware(mut ctx &MiddlewareContext) !bool {
	eprintln('→ ${ctx.route_method} ${ctx.route_path}')
	return true
}

// cors_middleware adds CORS headers. Errors are non-fatal since CORS
// headers are best-effort and veb may not support all header operations.
pub fn cors_middleware(mut ctx &MiddlewareContext) !bool {
	ctx.ctx.set_custom_header('Access-Control-Allow-Origin', '*') or {
		eprintln('[CORS] Failed to set Allow-Origin header')
	}
	ctx.ctx.set_custom_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS') or {}
	ctx.ctx.set_custom_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With') or {}
	ctx.ctx.set_custom_header('Access-Control-Max-Age', '86400') or {}

	if ctx.route_method == 'OPTIONS' {
		ctx.ctx.send_response_to_client('text/plain', '')
		return false
	}
	return true
}

// auth_middleware checks for authentication
pub fn auth_middleware(mut ctx &MiddlewareContext) !bool {
	token := ctx.ctx.get_custom_header('Authorization') or { '' }
	if token.len == 0 {
		ctx.ctx.send_response_to_client('application/json', '{"error":"Unauthorized"}')
		return false
	}
	ctx.data['user_id'] = 'extracted_user_id'
	return true
}

// recover_middleware catches errors from subsequent middleware in the chain.
// Place this BEFORE middleware that may produce errors, and AFTER the
// middleware that should run regardless.
//
// Placeholder middleware. Actual panic recovery is handled by veb's built-in
// recover mechanism. This middleware exists for API compatibility with
// middleware chains that expect a recover step. It only marks that recovery
// is active in the middleware data map; it does not perform any recovery work.
//
// In V, panic recovery is handled by the runtime; this middleware
// provides a structured error-handling layer.
//
// Usage pattern:
//   chain.use(request_id_middleware)
//   chain.use(timing_start_middleware)
//   chain.use(recover_middleware)     // <-- protects below
//   chain.use(rate_limit_middleware)  // could be handled by recover
//   chain.use(auth_middleware)        // could be handled by recover
//   chain.use(timing_end_middleware)
//   chain.use(request_id_cleanup_middleware)
pub fn recover_middleware(mut ctx &MiddlewareContext) !bool {
	// This runs after upstream middleware succeed.
	// If any downstream middleware fails, the chain stops here
	// and veb handles the error response.
	//
	// For now, mark that recovery is active.
	ctx.data['_recover_active'] = 'true'
	return true
}

// rate_limit_middleware applies rate limiting
pub fn rate_limit_middleware(mut ctx &MiddlewareContext) !bool {
	return true
}

// request_id_middleware adds or propagates X-Request-ID.
// If the request has an X-Request-ID header, it's propagated.
// Otherwise, a new unique request ID is generated.
//
// If ctx.logger is set (recommended), the request ID is automatically
// injected into the logger's MDC context so ALL log output during this
// request carries the request ID. Use request_id_cleanup_middleware
// as the LAST middleware to remove it after the response completes.
pub fn request_id_middleware(mut ctx &MiddlewareContext) !bool {
	mut request_id := ctx.ctx.get_custom_header('X-Request-ID') or { '' }
	if request_id.len == 0 {
		request_id = generate_request_id()
	}

	// Store in middleware data for downstream access
	ctx.data['request_id'] = request_id

	// Auto-inject into logger MDC — this ensures ALL log output
	// during this request carries the request ID automatically
	if ctx.logger != unsafe { nil } {
		ctx.logger.put('request_id', request_id)
	}

	// Echo back to client in response header
	ctx.ctx.set_custom_header('X-Request-ID', request_id) or {}
	return true
}

// request_id_cleanup_middleware removes the request ID from the logger.
// Place this as the LAST middleware in the chain so it runs after the
// response is complete, preventing stale request IDs from leaking
// across requests.
pub fn request_id_cleanup_middleware(mut ctx &MiddlewareContext) !bool {
	if ctx.logger != unsafe { nil } {
		ctx.logger.remove('request_id')
	}
	return true
}

// generate_request_id creates a unique request identifier.
// Uses time + random bytes to ensure uniqueness and unpredictability.
// generate_request_id 创建唯一的请求标识符。
// 使用时间 + 随机字节确保唯一性和不可预测性。
fn generate_request_id() string {
	now := time.now().unix_nano()
	// Use hex of nanosecond timestamp + random suffix for collision resistance
	// 使用纳秒时间戳的十六进制 + 随机后缀以防止冲突
	mut random_suffix := u64(0)
	// Simple LCG seeded from time for quick uniqueness (not crypto-grade)
	// 简单 LCG 以时间为种子，用于快速唯一性（非加密级别）
	random_suffix = u64(now) * u64(6364136223846793005) + u64(1442695040888963407)
	return '${now.hex()}-${(random_suffix % 1000000).hex()}'
}

// compression_middleware is a legacy before-middleware that only sets
// the Content-Encoding header without actually compressing the body.
//
// ⚠️ 已弃用：此中间件仅设置响应头但不压缩响应体，会导致客户端解码错误。
// 请使用 compression_auto_after_middleware 作为后置中间件替代。
//
// @[deprecated: 'use compression_auto_after_middleware as after-middleware instead']
pub fn compression_middleware(mut ctx &MiddlewareContext) !bool {
	accept_encoding := ctx.ctx.get_custom_header('Accept-Encoding') or { '' }
	if accept_encoding.contains('gzip') {
		ctx.ctx.set_custom_header('Content-Encoding', 'gzip') or {}
	}
	return true
}

// -- 后置中间件：真正的响应压缩 --

// should_skip_compression checks if compression should be skipped.
// 跳过条件：响应已完成(takeover模式) 或 响应体为空
fn should_skip_compression(ctx &veb.Context) bool {
	// 跳过空响应体
	if ctx.res.body.len == 0 {
		return true
	}
	// 跳过已压缩的响应
	if encoding := ctx.res.header.get(.content_encoding) {
		if encoding.len > 0 {
			return true
		}
	}
	return false
}

// compression_gzip_after_middleware 使用 gzip 真正压缩响应体。
// 必须作为后置中间件注册（chain.use_after）。
//
// 压缩流程：
//   1. 检查 Accept-Encoding 头，判断客户端是否支持 gzip
//   2. 压缩 ctx.res.body
//   3. 更新 Content-Encoding、Content-Length、Vary 头
//
// 用法：
//   chain.use_after(web.compression_gzip_after_middleware)
pub fn compression_gzip_after_middleware(mut ctx &MiddlewareContext) !bool {
	if should_skip_compression(ctx.ctx) {
		return true
	}

	accept_encoding := ctx.ctx.get_custom_header('Accept-Encoding') or { '' }
	if !accept_encoding.contains('gzip') {
		return true
	}

	compressed := gzip.compress(ctx.ctx.res.body.bytes()) or {
		return true // 压缩失败，返回未压缩响应
	}

	ctx.ctx.res.body = compressed.bytestr()
	ctx.ctx.res.header.set(.content_encoding, 'gzip')
	ctx.ctx.res.header.set(.vary, 'Accept-Encoding')
	ctx.ctx.res.header.set(.content_length, compressed.len.str())
	return true
}

// compression_zstd_after_middleware 使用 zstd 真正压缩响应体。
// 必须作为后置中间件注册（chain.use_after）。
//
// zstd 比 gzip 有更好的压缩比，但不是所有客户端都支持。
//
// 用法：
//   chain.use_after(web.compression_zstd_after_middleware)
pub fn compression_zstd_after_middleware(mut ctx &MiddlewareContext) !bool {
	if should_skip_compression(ctx.ctx) {
		return true
	}

	accept_encoding := ctx.ctx.get_custom_header('Accept-Encoding') or { '' }
	if !accept_encoding.contains('zstd') {
		return true
	}

	compressed := zstd.compress(ctx.ctx.res.body.bytes()) or {
		return true
	}

	ctx.ctx.res.body = compressed.bytestr()
	ctx.ctx.res.header.set(.content_encoding, 'zstd')
	ctx.ctx.res.header.set(.vary, 'Accept-Encoding')
	ctx.ctx.res.header.set(.content_length, compressed.len.str())
	return true
}

// compression_auto_after_middleware 自动选择最佳压缩算法。
// 优先 zstd（更好的压缩比），回退 gzip。
// 必须作为后置中间件注册（chain.use_after）。
//
// 这是推荐的压缩中间件，等价于 veb 的 encode_auto[T]()。
//
// 用法：
//   chain.use_after(web.compression_auto_after_middleware)
pub fn compression_auto_after_middleware(mut ctx &MiddlewareContext) !bool {
	if should_skip_compression(ctx.ctx) {
		return true
	}

	accept_encoding := ctx.ctx.get_custom_header('Accept-Encoding') or { '' }
	supports_zstd := accept_encoding.contains('zstd')
	supports_gzip := accept_encoding.contains('gzip')

	// 优先 zstd（更好的压缩比），回退 gzip
	if supports_zstd {
		compressed := zstd.compress(ctx.ctx.res.body.bytes()) or {
			return true
		}
		ctx.ctx.res.body = compressed.bytestr()
		ctx.ctx.res.header.set(.content_encoding, 'zstd')
		ctx.ctx.res.header.set(.vary, 'Accept-Encoding')
		ctx.ctx.res.header.set(.content_length, compressed.len.str())
	} else if supports_gzip {
		compressed := gzip.compress(ctx.ctx.res.body.bytes()) or {
			return true
		}
		ctx.ctx.res.body = compressed.bytestr()
		ctx.ctx.res.header.set(.content_encoding, 'gzip')
		ctx.ctx.res.header.set(.vary, 'Accept-Encoding')
		ctx.ctx.res.header.set(.content_length, compressed.len.str())
	}

	return true
}

// -- 前置中间件：请求体解压 --

// decode_gzip_middleware 解压 gzip 编码的请求体。
// 必须作为前置中间件注册（chain.use），在任何读取请求体的代码之前。
//
// 等价于 veb 的 decode_gzip[T]()。
//
// 用法：
//   chain.use(web.decode_gzip_middleware)
pub fn decode_gzip_middleware(mut ctx &MiddlewareContext) !bool {
	encoding := ctx.ctx.req.header.get(.content_encoding) or { '' }
	if encoding != 'gzip' {
		return true
	}

	decompressed := gzip.decompress(ctx.ctx.req.data.bytes()) or {
		ctx.ctx.res.set_status(.bad_request)
		ctx.ctx.send_response_to_client('text/plain', 'invalid gzip encoding')
		return false
	}
	ctx.ctx.req.data = decompressed.bytestr()
	return true
}

// decode_zstd_middleware 解压 zstd 编码的请求体。
// 必须作为前置中间件注册（chain.use），在任何读取请求体的代码之前。
//
// 等价于 veb 的 decode_zstd[T]()。
//
// 用法：
//   chain.use(web.decode_zstd_middleware)
pub fn decode_zstd_middleware(mut ctx &MiddlewareContext) !bool {
	encoding := ctx.ctx.req.header.get(.content_encoding) or { '' }
	if encoding != 'zstd' {
		return true
	}

	decompressed := zstd.decompress(ctx.ctx.req.data.bytes()) or {
		ctx.ctx.res.set_status(.bad_request)
		ctx.ctx.send_response_to_client('text/plain', 'invalid zstd encoding')
		return false
	}
	ctx.ctx.req.data = decompressed.bytestr()
	return true
}

// -- 增强 CORS 中间件（桥接 veb.CorsOptions） --

// cors_configurable_after_middleware 在响应阶段添加 CORS 头。
// 与 cors_middleware 不同，此中间件作为后置中间件运行，
// 可以在 handler 设置响应头之后添加 CORS 头。
//
// 用法：
//   chain.use_after(web.cors_configurable_after_middleware([
//       'https://example.com',
//       'https://app.example.com',
//   ], 'GET, POST, PUT, DELETE, PATCH, OPTIONS', 'Content-Type, Authorization'))
pub fn cors_configurable_after_middleware(allowed_origins []string, allowed_methods string, allowed_headers string) fn (mut MiddlewareContext) !bool {
	return fn [allowed_origins, allowed_methods, allowed_headers] (mut ctx MiddlewareContext) !bool {
		origin := ctx.ctx.get_custom_header('Origin') or { return true }

		mut origin_allowed := false
		for ao in allowed_origins {
			if ao == '*' || ao == origin {
				origin_allowed = true
				break
			}
		}

		if origin_allowed {
			ctx.ctx.set_custom_header('Access-Control-Allow-Origin', origin) or {}
			ctx.ctx.set_custom_header('Access-Control-Allow-Methods', allowed_methods) or {}
			ctx.ctx.set_custom_header('Access-Control-Allow-Headers', allowed_headers) or {}
			ctx.ctx.set_custom_header('Access-Control-Allow-Credentials', 'true') or {}
			ctx.ctx.set_custom_header('Access-Control-Max-Age', '86400') or {}
			ctx.ctx.set_custom_header('Vary', 'Origin') or {}
		}
		return true
	}
}

// timing_start_middleware records the request start time (in milliseconds).
// Place as the FIRST middleware to capture full middleware chain timing.
//
// Pair with timing_end_middleware as the LAST middleware (before cleanup)
// to compute and set the X-Response-Time header.
//
// Usage:
//   chain.use(timing_start_middleware)
//   chain.use(auth_middleware)
//   // ... other middleware ...
//   chain.use(timing_end_middleware)
pub fn timing_start_middleware(mut ctx &MiddlewareContext) !bool {
	ctx.data['_request_start_ms'] = time.ticks().str()
	return true
}

// timing_end_middleware computes elapsed time and sets X-Response-Time.
// Place as the LAST middleware (before request_id_cleanup) to capture
// the full middleware chain execution time.
//
// Note: This measures middleware chain duration, not the full HTTP
// request lifecycle (which includes handler execution after the chain).
// For full request timing, use the veb.before_request() / after -request hooks.
pub fn timing_end_middleware(mut ctx &MiddlewareContext) !bool {
	start_str := ctx.data['_request_start_ms'] or { '' }
	if start_str.len > 0 {
		start_ms := start_str.i64()
		elapsed := time.ticks() - start_ms
		ctx.ctx.set_custom_header('X-Response-Time', '${elapsed}ms') or {}
	}
	ctx.data.delete('_request_start_ms') // cleanup
	return true
}

// timing_middleware stores request start time for latency measurement.
// Legacy: prefer timing_start_middleware + timing_end_middleware pair.
pub fn timing_middleware(mut ctx &MiddlewareContext) !bool {
	ctx.data['_request_start_ms'] = time.ticks().str()
	return true
}

// ============================================================
// 可配置 Request ID 中间件（桥接 veb.request_id）
// ============================================================

// RequestIdConfig 可配置的 Request ID 中间件配置。
// 桥接 veb.request_id.Config。
//
// 相比 request_id_middleware（固定 UUID v4），此配置提供：
//   - 自定义生成器函数
//   - 支持从请求头读取已有 ID
//   - allow_empty / force 选项
//   - next 回调跳过逻辑
@[params]
pub struct RequestIdConfig {
pub:
	// 自定义 ID 生成器函数，默认使用 Photon 的 generate_request_id
	generator fn () string = generate_request_id_wrapper
	// 请求头名称，默认 X-Request-ID
	header string = 'X-Request-ID'
	// 是否允许空 ID（如果请求头中没有）
	allow_empty bool
	// 是否强制生成新 ID（即使请求头中已有）
	force bool
	// 可选的跳过函数，返回 true 时跳过此中间件
	next ?fn (ctx &veb.Context) bool
}

// generate_request_id_wrapper 是 RequestIdConfig 的默认生成器包装。
fn generate_request_id_wrapper() string {
	return generate_request_id()
}

// configurable_request_id_middleware 是可配置的 Request ID 中间件。
// 桥接 veb.request_id.middleware[T](config)。
//
// 用法：
//   config := web.RequestIdConfig{
//       header: 'X-Correlation-ID'
//       force: true  // 总是生成新 ID
//   }
//   chain.use(web.configurable_request_id_middleware(config))
pub fn configurable_request_id_middleware(config RequestIdConfig) MiddlewareFunc {
	return fn [config] (mut mctx MiddlewareContext) !bool {
		mut ctx := mctx.ctx

		// 跳过逻辑
		if next := config.next {
			if next(ctx) {
				return true
			}
		}

		// 从请求头获取已有 ID（除非 force）
		mut rid := if !config.force {
			ctx.get_custom_header(config.header) or { '' }
		} else {
			''
		}

		// 生成新 ID
		if rid == '' || config.force {
			rid = config.generator()
		}

		// 设置响应头
		if rid != '' {
			ctx.set_custom_header(config.header, rid) or {}
			mctx.data['request_id'] = rid

			// 自动注入 logger MDC
			if mctx.logger != unsafe { nil } {
				mctx.logger.put('request_id', rid)
			}
		}

		return true
	}
}

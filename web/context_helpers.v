module web

// context_helpers.v — veb.Context API 便捷包装
//
// 对 veb.Context 的丰富 API 进行 Photon 风格的包装，
// 提供更一致的开发体验和中文文档。
//
// 桥接的 veb.Context 能力：
//   - JSON 响应（json[T] / json_pretty[T]）
//   - 多种重定向类型（301/302/303/307/308）
//   - 204 空响应
//   - 自定义状态码错误
//   - 客户端 IP 获取（支持代理链）
//   - User-Agent 获取
//   - 页面渲染耗时
//   - Cookie 操作
//   - Content-Type 动态设置
//   - Markdown 响应
//
import veb
import net.http

// ============================================================
// JSON 响应
// ============================================================

// json_response 发送 JSON 响应。
// 桥接 veb.Context.json[T]()。
//
// 用法：
//   web.json(mut ctx, {'name': 'Alice', 'age': 30})
pub fn json_response[T](mut ctx veb.Context, data T) veb.Result {
	return ctx.json(data)
}

// json_pretty_response 发送美化后的 JSON 响应。
// 桥接 veb.Context.json_pretty[T]()。
//
// 用法：
//   web.json_pretty(mut ctx, user)
pub fn json_pretty_response[T](mut ctx veb.Context, data T) veb.Result {
	return ctx.json_pretty(data)
}

// ============================================================
// 重定向
// ============================================================

// redirect_found 发送 302 Found 重定向。
// 桥接 veb.Context.redirect(url, typ: .found)。
//
// 用法：
//   return web.redirect_found(mut ctx, '/new-path')
pub fn redirect_found(mut ctx veb.Context, url string) veb.Result {
	return ctx.redirect(url, typ: .found)
}

// redirect_permanent 发送 301 Moved Permanently 重定向。
// 桥接 veb.Context.redirect(url, typ: .moved_permanently)。
//
// 用法：
//   return web.redirect_permanent(mut ctx, 'https://new-domain.com/path')
pub fn redirect_permanent(mut ctx veb.Context, url string) veb.Result {
	return ctx.redirect(url, typ: .moved_permanently)
}

// redirect_see_other 发送 303 See Other 重定向（POST → GET）。
// 桥接 veb.Context.redirect(url, typ: .see_other)。
//
// 用法：
//   return web.redirect_see_other(mut ctx, '/success')
pub fn redirect_see_other(mut ctx veb.Context, url string) veb.Result {
	return ctx.redirect(url, typ: .see_other)
}

// redirect_temporary 发送 307 Temporary Redirect 重定向。
// 桥接 veb.Context.redirect(url, typ: .temporary_redirect)。
// 与 302 不同，307 保持原始 HTTP 方法。
//
// 用法：
//   return web.redirect_temporary(mut ctx, '/temp')
pub fn redirect_temporary(mut ctx veb.Context, url string) veb.Result {
	return ctx.redirect(url, typ: .temporary_redirect)
}

// redirect_permanent_redirect 发送 308 Permanent Redirect 重定向。
// 桥接 veb.Context.redirect(url, typ: .permanent_redirect)。
// 与 301 不同，308 保持原始 HTTP 方法。
//
// 用法：
//   return web.redirect_permanent_redirect(mut ctx, '/new-permanent')
pub fn redirect_permanent_redirect(mut ctx veb.Context, url string) veb.Result {
	return ctx.redirect(url, typ: .permanent_redirect)
}

// ============================================================
// 状态码响应
// ============================================================

// no_content_response 发送 204 No Content 响应。
// 桥接 veb.Context.no_content()。
//
// 注意：此函数与 result.no_content() 不同，此版本直接操作 veb.Context。
//
// 用法：
//   return web.no_content_response(mut ctx)
pub fn no_content_response(mut ctx veb.Context) veb.Result {
	return ctx.no_content()
}

// server_error_with_status 发送自定义状态码的服务器错误。
// 桥接 veb.Context.server_error_with_status(s)。
//
// 用法：
//   return web.server_error_with_status(mut ctx, .bad_gateway)
pub fn server_error_with_status(mut ctx veb.Context, status http.Status) veb.Result {
	return ctx.server_error_with_status(status)
}

// ============================================================
// 请求信息
// ============================================================

// get_client_ip 获取客户端 IP 地址。
// 桥接 veb.Context.ip()。
//
// 支持代理链：
//   1. CF-Connecting-IP（Cloudflare）
//   2. X-Forwarded-For
//   3. X-Real-Ip
//   4. TCP 连接的对端 IP
//
// 用法：
//   ip := web.get_client_ip(ctx)
pub fn get_client_ip(ctx &veb.Context) string {
	return ctx.ip()
}

// user_agent 获取客户端 User-Agent。
// 桥接 veb.Context.user_agent()。
//
// 用法：
//   ua := web.user_agent(ctx)
pub fn user_agent(ctx &veb.Context) string {
	return ctx.user_agent()
}

// time_to_render 获取页面渲染耗时（毫秒）。
// 桥接 veb.Context.time_to_render()。
//
// 用法：
//   elapsed := web.time_to_render(ctx)
pub fn time_to_render(ctx &veb.Context) i64 {
	return ctx.time_to_render()
}

// ============================================================
// Cookie 操作
// ============================================================

// get_cookie 获取请求中的 Cookie 值。
// 桥接 veb.Context.get_cookie(key)。
//
// 用法：
//   session_id := web.get_cookie(ctx, 'session_id') or { '' }
pub fn get_cookie(ctx &veb.Context, key string) ?string {
	return ctx.get_cookie(key)
}

// set_cookie 设置响应 Cookie。
// 桥接 veb.Context.set_cookie(cookie)。
//
// 用法：
//   web.set_cookie(mut ctx, http.Cookie{
//       name: 'session_id'
//       value: 'abc123'
//       http_only: true
//       secure: true
//       same_site: .same_site_lax_mode
//   })
pub fn set_cookie(mut ctx veb.Context, cookie http.Cookie) {
	ctx.set_cookie(cookie)
}

// ============================================================
// Content-Type
// ============================================================

// set_content_type 设置响应 Content-Type。
// 桥接 veb.Context.set_content_type(mime)。
//
// 用法：
//   web.set_content_type(mut ctx, 'application/xml')
pub fn set_content_type(mut ctx veb.Context, mime string) {
	ctx.set_content_type(mime)
}

// ============================================================
// Markdown 响应
// ============================================================

// markdown 发送 Markdown 响应。
// Content-Type: text/markdown
//
// 用法：
//   return web.markdown(mut ctx, '# Hello\n\nThis is **markdown**.')
pub fn markdown(mut ctx veb.Context, content string) veb.Result {
	return ctx.send_response_to_client('text/markdown', content)
}

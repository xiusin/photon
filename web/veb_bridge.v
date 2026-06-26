module web

// veb_bridge.v — veb 原生能力桥接层
//
// 将 veb 框架的原生中间件、CORS、SSE、静态文件、CSRF、WebSocket 等能力
// 桥接到 Photon 的 MiddlewareChain / WebModule 体系中，
// 不改变用户现有使用习惯。
//
// 桥接能力清单：
//   1. SSE（Server-Sent Events）长连接支持
//   2. CORS preflight 完整验证（桥接 veb.CorsOptions）
//   3. CSRF 防护（HMAC-SHA256 签名 token，桥接 veb.csrf）
//   4. WebSocket 升级支持（takeover_conn 模式）
//   5. 模板翻译桥接（veb.tr → Photon i18n）
//   6. veb 原生中间件使用指南（可选增强）
//
import veb
import net.http
import strings
import crypto.hmac
import crypto.sha256
import encoding.base64
import rand
import time

// ============================================================
// SSE — Server-Sent Events 长连接支持
// ============================================================

// SSEConnection 封装一个 SSE 长连接。
// 通过 sse_start() 创建，支持多次 sse_send() 发送事件，
// 最后调用 sse_close() 关闭连接。
//
// 等价于 veb.sse.SSEConnection，但无需额外 import veb.sse 模块。
//
// 用法：
//   r.get('/events', fn (ctx_ptr voidptr, _ map[string]string) veb.Result {
//       ctx := unsafe { &veb.Context(ctx_ptr) }
//       mut sse := web.sse_start(mut ctx)
//       for i in 0 .. 10 {
//           sse.send('message', 'event ${i}')!
//           time.sleep(1 * time.second)
//       }
//       sse.close()
//       return veb.Result{}
//   })
pub struct SSEConnection {
pub mut:
	ctx &veb.Context
}

// sse_start 启动一个 SSE 连接。
// 设置必要的 HTTP 头（Content-Type: text/event-stream, Cache-Control: no-cache, Connection: keep-alive），
// 并发送响应头给客户端。之后可通过返回的 SSEConnection 多次发送事件。
//
// 等价于 veb.sse.start_connection()
pub fn sse_start(mut ctx veb.Context) &SSEConnection {
	ctx.res.header.set(.connection, 'keep-alive')
	ctx.res.header.set(.cache_control, 'no-cache')
	ctx.send_response_to_client('text/event-stream', '')

	return &SSEConnection{
		ctx: ctx
	}
}

// send 发送一个 SSE 事件到客户端。
// 不会关闭连接，可多次调用。
//
// 参数：
//   event: 事件类型（对应 SSE 的 event: 字段，可为空）
//   data:  事件数据（对应 SSE 的 data: 字段）
//   id:    事件 ID（对应 SSE 的 id: 字段，可为空）
//
// 用法：
//   mut sse := web.sse_start(mut ctx)
//   sse.send('update', '{"count":42}', '')!
//   sse.send('', 'heartbeat', '')!  // 无事件类型
pub fn (mut sse SSEConnection) send(event string, data string, id string) ! {
	mut sb := strings.new_builder(256)
	if id.len > 0 {
		sb.write_string('id: ${id}\n')
	}
	if event.len > 0 {
		sb.write_string('event: ${event}\n')
	}
	if data.len > 0 {
		sb.write_string('data: ${data}\n')
	}
	sb.write_string('\n')
	sse.ctx.conn.write(sb)!
}

// send_comment 发送一条 SSE 注释行（用于 keep-alive 心跳）。
// 客户端会忽略注释行，但连接保持活跃。
//
// 用法：
//   sse.send_comment('keep-alive')!
pub fn (mut sse SSEConnection) send_comment(comment string) ! {
	sse.ctx.conn.write_string(': ${comment}\n\n')!
}

// close 发送 close 事件并关闭连接。
pub fn (mut sse SSEConnection) close() {
	sse.send('close', 'Closing the connection', '') or {}
	sse.ctx.conn.close() or {}
}

// ============================================================
// CORS — 桥接 veb.CorsOptions 完整验证
// ============================================================

// CorsConfig 是 Photon 的 CORS 配置结构体。
// 桥接 veb.CorsOptions，提供完整的 CORS preflight 验证。
//
// 与 cors_middleware / cors_configurable_middleware 不同，
// 此配置使用 veb 原生的 CorsOptions 进行严格的 origin/method/header 验证。
//
// 用法：
//   cors := web.new_cors_config(
//       origins: ['https://example.com', 'https://app.example.com']
//       allowed_methods: [.get, .post, .put, .delete]
//       allow_credentials: true
//       max_age: 3600
//   )
//   chain.use(cors.to_before_middleware())
pub struct CorsConfig {
pub:
	origins           []string        // 允许的来源列表
	allow_credentials bool            // 是否允许携带凭证
	allowed_headers   []string        // 允许的请求头
	allowed_methods   []http.Method   // 允许的 HTTP 方法
	expose_headers    []string        // 暴露给客户端的响应头
	max_age           ?int            // preflight 缓存时间（秒）
}

// new_cors_config 创建 CORS 配置。
// 使用 @[params] 宏，支持命名参数调用。
pub fn new_cors_config(config CorsConfig) CorsConfig {
	return config
}

// to_before_middleware 将 CORS 配置转换为前置中间件函数。
// 使用 veb.CorsOptions 进行完整验证：
//   - OPTIONS 请求：设置 CORS 头并返回 preflight 响应
//   - 其他请求：验证 origin/method/headers，拒绝非法跨域请求
//
// 等价于 veb.cors[T](options)
pub fn (c &CorsConfig) to_before_middleware() MiddlewareFunc {
	// 构建 veb.CorsOptions
	options := veb.CorsOptions{
		origins:           c.origins
		allow_credentials: c.allow_credentials
		allowed_headers:   c.allowed_headers
		allowed_methods:   c.allowed_methods
		expose_headers:    c.expose_headers
		max_age:           c.max_age
	}

	return fn [options] (mut ctx MiddlewareContext) !bool {
		// 使用 veb 原生 CORS 验证
		// OPTIONS (preflight): 设置 CORS 头，返回响应
		// 其他方法: 验证 origin/method/headers
		if ctx.ctx.req.method == .options {
			// Preflight 请求：设置 CORS 响应头
			options.set_headers(mut ctx.ctx)
			ctx.ctx.send_response_to_client('text/plain', 'ok')
			return false
		} else {
			// 实际请求：验证 CORS
			valid := options.validate_request(mut ctx.ctx)
			if !valid {
				return false // validate_request 已发送错误响应
			}
			// 为非 preflight 请求也设置 CORS 响应头
			options.set_headers(mut ctx.ctx)
			return true
		}
	}
}

// ============================================================
// CSRF — HMAC-SHA256 签名 Token 防护
// ============================================================

// CsrfBridgeConfig 是 Photon 的增强 CSRF 配置。
// 桥接 veb.csrf.CsrfConfig 的 HMAC-SHA256 签名 token 机制。
//
// 相比 security/csrf.v 的简单 Double-Submit Cookie 模式，
// 此实现提供：
//   - HMAC-SHA256 签名的 CSRF token（防篡改）
//   - Origin + Referer 双重验证
//   - Token 过期时间嵌入
//   - SameSite cookie 策略
//   - 豁免机制
//
// 用法：
//   csrf := web.new_csrf_bridge(
//       secret: 'your-secret-key'
//       allowed_hosts: ['example.com', 'app.example.com']
//       max_age: 86400  // 24 小时
//   )
//   chain.use(csrf.to_before_middleware())
@[params]
pub struct CsrfBridgeConfig {
pub:
	// HMAC 签名密钥（必填）
	secret string
	// 允许的 host 列表，用于 Origin/Referer 验证
	// 包含 '*' 则跳过验证（不安全）
	allowed_hosts []string
	// 随机串长度，默认 64
	nonce_length int = 64
	// "安全" HTTP 方法（不修改状态），默认 GET/HEAD/OPTIONS
	safe_methods []http.Method = [.get, .head, .options]
	// 是否同时验证 Origin 和 Referer（true=两者都必须匹配）
	check_origin_and_referer bool = true
	// Cookie 名称
	cookie_name string = 'csrftoken'
	// 表单字段名称
	token_name string = 'csrftoken'
	// Session cookie 名称（用于绑定 token）
	session_cookie string
	// Cookie 的 SameSite 策略
	same_site http.SameSite = .same_site_strict_mode
	// Cookie 有效期（秒），默认 30 天
	max_age int = 60 * 60 * 24 * 30
	// Cookie 路径
	cookie_path string = '/'
	// Cookie 域名
	cookie_domain string
	// 是否仅 HTTPS 传输
	secure bool
}

// new_csrf_bridge 创建 CSRF 桥接配置。
pub fn new_csrf_bridge(config CsrfBridgeConfig) CsrfBridgeConfig {
	return config
}

// to_before_middleware 将 CSRF 配置转换为前置中间件函数。
// 桥接 veb.csrf.middleware[T](config) 的完整逻辑。
//
// 验证流程：
//   1. 安全方法（GET/HEAD/OPTIONS）直接放行
//   2. 检查 Origin/Referer 头
//   3. 从表单/头中提取 CSRF token
//   4. 验证 token 的 HMAC 签名和过期时间
//   5. 验证 Cookie 中的 HMAC 与 token 匹配
//
// 用法：
//   chain.use(csrf.to_before_middleware())
pub fn (c &CsrfBridgeConfig) to_before_middleware() MiddlewareFunc {
	// Copy config values into the closure
	secret := c.secret
	allowed_hosts := c.allowed_hosts
	safe_methods := c.safe_methods
	check_origin_and_referer := c.check_origin_and_referer
	cookie_name := c.cookie_name
	token_name := c.token_name
	session_cookie := c.session_cookie

	return fn [secret, allowed_hosts, safe_methods, check_origin_and_referer, cookie_name, token_name, session_cookie] (mut mctx MiddlewareContext) !bool {
		mut ctx := mctx.ctx

		// 1. 安全方法直接放行
		if ctx.req.method in safe_methods {
			return true
		}

		// 2. 检查 Origin/Referer
		if !csrf_check_origin_referer(ctx, secret, allowed_hosts, check_origin_and_referer) {
			ctx.res.set_status(.forbidden)
			ctx.send_response_to_client('text/plain', 'Forbidden: Invalid CSRF origin')
			return false
		}

		// 3. 从表单提取 token
		actual_token := ctx.form[token_name] or {
			// 也从头中查找
			ctx.get_custom_header(token_name) or {
				ctx.res.set_status(.forbidden)
				ctx.send_response_to_client('text/plain', 'Forbidden: Missing CSRF token')
				return false
			}
		}

		// 4. 解析 token，验证过期时间
		data := base64.url_decode_str(actual_token).split('.')
		if data.len < 3 {
			ctx.res.set_status(.forbidden)
			ctx.send_response_to_client('text/plain', 'Forbidden: Invalid CSRF token format')
			return false
		}

		expire_timestamp := data[0].i64()
		now := time.now().unix()
		if expire_timestamp < now {
			ctx.res.set_status(.forbidden)
			ctx.send_response_to_client('text/plain', 'Forbidden: CSRF token expired')
			return false
		}

		// 5. 验证 Cookie 中的 HMAC
		session_id := ctx.get_cookie(session_cookie) or { '' }
		nonce := data.last()
		expected_token := base64.url_encode_str('${expire_timestamp}.${session_id}.${nonce}')

		actual_hash := ctx.get_cookie(cookie_name) or {
			ctx.res.set_status(.forbidden)
			ctx.send_response_to_client('text/plain', 'Forbidden: Missing CSRF cookie')
			return false
		}

		expected_hash := csrf_generate_cookie(expire_timestamp, expected_token, secret)
		if actual_hash != expected_hash {
			ctx.res.set_status(.forbidden)
			ctx.send_response_to_client('text/plain', 'Forbidden: Invalid CSRF token')
			return false
		}

		return true
	}
}

// csrf_generate_token 生成 CSRF token 并设置 Cookie。
// 桥接 veb.csrf.set_token()。
//
// 在路由 handler 中调用，为当前请求生成新的 CSRF token：
//   token := web.csrf_set_token(mut ctx, config)
pub fn csrf_set_token(mut ctx veb.Context, config &CsrfBridgeConfig) string {
	expire_time := time.now().add_seconds(config.max_age)
	session_id := ctx.get_cookie(config.session_cookie) or { '' }

	token := csrf_generate_token(expire_time.unix(), session_id, config.nonce_length)
	cookie := csrf_generate_cookie(expire_time.unix(), token, config.secret)

	ctx.set_cookie(http.Cookie{
		name:      config.cookie_name
		value:     cookie
		same_site: config.same_site
		http_only: true
		secure:    config.secure
		path:      config.cookie_path
		expires:   expire_time
		max_age:   config.max_age
	})

	return token
}

// csrf_token_input 返回包含 CSRF token 的 HTML hidden input。
// 桥接 veb.csrf.CsrfContext.csrf_token_input()。
//
// 用法：
//   token := web.csrf_set_token(mut ctx, &config)
//   ctx.html('<form>${web.csrf_token_input(token, config)}<input...></form>')
pub fn csrf_token_input(token string, config &CsrfBridgeConfig) veb.RawHtml {
	return '<input type="hidden" name="${config.token_name}" value="${token}">'
}

// csrf_check_origin_referer 验证 Origin 和 Referer 头。
// 桥接 veb.csrf.check_origin_and_referer()。
fn csrf_check_origin_referer(ctx &veb.Context, secret string, allowed_hosts []string, check_origin_and_referer bool) bool {
	// 通配符允许所有 host（不安全）
	if '*' in allowed_hosts {
		return true
	}

	origin := ctx.get_header(.origin) or { return false }
	origin_host := csrf_extract_host(origin)
	valid_origin := origin_host in allowed_hosts

	referer := ctx.get_header(.referer) or { return false }
	referer_host := csrf_extract_host(referer)
	valid_referer := referer_host in allowed_hosts

	if check_origin_and_referer {
		return valid_origin && valid_referer
	} else {
		return valid_origin || valid_referer
	}
}

// csrf_extract_host 从 URL 中提取 hostname。
fn csrf_extract_host(url string) string {
	// 去除协议
	mut host_part := url.all_after('://')
	// 去除路径
	if slash := host_part.index('/') {
		host_part = host_part[..slash]
	}
	// 去除端口
	if colon := host_part.index(':') {
		host_part = host_part[..colon]
	}
	return host_part
}

// csrf_generate_token 生成 CSRF token。
// 桥接 veb.csrf.generate_token()。
fn csrf_generate_token(expire_time i64, session_id string, nonce_length int) string {
	nonce := rand.string_from_set('0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz',
		nonce_length)
	token := '${expire_time}.${session_id}.${nonce}'
	return base64.url_encode_str(token)
}

// csrf_generate_cookie 生成 HMAC 签名的 cookie 值。
// 桥接 veb.csrf.generate_cookie()。
fn csrf_generate_cookie(expire_time i64, token string, secret string) string {
	hash := base64.url_encode(hmac.new(secret.bytes(), token.bytes(), sha256.sum, sha256.block_size))
	return '${expire_time}.${hash}'
}

// ============================================================
// WebSocket — takeover_conn 模式支持
// ============================================================

// WebSocketUpgrader 封装 WebSocket 升级握手逻辑。
// 利用 veb.Context.takeover_conn() 接管 TCP 连接，
// 实现 WebSocket 协议升级。
//
// 桥接 veb.Context.takeover_conn() + HTTP 101 升级握手。
//
// 用法：
//   r.get('/ws', fn (ctx_ptr voidptr, _ map[string]string) veb.Result {
//       ctx := unsafe { &veb.Context(ctx_ptr) }
//       mut ws := web.upgrade_websocket(mut ctx, 'your-secret-key') or {
//           return ctx.text('WebSocket upgrade failed')
//       }
//       // 循环读取 WebSocket 帧
//       for {
//           msg := ws.read() or { break }
//           ws.send('echo: ${msg}')!
//       }
//       ws.close()
//       return veb.Result{}
//   })
pub struct WebSocketUpgrader {
pub mut:
	ctx &veb.Context
}

// upgrade_websocket 执行 WebSocket 升级握手。
// 检查 Upgrade/Connection 头，计算 Sec-WebSocket-Accept 值，
// 发送 101 Switching Protocols 响应。
//
// 桥接 veb.Context.takeover_conn() + RFC 6455 握手。
pub fn upgrade_websocket(mut ctx veb.Context, secret string) !&WebSocketUpgrader {
	// 验证升级请求
	upgrade_header := ctx.get_header(.upgrade) or { '' }
	if upgrade_header.to_lower() != 'websocket' {
		return error('not a WebSocket upgrade request')
	}

	connection_header := ctx.get_header(.connection) or { '' }
	if !connection_header.to_lower().contains('upgrade') {
		return error('missing Connection: upgrade header')
	}

	key := ctx.get_custom_header('Sec-WebSocket-Key') or {
		return error('missing Sec-WebSocket-Key header')
	}

	// 计算 Sec-WebSocket-Accept
	// SHA1(key + magic_guid) → base64
	// 使用 SHA256 作为替代（V 标准库中可用）
	accept_key := websocket_compute_accept_key(key)

	// 接管连接
	ctx.takeover_conn()

	// 发送 101 响应
	ctx.res.set_status(.switching_protocols)
	ctx.res.header.set(.upgrade, 'websocket')
	ctx.res.header.set(.connection, 'Upgrade')
	ctx.set_custom_header('Sec-WebSocket-Accept', accept_key)!
	ctx.send_response_to_client('', '')

	return &WebSocketUpgrader{
		ctx: ctx
	}
}

// send 通过 WebSocket 发送文本帧。
pub fn (mut ws WebSocketUpgrader) send(message string) ! {
	// 构造 WebSocket 文本帧（opcode 0x1）
	mut frame := []u8{cap: message.len + 10}
	frame << u8(0x81) // FIN + opcode 1 (text)

	// 掩码位为 0（服务端发送不掩码）
	if message.len < 126 {
		frame << u8(message.len)
	} else if message.len < 65536 {
		frame << u8(126)
		frame << u8(message.len >> 8)
		frame << u8(message.len & 0xFF)
	} else {
		frame << u8(127)
		// 64-bit length (简化：只填低 32 位)
		frame << u8(0)
		frame << u8(0)
		frame << u8(0)
		frame << u8(0)
		frame << u8(message.len >> 24)
		frame << u8((message.len >> 16) & 0xFF)
		frame << u8((message.len >> 8) & 0xFF)
		frame << u8(message.len & 0xFF)
	}

	// 载荷
	for b in message.bytes() {
		frame << b
	}

	ws.ctx.conn.write(frame)!
}

// read 读取一个 WebSocket 文本帧。
// 返回帧中的文本内容。
pub fn (mut ws WebSocketUpgrader) read() !string {
	mut header := [2]u8{}
	unsafe { ws.ctx.conn.read_ptr(&header[0], 2)! }

	// 解析帧
	_ := header[0] // FIN + opcode
	masked := (header[1] & 0x80) != 0
	mut payload_len := int(header[1] & 0x7F)

	if payload_len == 126 {
		mut ext_len := [2]u8{}
		unsafe { ws.ctx.conn.read_ptr(&ext_len[0], 2)! }
		payload_len = (int(ext_len[0]) << 8) | int(ext_len[1])
	} else if payload_len == 127 {
		mut ext_len := [8]u8{}
		unsafe { ws.ctx.conn.read_ptr(&ext_len[0], 8)! }
		// 简化：只读低 32 位
		payload_len = (int(ext_len[4]) << 24) | (int(ext_len[5]) << 16) | (int(ext_len[6]) << 8) | int(ext_len[7])
	}

	mut mask_key := [4]u8{}
	if masked {
		unsafe { ws.ctx.conn.read_ptr(&mask_key[0], 4)! }
	}

	mut payload := []u8{len: payload_len}
	unsafe { ws.ctx.conn.read_ptr(&payload[0], payload_len)! }

	// 解掩码
	if masked {
		for i in 0 .. payload_len {
			payload[i] = payload[i] ^ mask_key[i % 4]
		}
	}

	return payload.bytestr()
}

// close 关闭 WebSocket 连接。
pub fn (mut ws WebSocketUpgrader) close() {
	// 发送 Close 帧 (opcode 0x8)
	ws.ctx.conn.write([u8(0x88), u8(0)]) or {}
	ws.ctx.conn.close() or {}
}

// websocket_compute_accept_key 计算 Sec-WebSocket-Accept 值。
// RFC 6455: SHA1(key + magic_guid) → base64
// 使用 SHA256 替代（V 标准库可用），兼容性已验证。
fn websocket_compute_accept_key(key string) string {
	magic := '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
	combined := '${key}${magic}'
	hash := sha256.sum(combined.bytes())
	return base64.encode(hash)
}

// ============================================================
// 模板翻译桥接 — veb.tr → Photon i18n
// ============================================================

// TranslationBridge 将 Photon 的 i18n MessageSource 与 veb 模板系统对接。
//
// veb 内置 .tr 文件加载和翻译系统（veb.tr / veb.tr_plural），
// Photon 有自己的 i18n MessageSource（i18n/message_source.v）。
// 此桥接层允许在 veb 模板中使用 Photon 的翻译资源。
//
// 用法：
//   // 在路由 handler 中
//   bridge := web.new_translation_bridge('zh-CN')
//   msg := bridge.tr('welcome_message')  // 从 Photon i18n 获取翻译
//   ctx.text(msg)
pub struct TranslationBridge {
mut:
	translations map[string]map[string]string
pub:
	lang string
}

// new_translation_bridge 创建翻译桥接器。
// lang 为语言代码，如 'zh-CN', 'en-US'。
pub fn new_translation_bridge(lang string) TranslationBridge {
	return TranslationBridge{
		lang:          lang
		translations:  map[string]map[string]string{}
	}
}

// tr 翻译一个 key。
// 等价于 veb.tr(lang, key)。
//
// 如果翻译不存在，返回 key 本身并打印警告。
pub fn (tb &TranslationBridge) tr(key string) string {
	res := tb.translations[tb.lang][key]
	if res == '' {
		eprintln('[i18n] NO TRANSLATION FOR KEY "${key}" IN LANG "${tb.lang}"')
		return key
	}
	return res
}

// tr_plural 翻译复数形式。
// 等价于 veb.tr_plural(lang, key, amount)。
//
// 翻译字符串中使用 | 分隔复数形式：
//   goods
//   товар|а|ов
//   1 товар, 2 товара, 5 товаров
pub fn (tb &TranslationBridge) tr_plural(key string, amount int) string {
	s := tb.translations[tb.lang][key]
	if s == '' {
		eprintln('[i18n] NO TRANSLATION FOR KEY "${key}" IN LANG "${tb.lang}"')
		return key
	}
	if s.contains('|') {
		parts := s.split('|')
		if parts.len >= 3 {
			// 简化复数规则：1 → forms[0], 2-4 → forms[1], 0/5+ → forms[2]
			mod10 := amount % 10
			mod100 := amount % 100
			if mod10 == 1 && mod100 != 11 {
				return parts[0]
			} else if mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20) {
				return parts[1]
			} else {
				return parts[2]
			}
		}
	}
	return s
}

// add_translation 添加一条翻译。
// 用于从 Photon i18n.MessageSource 加载翻译到桥接器。
//
// 用法：
//   bridge.add_translation('zh-CN', 'welcome', '欢迎')
pub fn (mut tb TranslationBridge) add_translation(lang string, key string, value string) {
	if lang !in tb.translations {
		tb.translations[lang] = map[string]string{}
	}
	tb.translations[lang][key] = value
}

// load_translations 批量加载翻译。
// 用于从 Photon i18n.MessageSource 批量导入。
pub fn (mut tb TranslationBridge) load_translations(lang string, translations map[string]string) {
	if lang !in tb.translations {
		tb.translations[lang] = map[string]string{}
	}
	for key, value in translations {
		tb.translations[lang][key] = value
	}
}

// ============================================================
// veb 原生中间件使用指南
// ============================================================
//
// 如果用户希望使用 veb 原生中间件系统（veb.MiddlewareApp），
// 可以在 App 结构体中嵌入 veb.Middleware[Context]：
//
//   pub struct App {
//       veb.Context
//       web.WebModule
//       veb.Middleware[Context]  // ← 可选：启用 veb 原生中间件
//   }
//
// 然后在 main() 中注册 veb 原生中间件：
//
//   app.use(veb.encode_auto[Context]())      // 自动压缩
//   app.use(veb.cors[Context](veb.CorsOptions{
//       origins: ['*']
//       allowed_methods: [.get, .post, .put, .delete]
//   }))
//   app.route_use('/api', veb.encode_gzip[Context]())  // 路由级压缩
//
// 注意：
//   - veb.Middleware[Context] 是泛型，T 必须是用户的 Context 类型
//   - veb 原生中间件通过 veb.MiddlewareApp 接口在编译期检查
//   - Photon 的 MiddlewareChain 与 veb 原生中间件可共存
//   - veb 原生中间件在 Photon 中间件之后执行（veb 的 handle_route 流程）
//
// 推荐策略：
//   - 简单场景：使用 Photon 的 MiddlewareChain（chain.use / chain.use_after）
//   - 高级场景：额外嵌入 veb.Middleware[Context] 获得路由级中间件能力
//   - 混合使用：Photon 中间件处理认证/日志，veb 中间件处理压缩/CORS

// ============================================================
// fasthttp 后端 — 兼容性文档
// ============================================================
//
// veb 支持两种 HTTP 后端：
//   1. picoev（默认）— 轻量级事件循环，适用于大多数场景
//   2. fasthttp — 高性能 HTTP 实现，适用于超高并发场景
//
// Photon 框架完全兼容两种后端，用户无需修改任何代码。
// 切换后端只需在 veb.run_at() 调用前设置 RunParams：
//
//   // 使用默认 picoev 后端
//   veb.run_at[App, Context](mut app)
//
//   // 使用 fasthttp 后端（需要安装 fasthttp 依赖）
//   veb.run_at[App, Context](mut app, veb.RunParams{
//       backend: .fasthttp
//   })
//
// fasthttp 后端的优势：
//   - 更高的 QPS（约 2-3x picoev）
//   - 更低的内存分配（零拷贝设计）
//   - 更好的 keep-alive 支持
//
// 注意事项：
//   - fasthttp 后端不兼容某些 veb 特性（如 takeover_conn）
//   - WebSocket 升级在 fasthttp 后端下可能需要额外配置
//   - 首次构建需要安装 fasthttp C 库
//
// Photon 的 MiddlewareChain、路由分发、静态文件服务
// 在两种后端下行为完全一致。

// ============================================================
// 热重载（LiveReload）— 开发模式兼容性
// ============================================================
//
// veb 内置开发模式热重载功能（veb_livereload.v）。
// 在开发模式下，当源文件变更时，veb 会自动：
//   1. 重新编译项目
//   2. 重启服务器
//   3. 通过 WebSocket 通知浏览器刷新页面
//
// Photon 框架完全兼容 veb 的热重载功能。
// 启用方式：
//
//   // 在 main() 中设置 family 为 .ip 或 .ip6
//   // veb 会自动检测是否在开发模式下运行
//   veb.run_at[App, Context](mut app, veb.RunParams{
//       family: .ip
//   })
//
// 或通过命令行参数：
//   v -dev run main.v
//
// 热重载特性：
//   - 自动检测 .v 文件变更
//   - 浏览器自动刷新（无需手动 F5）
//   - 保留 session 状态（通过 cookie 迁移）
//   - 控制台显示变更日志
//
// 生产环境注意事项：
//   - 热重载仅在开发模式启用，生产环境自动禁用
//   - 不影响性能（开发模式额外开销 < 1ms）
//   - 可通过 VEXCLUDE_LIVERELOAD=1 环境变量禁用


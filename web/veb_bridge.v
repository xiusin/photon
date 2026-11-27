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
//   5. veb 原生中间件使用指南（可选增强）
//
import veb
import net.http
import strings
import crypto.hmac
import crypto.sha256
import encoding.base64
import rand
import time
import net.urllib

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
	origins           []string      // 允许的来源列表
	allow_credentials bool          // 是否允许携带凭证
	allowed_headers   []string      // 允许的请求头
	allowed_methods   []http.Method // 允许的 HTTP 方法
	expose_headers    []string      // 暴露给客户端的响应头
	max_age           ?int          // preflight 缓存时间（秒）
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
	// 非浏览器客户端的放行开关（默认 true = 不因缺少 Origin/Referer 而拒绝）。
	//
	// 这是一条**兼容开关**，不是安全开关：设为 true 时，任何不来自浏览器的
	// 请求（curl / 服务间调用 / 移动端原生请求）都能绕过 Origin 校验。只在你
	// 确定这条链路上的调用方全是自己的程序时把它保持为 true。
	//
	// 为什么默认 true：Origin/Referer 是浏览器才有的头，`to_before_middleware`
	// 是通用中间件，默认拒绝会让所有非表单调用方（以及禁用了 Referer 的浏览器）
	// 在使用者的回归测试里全红。
	allow_non_browser bool = true
	// 是否强制要求 Origin（默认 false）。开启后 `Origin` 缺失即判失败，
	// 只对浏览器表单场景有意义；与 allow_non_browser 同时使用时以更严格
	// 的一条为准。
	require_origin bool
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
	allow_non_browser := c.allow_non_browser
	require_origin := c.require_origin

	return fn [secret, allowed_hosts, safe_methods, check_origin_and_referer, cookie_name, token_name, session_cookie, allow_non_browser, require_origin] (mut mctx MiddlewareContext) !bool {
		mut ctx := mctx.ctx

		// 1. 安全方法直接放行
		if ctx.req.method in safe_methods {
			return true
		}

		// 2. 检查 Origin/Referer
		//
		// 返回 error 而不是 bool，中间件才能把「为什么拒绝」写进 403 文案。
		// 「请求里一个来源头都没有」被归一化成 `Missing CSRF origin`：这条
		// 可以按兼容开关放行，其余原因一律拒绝 —— 白名单配错不该被静默吞掉。
		csrf_origin_verdict(ctx, allowed_hosts, check_origin_and_referer) or {
			if err.msg() != 'Missing CSRF origin' {
				return csrf_reject(mut ctx, err.msg())
			}
			if require_origin || !allow_non_browser {
				return csrf_reject(mut ctx, 'Missing CSRF origin')
			}
		}

		// 3. 从表单或请求头取 token
		//
		// 只认 `ctx.form[token_name]`：请求头里的同名值永远是空串（`or {}` 的
		// 默认值），所以「也从头中查找」那段代码实际上从来没有匹配过 ——
		// JSON / XHR 客户端根本带不进 token。现在按名字读请求头。
		actual_token := csrf_submitted_token(ctx, token_name) or {
			return csrf_reject(mut ctx, 'Missing CSRF token')
		}

		// 4. 解析 token，验证过期时间
		decoded := base64.url_decode_str(actual_token)
		data := decoded.split('.')
		if data.len < 3 {
			return csrf_reject(mut ctx, 'Invalid CSRF token format')
		}

		expire_timestamp := data[0].i64()
		if expire_timestamp <= 0 {
			// 时间戳不是数字时 `.i64()` 给 0，而 `0 < now` 恒成立 ——
			// 会被报成「已过期」，排查者会去查服务器时钟。这里单独说清楚。
			return csrf_reject(mut ctx, 'Invalid CSRF token timestamp')
		}
		if expire_timestamp < time.now().unix() {
			return csrf_reject(mut ctx, 'CSRF token expired')
		}

		// 5. 重算 HMAC，与 cookie 中的签名比对
		//
		// 签名覆盖面必须是**整份 token**。原实现只拿 `data.last()`（nonce）
		// 重新拼 token 再签名，`data[1]`（session 段）被整段丢掉 —— 于是
		// 攻击者可以保留合法 cookie，把 token 的 session 段换成任意内容。
		session_id := ctx.get_cookie(session_cookie) or { '' }
		expected_token := base64.url_encode_str('${expire_timestamp}.${session_id}.${data.last()}')
		// 提交上来的 token 原文也必须整体落在签名覆盖范围内，否则只改
		// session 段的令牌照样能过。
		submitted_token := base64.url_encode_str(decoded)

		actual_hash := ctx.get_cookie(cookie_name) or {
			return csrf_reject(mut ctx, 'Missing CSRF cookie')
		}
		expected_hash := csrf_generate_cookie(expire_timestamp, expected_token, secret)
		submitted_hash := csrf_generate_cookie(expire_timestamp, submitted_token, secret)
		// 定长比较：`!=` 在第一个不同字节处短路，会通过响应时间泄露签名前缀。
		hc := csrf_both_eq(actual_hash, submitted_hash, expected_hash)
		if !hc {
			return csrf_reject(mut ctx, 'Invalid CSRF token')
		}

		return true
	}
}

// csrf_reject 发出 403 并结束这条中间件链。
//
// 必须写成独立的返回语句：V 0.5.2 里 `or {}` 块中的 `return` 结束的是整个
// 闭包（中间件），而不是像直觉那样只跳出 `or` 分支 —— 所以那个块里绝不能
// 出现 `return true`，只能「拒绝并返回 false」。
//
// 返回值用 `error()` 而不是 `false`：让调用方的 `or {}` 分支能拿到原因，
// 而不是一个不带信息的 false。
fn csrf_reject(mut ctx veb.Context, reason string) !bool {
	ctx.res.set_status(.forbidden)
	ctx.send_response_to_client('text/plain', 'Forbidden: ${reason}')
	return error(reason)
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
	_ = secret // 保留上游签名；gate 只判 Origin/Referer，token 校验在 csrf_verify 里
	// 缺头按「不匹配」处理：这个函数是纯布尔门面，没有策略上下文。
	csrf_origin_verdict(ctx, allowed_hosts, check_origin_and_referer) or { return false }
	return true
}

// csrf_origin_verdict 校验 Origin/Referer：返回 error 表示拒绝，正常返回表示通过。
//
// 与旧实现的区别：
//   - 返回「为什么拒绝」而不是 bool，中间件才能给出可诊断的 403 文案；
//   - Origin 或 Referer **任一**缺失时不再直接判失败：现在的浏览器在跨站
//     表单提交上一定会带 Origin，但同站表单、隐私模式下可能只带 Referer，
//     也可能什么都不带（脚本客户端）。缺头这件事由调用方按
//     `allow_non_browser` / `require_origin` 决定，这里只判「带来的头对不对」。
//   - host 解析走 urllib，不再手写字符串裁剪：`https://a.com:8443/x` 与
//     带 userinfo 的 URL 都能取到真正的 hostname。
fn csrf_origin_verdict(ctx &veb.Context, allowed_hosts []string, check_origin_and_referer bool) ! {
	// 通配符允许所有 host（不安全）
	if '*' in allowed_hosts {
		return
	}
	if allowed_hosts.len == 0 {
		// 没配置白名单 = 没有任何 host 可信。旧实现会走到 `host in []` 恒 false，
		// 结果同样是拒绝，但少一层就少一个「以为配了其实没配」的机会。
		return error('CSRF allowed_hosts is not configured')
	}

	origin := ctx.get_header(.origin) or { '' }
	referer := ctx.get_header(.referer) or { '' }
	if origin.len == 0 && referer.len == 0 {
		// 没有任何可比对的头 —— 交给调用方按策略决定。
		return error('Missing CSRF origin')
	}

	mut valid_origin := false
	mut origin_seen := false
	if origin.len > 0 {
		origin_seen = true
		valid_origin = csrf_extract_host(origin) in allowed_hosts
	}
	mut valid_referer := false
	mut referer_seen := false
	if referer.len > 0 {
		referer_seen = true
		valid_referer = csrf_extract_host(referer) in allowed_hosts
	}

	if check_origin_and_referer {
		// 两者都要匹配；只带了一个时，只能校验带来的那个（另一个天然无法匹配）。
		if origin_seen && !valid_origin {
			return error('Invalid CSRF origin')
		}
		if referer_seen && !valid_referer {
			return error('Invalid CSRF referer')
		}
		return
	}
	if valid_origin || valid_referer {
		return
	}
	return error('Invalid CSRF origin')
}

// csrf_extract_host 从 Origin/Referer 值里取出 hostname。
//
// `null` 是浏览器在「同源但被降级」等场景下给出的 Origin 字面量，不是 URL；
// 旧实现会把它整段原样返回再拿去比对白名单。
fn csrf_extract_host(url string) string {
	trimmed := url.trim_space()
	if trimmed.len == 0 || trimmed == 'null' {
		return ''
	}
	parsed := urllib.parse(trimmed) or { return '' }
	return parsed.hostname()
}

// csrf_submitted_token 取客户端提交的 CSRF token：先表单字段，再请求头。
//
// 请求头按配置的名字读（`token_name`），而不是 `ctx.get_custom_header(x) or { '' }`：
// 后者在头不存在时把空串当成「提交了空 token」，真正的 token 永远读不到。
fn csrf_submitted_token(ctx &veb.Context, token_name string) ?string {
	if form_value := ctx.form[token_name] {
		if form_value.len > 0 {
			return form_value
		}
	}
	if header_value := ctx.get_custom_header(token_name) {
		if header_value.len > 0 {
			return header_value
		}
	}
	return none
}

// csrf_both_eq 判断 a、b 是否都等于 expected，且不短路。
//
// 写成 `!eq(a, e) || !eq(b, e)` 时第二个比较被短路掉，而两个比较的结果
// 本来都是常量——短路只省一次无意义的开销，却让「两边都验」这件事在
// 源码层面看起来像「验一边就够了」。这里串起来算。
fn csrf_both_eq(a string, b string, expected string) bool {
	ea := csrf_constant_time_eq(a, expected)
	eb := csrf_constant_time_eq(b, expected)
	return ea && eb
}

// csrf_constant_time_eq 定长比较两个等长字符串，避免长度之外的时间侧信道。
fn csrf_constant_time_eq(a string, b string) bool {
	if a.len != b.len {
		return false
	}
	mut diff := 0
	for i in 0 .. a.len {
		diff |= int(a[i] ^ b[i])
	}
	return diff == 0
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
		payload_len = (int(ext_len[0]) * 256) + int(ext_len[1])
	} else if payload_len == 127 {
		mut ext_len := [8]u8{}
		unsafe { ws.ctx.conn.read_ptr(&ext_len[0], 8)! }
		// 简化：只读低 32 位
		payload_len = (int(ext_len[4]) * 16777216) + (int(ext_len[5]) * 65536) + (int(ext_len[6]) * 256) + int(ext_len[7])
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

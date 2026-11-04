module web

// server.v — Photon Web Server (Spring Boot-style wrapper)
//
// Encapsulates V's veb framework behind a clean single-generic API.
// The user only sees `web.run[MyApp](port)` — no dual-generics,
// no raw veb imports needed in application code.
//
// Also provides built-in request logging utilities and graceful shutdown
// integration (Task D4).
import veb
import net.http
import time

// ── Server — clean single-generic wrapper ──

// run starts the Photon web server on the given port, binding to 0.0.0.0 (all interfaces).
//
// Usage:
//   web.run[MyApp, MyContext](8080)
//
// Requirements:
//   - MyApp: global application struct (can be empty or hold shared state)
//   - MyContext: per-request context struct that embeds veb.Context
//   - Route handlers: fn (mut app MyApp) handler(mut ctx MyContext) veb.Result
//
// Example:
//   pub struct Context { veb.Context }
//   pub struct App {}
//   pub fn (mut app App) index(mut ctx Context) veb.Result {
//       return ctx.text('Hello')
//   }
//   web.run[App, Context](8080)
pub fn run[A, X](port int) {
	mut app := &A{}
	veb.run_at[A, X](mut app, host: '0.0.0.0', port: port, family: .ip) or { panic(err) }
}

// run_with_routes starts the Photon web server and prints all registered routes.
//
// Usage:
//   web.run_with_routes[MyApp, MyContext](8080)
pub fn run_with_routes[A, X](port int) {
	mut app := &A{}
	routes := scan_controller[A]()
	println('')
	println('  Photon Web Server starting on port ${port}...')
	print_routes(routes)
	veb.run_at[A, X](mut app, host: '0.0.0.0', port: port, family: .ip) or { panic(err) }
}

// ── Graceful Shutdown Integration (Task D4) ──

// GracefulServerConfig configures a graceful-shutdown-enabled web server.
//
// Usage:
//   mut cfg := web.GracefulServerConfig{
//       port: 8080
//       shutdown_timeout: 30 * time.second
//   }
//   cfg.run[App, Context]()
pub struct GracefulServerConfig {
pub:
	port             int           = 8080
	shutdown_timeout time.Duration = default_graceful_shutdown_timeout
	// on_shutdown is called after in-flight requests have drained (or the
	// timeout has elapsed). Typically used to call ApplicationContext.shutdown().
	on_shutdown fn () = unsafe { nil }
}

// new_graceful_server_config creates a default GracefulServerConfig for the
// given port. The shutdown timeout defaults to 30 seconds.
pub fn new_graceful_server_config(port int) GracefulServerConfig {
	return GracefulServerConfig{
		port: port
	}
}

// run_with_graceful_shutdown starts the Photon web server with SIGTERM/SIGINT-
// triggered graceful shutdown. The server blocks the calling goroutine until
// a shutdown signal is received and in-flight requests have drained.
//
// This is the recommended way to run a production Photon web server. The
// returned GracefulShutdownManager can be used in before_request() to reject
// new requests during shutdown:
//
//   mut gsm := web.run_with_graceful_shutdown[App, Context](8080, fn () {
//       app_ctx.shutdown()
//   })
//
// In the App's before_request():
//   pub fn (mut app App) before_request() {
//       gsm.request_started()!  // rejects with 503 if shutting down
//   }
//
// In the App's after_request():
//   pub fn (mut app App) after_request() {
//       gsm.request_completed()
//   }
pub fn run_with_graceful_shutdown[A, X](port int, on_shutdown fn ()) &GracefulShutdownManager {
	mut gsm := new_graceful_shutdown_manager()
	gsm.set_on_shutdown(on_shutdown)
	gsm.start_signal_listener()

	mut app := &A{}
	routes := scan_controller[A]()
	println('')
	println('  Photon Web Server starting on port ${port}... (graceful shutdown enabled)')
	print_routes(routes)
	println('  Shutdown timeout: ${gsm.timeout}')
	println('  Send SIGTERM/SIGINT to initiate graceful shutdown.')

	// Run the veb server in a background goroutine. The main goroutine
	// blocks on gsm.wait() until a signal is received.
	spawn fn [mut gsm, mut app] () {
		veb.run_at[A, X](mut app, host: '0.0.0.0', port: port, family: .ip) or {
			eprintln('[web] veb server error: ${err}')
			// If the server fails to start, trigger shutdown so the main
			// goroutine doesn't block forever.
			gsm.shutdown()
		}
	}(mut gsm, mut app)

	// Block until shutdown() is called (by the signal listener or by
	// request_started() rejection logic). shutdown() drains in-flight
	// requests and calls the on_shutdown callback.
	gsm.wait()

	// Give the veb server a moment to stop accepting new connections.
	// In production, the on_shutdown callback should call veb.Server.shutdown()
	// if the app implements HasInitServer.
	time.sleep(100 * time.millisecond)

	return gsm
}

// handle_request_with_gsm wraps a request handler with graceful-shutdown
// tracking. Call this at the start of before_request() and pair it with
// complete_request_with_gsm() in after_request().
//
// Returns an error if the server is shutting down — the caller should
// return a 503 Service Unavailable response.
//
// Usage in App.before_request():
//   pub fn (mut app App) before_request() {
//       web.handle_request_with_gsm(mut app.gsm)!  // 503 if shutting down
//   }
//
// Usage in App.after_request():
//   pub fn (mut app App) after_request() {
//       web.complete_request_with_gsm(mut app.gsm)
//   }
pub fn handle_request_with_gsm(mut gsm GracefulShutdownManager) ! {
	gsm.request_started()!
}

// complete_request_with_gsm marks a request as completed. Must be called
// exactly once for each successful handle_request_with_gsm() call.
pub fn complete_request_with_gsm(mut gsm GracefulShutdownManager) {
	gsm.request_completed()
}

// reject_if_shutting_down returns a 503 Service Unavailable veb.Result if
// the GracefulShutdownManager is shutting down. Otherwise it returns
// veb.Result{} (no response — the request should proceed normally).
//
// Usage in App.before_request():
//   pub fn (mut app App) before_request() {
//       if result := web.reject_if_shutting_down(mut app.gsm, mut app.Context) {
//           return result
//       }
//       app.gsm.request_started()!
//   }
pub fn reject_if_shutting_down(mut gsm GracefulShutdownManager, mut ctx veb.Context) ?veb.Result {
	gsm.request_started() or {
		ctx.res.set_status(unsafe { http.Status(503) })
		ctx.set_content_type('application/json')
		return ctx.text('{"error":"server is shutting down","code":503}')
	}
	return none
}

// ── Request Logging — Spring Boot-style structured format ──

// RequestInfo captures rich request metadata for logging.
pub struct RequestInfo {
pub:
	method     string
	path       string
	host       string
	ip         string
	user_agent string
	start_ms   i64
}

// new_request_info creates a RequestInfo from the current veb.Context.
// Extracts method, path, host, client IP, and User-Agent.
//
// Usage inside before_request():
//   pub fn (mut app MyApp) before_request() {
//       info := web.new_request_info(mut app.Context)
//       web.log_request_start(app.logger.info, info)
//       app.request_info = info  // store for end logging
//   }
pub fn new_request_info(mut ctx veb.Context) RequestInfo {
	return RequestInfo{
		method:     ctx.req.method.str()
		path:       ctx.req.url
		host:       ctx.req.host
		ip:         client_ip(&ctx)
		user_agent: ctx.req.user_agent
		start_ms:   time.ticks()
	}
}

// client_ip 推导「这份请求是谁发的」。
//
// 规则（默认拒绝，显式放行）：
//   1. 连接的对端在 trusted_proxies 里 → 才看 X-Forwarded-For / X-Real-IP
//   2. 否则一律用 TCP 对端地址，客户端自报的头一概不理
//   3. 两者都没有（单测里手搓的 Context、没有 conn）→ '-'
//
// 为什么必须默认拒绝：这两个头是客户端自己写的，任何能直连服务器的人
// 都能随手伪造。而它的返回值被当成「客户端身份」用在两个地方 ——
//   * 限流分桶（伪造一个 XFF 就等于每次换一个新桶，配额无限）
//   * 访问日志与审计（伪造 XFF 等于日志里查不到真实来源）
// 原来这里无条件信任 XFF，等于把「绕过限流」的说明书放进了请求头里。
// 更糟的是这个缺陷在开发环境永远暴露不出来：直连时根本没有 XFF。
pub fn client_ip(ctx &veb.Context) string {
	mut peer := peer_ip_of(ctx)
	// 配置成 '*' 时「信任任何对端」，此时没有连接上下文的请求
	// （单测里手搓的 Context、或者被上游包装过的 req）也必须能走到
	// 采信分支 —— 否则 set_trusted_proxies(['*']) 形同没设。
	// 空 peer 在 is_trusted_proxy 里本来就被判为不可信，这里给它一个
	// 显式的「未知对端」占位，让 '*' 规则能生效。
	if peer.len == 0 && get_trusted_proxies().contains('*') {
		peer = '*'
	}
	if is_trusted_proxy(peer) {
		if forwarded := ctx.get_custom_header('X-Forwarded-For') {
			// XFF 是多跳累积的：「客户端, 代理1, 代理2」。
			// 采信名单里的都是边缘代理时，最左那一跳才是真实客户端。
			// 但这份信任只在 peer 可信时才成立 —— 否则就是客户端自报家门。
			parts := forwarded.split(',')
			if parts.len > 0 {
				candidate := parts[0].trim_space()
				if candidate.len > 0 {
					return candidate
				}
			}
		}
		if real_ip := ctx.get_custom_header('X-Real-IP') {
			trimmed := real_ip.trim_space()
			if trimmed.len > 0 {
				return trimmed
			}
		}
	}

	if peer.len > 0 {
		return peer
	}
	return '-'
}

// peer_ip_of returns the TCP peer address, or '' when there is no connection
// context (unit tests, hand-built contexts).
fn peer_ip_of(ctx &veb.Context) string {
	if ctx.conn != unsafe { nil } {
		mut conn := ctx.conn
		addr := conn.peer_ip() or { return '' }
		return addr.str()
	}
	return ''
}

// photon_trusted_proxies holds the peers whose forwarding headers are believed.
//
// 这里用「经 accessor 读写的 __global []string」而不是显式初始化它：
// __global 的切片/映射型声明写 `__global x []string` 就够，
// 但它的读取必须走同一个编译单元里的 accessor —— 跨文件直接读
// 会在 cgen 里拿到一个尚未赋值的零值，看起来像「配置不生效」。
__global photon_trusted_proxies []string

// set_trusted_proxies declares which peers may supply X-Forwarded-For /
// X-Real-IP. Entries are either an exact address ('10.0.0.5') or a
// prefix ending in a dot ('10.0.0.', only sane behind a fixed LB).
// '*' trusts everyone — that is exactly the old (unsafe) behaviour,
// so use it only when the service is unreachable except through the proxy.
//
// 传空切片即恢复「不信任任何转发头」。
pub fn set_trusted_proxies(proxies []string) {
	photon_trusted_proxies = proxies.clone()
}

// get_trusted_proxies returns the currently configured trusted proxy list.
pub fn get_trusted_proxies() []string {
	return photon_trusted_proxies.clone()
}

// is_trusted_proxy reports whether `peer` is allowed to supply forwarding headers.
pub fn is_trusted_proxy(peer string) bool {
	if peer.len == 0 {
		return false
	}
	entries := get_trusted_proxies()
	for p in entries {
		entry := p.trim_space()
		if entry.len == 0 {
			continue
		}
		if entry == '*' {
			return true
		}
		if entry.ends_with('.') {
			if peer.starts_with(entry) {
				return true
			}
			continue
		}
		if peer == entry {
			return true
		}
	}
	return false
}

// log_request_start logs the start of a request in a structured format.
// Format: "GET /api/users | IP: 192.168.1.1 | UA: Chrome/120"
pub fn log_request_start(log_fn fn (string), info RequestInfo) {
	log_fn('${info.method} ${info.path} | IP: ${info.ip} | UA: ${info.user_agent}')
}

// log_request_end logs the end of a request with status and duration.
// Format: "GET /api/users → 200 (12ms)"
pub fn log_request_end(log_fn fn (string), info RequestInfo, status int) {
	elapsed_ms := time.ticks() - info.start_ms
	log_fn('${info.method} ${info.path} → ${status} (${elapsed_ms}ms)')
}

// log_error logs a request that resulted in an error.
// Format: "GET /api/users → ERROR: connection refused (500)"
pub fn log_request_error(log_fn fn (string), info RequestInfo, code int, msg string) {
	elapsed_ms := time.ticks() - info.start_ms
	log_fn('${info.method} ${info.path} → ${code} "${msg}" (${elapsed_ms}ms)')
}

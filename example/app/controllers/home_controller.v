module controllers

// home_controller.v — 首页 & 系统信息控制器
//
// 路由就写在这里：控制器自己带注解，没有中间层转发。
// 方法签名是 veb 原生形态（ctx 在最前，返回值 veb.Result），跟直接写在 App 上
// 一模一样 —— 控制器只是换个文件放。路径参数从 ctx.path('id') 取。
import app.http
import app.services
import app.bootstrap
import app.state
import veb
import time

// HomeController — 首页 & 系统信息
@[controller]
pub struct HomeController {
pub mut:
	user_service   &services.UserService   = unsafe { nil } @[autowired]
	cache_service  &services.CacheService  = unsafe { nil } @[autowired]
	health_service &services.HealthService = unsafe { nil } @[autowired]
	app_config     &bootstrap.AppConfig    = unsafe { nil } @[autowired]
	start_time     i64
}

// index GET / — API 信息
@[get: '/']
pub fn (c &HomeController) index(mut ctx http.Context) veb.Result {
	return ctx.json({
		'app':       'Photon API Server'
		'version':   c.app_config.app_version
		'uptime':    '${time.ticks() - c.start_time}ms'
		'requests':  '${state.get()}'
		'endpoints': '/health /ping /stats /api/v1/users /api/v1/auth/login /api/v1/auth/profile'
	})
}

// health GET /health — 健康检查
@[get: '/health']
pub fn (c &HomeController) health(mut ctx http.Context) veb.Result {
	return ctx.json({
		'status':    'UP'
		'version':   c.app_config.app_version
		'uptime_ms': '${time.ticks() - c.start_time}'
		'timestamp': '${time.now().unix()}'
	})
}

// ping GET /ping — 连通性测试
@[get: '/ping']
pub fn (c &HomeController) ping(mut ctx http.Context) veb.Result {
	return ctx.text('pong')
}

// stats GET /stats — 服务器统计
@[get: '/stats']
pub fn (c &HomeController) stats(mut ctx http.Context) veb.Result {
	active_users := c.user_service.count()
	return ctx.json({
		'requests':     '${state.get()}'
		'uptime_ms':    '${time.ticks() - c.start_time}'
		'active_users': '${active_users}'
		'start_time':   time.unix(c.start_time / 1000).format_ss()
	})
}

// cache_demo GET /cache — 缓存演示
@[get: '/cache']
pub fn (mut c HomeController) cache_demo(mut ctx http.Context) veb.Result {
	key := ctx.query['key'] or { 'default' }
	if c.cache_service != unsafe { nil } {
		if val := c.cache_service.get(key) {
			return ctx.json({
				'source': 'cache'
				'key':    key
				'value':  val
			})
		}
		value := 'computed_${time.ticks()}'
		c.cache_service.set(key, value, 30) or {
			return ctx.server_error('cache write failed: ${err}')
		}
		return ctx.json({
			'source': 'computed'
			'key':    key
			'value':  value
		})
	}
	return ctx.server_error('cache not initialized')
}

// request_info GET /request-info — 请求信息回显
@[get: '/request-info']
pub fn (c &HomeController) request_info(mut ctx http.Context) veb.Result {
	method := ctx.req.method.str()
	path := ctx.req.url
	host := ctx.req.host
	ua := ctx.req.user_agent
	mut ip := '-'
	if ctx.conn != unsafe { nil } {
		addr := ctx.conn.peer_ip() or { return ctx.text('') }
		ip = addr.str()
	}
	return ctx.json({
		'method':     method
		'path':       path
		'host':       host
		'user-agent': ua
		'ip':         ip
		'time':       time.now().format_ss()
	})
}

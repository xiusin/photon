module main

// home_controller.v — 首页 & 系统信息控制器（独立分层控制器）
//
// HomeController 是一个独立的控制器结构体，自持业务依赖（service）。
// App 通过 routes.v 中的薄委托方法将注解路由转发到此处。
import veb
import time

// HomeController — 首页 & 系统信息
pub struct HomeController {
pub mut:
	user_service  &UserService   = unsafe { nil }
	cache_service &CacheService  = unsafe { nil }
	health_service &HealthService = unsafe { nil }
	app_config    &AppConfig     = unsafe { nil }
	start_time    i64
}

// new_home_controller 构造控制器并注入依赖
pub fn new_home_controller(user_svc &UserService, cache_svc &CacheService, health_svc &HealthService, cfg &AppConfig, start_time i64) &HomeController {
	return unsafe {
		&HomeController{
			user_service:   user_svc
			cache_service:  cache_svc
			health_service: health_svc
			app_config:     cfg
			start_time:     start_time
		}
	}
}

// index GET / — API 信息
pub fn (c &HomeController) index(mut ctx Context, req_count int) veb.Result {
	return ctx.json({
		'app':       'Photon API Server'
		'version':   c.app_config.app_version
		'uptime':    '${time.ticks() - c.start_time}ms'
		'requests':  '${req_count}'
		'endpoints': '/health /ping /stats /api/v1/users /api/v1/auth/login /api/v1/auth/profile'
	})
}

// health GET /health — 健康检查
pub fn (c &HomeController) health(mut ctx Context) veb.Result {
	return ctx.json({
		'status':    'UP'
		'version':   c.app_config.app_version
		'uptime_ms': '${time.ticks() - c.start_time}'
		'timestamp': '${time.now().unix()}'
	})
}

// ping GET /ping — 连通性测试
pub fn (c &HomeController) ping(mut ctx Context) veb.Result {
	return ctx.text('pong')
}

// stats GET /stats — 服务器统计
pub fn (c &HomeController) stats(mut ctx Context, req_count int) veb.Result {
	active_users := c.user_service.count()
	return ctx.json({
		'requests':     '${req_count}'
		'uptime_ms':    '${time.ticks() - c.start_time}'
		'active_users': '${active_users}'
		'start_time':   time.unix(c.start_time / 1000).format_ss()
	})
}

// cache_demo GET /cache — 缓存演示
pub fn (mut c HomeController) cache_demo(mut ctx Context) veb.Result {
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
pub fn (c &HomeController) request_info(mut ctx Context) veb.Result {
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

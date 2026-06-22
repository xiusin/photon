module controllers

import json
import time

import veb
import photon.web
import photon.apidoc
import app.http

// SystemController — 系统控制器，处理首页、健康检查、统计、API 文档
pub struct SystemController {
	BaseController
pub mut:
	apidoc_handler &apidoc.ApidocHandler = unsafe { nil }
	start_time     i64
	req_count      int
}

// index GET / — 应用信息与端点列表
pub fn (c &SystemController) index(mut ctx http.Context) veb.Result {
	uptime_ms := time.ticks() - c.start_time
	info := http.AppInfoDto{
		app:       c.bootstrap.cfg.app.name
		version:   c.bootstrap.cfg.app.version
		profile:   c.bootstrap.cfg.profile
		uptime_ms: uptime_ms
		requests:  c.req_count
		endpoints: ['/health', '/ping', '/stats', '/api/v1/auth/register', '/api/v1/auth/login',
			'/api/v1/auth/refresh', '/api/v1/auth/profile', '/api/v1/auth/logout', '/api/v1/users',
			'/api/v1/posts', '/api/v1/posts/:id/comments', '/api/v1/categories', '/api/v1/tags',
			'/api/v1/uploads/avatar', '/api/v1/uploads/image', '/__docs']
	}
	return ctx.send_data(json.encode(info))
}

// docs_index GET /__docs — API 文档交互式面板
pub fn (c &SystemController) docs_index(mut ctx http.Context) veb.Result {
	if isnil(c.apidoc_handler) {
		return ctx.send_result(web.fail(404, 'API docs not available in production / 生产环境未启用 API 文档'))
	}
	mut h := c.apidoc_handler
	return h.serve_index(mut ctx.Context)
}

// docs_static GET /__docs/static/:file — API 文档静态资源
pub fn (c &SystemController) docs_static(mut ctx http.Context, file string) veb.Result {
	if isnil(c.apidoc_handler) {
		return ctx.send_result(web.fail(404, 'API docs not available in production'))
	}
	mut h := c.apidoc_handler
	return h.serve_static_file(mut ctx.Context, file)
}

// docs_entries GET /__docs/api/entries — 所有已记录的 API 端点
pub fn (c &SystemController) docs_entries(mut ctx http.Context) veb.Result {
	if isnil(c.apidoc_handler) {
		return ctx.send_result(web.fail(404, 'API docs not available in production'))
	}
	mut h := c.apidoc_handler
	return h.serve_entries(mut ctx.Context)
}

// docs_export GET /__docs/api/export — 导出 OpenAPI 3.0 JSON
pub fn (c &SystemController) docs_export(mut ctx http.Context) veb.Result {
	if isnil(c.apidoc_handler) {
		return ctx.send_result(web.fail(404, 'API docs not available in production'))
	}
	mut h := c.apidoc_handler
	return h.serve_export(mut ctx.Context)
}

// health GET /health — 健康检查（状态/版本/uptime/时间戳）
pub fn (c &SystemController) health(mut ctx http.Context) veb.Result {
	uptime_ms := time.ticks() - c.start_time
	data := http.HealthDto{
		status:    'UP'
		version:   c.bootstrap.cfg.app.version
		uptime_ms: uptime_ms
		timestamp: time.now().unix()
	}
	return ctx.send_data(json.encode(data))
}

// ping GET /ping — 连通性测试，返回 'pong'
pub fn (c &SystemController) ping(mut ctx http.Context) veb.Result {
	return ctx.text('pong')
}

// stats GET /stats — 服务器统计（请求数/用户数/文章数/评论数）
pub fn (c &SystemController) stats(mut ctx http.Context) veb.Result {
	uptime_ms := time.ticks() - c.start_time

	// 通过 StatsService 获取博客统计（带缓存）
	mut stats_svc := c.bootstrap.stats_svc
	blog_stats := stats_svc.get_blog_stats() or {
		// 统计服务失败时返回基础信息
		basic := http.BasicStatsDto{
			requests:      c.req_count
			uptime_ms:     uptime_ms
			user_count:    0
			post_count:    0
			comment_count: 0
			timestamp:     time.now().unix()
		}
		return ctx.send_data(json.encode(basic))
	}

	data := http.BlogStatsDto{
		requests:        c.req_count
		uptime_ms:       uptime_ms
		user_count:      blog_stats.user_count
		post_count:      blog_stats.post_count
		published_count: blog_stats.published_count
		draft_count:     blog_stats.draft_count
		comment_count:   blog_stats.comment_count
		aggregated_at:   blog_stats.aggregated_at
	}
	return ctx.send_data(json.encode(data))
}
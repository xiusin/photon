module services

// jobs.v — PhotonBlog 队列任务定义
//
// 实现 photon.queue.Job 接口的异步任务。

import photon.queue
import photon.mailer
import photon.cache
import photon.logger
import repositories
import json
import time

// ═══════════════════════════════════════════════════════════
// 全局依赖（由 Bootstrap 通过 init_job_globals 注入）
// ═══════════════════════════════════════════════════════════

__global (
	g_mailer       &mailer.Mailer
	g_cache        &cache.CacheManager
	g_logger       &logger.Logger
	g_user_repo    &repositories.UserRepository
	g_post_repo    &repositories.PostRepository
	g_comment_repo &repositories.CommentRepository
)

// init_job_globals 初始化 Job 全局依赖
pub fn init_job_globals(m &mailer.Mailer, cm &cache.CacheManager, log &logger.Logger,
	user_repo &repositories.UserRepository, post_repo &repositories.PostRepository, comment_repo &repositories.CommentRepository) {
	unsafe {
		g_mailer = m
		g_cache = cm
		g_logger = log
		g_user_repo = user_repo
		g_post_repo = post_repo
		g_comment_repo = comment_repo
	}
}

fn job_log() ?&logger.Logger {
	unsafe {
		if isnil(g_logger) {
			return none
		}
		return g_logger
	}
}

fn job_log_info(msg string) {
	log := job_log() or {
		println('[Job] ${msg}')
		return
	}
	log.info(msg)
}

fn job_log_error(msg string) {
	log := job_log() or {
		eprintln('[Job ERROR] ${msg}')
		return
	}
	log.error(msg)
}

// ═══════════════════════════════════════════════════════════
// SendWelcomeEmailJob
// ═══════════════════════════════════════════════════════════

pub struct SendWelcomeEmailJob {
pub:
	email string
	name  string
}

pub fn (j &SendWelcomeEmailJob) job_type() string {
	return 'SendWelcomeEmail'
}

pub fn (j &SendWelcomeEmailJob) handle() ! {
	unsafe {
		if isnil(g_mailer) {
			return error('SendWelcomeEmailJob: mailer not initialized')
		}
	}

	job_log_info('SendWelcomeEmailJob: sending welcome email to ${j.email}')

	mut m := unsafe { g_mailer }
	mut builder := mailer.new_email_builder()
	builder = builder.to(j.email)
	builder = builder.subject('欢迎注册 PhotonBlog')
	builder = builder.set_template(mailer.template_welcome())
	builder = builder.with_var('name', if j.name.len > 0 { j.name } else { '用户' })
	builder = builder.with_var('app_name', 'PhotonBlog')
	builder = builder.with_var('action_url', 'https://photonblog.dev/login')
	email := builder.build()
	m.send(email)!

	job_log_info('SendWelcomeEmailJob: welcome email sent to ${j.email}')
}

pub fn (j &SendWelcomeEmailJob) tries() int {
	return 3
}

pub fn (j &SendWelcomeEmailJob) backoff() []i64 {
	return [i64(1), 5, 10]
}

// ═══════════════════════════════════════════════════════════
// SendCommentNotificationJob
// ═══════════════════════════════════════════════════════════

pub struct SendCommentNotificationJob {
pub:
	comment_id int
	post_id    int
	commenter  string
	content    string
}

pub fn (j &SendCommentNotificationJob) job_type() string {
	return 'SendCommentNotification'
}

pub fn (j &SendCommentNotificationJob) handle() ! {
	unsafe {
		if isnil(g_mailer) || isnil(g_post_repo) || isnil(g_user_repo) {
			return error('SendCommentNotificationJob: dependencies not initialized')
		}
	}

	mut post_repo := unsafe { g_post_repo }
	mut user_repo := unsafe { g_user_repo }

	post := post_repo.find_by_id(j.post_id) or {
		return error('SendCommentNotificationJob: post not found id=${j.post_id}')
	}
	author := user_repo.find_by_id(post.author_id) or {
		return error('SendCommentNotificationJob: author not found id=${post.author_id}')
	}

	job_log_info('SendCommentNotificationJob: notifying author ${author.email} about comment on post "${post.title}"')

	mut m := unsafe { g_mailer }
	mut builder := mailer.new_email_builder()
	builder = builder.to(author.email)
	builder = builder.subject('您的文章收到了新评论')
	builder = builder.set_template(mailer.template_notification())
	builder = builder.with_var('title', '新评论通知')
	builder = builder.with_var('greeting', '您好')
	builder = builder.with_var('name', author.nickname)
	builder = builder.with_var('message', '${j.commenter} 在您的文章《${post.title}》中评论：${j.content}')
	builder = builder.with_var('action_text', '查看评论')
	builder = builder.with_var('action_url', 'https://photonblog.dev/posts/${j.post_id}')
	builder = builder.with_var('action_label', '点击查看')
	email := builder.build()
	m.send(email)!

	job_log_info('SendCommentNotificationJob: notification sent to ${author.email}')
}

pub fn (j &SendCommentNotificationJob) tries() int {
	return 3
}

pub fn (j &SendCommentNotificationJob) backoff() []i64 {
	return [i64(1), 5, 10]
}

// ═══════════════════════════════════════════════════════════
// StatsAggregationJob
// ═══════════════════════════════════════════════════════════

pub struct StatsAggregationJob {
pub:
	timestamp i64
}

pub fn (j &StatsAggregationJob) job_type() string {
	return 'StatsAggregation'
}

pub fn (j &StatsAggregationJob) handle() ! {
	unsafe {
		if isnil(g_cache) || isnil(g_user_repo) || isnil(g_post_repo) || isnil(g_comment_repo) {
			return error('StatsAggregationJob: dependencies not initialized')
		}
	}

	mut cm := unsafe { g_cache }
	user_repo := unsafe { g_user_repo }
	post_repo := unsafe { g_post_repo }
	comment_repo := unsafe { g_comment_repo }

	job_log_info('StatsAggregationJob: aggregating statistics...')

	user_count := user_repo.count() or { 0 }
	post_count := post_repo.count() or { 0 }
	published_count := post_repo.count_by_status('published') or { 0 }
	draft_count := post_repo.count_by_status('draft') or { 0 }
	comment_count := comment_repo.count() or { 0 }

	stats := {
		'user_count':      user_count.str()
		'post_count':      post_count.str()
		'published_count': published_count.str()
		'draft_count':     draft_count.str()
		'comment_count':   comment_count.str()
		'aggregated_at':   time.now().unix().str()
	}
	stats_json := json.encode(stats)

	cm.set('stats:blog', stats_json, 3600)!
	cm.set('stats:user_count', user_count.str(), 3600)!
	cm.set('stats:post_count', post_count.str(), 3600)!
	cm.set('stats:published_count', published_count.str(), 3600)!
	cm.set('stats:comment_count', comment_count.str(), 3600)!

	job_log_info('StatsAggregationJob: statistics aggregated — users=${user_count} posts=${post_count} comments=${comment_count}')
}

pub fn (j &StatsAggregationJob) tries() int {
	return 3
}

pub fn (j &StatsAggregationJob) backoff() []i64 {
	return [i64(1), 5, 10]
}

// ═══════════════════════════════════════════════════════════
// CleanupExpiredTokensJob
// ═══════════════════════════════════════════════════════════

pub struct CleanupExpiredTokensJob {
pub:
	run_at i64
}

pub fn (j &CleanupExpiredTokensJob) job_type() string {
	return 'CleanupExpiredTokens'
}

pub fn (j &CleanupExpiredTokensJob) handle() ! {
	unsafe {
		if isnil(g_cache) {
			return error('CleanupExpiredTokensJob: cache not initialized')
		}
	}

	mut cm := unsafe { g_cache }
	job_log_info('CleanupExpiredTokensJob: scanning for expired JWT blacklist tokens...')

	mut cleaned := 0
	unsafe {
		mut default_cache := g_cache.default_cache
		keys := default_cache.keys()
		for key in keys {
			if key.starts_with('jwt:blacklist:') {
				_ = cm.get(key) or {
					cleaned++
					continue
				}
			}
		}
	}

	job_log_info('CleanupExpiredTokensJob: cleanup complete, removed ${cleaned} expired token entries')
}

pub fn (j &CleanupExpiredTokensJob) tries() int {
	return 3
}

pub fn (j &CleanupExpiredTokensJob) backoff() []i64 {
	return [i64(1), 5, 10]
}

// ═══════════════════════════════════════════════════════════
// Job 工厂注册表
// ═══════════════════════════════════════════════════════════

pub fn register_jobs(worker &queue.QueueWorker) {
	mut w := unsafe { mut worker }
	w.register('SendWelcomeEmail', fn () &queue.Job {
		return &SendWelcomeEmailJob{}
	})
	w.register('SendCommentNotification', fn () &queue.Job {
		return &SendCommentNotificationJob{}
	})
	w.register('StatsAggregation', fn () &queue.Job {
		return &StatsAggregationJob{}
	})
	w.register('CleanupExpiredTokens', fn () &queue.Job {
		return &CleanupExpiredTokensJob{}
	})
}

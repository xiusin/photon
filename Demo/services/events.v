module services

// events.v — PhotonBlog 事件系统
//
// 定义事件常量与监听器注册入口。监听器通过 EventBus 订阅领域事件，
// 在事件触发时执行副作用（分发队列任务、清除缓存、推送通知等）。
//
// 事件清单：
//   user.registered  — 用户注册成功 → 发送欢迎邮件 + 失效统计缓存
//   user.logged_in   — 用户登录成功 → 记录日志（演示）
//   post.published   — 文章发布     → 清除文章缓存 + 推送通知
//   post.updated     — 文章更新     → 清除文章缓存
//   comment.posted   — 评论创建     → 通知文章作者

import photon.core
import photon.cache
import photon.queue
import photon.logger

// ═══════════════════════════════════════════════════════════
// 事件常量
// ═══════════════════════════════════════════════════════════

pub const event_user_registered = 'user.registered'
pub const event_user_logged_in = 'user.logged_in'
pub const event_post_published = 'post.published'
pub const event_post_updated = 'post.updated'
pub const event_comment_posted = 'comment.posted'

// ═══════════════════════════════════════════════════════════
// 监听器注册入口
// ═══════════════════════════════════════════════════════════

// register_event_listeners 将所有事件监听器注册到 EventBus
//
// 由 Bootstrap 在启动时调用，注入 CacheManager 与 Logger 依赖。
// 监听器内部通过 queue.dispatch 分发异步任务，通过 CacheManager
// 直接操作缓存。
pub fn register_event_listeners(bus &core.EventBus, cm &cache.CacheManager, log &logger.Logger) {
	mut b := unsafe { mut bus }

	// ── UserRegisteredListener ──
	// 分发 SendWelcomeEmailJob + 失效统计缓存
	b.on(event_user_registered, fn [cm, log] (e &core.Event) {
		email := e.data['email']
		username := e.data['username']

		log.info('[UserRegisteredListener] 处理用户注册事件: username=${username} email=${email}')

		// 分发欢迎邮件任务
		job := SendWelcomeEmailJob{
			email: email
			name: username
		}
		queue.dispatch(job) or {
			log.error('[UserRegisteredListener] 分发 SendWelcomeEmailJob 失败: ${err}')
		}

		// 失效统计缓存（TaggedCache 批量失效 'stats' 标签）
		flush_cache_tag(cm, 'stats')
		log.info('[UserRegisteredListener] 统计缓存已失效')
	})

	// ── UserLoggedInListener ──
	// 记录登录日志（演示用）
	b.on(event_user_logged_in, fn [log] (e &core.Event) {
		username := e.payload_str
		user_id := e.data['user_id']
		log.info('[UserLoggedInListener] 用户登录: id=${user_id} username=${username}')
	})

	// ── PostPublishedListener ──
	// 清除文章缓存 + 推送通知
	b.on(event_post_published, fn [cm, log] (e &core.Event) {
		post_id := e.data['post_id']
		title := e.data['title']

		log.info('[PostPublishedListener] 处理文章发布事件: id=${post_id} title="${title}"')

		// TaggedCache 批量失效 'posts' 和 'stats' 标签下所有缓存键
		flush_cache_tag(cm, 'posts')
		flush_cache_tag(cm, 'stats')

		// 推送通知（演示用 — 实际可接入 WebSocket / 站内信）
		log.info('[PostPublishedListener] 文章发布通知已推送: "${title}"')
	})

	// ── PostUpdatedListener ──
	// 清除文章缓存
	b.on(event_post_updated, fn [cm, log] (e &core.Event) {
		post_id := e.data['post_id']

		log.info('[PostUpdatedListener] 处理文章更新事件: id=${post_id}')

		// TaggedCache 批量失效 'posts' 标签下所有缓存键
		flush_cache_tag(cm, 'posts')
	})

	// ── CommentPostedListener ──
	// 分发通知邮件给文章作者
	b.on(event_comment_posted, fn [cm, log] (e &core.Event) {
		comment_id := e.data['comment_id'].int()
		post_id := e.data['post_id'].int()
		commenter := e.data['username']
		content := e.data['content']

		log.info('[CommentPostedListener] 处理评论事件: comment_id=${comment_id} post_id=${post_id} by=${commenter}')

		// 分发评论通知任务
		job := SendCommentNotificationJob{
			comment_id: comment_id
			post_id: post_id
			commenter: commenter
			content: content
		}
		queue.dispatch(job) or {
			log.error('[CommentPostedListener] 分发 SendCommentNotificationJob 失败: ${err}')
		}

		// 失效评论统计缓存（TaggedCache 批量失效 'stats' 标签）
		flush_cache_tag(cm, 'stats')
	})
}

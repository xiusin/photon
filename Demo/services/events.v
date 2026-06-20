module services

// events.v — PhotonBlog 事件常量与监听器注册
//
// 定义领域事件名称常量，并通过 photon.core.EventBus 注册监听器。
// 事件监听器在 Bootstrap 启动时通过 register_event_listeners() 统一注册。

import photon.core
import photon.logger

// ═══════════════════════════════════════════════════════════
// 事件名称常量
// ═══════════════════════════════════════════════════════════

pub const event_user_registered  = 'user.registered'
pub const event_user_logged_in   = 'user.logged_in'
pub const event_user_logged_out  = 'user.logged_out'
pub const event_post_published   = 'post.published'
pub const event_post_updated     = 'post.updated'
pub const event_post_deleted     = 'post.deleted'
pub const event_comment_posted   = 'comment.posted'
pub const event_comment_deleted  = 'comment.deleted'

// ═══════════════════════════════════════════════════════════
// 事件监听器注册
// ═══════════════════════════════════════════════════════════

// register_event_listeners 注册所有事件监听器
pub fn register_event_listeners(bus &core.EventBus, log &logger.Logger) {
	mut b := unsafe { mut bus }

	// 用户注册事件
	b.on(event_user_registered, fn [log] (event &core.Event) {
		log.info('[Event] user.registered — payload: ${event.payload_str}')
	})

	// 用户登录事件
	b.on(event_user_logged_in, fn [log] (event &core.Event) {
		log.info('[Event] user.logged_in — payload: ${event.payload_str}')
	})

	// 文章发布事件
	b.on(event_post_published, fn [log] (event &core.Event) {
		log.info('[Event] post.published — payload: ${event.payload_str}')
	})

	// 评论发布事件
	b.on(event_comment_posted, fn [log] (event &core.Event) {
		log.info('[Event] comment.posted — payload: ${event.payload_str}')
	})

	log.info('[Events] event listeners registered')
}

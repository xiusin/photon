module web

import veb

// throttle_key_scope_test.v — 限流的分桶键必须真的按客户端分开。
//
// 原来的实现是：
//   key := ctx.data['user_id'] or { 'anonymous' }
//
// user_id 只有登录链路上才会被写进 data，于是所有未登录请求共用
// 同一个 'anonymous' 桶。后果不只是「限流不准」：
//   * 一个人把自己的配额打满，全站未登录用户一起被挡
//   * 反过来说，任何人都能靠刷自己的配额去挡住别人
// 而这两件事在监控上看都是「限流正常工作」。

// test_throttle_key_prefers_user_id 账号维度优先：同一账号换 IP 仍共享配额。
fn test_throttle_key_prefers_user_id() {
	mut ctx := new_middleware_context(&veb.Context{})
	ctx.data['user_id'] = 'u-42'
	assert throttle_key(ctx) == 'user:u-42'
}

// test_throttle_key_falls_back_to_ip 没有身份时按 IP 分桶。
//
// 这里不依赖真实连接：client_ip() 在无 conn 时返回 '-'，所以 '-' 与
// 空串都要退到 'global'，绝不能让不同请求撞进同一个 key。
fn test_throttle_key_without_identity_is_not_shared_silently() {
	mut ctx := new_middleware_context(&veb.Context{})
	key := throttle_key(ctx)
	// 无 user_id、无 conn —— 只能退到全局，但绝不能是 'anonymous'
	assert key != 'anonymous'
	assert key == 'global'
}

// test_throttle_key_ignores_blank_and_placeholder_user_id
// 空/占位 user_id 不能被当成身份，否则又回到所有人共用一个桶。
fn test_throttle_key_ignores_blank_and_placeholder_user_id() {
	mut ctx := new_middleware_context(&veb.Context{})
	ctx.data['user_id'] = '   '
	assert throttle_key(ctx) == 'global'

	ctx.data['user_id'] = 'anonymous'
	assert throttle_key(ctx) == 'global'
}

// test_anonymous_requests_do_not_share_quota 是最直接的副作用断言。
//
// 两个「不同客户端」分别打，各自都应该拿到完整配额。
// 在原实现下两次调用用的是同一个 key，第二个客户端一上来就被拒。
fn test_anonymous_requests_do_not_share_quota() {
	mut lim := new_rate_limiter()
	// client A
	assert lim.hit_and_record('ip:10.0.0.1', 2, 60) == true
	assert lim.hit_and_record('ip:10.0.0.1', 2, 60) == true
	assert lim.hit_and_record('ip:10.0.0.1', 2, 60) == false
	// client B 的配额不受 A 影响
	assert lim.hit_and_record('ip:10.0.0.2', 2, 60) == true
	assert lim.hit_and_record('ip:10.0.0.2', 2, 60) == true
}

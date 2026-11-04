module web

import time

// ratelimit_boundary_test.v —— 限流器的两处「返回值形状正确、语义错误」
//
// 两条断言都盯「值是不是从正确的来源来的」：
//   1. remaining() 在无记录时必须等于配额本身
//   2. retry_after() 必须落在窗口内最早那条**未过期**记录上

fn test_remaining_without_records_equals_quota() {
	mut r := new_rate_limiter()
	// 一个从没被记录过的 key：剩余配额就是配额本身。
	// 旧实现 `r.attempts[key] or { return max_attempts }` 的 else 分支
	// 返回的是 Option 的默认值 0，于是「满配额」被报成「已用尽」。
	assert r.remaining('never-seen', 5, 60) == 5
	assert r.remaining('never-seen', 1, 60) == 1
}

fn test_remaining_after_hits_is_monotonic() {
	mut r := new_rate_limiter()
	assert r.remaining('k', 3, 60) == 3
	r.hit('k')
	assert r.remaining('k', 3, 60) == 2
	r.hit('k')
	assert r.remaining('k', 3, 60) == 1
	r.hit('k')
	// 第 max 次仍在配额内
	assert r.remaining('k', 3, 60) == 0
	assert !r.too_many_attempts('k', 3, 60)
	r.hit('k')
	// 第 max+1 次才超限
	assert r.too_many_attempts('k', 3, 60)
}

fn test_retry_after_ignores_expired_leading_records() {
	mut r := new_rate_limiter()
	// 直接注入时间戳：把「已过期」和「仍在窗口内」的记录混在同一个 key 上，
	// 且过期的那条排在前面（真实场景里就是这么累积出来的 ——
	// 过期记录只在 too_many_attempts/hit_and_record 里被顺手清掉，
	// 中间夹着别的操作就会留着）。
	now := time.now().unix()
	mut attempts := r.attempts['k'] or { []i64{} }
	attempts << now - 100 // 早已过期
	attempts << now - 2 // 仍在 60s 窗口内
	r.attempts['k'] = attempts

	// 旧实现取 attempts[0]（已过期）→ decay_time 落在过去 → 返回 0，
	// 于是 429 的 Retry-After 写成 0，调用方立刻重试、立刻再被拒。
	retry := r.retry_after('k', 60)
	assert retry > 50 && retry <= 60, 'retry_after=${retry}，应落在窗口内最早那条记录上'
}

fn test_retry_after_zero_when_all_expired() {
	mut r := new_rate_limiter()
	now := time.now().unix()
	r.attempts['k'] = [now - 100, now - 200]
	assert r.retry_after('k', 60) == 0
}

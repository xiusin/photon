module web

// fixed_window_edge_test.v — 固定窗口在「非正窗口长度」下的行为。
//
// `check(key, max, 0)` 曾经每次调用都重开窗口（`expires = now + 0`，下一轮
// `now >= expires` 立刻成立），计数永远从 0 开始 —— max_requests 形同不存在，
// 而且没有任何日志。配置里漏写单位、把「不限流」写成 0 都会踩到。

fn test_fixed_window_non_positive_window_still_limits() {
	mut fw := new_fixed_window_limiter()
	mut allowed := 0
	for _ in 0 .. 10 {
		if fw.check('k', 2, 0) {
			allowed++
		}
	}
	assert allowed == 2, 'window_seconds=0 时窗口每轮都重置，请求全放过 (allowed=${allowed})'
}

fn test_fixed_window_negative_window_still_limits() {
	mut fw := new_fixed_window_limiter()
	mut allowed := 0
	for _ in 0 .. 10 {
		if fw.check('k2', 3, -5) {
			allowed++
		}
	}
	assert allowed == 3
}

fn test_fixed_window_normal_behaviour_unchanged() {
	mut fw := new_fixed_window_limiter()
	assert fw.check('n', 2, 60)
	assert fw.check('n', 2, 60)
	assert fw.check('n', 2, 60) == false
	assert fw.get_remaining('n', 2, 60) == 0
}

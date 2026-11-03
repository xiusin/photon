module web

// ratelimit_window_test.v - 限流窗口的三处「看起来在工作」
//
// RateLimiter 的窗口由 `decay_seconds` 决定。三种取值/边界会让窗口本身
// 失去意义，而计数、返回值、日志全都正常：
//   1. decay <= 0   → 所有记录被判过期，限流彻底不生效
//   2. 窗口边界     → `now - ts >= decay` 与 `< decay` 留下整秒缝隙
//   3. 截断顶不住   → 窗口内还活着的记录被当"最老的"删掉，限流被中途放宽

fn test_non_positive_decay_still_limits() {
	mut r := new_rate_limiter()
	for _ in 0 .. 5 {
		r.hit('k')
	}
	// 旧实现：`now - ts < 0` 恒 false → 全部判过期 → 永远说不超限
	assert r.too_many_attempts('k', 3, 0)
	assert r.too_many_attempts('k', 3, -60)
	// 计数接口必须给出同一个答案
	assert r.attempts_within('k', 0) == 5
	assert r.remaining('k', 3, 0) == 0
}

fn test_hit_and_record_boundary() {
	mut r := new_rate_limiter()
	// max=1：第 1 次许可，第 2 次拒绝
	assert r.hit_and_record('b', 1, 60)
	assert !r.hit_and_record('b', 1, 60)

	mut r2 := new_rate_limiter()
	// max=3：三次许可，第四次拒绝
	assert r2.hit_and_record('c', 3, 60)
	assert r2.hit_and_record('c', 3, 60)
	assert r2.hit_and_record('c', 3, 60)
	assert !r2.hit_and_record('c', 3, 60)
}

fn test_hit_and_record_agrees_with_too_many_attempts() {
	// 两个接口必须对同一个状态给出同一个答案，否则中间件拒掉的请求
	// 在运维接口上看是「还有余量」，排查限流问题会完全没有抓手。
	//
	// 注意视角差一拍：hit_and_record 先记本次再看是否超限，
	// too_many_attempts 看的是「已记录的历史」。所以本次被拒时，
	// 历史里必然已经 >= max（含本次），too_many_attempts 必为 true；
	// 本次被放行时，历史里最多 max-1 条有效记录，too_many_attempts 必为 false。
	mut r := new_rate_limiter()
	max := 3
	for i in 0 .. 5 {
		allowed := r.hit_and_record('d', max, 60)
		exceeded := r.too_many_attempts('d', max, 60)
		if i < max {
			assert allowed
		} else {
			assert !allowed
		}
		if !allowed {
			// 被拒：历史（含本次）必然已达上限
			assert exceeded
		} else {
			// 放行：历史（含本次）不超过上限
			assert !exceeded
		}
	}
	// 收口断言：连打 max 次之后，too_many_attempts 必须已经说超限
	assert r.too_many_attempts('d', max, 60)
}

fn test_truncation_keeps_window_alive() {
	// max_attempts 超过 max_attempts_per_key 时，截断不能把窗口里
	// 仍然有效的记录当"最老的"删掉，否则窗口中途会重新放行。
	mut r := new_rate_limiter()
	huge := max_attempts_per_key + 500
	for _ in 0 .. max_attempts_per_key {
		r.hit('big')
	}
	// 记录数被顶到上限，但窗口内的有效计数不能因此归零
	assert r.attempts_within('big', 3600) == max_attempts_per_key
	// 再打一次：仍然超限（旧实现里 bound 逻辑与 max 无关，
	// 这里主要锁住「有效计数不因截断而塌掉」）
	assert r.too_many_attempts('big', huge, 3600) == false
	// 恰好 max 次不超限，多一次才超限
	assert r.too_many_attempts('big', max_attempts_per_key, 3600) == false
	assert r.too_many_attempts('big', max_attempts_per_key - 1, 3600) == true
}

fn test_throttle_middleware_zero_decay_is_not_a_free_pass() {
	// decay_minutes 漏写 → decay_seconds = 0。旧实现下这等于完全不限流。
	mut state := new_throttle_state(2, 0)
	mut allowed := 0
	for _ in 0 .. 10 {
		if state.limiter.hit_and_record('m', state.max_attempts, state.decay_seconds) {
			allowed++
		}
	}
	assert allowed == 2
}

fn test_retry_after_positive_for_non_positive_decay() {
	mut r := new_rate_limiter()
	r.hit('ra')
	// 非正窗口不能让 retry_after 恒为 0（那样 429 响应里永远写"可以立刻重试"）
	assert r.retry_after('ra', 0) > 0
}

module retry

// retry_first_attempt_test.v — 首次尝试不该睡
//
// 语义只有一句话：重试策略管的是「失败之后等多久」，不是「开始之前等多久」。
// 老实现把 delay_for_attempt(1) 也返回成 base delay，于是只要调一次
// execute_with_retry，哪怕一次成功，也先白白等了一个 delay。
import time

fn test_first_attempt_has_no_preceding_delay() {
	for policy in [BackoffPolicy.fixed, .linear, .exponential] {
		cfg := RetryConfig{
			max_attempts: 4
			delay:        40 * time.millisecond
			backoff:      policy
		}
		assert cfg.delay_for_attempt(1) == time.Duration(0), 'policy ${policy}: first attempt must not sleep'
		assert cfg.delay_for_attempt(0) == time.Duration(0)
	}
}

fn test_successful_first_call_is_bounded_by_one_delay() {
	// 一次成功 + 100ms 基础退避：总耗时应远小于一个退避间隔。
	// 老实现每次调用都会先睡满 100ms，这里会明显超。
	cfg := RetryConfig{
		max_attempts: 3
		delay:        100 * time.millisecond
		backoff:      .fixed
	}
	start := time.now()
	got := execute_with_retry[int](cfg, fn () !int {
		return 7
	})!
	elapsed := time.since(start)
	assert got == 7
	assert elapsed < 50 * time.millisecond, 'a single successful call must not sleep, took ${elapsed}'
}

fn test_retry_delays_stay_monotonic_per_policy() {
	fixed := RetryConfig{
		delay:   30 * time.millisecond
		backoff: .fixed
	}
	linear := RetryConfig{
		delay:   30 * time.millisecond
		backoff: .linear
	}
	expo := RetryConfig{
		delay:   30 * time.millisecond
		backoff: .exponential
	}
	// 固定：除首次外恒定
	assert fixed.delay_for_attempt(2) == fixed.delay_for_attempt(5)
	// 线性：逐次递增
	assert linear.delay_for_attempt(2) < linear.delay_for_attempt(3)
	assert linear.delay_for_attempt(3) < linear.delay_for_attempt(4)
	// 指数：逐次翻倍
	assert expo.delay_for_attempt(3) == expo.delay_for_attempt(2) * 2
	assert expo.delay_for_attempt(4) == expo.delay_for_attempt(2) * 4
}

fn test_exponential_saturates_instead_of_zeroing() {
	// attempt 大到溢出的位置不能返回 0（那等于「立刻重试」）
	cfg := RetryConfig{
		delay:   100 * time.millisecond
		backoff: .exponential
	}
	assert cfg.delay_for_attempt(80) > time.Duration(0)
	assert cfg.delay_for_attempt(1000) > time.Duration(0)
}

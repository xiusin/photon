module ticker

import time

// cron 解析过去对任何垃圾输入都返回一个「合法」结果：
// `'a'.int()` 在 V 里是 0，于是 "a b c d e" 被解析成「每天 0:00」。
// 这类缺陷不报错、不 panic，只是定时任务在错误的时间点跑。

fn test_garbage_token_is_rejected() {
	parse_cron('a b c d e') or {
		assert err.msg().contains('not a number')
		return
	}
	assert false
}

fn test_out_of_range_is_rejected() {
	if _ := parse_cron('60 * * * *') {
		assert false, 'minute 60 must be rejected'
	}
	if _ := parse_cron('* 24 * * *') {
		assert false, 'hour 24 must be rejected'
	}
	if _ := parse_cron('* * 32 * *') {
		assert false, 'day 32 must be rejected'
	}
	if _ := parse_cron('* * * 13 *') {
		assert false, 'month 13 must be rejected'
	}
	if _ := parse_cron('* * * * 8') {
		assert false, 'weekday 8 must be rejected'
	}
}

fn test_inverted_range_is_rejected() {
	// 5-1 之前会退化成空集合；空集合意味着这个任务永远不触发，
	// 而且没有任何地方报错。
	if _ := parse_cron('5-1 * * * *') {
		assert false, 'inverted range must be rejected'
	}
	if _ := parse_cron('*/5-1 * * * *') {
		assert false, 'inverted step range must be rejected'
	}
}

fn test_weekday_zero_and_seven_are_same_day() ! {
	// crontab 惯例：0 和 7 都是周日。time.day_of_week() 返回 1..7，
	// 所以 0 必须被归一化，否则 "0 9 * * 0" 永远不会匹配。
	sunday_zero := parse_cron('0 9 * * 0')!
	sunday_seven := parse_cron('0 9 * * 7')!
	assert sunday_zero[4].values == sunday_seven[4].values
	assert sunday_zero[4].values.len == 1
	assert sunday_zero[4].values[0] == 7

	t_sun := time.new(year: 2025, month: 6, day: 15, hour: 9, minute: 0)
	assert cron_matches(sunday_zero, t_sun)
	assert cron_matches(sunday_seven, t_sun)
}

fn test_whitespace_is_normalised() ! {
	// 手写 cron 里多打几个空格是常态，不该报「6 fields」。
	fields := parse_cron('  0  9 * * 1-5 ')!
	assert fields.len == 5
	assert fields[0].values == [0]
	assert fields[1].values == [9]
}

fn test_step_larger_than_range_yields_start_only() ! {
	fields := parse_cron('50/10 * * * *')!
	assert fields[0].values == [50]
}

fn test_step_of_zero_is_rejected() {
	if _ := parse_cron('*/0 * * * *') {
		assert false, 'step 0 must be rejected'
	}
}

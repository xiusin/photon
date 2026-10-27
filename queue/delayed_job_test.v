module queue

// delayed_job_test.v — 延迟任务确实会「延迟」
//
// push() 会给延迟任务的 payload 加上 `<run_at_ns>||` 前缀，但此前没有任何
// 代码消费这个前缀：
//   - worker 的 deserialize_job 按第一个 '||' 切分，拿到的 job_type 是那串
//     纳秒时间戳，按类型找不到工厂 → 任务被记成 "unregistered job type"
//   - 退避重试 / dispatch_later 全走这条路，等于延迟语义整体失效
//
// 这组测试锁住三件事：前缀确实写入了、到期的任务会执行、没到期的不执行。

import time

@[heap]
struct DelayedProbe {
mut:
	executed int
}

fn (j &DelayedProbe) job_type() string {
	return 'delayed_probe'
}

fn (j &DelayedProbe) handle() ! {}

fn (j &DelayedProbe) tries() int {
	return 1
}

fn (j &DelayedProbe) backoff() []i64 {
	return [i64(0)]
}

fn (j &DelayedProbe) data() string {
	return '{}'
}

fn (mut j DelayedProbe) from_json(data string) ! {}

fn make_delayed_probe() &Job {
	mut j := DelayedProbe{}
	return &j
}

fn test_delayed_push_prefixes_run_at() {
	mut d := new_memory_driver()
	before := time.now().unix_nano()
	d.push_delayed('delayed', serialize_job('delayed_probe', '{}'), 2)!
	assert d.count('delayed') == 1

	// 未到期：pop 不出来
	if _ := d.pop('delayed') {
		assert false, 'not-yet-due job must not be visible'
	}
	_ = before
}

fn test_push_delayed_is_visible_after_due() {
	mut d := new_memory_driver()
	d.push_delayed('q', serialize_job('delayed_probe', '{}'), -1)!
	payload := d.pop('q')!
	assert payload.contains('||')
	run_at, inner := split_delay(payload)
	assert run_at > 0
	assert inner == serialize_job('delayed_probe', '{}')
}

fn test_run_at_prefix_is_parsed() {
	raw := '1700000000000000000||${serialize_job('delayed_probe', '{}')}'
	run_at, inner := split_delay(raw)
	assert run_at == 1700000000000000000
	assert inner == serialize_job('delayed_probe', '{}')
	// 不是时间戳前缀的原样返回
	plain := serialize_job('delayed_probe', '{}')
	plain_run_at, plain_inner := split_delay(plain)
	assert plain_run_at == 0
	assert plain_inner == plain
}

fn test_immediate_job_not_mistaken_for_delayed() {
	// job_type 里含 '||' 也不能被误判成延迟前缀（首段必须全数字）
	raw := 'abc||def'
	assert delayed_run_at(raw) == 0
	assert strip_delay_prefix(raw) == raw
}

fn test_delayed_job_does_not_block_immediate_job() {
	mut d := new_memory_driver()
	d.push('q', 'immediate')!
	d.push_delayed('q', 'future', 3600)!
	// 延迟任务不能挡住后面的立即任务
	assert d.pop('q')! == 'immediate'
}

fn test_worker_runs_ready_delayed_job() {
	mut disp := get_dispatcher()
	disp.driver.clear('default') or {}
	disp.driver.push_delayed('default', serialize_job('delayed_probe', '{}'), -1)!

	mut w := new_worker()
	w.register('delayed_probe', make_delayed_probe)
	w.run()
	w.tick()
	w.stop()

	stats := get_queue_stats('default')
	assert stats.completed >= 1
}

// ── dispatch_later 必须真的延迟，并且计入 pending ──

fn test_dispatch_later_is_not_run_immediately() {
	clear_queue()!
	d := get_dispatcher()
	d.driver.clear('default')!

	dispatch_later(&DelayedProbe{}, 60)!

	// 还没到期：pop 必须拿不到
	if payload := d.driver.pop('default') {
		assert false, 'delayed job became visible before its run_at: ${payload}'
	}
	// 但队列里确实有一条待处理
	assert d.driver.count('default') == 1
	clear_queue()!
}

fn test_dispatch_later_zero_delay_is_immediate() {
	mut drv := new_memory_driver()
	drv.push_delayed('q', 'Job||{}', 0)!
	// delay=0 → run_at 就是当下，pop 立刻可见
	assert drv.count('q') == 1
	payload := drv.pop('q')!
	assert payload.contains('Job')
}

fn test_dispatch_later_counts_pending_stat() {
	d := get_dispatcher()
	d.driver.clear('default')!
	dispatch_later(&DelayedProbe{}, 30)!
	stats := get_queue_stats('default')
	assert stats.pending == 1
	clear_queue()!
}

fn test_push_with_delay_uses_delayed_table() {
	mut d := get_dispatcher()
	d.driver.clear('default')!
	push('default', &DelayedProbe{}, 45)!
	// 未到期 → 取不到，但 count 里有它
	if _ := d.driver.pop('default') {
		assert false, 'delayed job must not be popped immediately'
	}
	assert d.driver.count('default') == 1
	clear_queue()!
}

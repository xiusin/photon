module queue

// delayed_job_test.v — 延迟任务确实会「延迟」，且出队 payload 是干净的
//
// 历史包袱：早期 push_delayed() 会把 `<run_at_ns>||` 前缀拼进 payload，
// 而没有任何代码消费这个前缀 —— worker 的 deserialize_job 按第一个 '||'
// 切分，拿到的 job_type 是那串纳秒时间戳，按类型找不到工厂，任务被记成
// "unregistered job type"。
//
// 现在的契约：
//   * MemoryDriver 把 run_at 只存在自己的 delayed 表里，**不**写进 payload；
//   * 到期搬进主队列时再剥一次前缀（兼容历史数据）；
//   * RedisDriver 把 run_at 放在 zset 的 score 里 —— 两个驱动出队的
//     payload 形态因此完全一致，换驱动不需要换约定。
//
// 这组测试锁住四件事：未到期不可见、到期可执行、出队 payload 无前缀、
// 延迟任务不挡立即任务。

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

fn test_delayed_push_is_held_back_until_due() {
	mut d := new_memory_driver()
	d.push_delayed('delayed', serialize_job('delayed_probe', '{}'), 2)!
	// 延迟项计入队列长度，但 pop 取不到
	assert d.count('delayed') == 1
	if _ := d.pop('delayed') {
		assert false, 'not-yet-due job must not be visible'
	}
}

fn test_push_delayed_is_visible_after_due() {
	mut d := new_memory_driver()
	// 负延迟 = 已到期：应立刻出队，并且 payload 是干净的（不带 run_at 前缀）
	d.push_delayed('q', serialize_job('delayed_probe', '{}'), -1)!
	payload := d.pop('q')!
	assert payload == serialize_job('delayed_probe', '{}')
	run_at, inner := split_delay(payload)
	assert run_at == 0, 'popped payload must not carry a run_at prefix'
	assert inner == payload
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
	// 未到期的仍然留在延迟表里
	assert d.count('q') == 1
}

fn test_expired_delayed_payload_has_no_prefix() {
	// 到期搬运进主队列时，run_at 前缀必须已经剥掉：
	// 否则 worker 会把纳秒时间戳当成 job_type，任务被记成
	// 「unregistered job type」—— 不报错，但任务根本没执行。
	mut d := new_memory_driver()
	d.push_delayed('q', 'DelayedJob||{"id":1}', -1)!
	payload := d.pop('q')!
	assert payload == 'DelayedJob||{"id":1}'
}

fn test_zero_delay_payload_is_clean() {
	mut d := new_memory_driver()
	d.push_delayed('q', 'DelayedJob||{}', 0)!
	assert d.pop('q')! == 'DelayedJob||{}'
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
	mut d := get_dispatcher()
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
	// delay=0 → 直接进主队列，pop 立刻可见且 payload 干净
	assert drv.count('q') == 1
	payload := drv.pop('q')!
	assert payload == 'Job||{}'
}

fn test_dispatch_later_counts_pending_stat() {
	mut d := get_dispatcher()
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

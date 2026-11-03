module queue

import time

// backoff_retry_count_test.v — 带退避的重放，计数还能不能接上。
//
// 失败任务有两条重放入口：
//   retry(id)              —— delay 0，payload 直接进主队列
//   retry_with_backoff(id) —— delay > 0，payload 头部多了 <run_at_ns>||
//
// 计数靠 payload 头部的 `#r<n>` 传递。而 `#r` 的位置在两种情况下不同：
//   立即重放：  #r2||DemoJob||{}
//   退避重放：  <run_at_ns>||#r2||DemoJob||{}
//
// 原来 payload_retry_count() 只看 payload 的**开头**是不是 `#r`，
// 于是退避重放这条路径上它恒返回 0。表现出来就是：
//   * 任务退避重放后再失败 → 新记录 retry_count = 0
//   * 退避延迟 = 1s * 2^0 = 1s，永远不会增长
//   * max_retries 永远数不到上限 → 死信队列变成永动机
//
// 已有的 failed_jobs_bound_test 只覆盖了前者（delay 0）。这两条用例
// 专门盯后者。

// test_payload_retry_count_reads_delayed_payload 直接锁住解析函数。
fn test_payload_retry_count_reads_delayed_payload() {
	// 立即重放形态
	assert payload_retry_count('#r2||DemoJob||{}') == 2
	// 退避重放形态 —— `#r` 不在开头
	assert payload_retry_count('1700000000000000000||#r2||DemoJob||{}') == 2
	// 多层延迟前缀（理论上不该出现，但解析规则必须一致）
	assert payload_retry_count('1700000000000000000||1700000000000000001||#r5||DemoJob||{}') == 5
	// 没有计数头
	assert payload_retry_count('DemoJob||{}') == 0
	assert payload_retry_count('1700000000000000000||DemoJob||{}') == 0
	// 非数字时间戳不能被当成延迟前缀
	assert payload_retry_count('#r3||DemoJob||{}') == 3
}

// test_backoff_replay_keeps_accumulating 是端到端的那一条。
//
// 走 retry_with_backoff（真实退避路径），把投递出去的 payload 捞回来
// 再喂给 handle()，看新记录的 retry_count 有没有接上。
fn test_backoff_replay_keeps_accumulating() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	// 这一条要验证的是「计数能不能累加」，不是上限，先放开
	h.max_retries = -1

	h.handle('DemoJob', 'DemoJob||{}', 'boom', 'default', 1)!
	first := repo.all()![0]
	assert first.retry_count == 0

	// 带退避重放：delay = 1s * 2^0 = 1s > 0，payload 会带 <run_at_ns>|| 前缀
	h.retry_with_backoff(first.id)!

	popped := pending_delayed_payload('default')
	assert popped.len > 0, '退避重放没有投递出任务'
	assert payload_retry_count(popped) == 1, '退避重放的 payload 上读不到 #r1：延迟前缀把计数头挡住了'

	// 重放后再次失败
	h.handle('DemoJob', popped, 'boom again', 'default', 1)!
	second := repo.all()![0]
	assert second.retry_count == 1, '退避重放后再次失败，计数必须接上 1，而不是重置成 0'
}

// test_backoff_delay_grows_with_accumulated_count 锁住「退避真的在增长」。
//
// 计数读成 0 时，第二次退避仍是 1s —— 这才让死信队列变成永动机：
// 每次都以同样的间隔重投，且每次都声称自己「刚重试过一次」。
fn test_backoff_delay_grows_with_accumulated_count() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	h.max_retries = -1

	// 用「失败一次 → 退避重放 three 次」累积出 retry_count = 3，
	// 而不是手写一条记录：手写的记录不会被 retry 删除，
	// 会和重投出去的新记录在 repo 里并存，断言容易看错那一条。
	h.handle('DemoJob', 'DemoJob||{}', 'boom', 'default', 1)!
	first := repo.all()![0]

	mut payload := first.payload
	for _ in 0 .. 3 {
		h.retry_with_backoff(first.id)!
		payload = pending_delayed_payload('default')
		// 把投递出去的 payload 重新记为一条失败，模拟「重放后又失败」
		h.handle('DemoJob', payload, 'boom again', 'default', 1)!
		// 清掉延迟表里那条，下一轮看新一轮投递
		clear_pending_delayed('default')
	}
	assert payload_retry_count(payload) == 3, '三轮退避重放后计数应为 3，实际=${payload_retry_count(payload)}'

	// 第 4 次退避：2^3 = 8s
	last := repo.all()!.last()
	h.retry_with_backoff(last.id)!
	after := pending_delayed_payload('default')
	assert payload_retry_count(after) == 4, '重放后计数应递增到 4'
	saved := repo.find_by_id(last.id)!
	expected := time.now().unix() + 8
	assert saved.next_retry >= expected - 3 && saved.next_retry <= expected + 3, '退避秒数应为 2^3 = 8s，实际 next_retry 与 now 相差 ${saved.next_retry - time.now().unix()}s'
}

// clear_pending_delayed 清空延迟表，避免上一轮投递影响下一轮的取用。
fn clear_pending_delayed(queue_name string) {
	d := get_dispatcher()
	mut md := unsafe { &MemoryDriver(d.driver) }
	md.mu.@lock()
	defer { md.mu.unlock() }
	md.delayed.delete(queue_name)
}

// pending_delayed_payload 取出队列里**尚未到期**的那条延迟 payload 原文。
//
// 为什么要看原文、而不是直接 pop：MemoryDriver.pop() 在搬运到期任务时
// 会剥掉 `<run_at_ns>||` 前缀（见 promote_ready_delayed）。也就是说，
// worker 真正拿到的是干净串，payload_retry_count 在 worker 侧一直是好的。
//
// 出问题的是**投递瞬间**：record_failure 收到的 payload 来自 retry 时
// 构造的原始串，此时 `#r` 前面还压着延迟前缀。计数在这一步读成 0，
// 新记录的 retry_count 就被写成 0，退避与 max_retries 随即失效。
// 所以这里要取原文验证。
fn pending_delayed_payload(queue_name string) string {
	d := get_dispatcher()
	mut md := unsafe { &MemoryDriver(d.driver) }
	md.mu.@lock()
	defer { md.mu.unlock() }
	list := md.delayed[queue_name] or { return '' }
	if list.len == 0 {
		return ''
	}
	return list[0]
}

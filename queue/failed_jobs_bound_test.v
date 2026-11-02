module queue

// failed_jobs_bound_test.v - 死信重投必须收敛
//
// 旧行为：retry() 先删记录再投递；任务再次失败时 record_failure 把计数
// 写成 0 并存成一条新记录。于是「失败 → 重放 → 再失败 → 再重放」永远
// 循环：仓库里永远一条记录，retry_count 永远是 0，退避算出来永远是 1 秒。
// 死信队列看起来在"处理"，实际是一台停不下来的重投机器。
//
// 这组测试锁住两件事：
//   1. 重放次数随 payload 走，第二次失败能接上第一次的计数
//   2. 超过 max_retries 的记录拒绝重放（而不是原地再重投一轮）

fn test_retry_count_travels_with_payload() {
	// 没有任何元数据 → 0
	assert payload_retry_count('DemoJob||{}') == 0
	// 带头 → 读出计数
	assert payload_retry_count('#r3||DemoJob||{}') == 3
	// 头被剥掉之后交给 worker 的仍然是干净的 job_type
	job_type, data := split_delay_payload('#r2||DemoJob||{"a":1}')
	assert job_type == 'DemoJob'
	assert data == '{"a":1}'
	// 坏头按「没有」处理，不当成 0 次之外的东西
	assert payload_retry_count('#rabc||DemoJob||{}') == 0
}

fn test_retry_attempt_tags_payload_in_driver() {
	mut d := new_memory_driver()
	d.push_attempt('q', 'DemoJob||{}', 0, 2)!
	popped := d.pop('q')!
	assert payload_retry_count(popped) == 2
	jt, data := split_delay_payload(popped)
	assert jt == 'DemoJob'
	assert data == '{}'
}

fn test_failure_after_replay_keeps_accumulating() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)

	// 第一次失败：计数 0
	h.handle('DemoJob', 'DemoJob||{}', 'boom', 'default', 1)!
	first := repo.all()![0]
	assert first.retry_count == 0

	// 重放一次：payload 带上 #r1，任务再次失败时记录必须是 1
	h.retry(first.id)!
	mut d := get_dispatcher()
	popped := d.driver.pop('default')!
	assert payload_retry_count(popped) == 1
	h.handle('DemoJob', popped, 'boom again', 'default', 1)!
	second := repo.all()![0]
	assert second.retry_count == 1, 'replayed job must not restart its counter at 0'
}

fn test_retry_stops_after_max_retries() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	h.max_retries = 2

	id := seed_bound_record(mut h, 2)
	mut failed := false
	h.retry(id) or { failed = true }
	assert failed, 'a job that already used up its replays must be rejected'
	assert repo.count() == 1, 'rejected job must stay in the dead-letter list'
}

fn test_retry_all_skips_exhausted_records() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	h.max_retries = 1

	// 一条耗尽的、一条还能重放的
	seed_bound_record(mut h, 5)
	mut ok_job := FailedJob{
		id:        'fresh'
		job_type:  'DemoJob'
		payload:   'DemoJob||{}'
		failed_at: 1
	}
	repo.save(ok_job)!
	assert repo.count() == 2

	h.retry_all()!
	// 耗尽的留着，能重放的被移出
	remaining := repo.all()!
	assert remaining.len == 1
	assert remaining[0].retry_count == 5
}

fn test_zero_max_retries_means_unlimited() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	h.max_retries = -1
	id := seed_bound_record(mut h, 99)
	h.retry(id)!
	assert repo.count() == 0, 'negative max_retries must disable the cap'
}

// seed_bound_record 造一条已经重放过 retry_count 次的失败记录。
fn seed_bound_record(mut h FailedJobHandler, retry_count int) string {
	payload := attach_retry_count('DemoJob||{}', retry_count)
	h.handle('DemoJob', payload, 'boom', 'default', 1) or {}
	jobs := h.repository.all() or { []FailedJob{} }
	return jobs[jobs.len - 1].id
}

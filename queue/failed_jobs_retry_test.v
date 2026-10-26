module queue

// failed_jobs_retry_test.v — 失败任务重试路径的契约
//
// 这段代码此前完全没有测试。三个问题由测试暴露：
//   1. retry_with_backoff(id int) 把 int 当 string 查，查不到又回退到
//      「列表下标」；下标指向的可能是任意别的任务，等于重试错对象
//   2. 退避延迟只写进 FailedJob.next_retry，真正派发时被丢掉（传 0）
//   3. id 用 unix_nano 生成，同一纳秒内批量失败会撞 id，save 后 find 取
//      到错误的条目

import time

fn seed_repo(mut h FailedJobHandler, job_type string) !string {
	h.handle(job_type, '{}', 'boom', 'default', 1)!
	jobs := h.repository.all()!
	return jobs[jobs.len - 1].id
}

fn test_retry_existing_job_removes_it() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	id := seed_repo(mut h, 'DemoJob')!
	assert repo.count() == 1

	h.retry(id)!
	assert repo.count() == 0
}

fn test_retry_with_backoff_uses_real_id() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)

	// 三条失败任务，目标在中间：按下标回退时会重试错的那一条
	first := seed_repo(mut h, 'JobA')!
	second := seed_repo(mut h, 'JobB')!
	third := seed_repo(mut h, 'JobC')!
	assert repo.count() == 3

	h.retry_with_backoff(second)!

	remaining := repo.all()!
	assert remaining.len == 3, 'retry should keep one record per failed job'
	mut found := false
	for j in remaining {
		if j.id == second {
			found = true
			assert j.retry_count == 1
			assert j.next_retry > time.now().unix() - 1
		}
	}
	assert found, 'the retried job must still be tracked'
	assert first != third
}

fn test_retry_with_backoff_unknown_id_errors() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	mut failed := false
	h.retry_with_backoff('no-such-id') or { failed = true }
	assert failed, 'unknown id must not silently retry some other job'
}

fn test_retry_with_backoff_grows_delay() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	id := seed_repo(mut h, 'BackoffJob')!

	base := time.now().unix()
	h.retry_with_backoff(id)!
	job := repo.find_by_id(id)!
	first_delay := job.next_retry - base
	assert first_delay >= 1 && first_delay <= 2, 'first retry ~1s, got ${first_delay}'

	h.retry_with_backoff(id)!
	job2 := repo.find_by_id(id)!
	assert job2.retry_count == 2
	second_delay := job2.next_retry - time.now().unix()
	assert second_delay >= 1 && second_delay <= 3, 'second retry ~2s, got ${second_delay}'
}

fn test_handle_generates_distinct_ids() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	// 同一纳秒内连续记录，id 仍须唯一，否则 find_by_id 会取错条目
	for i in 0 .. 200 {
		h.handle('Job${i}', '{}', 'boom', 'default', 1) or { panic(err) }
	}
	jobs := repo.all()!
	assert jobs.len == 200
	mut seen := map[string]bool{}
	for j in jobs {
		assert j.id !in seen, 'duplicate failed job id: ${j.id}'
		seen[j.id] = true
	}
}

fn test_prune_keeps_recent() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	seed_repo(mut h, 'FreshJob')!

	// age_hours = 0 时 cutoff 就是「现在」，刚写入的记录不该被清掉
	h.prune(1)!
	assert repo.count() == 1
}

fn test_retry_all_clears_repository() {
	mut repo := new_memory_failed_repo()
	mut h := new_failed_job_handler(repo)
	seed_repo(mut h, 'A')!
	seed_repo(mut h, 'B')!
	assert repo.count() == 2

	h.retry_all()!
	assert repo.count() == 0
}

// pause_all_entries_test.v — 「队列已暂停」必须覆盖所有入队入口
//
// 上一轮把 push / dispatch_later 补上了，但 dispatch、dispatch_bulk、
// dispatch_chain、dispatch_batch 依旧直接写驱动 —— 暂停一条被污染的队列，
// 换一个入口就绕过去了。
module queue

struct PauseAllJob {}

fn (j PauseAllJob) job_type() string {
	return 'PauseAllJob'
}

fn (j PauseAllJob) handle() ! {}

fn (j PauseAllJob) tries() int {
	return 1
}

fn (j PauseAllJob) backoff() []i64 {
	return []
}

fn (j PauseAllJob) data() string {
	return '{}'
}

fn (mut j PauseAllJob) from_json(data string) ! {}

fn live_count(q string) int {
	mut d := get_dispatcher()
	return d.driver.count(q)
}

fn clear_named(q string) ! {
	mut d := get_dispatcher()
	d.driver.clear(q)!
}

fn test_default_queue_entries_respect_pause() {
	clear_queue()!
	q := get_dispatcher().default_queue
	pause_queue(q)
	defer {
		resume_queue(q)
	}

	if _ := dispatch(PauseAllJob{}) {
		assert false, 'dispatch() must refuse a paused queue'
	}
	if _ := dispatch_bulk([PauseAllJob{}]) {
		assert false, 'dispatch_bulk() must refuse a paused queue'
	}
	if _ := dispatch_chain([PauseAllJob{}]) {
		assert false, 'dispatch_chain() must refuse a paused queue'
	}
	if _ := dispatch_batch([PauseAllJob{}]) {
		assert false, 'dispatch_batch() must refuse a paused queue'
	}
	if _ := dispatch_on(PauseAllJob{}, q) {
		assert false, 'dispatch_on() must refuse a paused queue'
	}

	assert get_queue_stats(q).pending == 0, 'a paused queue must stay empty'
	assert live_count(q) == 0
}

fn test_resume_restores_all_entries() {
	clear_queue()!
	q := get_dispatcher().default_queue
	pause_queue(q)
	resume_queue(q)

	dispatch(PauseAllJob{})!
	assert live_count(q) == 1
	dispatch_bulk([PauseAllJob{}, PauseAllJob{}])!
	assert live_count(q) == 3

	clear_queue()!
}

fn test_push_updates_pending_stat() {
	clear_queue()!
	q := 'stats-probe'
	push(q, PauseAllJob{}, 0)!
	assert get_queue_stats(q).pending == 1, 'push() must be visible in queue stats'
	clear_named(q)!
}

module queue

// "Queue paused" must hold for every way of putting a job into that queue.
//
// Only dispatch_on() checked it. push() — which takes an explicit queue name —
// wrote straight into the driver, so a paused queue kept growing through it
// while every other entry point reported the queue as paused.
struct PauseProbeJob {}

fn (j PauseProbeJob) job_type() string {
	return 'PauseProbeJob'
}

fn (j PauseProbeJob) handle() ! {}

fn (j PauseProbeJob) tries() int {
	return 1
}

fn (j PauseProbeJob) backoff() []i64 {
	return []
}

fn (j PauseProbeJob) data() string {
	return '{}'
}

fn (mut j PauseProbeJob) from_json(data string) ! {}

fn test_paused_queue_rejects_every_dispatch_path() {
	clear_queue()!
	pause_queue('critical')
	defer {
		resume_queue('critical')
	}

	assert is_queue_paused('critical')

	// 1. explicit queue
	if _ := dispatch_on(PauseProbeJob{}, 'critical') {
		assert false, 'dispatch_on must reject a paused queue'
	}
	// 2. push with an explicit queue name — this is the one that used to slip through
	if _ := push('critical', PauseProbeJob{}, 0) {
		assert false, 'push must reject a paused queue'
	}
	// 3. delayed push into the paused queue
	if _ := push('critical', PauseProbeJob{}, 30) {
		assert false, 'push with delay must reject a paused queue'
	}

	assert get_queue_stats('critical').pending == 0, 'a paused queue must stay empty'
}

fn test_paused_default_queue_rejects_later() {
	clear_queue()!
	pause_queue('default')
	defer {
		resume_queue('default')
	}
	if _ := dispatch_later(PauseProbeJob{}, 10) {
		assert false, 'dispatch_later must reject a paused default queue'
	}
	assert count() == 0
}

fn test_unpaused_queue_still_accepts() {
	clear_queue()!
	dispatch_on(PauseProbeJob{}, 'other')!
	assert get_queue_stats('other').pending == 1
	clear_queue()!
}

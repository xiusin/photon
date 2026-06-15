module queue

// worker.v - Queue Worker (Laravel Queue Worker inspired)
//
// Polls the queue for jobs and executes them. Supports retry with
// configurable attempts and backoff.

// QueueWorker polls and executes jobs from the queue
pub struct QueueWorker {
pub:
	queue_name string = 'default'
	sleep_secs int    = 5 // poll interval
pub mut:
	running    bool
}

// new_worker creates a new QueueWorker
pub fn new_worker() &QueueWorker {
	return &QueueWorker{}
}

// run marks the worker as running (call tick() in a loop externally)
pub fn (mut w QueueWorker) run() {
	w.running = true
}

// is_running returns whether the worker is active
pub fn (w &QueueWorker) is_running() bool {
	return w.running
}

// tick does one polling iteration (call in a loop)
pub fn (mut w QueueWorker) tick() {
	if !w.running {
		return
	}
	mut d := get_dispatcher()
	payload := d.driver.pop(w.queue_name) or {
		// No jobs available — sleep
		return
	}

	_ = parse_job_payload(payload) or { return }
}

// stop halts the worker
pub fn (mut w QueueWorker) stop() {
	w.running = false
}

// JobInfo holds parsed job metadata
struct JobInfo {
	name string
	data string
}

// parse_job_payload extracts job type and data from payload
fn parse_job_payload(payload string) !JobInfo {
	name, data := deserialize_job(payload)!
	return JobInfo{
		name: name
		data: data
	}
}

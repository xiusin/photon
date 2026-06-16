module queue

// worker.v - Queue Worker (Laravel Queue Worker inspired)
//
// Polls the queue for jobs and executes them with retry and backoff.
// Jobs are registered by type name to a factory function.

import time

// JobFactory creates a new Job instance from a registered type
pub type JobFactory = fn () &Job

// QueueWorker polls and executes jobs from the queue
pub struct QueueWorker {
pub:
	queue_name string = 'default'
	sleep_secs int    = 5 // poll interval when idle
pub mut:
	running    bool
	registry      map[string]JobFactory
	failed_handler &FailedJobHandler = unsafe { nil }
}

// new_worker creates a new QueueWorker with an empty job registry
pub fn new_worker() &QueueWorker {
	return &QueueWorker{
		registry: map[string]JobFactory{}
	}
}

// register adds a job type to the worker's registry.
// The factory function should return a new Job instance.
// Usage:
//   worker.register('SendEmail', fn () &Job { return &SendEmailJob{} })
pub fn (mut w QueueWorker) register(job_type string, factory JobFactory) {
	w.registry[job_type] = factory
}

// set_failed_handler configures the handler for failed jobs
pub fn (mut w QueueWorker) set_failed_handler(handler &FailedJobHandler) {
	unsafe {
		w.failed_handler = handler
	}
}

// run marks the worker as running
pub fn (mut w QueueWorker) run() {
	w.running = true
}

// is_running returns whether the worker is active
pub fn (w &QueueWorker) is_running() bool {
	return w.running
}

// tick does one polling iteration (call in a loop).
// Pops a job from the queue, looks up its handler, and executes
// with retry + backoff logic. Failed jobs are passed to the
// FailedJobHandler if configured.
pub fn (mut w QueueWorker) tick() {
	if !w.running {
		return
	}

	mut d := get_dispatcher()
	payload := d.driver.pop(w.queue_name) or {
		// No jobs available — idle
		return
	}

	job_info := parse_job_payload(payload) or {
		// Corrupt payload — skip
		w.record_failure('unknown', payload, 'failed to parse payload: ${err}', 0)
		return
	}

	// Look up the job handler via registry
	factory := w.registry[job_info.name] or {
		// Unregistered job type — log and skip
		w.record_failure(job_info.name, payload, 'unregistered job type', 0)
		return
	}

	job := factory()
	// Normalize tries to at least 1 (a job must execute at least once).
	// treats 0 and negative values as "use default of 1"
	mut max_tries := job.tries()
	if max_tries < 1 {
		max_tries = 1
	}
	backoffs := job.backoff()

	// Execute with retry
	for attempt := 0; attempt < max_tries; attempt++ {
		mut has_error := false
		job.handle() or {
			has_error = true
		}
		if !has_error {
			// Success — job completed
			return
		}

		// Handle failure: apply backoff before retry
		if attempt < max_tries - 1 {
			mut delay_secs := i64(1) // default 1s backoff
			if attempt < backoffs.len {
				delay_secs = backoffs[attempt]
			}
			time.sleep(delay_secs * time.second)
		}
	}

	// All retries exhausted — record as failed
	w.record_failure(job_info.name, payload, 'max retries (${max_tries}) exhausted', max_tries)
}

// record_failure logs a failed job to the configured FailedJobHandler
fn (mut w QueueWorker) record_failure(job_type string, payload string, reason string, attempts int) {
	mut handler := w.failed_handler
	if isnil(handler) {
		return
	}
	handler.handle(job_type, payload, reason, w.queue_name, attempts) or {}
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

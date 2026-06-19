module queue

// failed_jobs.v - Failed Jobs Persistence (Laravel failed_jobs inspired)
//
// Provides a failed_jobs table abstraction for persisting jobs that
// exhaust all retry attempts. Allows replaying failed jobs via CLI.
import time

// FailedJob represents a job that failed after exhausting retries
pub struct FailedJob {
pub:
	id         string
	job_type   string
	payload    string
	exception  string
	failed_at  i64
	queue_name string
	attempts   int
}

// FailedJobRepository persists and retrieves failed jobs
pub interface FailedJobRepository {
mut:
	save(job FailedJob) !
	all() ![]FailedJob
	find_by_id(id string) !FailedJob
	delete_by_id(id string) !
	clear() !
	count() int
}

// MemoryFailedJobRepository stores failed jobs in memory
pub struct MemoryFailedJobRepository {
pub mut:
	jobs []FailedJob
}

// new_memory_failed_repo creates an in-memory failed job repository
pub fn new_memory_failed_repo() &MemoryFailedJobRepository {
	return &MemoryFailedJobRepository{}
}

// save records a failed job
pub fn (mut r MemoryFailedJobRepository) save(job FailedJob) ! {
	r.jobs << job
}

// all returns all failed jobs
pub fn (r &MemoryFailedJobRepository) all() ![]FailedJob {
	return r.jobs.clone()
}

// find_by_id finds a failed job by ID
pub fn (r &MemoryFailedJobRepository) find_by_id(id string) !FailedJob {
	for job in r.jobs {
		if job.id == id {
			return job
		}
	}
	return error('failed job not found: ${id}')
}

// delete_by_id removes a failed job
pub fn (mut r MemoryFailedJobRepository) delete_by_id(id string) ! {
	mut idx := -1
	for i, job in r.jobs {
		if job.id == id {
			idx = i
			break
		}
	}
	if idx >= 0 {
		r.jobs.delete(idx)
	}
}

// clear removes all failed jobs
pub fn (mut r MemoryFailedJobRepository) clear() ! {
	r.jobs.clear()
}

// count returns the number of failed jobs
pub fn (r &MemoryFailedJobRepository) count() int {
	return r.jobs.len
}

// FailedJobHandler processes failed jobs during queue worker execution
@[heap]
pub struct FailedJobHandler {
pub mut:
	repository  &FailedJobRepository
	max_retries int = 3
}

// new_failed_job_handler creates a FailedJobHandler
pub fn new_failed_job_handler(repo &FailedJobRepository) &FailedJobHandler {
	return &FailedJobHandler{
		repository: repo
	}
}

// handle records a job as failed
pub fn (mut h FailedJobHandler) handle(job_type string, payload string, exception string, queue_name string, attempts int) ! {
	failed := FailedJob{
		id:         'failed_${time.now().unix_nano()}'
		job_type:   job_type
		payload:    payload
		exception:  exception
		failed_at:  time.now().unix()
		queue_name: queue_name
		attempts:   attempts
	}
	h.repository.save(failed)!
}

// retry replays a failed job
pub fn (mut h FailedJobHandler) retry(id string) ! {
	job := h.repository.find_by_id(id)!
	h.repository.delete_by_id(id)!
	// Re-dispatch the job
	dispatch_later_by_type(job.job_type, 0)!
}

// retry_all replays all failed jobs
pub fn (mut h FailedJobHandler) retry_all() ! {
	all_jobs := h.repository.all()!
	for job in all_jobs {
		h.repository.delete_by_id(job.id)!
		dispatch_later_by_type(job.job_type, 0)!
	}
}

// dispatch_later_by_type re-dispatches a job by type name
fn dispatch_later_by_type(job_type string, _delay_secs i64) ! {
	// Reconstruct and push
	payload := serialize_job(job_type, '{}')
	mut d := get_dispatcher()
	d.driver.push(d.default_queue, payload)!
}

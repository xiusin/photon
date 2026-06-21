module queue

// dispatcher.v - Job Dispatcher (Laravel Queue Dispatcher inspired)
import time
import sync

// get_dispatcher returns the global queue singleton (thread-safe).
// Uses double-checked locking with a read lock on the fast path so the
// write mutex is only contended during the very first initialization.
//
// IMPORTANT (H5): the fast-path read of global_dispatcher MUST be under at
// least a read lock. A bare `if global_dispatcher != nil` read has no memory
// barrier — on weak-memory architectures (ARM, Apple Silicon) another
// goroutine's write to global_dispatcher may not be visible, leading to
// duplicate initialization or use of a partially-constructed object.
fn get_dispatcher() &QueueDispatcher {
	// Fast path: read under read lock for memory visibility.
	dispatcher_mu.rlock()
	d := unsafe { global_dispatcher }
	dispatcher_mu.runlock()
	if !isnil(d) {
		return d
	}

	// Slow path: acquire write lock to create the dispatcher.
	dispatcher_mu.@lock()
	// Double-check after acquiring write lock (another goroutine may have
	// created it while we waited).
	if !isnil(unsafe { global_dispatcher }) {
		d2 := unsafe { global_dispatcher }
		dispatcher_mu.unlock()
		return d2
	}
	unsafe {
		global_dispatcher = new_dispatcher(new_memory_driver())
	}
	d3 := unsafe { global_dispatcher }
	dispatcher_mu.unlock()
	return d3
}

__global (
	dispatcher_mu     sync.RwMutex
	global_dispatcher &QueueDispatcher
)

// QueueDispatcher handles job dispatching with chain/batch/later support
pub struct QueueDispatcher {
pub:
	default_queue string = 'default'
pub mut:
	driver &QueueDriver = new_memory_driver()
}

// new_dispatcher creates a QueueDispatcher
pub fn new_dispatcher(driver &MemoryDriver) &QueueDispatcher {
	return unsafe {
		&QueueDispatcher{
			driver: driver
		}
	}
}

// dispatch pushes a job onto the default queue
pub fn dispatch(job Job) ! {
	mut d := get_dispatcher()
	payload := serialize_job(job.job_type(), '{}')
	d.driver.push(d.default_queue, payload)!
}

// dispatch_chain dispatches jobs sequentially
pub fn dispatch_chain(jobs []Job) ! {
	mut d := get_dispatcher()
	for job in jobs {
		payload := serialize_job(job.job_type(), '{}')
		d.driver.push(d.default_queue, payload)!
	}
}

// push pushes a serialized job to a specific queue
pub fn push(queue_name string, job Job, delay_secs i64) ! {
	mut d := get_dispatcher()
	mut payload := serialize_job(job.job_type(), '{}')

	// Delayed jobs include a timestamp prefix
	if delay_secs > 0 {
		run_at := time.now().unix_nano() + delay_secs * 1_000_000_000
		payload = '${run_at}||${payload}'
	}
	d.driver.push(queue_name, payload)!
}

// dispatch_later dispatches a job to run after a delay
pub fn dispatch_later(job Job, delay_secs i64) ! {
	push('default', job, delay_secs)!
}

// dispatch_batch dispatches multiple jobs as a batch
pub fn dispatch_batch(jobs []Job) !string {
	batch_id := generate_batch_id()
	mut d := get_dispatcher()
	for job in jobs {
		payload := serialize_job(job.job_type(), '{"batch_id":"${batch_id}"}')
		d.driver.push(d.default_queue, payload)!
	}
	return batch_id
}

// count returns the number of pending jobs
pub fn count() int {
	mut d := get_dispatcher()
	return d.driver.count(d.default_queue)
}

// clear removes all jobs from the default queue
pub fn clear_queue() ! {
	mut d := get_dispatcher()
	d.driver.clear(d.default_queue)!
}

// generate_batch_id creates a unique batch identifier
fn generate_batch_id() string {
	return 'batch_${time.now().unix_nano()}'
}

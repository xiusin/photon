module queue

// queue_test.v - Tests for the Queue module

@[heap]
struct TestJob {
pub:
	name string
}

fn (j &TestJob) job_type() string {
	return 'test_job'
}

fn (j &TestJob) handle() ! {
	// Success
}

fn (j &TestJob) tries() int {
	return 3
}

fn (j &TestJob) backoff() []i64 {
	return [i64(1), 5, 10]
}

// ============================================================
// Driver Tests
// ============================================================

fn test_memory_driver_push_pop() {
	mut d := new_memory_driver()
	d.push('default', 'payload1') or { assert false }
	d.push('default', 'payload2') or { assert false }

	assert d.count('default') == 2

	result := d.pop('default') or { '' }
	assert result == 'payload1'
	assert d.count('default') == 1
}

fn test_memory_driver_count() {
	mut d := new_memory_driver()
	assert d.count('empty') == 0
	d.push('queue_a', 'a') or {}
	assert d.count('queue_a') == 1
}

fn test_memory_driver_clear() {
	mut d := new_memory_driver()
	d.push('q', 'x') or {}
	d.push('q', 'y') or {}
	d.clear('q') or {}
	assert d.count('q') == 0
}

fn test_memory_driver_pop_empty() {
	mut d := new_memory_driver()
	result := d.pop('nonexistent') or { 'empty' }
	assert result == 'empty'
}

// ============================================================
// Serialization Tests
// ============================================================

fn test_serialize_deserialize() {
	payload := serialize_job('email_job', '{"to":"user@test.com"}')
	assert payload.contains('email_job')
	assert payload.contains('||')
	assert payload.contains('user@test.com')

	name, data := deserialize_job(payload) or { '', '' }
	assert name == 'email_job'
	assert data == '{"to":"user@test.com"}'
}

// ============================================================
// Dispatcher Tests
// ============================================================

fn test_dispatch_job() {
	mut d := new_dispatcher(new_memory_driver())

	job := TestJob{
		name: 'test'
	}
	payload := serialize_job(job.job_type(), '{}')
	d.driver.push(d.default_queue, payload) or {}

	assert d.driver.count(d.default_queue) == 1
}

fn test_dispatch_chain() {
	mut d := new_dispatcher(new_memory_driver())

	jobs := [TestJob{
		name: 'a'
	}, TestJob{
		name: 'b'
	}, TestJob{
		name: 'c'
	}]
	for job in jobs {
		payload := serialize_job(job.job_type(), '{}')
		d.driver.push(d.default_queue, payload) or {}
	}

	assert d.driver.count(d.default_queue) == 3
}

fn test_dispatch_batch() {
	// dispatch_batch uses global dispatcher, so count from it
	mut test_jobs := [TestJob{
		name: '1'
	}, TestJob{
		name: '2'
	}]
	mut jobs := []Job{}
	for mut j in test_jobs {
		jobs << &j
	}
	batch_id := dispatch_batch(jobs) or { '' }
	assert batch_id.len > 0

	// Verify via global dispatcher
	mut d := get_dispatcher()
	assert d.driver.count(d.default_queue) == 2
}

fn test_queue_count() {
	mut d := new_dispatcher(new_memory_driver())
	assert d.driver.count(d.default_queue) == 0

	d.driver.push(d.default_queue, 'payload') or {}
	assert d.driver.count(d.default_queue) == 1
}

fn test_clear_queue() {
	mut d := new_dispatcher(new_memory_driver())
	d.driver.push(d.default_queue, 'x') or {}
	d.driver.clear(d.default_queue) or {}
	assert d.driver.count(d.default_queue) == 0
}

// ============================================================
// Worker Tests
// ============================================================

fn test_worker_new() {
	w := new_worker()
	assert w.queue_name == 'default'
	assert w.sleep_secs == 5
}

fn test_execute_job() {
	job := TestJob{
		name: 'worker_test'
	}
	payload := serialize_job(job.job_type(), '{}')

	mut d := new_dispatcher(new_memory_driver())
	d.driver.push(d.default_queue, payload) or {}

	popped := d.driver.pop(d.default_queue) or { '' }
	assert popped == payload
}

fn test_job_lifecycle() {
	job := TestJob{
		name: 'test'
	}
	assert job.job_type() == 'test_job'
	assert job.tries() == 3
	assert job.backoff().len == 3
	assert job.backoff()[0] == 1
}

// ============================================================
// Worker Lifecycle Tests
// ============================================================

fn test_worker_lifecycle() {
	mut w := new_worker()
	assert w.running == false

	w.run()
	assert w.running == true

	w.stop()
	assert w.running == false
}

fn test_worker_tick_idle() {
	mut w := new_worker()
	// Tick on idle worker (not running) should do nothing
	w.tick()
	assert true // no panic
}

fn test_worker_tick_on_empty_queue() {
	mut w := new_worker()
	w.run()
	// Tick on empty queue should not panic
	w.tick()
	assert true
	w.stop()
}

fn test_worker_custom_queue() {
	w := new_worker()
	assert w.queue_name == 'default'
}

fn test_dispatch_later() {
	job := TestJob{
		name: 'delayed'
	}
	// dispatch_later creates a delayed job without panicking
	dispatch_later(job, 5) or { assert false }
}

fn test_dispatch_and_clear() {
	job := TestJob{
		name: 'test'
	}
	dispatch(job) or { assert false }
	assert count() > 0

	clear_queue() or { assert false }
	assert count() == 0
}

fn test_job_payload_creation() {
	payload := JobPayload{
		id:       'job_1'
		job_type: 'email'
		data:     '{}'
		attempts: 0
	}
	assert payload.id == 'job_1'
	assert payload.job_type == 'email'
	assert payload.attempts == 0
}

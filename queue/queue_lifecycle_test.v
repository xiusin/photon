module queue

// queue_lifecycle_test.v - Lifecycle tests for Queue Worker and FailedJobs
//
// Verifies fixes for:
//   - H3:  Worker.running flag thread-safe (sync.Mutex protected)
//   - C7:  registry map protected by sync.RwMutex
//   - C7:  failed_jobs slice protected by sync.Mutex
//   - M6:  memory_driver.count() acquires lock for consistent snapshot
//   - M25: retry sleep interruptible via stop_ch (stop() breaks backoff)

// LifecycleJob — local job implementation for lifecycle tests.
// Defined locally because cross-test-file struct visibility for
// interface returns can be unreliable in V's test compiler.
@[heap]
struct LifecycleJob {
pub:
	name string
}

fn (j &LifecycleJob) job_type() string {
	return 'lifecycle_job'
}

fn (j &LifecycleJob) handle() ! {
}

fn (j &LifecycleJob) tries() int {
	return 1
}

fn (j &LifecycleJob) backoff() []i64 {
	return [i64(1)]
}

// Named factory functions — V's type inference cannot reliably infer
// `fn () &Job` from inline closures, so we declare them explicitly.
// NOTE: function names must NOT start with `test_` or V treats them as
// test functions (which cannot return values).
fn make_lifecycle_job_default() &Job {
	mut j := LifecycleJob{
		name: 'factory'
	}
	return &j
}

fn make_lifecycle_job_email() &Job {
	mut j := LifecycleJob{
		name: 'email'
	}
	return &j
}

fn make_lifecycle_job_cleanup() &Job {
	mut j := LifecycleJob{
		name: 'cleanup'
	}
	return &j
}

// ============================================================
// Worker.running flag — thread-safe (H3)
// ============================================================

fn test_queue_lifecycle_worker_running_flag() {
	mut w := new_worker()
	assert w.is_running() == false

	w.run()
	assert w.is_running() == true

	w.stop()
	assert w.is_running() == false
}

fn test_queue_lifecycle_worker_stop_is_idempotent() {
	mut w := new_worker()
	w.run()
	w.stop()
	// Calling stop again should be safe
	w.stop()
	assert w.is_running() == false
}

fn test_queue_lifecycle_worker_running_concurrent_reads() {
	mut w := new_worker()
	w.run()

	done := chan bool{cap: 20}

	// Spawn many goroutines reading the running flag concurrently
	for _ in 0 .. 20 {
		spawn fn (gw &QueueWorker, d chan bool) {
			_ = gw.is_running()
			d <- true
		}(w, done)
	}

	mut completed := 0
	for _ in 0 .. 20 {
		_ = <-done
		completed++
	}
	assert completed == 20
	assert w.is_running() == true
	w.stop()
}

// ============================================================
// Worker.registry map — thread-safe (C7)
// ============================================================

fn test_queue_lifecycle_registry_concurrent_register() {
	mut w := new_worker()
	done := chan bool{cap: 20}

	// Register job types concurrently
	for i in 0 .. 20 {
		spawn fn (gw &QueueWorker, idx int, d chan bool) {
			unsafe {
				mut w := gw
				w.register('job-${idx}', make_lifecycle_job_default)
			}
			d <- true
		}(w, i, done)
	}

	for _ in 0 .. 20 {
		_ = <-done
	}

	// All 20 job types should be registered
	w.registry_mu.@rlock()
	count := w.registry.len
	w.registry_mu.runlock()
	assert count == 20
}

fn test_queue_lifecycle_registry_lookup() {
	mut w := new_worker()
	w.register('email', make_lifecycle_job_email)
	w.register('cleanup', make_lifecycle_job_cleanup)

	w.registry_mu.@rlock()
	assert 'email' in w.registry
	assert 'cleanup' in w.registry
	assert w.registry.len == 2
	w.registry_mu.runlock()
}

// ============================================================
// Worker.stop() — interrupts pending operations (M25)
// ============================================================

fn test_queue_lifecycle_stop_signals_interrupt() {
	mut w := new_worker()
	w.run()
	// stop() signals stop_ch which allows interruptible_sleep to return early.
	// We verify stop() completes without hanging and sets running=false.
	w.stop()
	assert w.is_running() == false
}

// ============================================================
// MemoryFailedJobRepository — thread-safe (C7)
// ============================================================

fn test_queue_lifecycle_failed_jobs_concurrent_save() {
	mut repo := new_memory_failed_repo()
	done := chan bool{cap: 50}

	// Concurrent saves
	for i in 0 .. 50 {
		spawn fn (gr &MemoryFailedJobRepository, idx int, d chan bool) {
			job := FailedJob{
				id:         'job-${idx}'
				job_type:   'TestJob'
				payload:    '{}'
				exception:  'test error'
				failed_at:  0
				queue_name: 'default'
				attempts:   1
			}
			unsafe {
				mut r := gr
				r.save(job) or {}
			}
			d <- true
		}(repo, i, done)
	}

	for _ in 0 .. 50 {
		_ = <-done
	}
	assert repo.count() == 50
}

fn test_queue_lifecycle_failed_jobs_concurrent_read_write() {
	mut repo := new_memory_failed_repo()

	// Pre-populate
	for i in 0 .. 10 {
		repo.save(FailedJob{
			id:         'pre-${i}'
			job_type:   'TestJob'
			payload:    '{}'
			exception:  'err'
			failed_at:  0
			queue_name: 'default'
			attempts:   1
		}) or {}
	}

	done := chan bool{cap: 30}

	// Concurrent writers
	for i in 0 .. 10 {
		spawn fn (gr &MemoryFailedJobRepository, idx int, d chan bool) {
			unsafe {
				mut r := gr
				r.save(FailedJob{
					id:         'concurrent-${idx}'
					job_type:   'TestJob'
					payload:    '{}'
					exception:  'err'
					failed_at:  0
					queue_name: 'default'
					attempts:   1
				}) or {}
			}
			d <- true
		}(repo, i, done)
	}

	// Concurrent readers
	for _ in 0 .. 20 {
		spawn fn (gr &MemoryFailedJobRepository, d chan bool) {
			unsafe {
				mut r := gr
				_ = r.count()
				_ = r.all() or { []FailedJob{} }
			}
			d <- true
		}(repo, done)
	}

	for _ in 0 .. 30 {
		_ = <-done
	}
	// 10 pre-populated + 10 concurrent = 20
	assert repo.count() == 20
}

fn test_queue_lifecycle_failed_jobs_find_and_delete() {
	mut repo := new_memory_failed_repo()
	repo.save(FailedJob{
		id:         'find-me'
		job_type:   'TestJob'
		payload:    '{}'
		exception:  'error'
		failed_at:  0
		queue_name: 'default'
		attempts:   1
	}) or { assert false }

	found := repo.find_by_id('find-me') or {
		assert false
		return
	}
	assert found.id == 'find-me'

	repo.delete_by_id('find-me') or { assert false }
	assert repo.count() == 0

	// find_by_id on deleted should error
	repo.find_by_id('find-me') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_queue_lifecycle_failed_jobs_clear() {
	mut repo := new_memory_failed_repo()
	for i in 0 .. 5 {
		repo.save(FailedJob{
			id:         'job-${i}'
			job_type:   'TestJob'
			payload:    '{}'
			exception:  'err'
			failed_at:  0
			queue_name: 'default'
			attempts:   1
		}) or {}
	}
	assert repo.count() == 5
	repo.clear() or { assert false }
	assert repo.count() == 0
}

// ============================================================
// MemoryDriver.count() — thread-safe (M6)
// ============================================================

fn test_queue_lifecycle_memory_driver_count_locked() {
	mut d := new_memory_driver()
	d.push('q1', 'job1') or { assert false }
	d.push('q1', 'job2') or { assert false }
	d.push('q2', 'job3') or { assert false }

	assert d.count('q1') == 2
	assert d.count('q2') == 1
	assert d.count('empty') == 0
}

fn test_queue_lifecycle_memory_driver_count_concurrent() {
	mut d := new_memory_driver()
	done := chan bool{cap: 25}

	// Concurrent pushes
	for i in 0 .. 20 {
		spawn fn (gd &MemoryDriver, idx int, d chan bool) {
			unsafe {
				mut dr := gd
				dr.push('concurrent-q', 'job-${idx}') or {}
			}
			d <- true
		}(d, i, done)
	}

	// Concurrent counts (should not race with pushes)
	for _ in 0 .. 5 {
		spawn fn (gd &MemoryDriver, d chan bool) {
			unsafe {
				mut dr := gd
				_ = dr.count('concurrent-q')
			}
			d <- true
		}(d, done)
	}

	for _ in 0 .. 25 {
		_ = <-done
	}
	assert d.count('concurrent-q') == 20
}

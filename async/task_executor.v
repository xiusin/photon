module async

// task_executor.v - TaskExecutor Thread Pool (Spring @Async / TaskExecutor inspired)
//
// Provides a bounded thread pool with a task queue. Workers pull tasks from
// the queue and execute them concurrently. This is the runtime engine for
// the @[async] annotation (see annotation.v).
//
// Features:
//   - Fixed-size worker pool (no goroutine-per-task explosion)
//   - Bounded task queue with backpressure (blocking submit)
//   - Non-blocking try_submit for overflow handling
//   - Graceful shutdown: waits for all submitted tasks to complete
//   - wait_all() barrier for batch synchronization
//   - Thread-safe; no goroutine leaks on shutdown
//
// Usage:
//   import photon.async
//
//   mut te := async.new_task_executor(4, 64) // 4 workers, queue cap 64
//   te.submit(fn () { send_email(user) })!
//   te.wait_all()   // block until all tasks done
//   te.shutdown()   // stop workers, free resources
import sync

// TaskFunc is a zero-argument, zero-return function that can be submitted
// to the TaskExecutor.
pub type TaskFunc = fn ()

// TaskExecutor is a thread pool with a bounded task queue.
//
// Workers run `worker_loop`, blocking on the task_queue channel. Each
// submitted task increments `task_wg`; workers decrement it after the
// task completes. `shutdown()` waits on `task_wg` (drain all tasks)
// before closing the queue and joining workers — guaranteeing no
// goroutine leaks and no lost work.
pub struct TaskExecutor {
pub mut:
	mu           sync.Mutex
	task_queue   chan TaskFunc
	worker_count int
	wg           sync.WaitGroup // tracks worker goroutines
	task_wg      sync.WaitGroup // tracks submitted (in-flight) tasks
	stopped      bool
}

// new_task_executor creates a TaskExecutor with `worker_count` worker
// goroutines and a task queue of capacity `queue_size`.
//
// Both parameters must be positive; otherwise the function panics with
// a bilingual error message.
pub fn new_task_executor(worker_count int, queue_size int) &TaskExecutor {
	if worker_count <= 0 {
		panic('TaskExecutor: worker_count must be > 0 / worker_count 必须 > 0')
	}
	if queue_size <= 0 {
		panic('TaskExecutor: queue_size must be > 0 / queue_size 必须 > 0')
	}
	mut te := &TaskExecutor{
		task_queue: chan TaskFunc{cap: queue_size}
		worker_count: worker_count
	}
	te.start_workers()
	return te
}

// start_workers spawns the worker goroutines. Called once by the constructor.
fn (mut te TaskExecutor) start_workers() {
	for _ in 0 .. te.worker_count {
		te.wg.add(1)
		spawn worker_loop(mut te)
	}
}

// worker_loop is the main loop for each worker goroutine.
// It pulls tasks from the queue and executes them. When the queue is
// closed (by shutdown), the channel receive returns a nil function and
// the worker exits.
fn worker_loop(mut te TaskExecutor) {
	defer {
		te.wg.done()
	}
	for {
		task := <-te.task_queue
		// A nil TaskFunc means the channel was closed by shutdown().
		if task == unsafe { nil } {
			return
		}
		task()
		te.task_wg.done()
	}
}

// submit enqueues a task for execution by a worker. Blocks if the queue
// is full (backpressure). Returns an error if the executor has been
// shut down.
//
// The task is guaranteed to execute before shutdown() returns, as long
// as submit itself returned successfully.
pub fn (mut te TaskExecutor) submit(task TaskFunc) ! {
	te.mu.@lock()
	if te.stopped {
		te.mu.unlock()
		return error('TaskExecutor is stopped / 任务执行器已停止')
	}
	// Track the task so shutdown() can wait for it.
	te.task_wg.add(1)
	te.mu.unlock()

	// Blocking send. Workers are always draining the queue, so this will
	// eventually succeed (unless shutdown closes the queue, but shutdown
	// waits on task_wg first, which blocks until this send succeeds and
	// the task completes — so no deadlock and no send-on-closed).
	te.task_queue <- task
}

// try_submit attempts to enqueue a task without blocking. Returns
// `true` if the task was accepted, `false` if the queue is full.
// Returns an error if the executor has been shut down.
//
// Use this for non-critical tasks that can be dropped under load.
//
// Race-safety: task_wg is incremented before the non-blocking send so
// that a concurrent shutdown()'s task_wg.wait() observes the pending
// task. If the send fails (queue full), task_wg is decremented back.
pub fn (mut te TaskExecutor) try_submit(task TaskFunc) !bool {
	te.mu.@lock()
	if te.stopped {
		te.mu.unlock()
		return error('TaskExecutor is stopped / 任务执行器已停止')
	}
	// Track the task before attempting to enqueue, so shutdown()'s
	// task_wg.wait() cannot return before this task is resolved.
	te.task_wg.add(1)
	te.mu.unlock()

	mut accepted := false
	select {
		te.task_queue <- task {
			accepted = true
		}
		else {
			accepted = false
		}
	}
	if !accepted {
		// Undo the add — the task was not enqueued.
		te.task_wg.done()
	}
	return accepted
}

// shutdown stops the executor gracefully. It:
//   1. Marks the executor as stopped (rejects new submits).
//   2. Waits for all already-submitted tasks to complete.
//   3. Closes the task queue so workers exit.
//   4. Waits for all worker goroutines to terminate.
//
// Idempotent: calling shutdown multiple times is safe.
pub fn (mut te TaskExecutor) shutdown() {
	te.mu.@lock()
	if te.stopped {
		te.mu.unlock()
		return
	}
	te.stopped = true
	te.mu.unlock()

	// Wait for all submitted tasks to finish before closing the queue.
	// This guarantees no submitted task is lost.
	te.task_wg.wait()

	// Close the queue: workers receive a nil TaskFunc and exit.
	te.task_queue.close()

	// Join all worker goroutines.
	te.wg.wait()
}

// wait_all blocks until every submitted task has completed.
// Does not stop the executor — new tasks can still be submitted afterward.
pub fn (mut te TaskExecutor) wait_all() {
	te.task_wg.wait()
}

// is_stopped returns true if the executor has been shut down.
pub fn (mut te TaskExecutor) is_stopped() bool {
	te.mu.@lock()
	defer {
		te.mu.unlock()
	}
	return te.stopped
}

// worker_count returns the number of worker goroutines.
pub fn (te &TaskExecutor) worker_count() int {
	return te.worker_count
}

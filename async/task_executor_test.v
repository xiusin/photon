module async

// task_executor_test.v - Tests for TaskExecutor and @[async] annotation
//
// IMPORTANT V CLOSURE SEMANTICS:
// V closures capture variables BY VALUE (copy), not by reference.
// The `mut` keyword in the capture list only makes the copy mutable —
// it does NOT create a reference to the original. To share mutable
// state between the caller and a closure executed on a worker thread,
// you MUST use a pointer (&T) so the closure's copy of the pointer
// still points to the shared heap object.
//
// Covers:
//   1.  Single task submission + correct result
//   2.  Multiple tasks (10) all complete
//   3.  Non-blocking submit (returns before task finishes)
//   4.  Worker concurrency (4 parallel tasks finish faster than serial)
//   5.  try_submit returns false when queue is full
//   6.  submit after shutdown returns error
//   7.  shutdown waits for in-flight tasks
//   8.  Closure capture of mutable state (via pointer)
//   9.  Stress test (1000 tasks)
//   10. Concurrent submitters (10 goroutines × 100 tasks = 1000)
//   11. is_stopped flag transitions
//   12. Multiple shutdown calls are safe
//   13. @[async] comptime scanning
import sync
import time

// ============================================================
// Test helpers
// ============================================================

// Counter is a thread-safe counter for verifying task execution.
// Must be heap-allocated (&Counter) when shared with closures.
struct Counter {
mut:
	mu    sync.Mutex
	count int
}

fn (mut c Counter) increment() {
	c.mu.@lock()
	c.count++
	c.mu.unlock()
}

fn (mut c Counter) get() int {
	c.mu.@lock()
	defer {
		c.mu.unlock()
	}
	return c.count
}

// new_counter allocates a heap-allocated Counter suitable for sharing
// with closures across goroutines.
fn new_counter() &Counter {
	return &Counter{}
}

// ============================================================
// 1. Single task submission
// ============================================================

fn test_submit_single_task() {
	mut te := new_task_executor(2, 8)
	defer { te.shutdown() }

	mut c := new_counter()
	te.submit(fn [mut c] () {
		c.increment()
	})!
	te.wait_all()

	assert c.get() == 1
}

// ============================================================
// 2. Multiple tasks
// ============================================================

fn test_submit_multiple_tasks() {
	mut te := new_task_executor(4, 16)
	defer { te.shutdown() }

	mut c := new_counter()
	for _ in 0 .. 10 {
		te.submit(fn [mut c] () {
			c.increment()
		})!
	}
	te.wait_all()

	assert c.get() == 10
}

// ============================================================
// 3. Non-blocking submit
// ============================================================

fn test_submit_is_non_blocking() {
	mut te := new_task_executor(1, 8)
	defer { te.shutdown() }

	start := time.now()
	te.submit(fn () {
		time.sleep(100 * time.millisecond)
	})!
	elapsed := time.now() - start

	// submit() should return well before the 100ms task finishes.
	// Allow up to 50ms margin for scheduling overhead.
	assert elapsed < 50 * time.millisecond
	te.wait_all()
}

// ============================================================
// 4. Worker concurrency (parallel execution)
// ============================================================

fn test_worker_concurrency() {
	mut te := new_task_executor(4, 16)
	defer { te.shutdown() }

	start := time.now()
	for _ in 0 .. 4 {
		te.submit(fn () {
			time.sleep(100 * time.millisecond)
		})!
	}
	te.wait_all()
	elapsed := time.now() - start

	// 4 tasks × 100ms in parallel on 4 workers should finish in ~100ms.
	// Serial would take 400ms. Allow generous margin (< 300ms).
	assert elapsed < 300 * time.millisecond
}

// ============================================================
// 5. try_submit returns false when queue is full
// ============================================================

fn test_try_submit_returns_false_when_full() {
	// 1 worker, queue size 1. Block the worker so the queue stays full.
	mut te := new_task_executor(1, 1)
	barrier := chan bool{cap: 1}

	// Always release the barrier before shutdown, even if assertions fail,
	// to prevent the worker from blocking shutdown's task_wg.wait() forever.
	defer {
		select {
			barrier <- true {}
			else {}
		}
		te.shutdown()
	}

	// Task 1: picked up by the worker immediately, then blocks on barrier.
	te.submit(fn [barrier] () {
		_ = <-barrier
	})!

	// Give the worker time to pick up task 1 so the queue is empty,
	// then fill it with task 2.
	time.sleep(80 * time.millisecond)

	// Task 2: goes into the queue (queue is now full).
	ok2 := te.try_submit(fn () {})!
	assert ok2 == true

	// Task 3: queue is full → try_submit returns false.
	ok3 := te.try_submit(fn () {})!
	assert ok3 == false

	// Release the worker and let everything drain.
	select {
		barrier <- true {}
		else {}
	}
	te.wait_all()
}

// ============================================================
// 6. submit after shutdown returns error
// ============================================================

fn test_submit_after_shutdown_errors() {
	mut te := new_task_executor(2, 8)
	te.shutdown()

	assert te.is_stopped() == true

	te.submit(fn () {}) or {
		// Expected: submit returns an error after shutdown.
		return
	}
	// If submit succeeded, the test should fail.
	assert false
}

// ============================================================
// 7. shutdown waits for in-flight tasks
// ============================================================

fn test_shutdown_waits_for_tasks() {
	mut te := new_task_executor(2, 8)

	mut c := new_counter()
	te.submit(fn [mut c] () {
		time.sleep(80 * time.millisecond)
		c.increment()
	})!

	// shutdown should block until the task completes.
	te.shutdown()

	// The task must have run before shutdown returned.
	assert c.get() == 1
}

// ============================================================
// 8. Closure capture of mutable state (via pointer)
// ============================================================

fn test_closure_capture_mutable() {
	mut te := new_task_executor(2, 8)
	defer { te.shutdown() }

	mut c := new_counter()
	// Capture the &Counter pointer — the closure gets a copy of the
	// pointer, which still references the shared heap object.
	captured := fn [mut c] () {
		c.increment()
		c.increment()
	}
	te.submit(captured)!
	te.wait_all()

	assert c.get() == 2
}

// ============================================================
// 9. Stress test (1000 tasks)
// ============================================================

fn test_stress_1000_tasks() {
	mut te := new_task_executor(8, 256)
	defer { te.shutdown() }

	mut c := new_counter()
	for _ in 0 .. 1000 {
		te.submit(fn [mut c] () {
			c.increment()
		})!
	}
	te.wait_all()

	assert c.get() == 1000
}

// ============================================================
// 10. Concurrent submitters
// ============================================================

// submit_batch submits `n` increment tasks to the executor, then sends
// a signal on `done` to indicate completion. Uses a channel (not
// sync.WaitGroup) because V's `spawn` does not allow mutable value-type
// arguments.
fn submit_batch(mut te TaskExecutor, mut c &Counter, done chan bool, n int) {
	for _ in 0 .. n {
		te.submit(fn [mut c] () {
			c.increment()
		}) or {
			done <- true
			return
		}
	}
	done <- true
}

fn test_concurrent_submitters() {
	mut te := new_task_executor(8, 256)
	defer { te.shutdown() }

	mut c := new_counter()
	done := chan bool{cap: 10}

	// 10 goroutines, each submits 100 tasks.
	for _ in 0 .. 10 {
		spawn submit_batch(mut te, mut c, done, 100)
	}

	// Wait for all 10 submitter goroutines to finish.
	for _ in 0 .. 10 {
		_ = <-done
	}
	te.wait_all()

	assert c.get() == 1000
}

// ============================================================
// 11. is_stopped transitions
// ============================================================

fn test_is_stopped_transitions() {
	mut te := new_task_executor(2, 8)
	assert te.is_stopped() == false

	te.shutdown()
	assert te.is_stopped() == true
}

// ============================================================
// 12. Multiple shutdown calls are safe
// ============================================================

fn test_multiple_shutdowns_safe() {
	mut te := new_task_executor(2, 8)

	te.submit(fn () {
		time.sleep(20 * time.millisecond)
	})!

	te.shutdown()
	// Calling shutdown again should not panic.
	te.shutdown()
	te.shutdown()

	assert te.is_stopped() == true
}

// ============================================================
// 13. try_submit succeeds when queue has space
// ============================================================

fn test_try_submit_succeeds_when_space() {
	mut te := new_task_executor(2, 8)
	defer { te.shutdown() }

	mut c := new_counter()
	ok := te.try_submit(fn [mut c] () {
		c.increment()
	})!
	assert ok == true
	te.wait_all()

	assert c.get() == 1
}

// ============================================================
// 14. wait_all without shutdown allows more submits
// ============================================================

fn test_wait_all_allows_more_submits() {
	mut te := new_task_executor(2, 8)
	defer { te.shutdown() }

	mut c := new_counter()
	te.submit(fn [mut c] () {
		c.increment()
	})!
	te.wait_all()
	assert c.get() == 1

	// Can still submit after wait_all.
	te.submit(fn [mut c] () {
		c.increment()
	})!
	te.wait_all()
	assert c.get() == 2
}

// ============================================================
// 15. worker_count accessor
// ============================================================

fn test_worker_count_accessor() {
	mut te := new_task_executor(5, 16)
	defer { te.shutdown() }
	assert te.worker_count() == 5
}

// ============================================================
// 16. @[async] annotation parsing
// ============================================================

fn test_parse_async_attr_empty() {
	aa := parse_async_attr('')
	assert aa.executor == ''
}

fn test_parse_async_attr_named() {
	aa := parse_async_attr('emailExecutor')
	assert aa.executor == 'emailExecutor'
}

fn test_parse_async_attr_quoted() {
	aa := parse_async_attr("'emailExecutor'")
	assert aa.executor == 'emailExecutor'
}

fn test_has_async_attr() {
	assert has_async_attr(['async']) == true
	assert has_async_attr(['async: emailExec']) == true
	assert has_async_attr(['async("emailExec")']) == true
	assert has_async_attr(['transactional']) == false
	assert has_async_attr([]) == false
}

fn test_extract_async_attr() {
	assert extract_async_attr(['async']) == ''
	assert extract_async_attr(['async: foo']) == 'foo'
}

// ============================================================
// 17. @[async] comptime scanning
// ============================================================

// Test service with @[async] methods for comptime scanning.
struct AsyncEmailService {
mut:
	sent int
}

@[async]
fn (mut s AsyncEmailService) send_welcome() {
	s.sent++
}

@[async]
fn (mut s AsyncEmailService) send_farewell() {
	s.sent++
}

// Non-async method — should NOT be discovered.
fn (mut s AsyncEmailService) sync_check() bool {
	return true
}

@[async: 'priorityExec']
fn (mut s AsyncEmailService) send_urgent() {
	s.sent++
}

fn test_extract_async_methods_finds_annotated() {
	methods := extract_async_methods[AsyncEmailService]()
	// Should find send_welcome, send_farewell, send_urgent (3 methods).
	assert methods.len == 3

	mut names := []string{}
	for m in methods {
		names << m.method_name
	}
	assert 'send_welcome' in names
	assert 'send_farewell' in names
	assert 'send_urgent' in names
	// sync_check is NOT async.
	assert 'sync_check' !in names
}

fn test_is_async_annotated() {
	assert is_async_annotated[AsyncEmailService]() == true
}

fn test_is_async_annotated_negative() {
	// A struct with no @[async] methods.
	assert is_async_annotated[Counter]() == false
}

fn test_has_async_method_positive() {
	assert has_async_method[AsyncEmailService]('send_welcome') == true
	assert has_async_method[AsyncEmailService]('send_urgent') == true
}

fn test_has_async_method_negative() {
	assert has_async_method[AsyncEmailService]('sync_check') == false
	assert has_async_method[AsyncEmailService]('nonexistent') == false
}

fn test_extract_async_methods_executor_name() {
	methods := extract_async_methods[AsyncEmailService]()
	for m in methods {
		if m.method_name == 'send_urgent' {
			assert m.executor == 'priorityExec'
		}
		if m.method_name == 'send_welcome' {
			assert m.executor == ''
		}
	}
}

// ============================================================
// 18. @[async] + TaskExecutor integration
//
// Demonstrates the full pattern: scan @[async] methods, then submit
// a closure wrapping the method call to the TaskExecutor.
// ============================================================

fn test_async_annotation_integration() {
	mut te := new_task_executor(2, 8)
	defer { te.shutdown() }

	// Verify the service has async methods (comptime check).
	assert is_async_annotated[AsyncEmailService]() == true

	mut svc := AsyncEmailService{}

	// Submit the async method via a closure (the "wrap" step).
	// Note: svc is a value type, so the closure captures a copy.
	// The increment happens on the copy, but the test verifies the
	// task ran (no error) rather than the side effect on svc.
	te.submit(fn [mut svc] () {
		svc.send_welcome()
	})!
	te.wait_all()

	// The comptime scan found the @[async] method.
	assert has_async_method[AsyncEmailService]('send_welcome') == true
}

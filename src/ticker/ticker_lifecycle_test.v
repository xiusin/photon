module ticker

// ticker_lifecycle_test.v - Tests for goroutine lifecycle management
//
// Verifies the fixes for CRITICAL #1 (scheduler_run never stops),
// CRITICAL #2 (Ticker.stop ineffective), H2 (is_running read without lock),
// and the wg-based goroutine lifecycle.
//
// Each test uses its own channel for tick counting to avoid cross-test
// contamination (V may run test functions within a file concurrently).
import time

// drain_channel removes all pending values from ch (non-blocking) and returns
// the count.
fn drain_channel(ch chan bool) int {
	mut count := 0
	mut done := false
	for !done {
		select {
			_ := <-ch {
				count++
			}
			else {
				done = true
			}
		}
	}
	return count
}

// ── CRITICAL #1: scheduler_run goroutine must exit on stop() ──

// test_scheduler_goroutine_exits_on_stop verifies that after stop() returns,
// the background goroutine has fully exited and no more ticks are delivered.
fn test_scheduler_goroutine_exits_on_stop() {
	ch := chan bool{cap: 1000}
	callback := fn [ch] () {
		select {
			ch <- true {}
			else {}
		}
	}

	mut s := new_scheduler()
	s.start()

	// Confirm the scheduler is running.
	s.mu.@lock()
	running_before := s.running
	s.mu.unlock()
	assert running_before == true

	// Schedule a periodic ticker (20ms interval) directly on this scheduler.
	entry := new_timer_entry(time.now().unix_nano() + 20_000_000, 20_000_000, callback)
	s.add_entry(entry)

	// Let it tick a few times.
	time.sleep(100 * time.millisecond)
	count_before_stop := drain_channel(ch)
	assert count_before_stop >= 1

	// stop() must block until the goroutine has fully exited (wg.wait()).
	s.stop()

	// After stop(), running must be false.
	s.mu.@lock()
	running_after := s.running
	s.mu.unlock()
	assert running_after == false

	// Drain any ticks that arrived between the last drain and stop.
	drain_channel(ch)

	// Wait long enough that, if the goroutine were still running, several more
	// ticks would have been delivered (20ms interval => ~5 ticks in 100ms).
	time.sleep(100 * time.millisecond)

	// If the goroutine leaked, ticks would have arrived on the channel.
	leaked := drain_channel(ch)
	assert leaked == 0
}

// test_scheduler_stop_waits_for_goroutine verifies that stop() returns only
// after the goroutine has exited (i.e. wg.wait() completes promptly).
fn test_scheduler_stop_waits_for_goroutine() {
	mut s := new_scheduler()
	s.start()

	start := time.now()
	s.stop()
	elapsed := time.now() - start

	// The poll interval is at most 50ms, so stop() should return well within
	// 500ms once the goroutine observes the signal.
	assert elapsed < 500 * time.millisecond

	s.mu.@lock()
	running := s.running
	s.mu.unlock()
	assert running == false
}

// test_scheduler_stop_is_idempotent verifies stop() can be called multiple
// times safely.
fn test_scheduler_stop_is_idempotent() {
	mut s := new_scheduler()
	s.start()
	s.stop()
	// Calling stop again must not block or panic.
	s.stop()
	s.stop()

	s.mu.@lock()
	running := s.running
	s.mu.unlock()
	assert running == false
}

// test_scheduler_start_is_idempotent verifies start() can be called multiple
// times safely (only one goroutine is spawned).
fn test_scheduler_start_is_idempotent() {
	mut s := new_scheduler()
	s.start()
	s.start() // should be a no-op
	s.start() // should be a no-op
	s.stop()

	s.mu.@lock()
	running := s.running
	s.mu.unlock()
	assert running == false
}

// ── CRITICAL #2: Ticker.stop() must actually remove the scheduled entry ──

// test_remove_entry_periodic_matches_by_period verifies that remove_entry
// removes a periodic (ticker) entry by matching period, even when when=0.
// This is the core fix for CRITICAL #2: previously Ticker.stop() passed
// when=0 which never matched any scheduled entry.
fn test_remove_entry_periodic_matches_by_period() {
	mut s := new_scheduler()
	s.start()

	period := i64(30_000_000) // 30ms in nanoseconds
	when := time.now().unix_nano() + period

	callback := fn () {}
	entry := new_timer_entry(when, period, callback)
	idx := s.add_entry(entry)

	// Verify the entry was added.
	assert s.buckets[idx].heap.len() == 1

	// Remove using when=0 (as Ticker.stop() does) — must match by period.
	s.remove_entry(idx, 0, period)

	// Verify the entry was removed.
	assert s.buckets[idx].heap.len() == 0

	s.stop()
}

// test_remove_entry_oneshot_matches_by_when verifies that one-shot timer
// entries are still matched by when (unchanged behavior).
fn test_remove_entry_oneshot_matches_by_when() {
	mut s := new_scheduler()
	s.start()

	when := time.now().unix_nano() + 1_000_000_000

	callback := fn () {}
	entry := new_timer_entry(when, 0, callback)
	idx := s.add_entry(entry)

	assert s.buckets[idx].heap.len() == 1

	// Remove using the correct when value, period=0.
	s.remove_entry(idx, when, 0)
	assert s.buckets[idx].heap.len() == 0

	// Removing with a wrong when value must NOT remove anything.
	entry2 := new_timer_entry(when, 0, callback)
	idx2 := s.add_entry(entry2)
	assert s.buckets[idx2].heap.len() == 1
	s.remove_entry(idx2, when + 999, 0)
	assert s.buckets[idx2].heap.len() == 1

	s.stop()
}

// test_ticker_stop_prevents_future_ticks is an integration test verifying that
// after Ticker.stop() (remove_entry with when=0, period>0), no further ticks
// are delivered.
fn test_ticker_stop_prevents_future_ticks() {
	ch := chan bool{cap: 1000}
	callback := fn [ch] () {
		select {
			ch <- true {}
			else {}
		}
	}

	// Use a dedicated scheduler so the test is isolated from the global one.
	mut s := new_scheduler()
	s.start()

	period_ns := i64(20_000_000) // 20ms
	when := time.now().unix_nano() + period_ns
	entry := new_timer_entry(when, period_ns, callback)
	idx := s.add_entry(entry)

	// Let it tick a couple of times.
	time.sleep(100 * time.millisecond)
	count_before_stop := drain_channel(ch)
	assert count_before_stop >= 1

	// Stop the ticker (simulating Ticker.stop() — when=0, period>0).
	s.remove_entry(idx, 0, period_ns)

	// Drain any in-flight ticks.
	drain_channel(ch)

	// Wait long enough that several more ticks would have fired.
	time.sleep(100 * time.millisecond)

	// No more ticks should have been delivered after stop.
	leaked := drain_channel(ch)
	assert leaked == 0

	s.stop()
}

// ── Scheduler (schedule.v) lifecycle ──

// test_task_scheduler_goroutine_exits_on_stop verifies the Scheduler (from
// schedule.v) background goroutine exits on stop() and does not leak.
fn test_task_scheduler_goroutine_exits_on_stop() {
	ch := chan bool{cap: 1000}

	mut sched := new_task_scheduler()
	mut b := sched.every(20 * time.millisecond)
	b.task_fn = fn [ch] () ! {
		select {
			ch <- true {}
			else {}
		}
	}
	b.name_ = 'lifecycle_test_task'
	sched.register(b)
	sched.start()

	// Let it tick a couple of times.
	time.sleep(100 * time.millisecond)
	count_before_stop := drain_channel(ch)
	assert count_before_stop >= 1

	// stop() must block until the goroutine has exited.
	sched.stop()

	assert sched.is_running == false

	// Drain any in-flight ticks.
	drain_channel(ch)

	// Wait long enough that more ticks would have fired if goroutine leaked.
	time.sleep(100 * time.millisecond)
	leaked := drain_channel(ch)
	assert leaked == 0
}

// test_task_scheduler_stop_waits_for_goroutine verifies stop() returns
// promptly after the goroutine exits.
fn test_task_scheduler_stop_waits_for_goroutine() {
	mut sched := new_task_scheduler()
	sched.start()

	start := time.now()
	sched.stop()
	elapsed := time.now() - start

	// The poll interval is 1 second, but the goroutine checks stop_signal
	// non-blockingly each iteration, so it should exit well within 2s.
	assert elapsed < 2000 * time.millisecond
	assert sched.is_running == false
}

// test_task_scheduler_lock_protected_counts verifies task_count() and
// enabled_count() are safe to call (M8 fix — they now acquire the read lock).
fn test_task_scheduler_lock_protected_counts() {
	mut sched := new_task_scheduler()

	mut b1 := sched.every(1 * time.second)
	b1.task_fn = fn () ! {}
	b1.name_ = 't1'
	sched.register(b1)

	mut b2 := sched.every(2 * time.second)
	b2.task_fn = fn () ! {}
	b2.name_ = 't2'
	sched.register(b2)

	assert sched.task_count() == 2
	assert sched.enabled_count() == 2

	sched.start()
	// Calling count methods while the goroutine is running must not race.
	assert sched.task_count() == 2
	assert sched.enabled_count() == 2
	sched.stop()

	assert sched.task_count() == 2
	assert sched.enabled_count() == 2
}

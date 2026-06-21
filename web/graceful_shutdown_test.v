module web

// graceful_shutdown_test.v - Tests for GracefulShutdownManager (Task D4)
//
// Covers:
//   - request_started / request_completed counter tracking
//   - is_stopped flag transitions
//   - shutdown() rejects new requests
//   - shutdown() waits for in-flight requests
//   - shutdown() timeout behavior
//   - on_shutdown callback invocation
//   - idempotent shutdown()
//   - concurrent request tracking (no race)
//   - signal listener (SIGTERM/SIGINT) triggers shutdown
//   - full flow: requests + signal + graceful drain
//
// Note: V closures capture stack variables by value, so we use channels
// (chan bool) for cross-goroutine synchronization in tests.
import os
import sync
import time

// ── Basic state tests ──

fn test_graceful_shutdown_new_manager_not_stopped() {
	mut gsm := new_graceful_shutdown_manager()
	assert gsm.is_stopped() == false
}

fn test_graceful_shutdown_default_timeout_is_30s() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.mu.@lock()
	t := gsm.timeout
	gsm.mu.unlock()
	assert t == 30 * time.second
}

fn test_graceful_shutdown_set_timeout() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.set_timeout(5 * time.second)
	gsm.mu.@lock()
	t := gsm.timeout
	gsm.mu.unlock()
	assert t == 5 * time.second
}

// ── request_started / request_completed ──

fn test_graceful_shutdown_request_started_succeeds_when_running() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.request_started() or {
		assert false
		return
	}
	gsm.request_completed()
}

fn test_graceful_shutdown_request_completed_allows_fast_shutdown() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.request_started()!
	gsm.request_completed()

	// shutdown() should complete quickly since no requests are in-flight
	done := chan bool{cap: 1}
	spawn fn (mut g GracefulShutdownManager, d chan bool) {
		g.shutdown()
		d <- true
	}(mut gsm, done)

	mut finished := false
	for _ in 0 .. 50 {
		time.sleep(10 * time.millisecond)
		select {
			_ := <-done {
				finished = true
				break
			}
			else {}
		}
		if finished {
			break
		}
	}
	assert finished == true
	assert gsm.is_stopped() == true
}

// ── shutdown() behavior ──

fn test_graceful_shutdown_sets_stopped_flag() {
	mut gsm := new_graceful_shutdown_manager()
	assert gsm.is_stopped() == false
	gsm.shutdown()
	assert gsm.is_stopped() == true
}

fn test_graceful_shutdown_rejects_new_requests_after_shutdown() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.shutdown()
	gsm.request_started() or {
		// Expected — server is shutting down
		return
	}
	assert false
}

fn test_graceful_shutdown_idempotent() {
	mut gsm := new_graceful_shutdown_manager()
	// Use a channel to count callback invocations (closures capture by value)
	cb_ch := chan bool{cap: 2}
	gsm.set_on_shutdown(fn [cb_ch] () {
		select {
			cb_ch <- true {}
			else {}
		}
	})
	gsm.shutdown()
	gsm.shutdown() // second call should be a no-op

	// Count callbacks: should be exactly 1
	mut count := 0
	for _ in 0 .. 2 {
		select {
			_ := <-cb_ch {
				count++
			}
			else {
				break
			}
		}
	}
	assert count == 1
	assert gsm.is_stopped() == true
}

// ── on_shutdown callback ──

fn test_graceful_shutdown_callback_invoked() {
	mut gsm := new_graceful_shutdown_manager()
	cb_ch := chan bool{cap: 1}
	gsm.set_on_shutdown(fn [cb_ch] () {
		cb_ch <- true
	})
	gsm.shutdown()

	// Wait for callback to fire (with timeout)
	mut invoked := false
	for _ in 0 .. 50 {
		select {
			_ := <-cb_ch {
				invoked = true
				break
			}
			else {
				time.sleep(10 * time.millisecond)
			}
		}
		if invoked {
			break
		}
	}
	assert invoked == true
}

fn test_graceful_shutdown_no_callback_safe() {
	mut gsm := new_graceful_shutdown_manager()
	// No callback set — shutdown should still work
	gsm.shutdown()
	assert gsm.is_stopped() == true
}

// ── In-flight request draining ──

fn test_graceful_shutdown_waits_for_in_flight() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.set_timeout(5 * time.second) // generous timeout; should NOT be hit

	// Start a request that completes after a short delay
	gsm.request_started()!
	spawn fn (mut g GracefulShutdownManager) {
		time.sleep(150 * time.millisecond)
		g.request_completed()
	}(mut gsm)

	shutdown_done := chan bool{cap: 1}
	spawn fn (mut g GracefulShutdownManager, d chan bool) {
		g.shutdown()
		d <- true
	}(mut gsm, shutdown_done)

	// shutdown() should block until the in-flight request completes (~150ms)
	time.sleep(50 * time.millisecond)
	select {
		_ := <-shutdown_done {
			assert false
		}
		else {}
	}

	// Wait for the in-flight request to complete and shutdown to finish
	mut finished := false
	for _ in 0 .. 100 {
		time.sleep(20 * time.millisecond)
		select {
			_ := <-shutdown_done {
				finished = true
				break
			}
			else {}
		}
		if finished {
			break
		}
	}
	assert finished == true
	assert gsm.is_stopped() == true
}

fn test_graceful_shutdown_timeout_forces_shutdown() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.set_timeout(100 * time.millisecond) // short timeout

	// Start a request that NEVER completes (simulates a stuck handler)
	gsm.request_started()!

	start_ns := time.now().unix_nano()
	gsm.shutdown()
	elapsed_ms := (time.now().unix_nano() - start_ns) / 1_000_000

	// shutdown() should return after ~100ms even though the request is still in-flight
	assert elapsed_ms >= 90
	assert elapsed_ms < 500
	assert gsm.is_stopped() == true

	// Clean up: complete the stuck request so the WaitGroup doesn't leak
	gsm.request_completed()
}

// ── Concurrent request tracking ──

fn test_graceful_shutdown_concurrent_requests_no_race() {
	mut gsm := new_graceful_shutdown_manager()
	mut wg := sync.new_waitgroup()
	for _ in 0 .. 50 {
		wg.add(1)
		spawn fn (mut g GracefulShutdownManager, mut w sync.WaitGroup) {
			defer { w.done() }
			g.request_started() or { return }
			time.sleep(1 * time.millisecond)
			g.request_completed()
		}(mut gsm, mut wg)
	}
	wg.wait()
	// All requests completed — shutdown should not block
	gsm.set_timeout(1 * time.second)
	gsm.shutdown()
	assert gsm.is_stopped() == true
}

// ── wait() behavior ──

fn test_graceful_shutdown_wait_blocks_until_shutdown() {
	mut gsm := new_graceful_shutdown_manager()

	wait_done := chan bool{cap: 1}
	spawn fn (g &GracefulShutdownManager, d chan bool) {
		g.wait()
		d <- true
	}(gsm, wait_done)

	// wait() should still be blocking
	time.sleep(50 * time.millisecond)
	select {
		_ := <-wait_done {
			assert false
		}
		else {}
	}

	// Trigger shutdown — wait() should now return
	gsm.shutdown()
	mut returned := false
	for _ in 0 .. 50 {
		time.sleep(10 * time.millisecond)
		select {
			_ := <-wait_done {
				returned = true
				break
			}
			else {}
		}
		if returned {
			break
		}
	}
	assert returned == true
}

// ── Signal listener ──
//
// Signal tests use C.kill to send SIGTERM to the current process.
// The signal listener registers a handler via os.signal_opt() and calls
// shutdown() when the signal is received.
//
// Note: Only SIGTERM is tested with actual signal delivery because V's test
// runner may install its own SIGINT handler. The signal listener registers
// handlers for both SIGTERM and SIGINT in production; here we verify the
// SIGTERM path end-to-end.
//
// V may run test functions within a file concurrently, but signal handlers
// are process-global. A global mutex serializes signal tests so they don't
// interfere with each other.
__global gsm_signal_test_mu sync.Mutex

fn gsm_signal_test_lock() {
	unsafe {
		mut m := &gsm_signal_test_mu
		m.@lock()
	}
}

fn gsm_signal_test_unlock() {
	unsafe {
		mut m := &gsm_signal_test_mu
		m.unlock()
	}
}

fn test_graceful_shutdown_signal_listener_triggers_shutdown() {
	gsm_signal_test_lock()
	defer { gsm_signal_test_unlock() }

	mut gsm := new_graceful_shutdown_manager()
	gsm.set_timeout(2 * time.second)
	gsm.start_signal_listener()
	gsm.wait_signal_ready()

	// Send SIGTERM to self
	pid := os.getpid()
	C.kill(pid, C.SIGTERM)

	// Wait for the signal listener to call shutdown()
	mut stopped := false
	for _ in 0 .. 200 {
		time.sleep(10 * time.millisecond)
		if gsm.is_stopped() {
			stopped = true
			break
		}
	}
	assert stopped == true

	// Wait for the signal-listener goroutine to exit cleanly
	gsm.wait_signal_listener()
}

fn test_graceful_shutdown_signal_listener_idempotent() {
	gsm_signal_test_lock()
	defer { gsm_signal_test_unlock() }

	mut gsm := new_graceful_shutdown_manager()
	gsm.start_signal_listener()
	gsm.start_signal_listener() // second call should be a no-op
	gsm.start_signal_listener() // third call should be a no-op
	gsm.wait_signal_ready()

	// Trigger shutdown via signal
	pid := os.getpid()
	C.kill(pid, C.SIGTERM)

	mut stopped := false
	for _ in 0 .. 200 {
		time.sleep(10 * time.millisecond)
		if gsm.is_stopped() {
			stopped = true
			break
		}
	}
	assert stopped == true
	gsm.wait_signal_listener()
}

// ── Full flow: requests + signal + graceful drain ──

fn test_graceful_shutdown_full_flow_with_in_flight() {
	gsm_signal_test_lock()
	defer { gsm_signal_test_unlock() }

	mut gsm := new_graceful_shutdown_manager()
	gsm.set_timeout(3 * time.second)

	// Use a channel to track callback invocation
	cb_ch := chan bool{cap: 1}
	gsm.set_on_shutdown(fn [cb_ch] () {
		select {
			cb_ch <- true {}
			else {}
		}
	})

	// Start an in-flight request that completes after 100ms
	gsm.request_started()!
	spawn fn (mut g GracefulShutdownManager) {
		time.sleep(100 * time.millisecond)
		g.request_completed()
	}(mut gsm)

	// Start signal listener and send SIGTERM
	gsm.start_signal_listener()
	gsm.wait_signal_ready()
	pid := os.getpid()
	C.kill(pid, C.SIGTERM)

	// Wait for shutdown to be initiated
	mut stopped := false
	for _ in 0 .. 200 {
		time.sleep(10 * time.millisecond)
		if gsm.is_stopped() {
			stopped = true
			break
		}
	}
	assert stopped == true

	// Wait for the callback to fire (shutdown drains in-flight, then calls callback)
	mut cb_fired := false
	for _ in 0 .. 100 {
		select {
			_ := <-cb_ch {
				cb_fired = true
				break
			}
			else {
				time.sleep(10 * time.millisecond)
			}
		}
		if cb_fired {
			break
		}
	}
	assert cb_fired == true

	// New requests should be rejected
	gsm.request_started() or {
		return
	}
	assert false
}

// ── Multiple concurrent in-flight requests drained ──

fn test_graceful_shutdown_drains_multiple_in_flight() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.set_timeout(3 * time.second)

	// Start 3 in-flight requests with different completion times
	gsm.request_started()!
	gsm.request_started()!
	gsm.request_started()!

	spawn fn (mut g GracefulShutdownManager) {
		time.sleep(50 * time.millisecond)
		g.request_completed()
	}(mut gsm)
	spawn fn (mut g GracefulShutdownManager) {
		time.sleep(100 * time.millisecond)
		g.request_completed()
	}(mut gsm)
	spawn fn (mut g GracefulShutdownManager) {
		time.sleep(150 * time.millisecond)
		g.request_completed()
	}(mut gsm)

	start_ns := time.now().unix_nano()
	gsm.shutdown()
	elapsed_ms := (time.now().unix_nano() - start_ns) / 1_000_000

	// Should wait for all 3 requests (~150ms) but not hit the 3s timeout
	assert elapsed_ms >= 140
	assert elapsed_ms < 1000
	assert gsm.is_stopped() == true
}

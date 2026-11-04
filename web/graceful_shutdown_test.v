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
			else {
			}
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
			cb_ch <- true {
			}
			else {
			}
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
		else {
		}
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
			else {
			}
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
		else {
		}
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
			else {
			}
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
			cb_ch <- true {
			}
			else {
			}
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

// ── 排空语义：in-flight 请求真的被等到了吗 ──
//
// 只断言「shutdown() 最终返回了」是测不出问题的：它在两种情况下都会返回 ——
// 请求跑完了，或者超时兜底了。而超时兜底恰恰是 in-flight 计数失效时的表现。
// 所以这里断言的是**回调在什么时刻被调用**：早于请求完成即为漏排。
__global gsm_drain_completed_ns i64
__global gsm_drain_order_ok bool

fn test_graceful_shutdown_drains_before_callback() {
	mut gsm := new_graceful_shutdown_manager()
	gsm.set_timeout(5 * time.second) // 远大于请求耗时：超时兜底不该发生

	gsm_drain_completed_ns = 0
	gsm_drain_order_ok = false
	// 标记必须走 __global：V 0.5.2 里闭包对 `[mut x]` 捕获的是**跨线程共享的副本**，
	// 主线程事后读到的 x 永远是闭包创建时的值，其它线程的写入它也看不见。
	// 用它做「回调晚于请求完成」的判断，断言会恒假 —— 测出来的是语言行为，不是框架。
	gsm.set_on_shutdown(fn () {
		gsm_drain_order_ok = gsm_drain_completed_ns > 0
			&& time.now().unix_nano() >= gsm_drain_completed_ns
	})

	gsm.request_started()!
	spawn fn (mut g GracefulShutdownManager) {
		time.sleep(150 * time.millisecond)
		gsm_drain_completed_ns = time.now().unix_nano()
		g.request_completed()
	}(mut gsm)

	start_ns := time.now().unix_nano()
	gsm.shutdown()
	elapsed_ms := (time.now().unix_nano() - start_ns) / 1_000_000

	// 请求耗时 150ms：真的排空就不可能 50ms 内回来
	assert elapsed_ms >= 140, 'shutdown() returned in ${elapsed_ms}ms — in-flight requests were not drained'
	assert gsm_drain_completed_ns > 0, 'in-flight request never completed'
	assert gsm_drain_order_ok, 'on_shutdown fired before the in-flight request completed'
}

// ── 反向对照：计数接到副本上，等待就必然失效 ──
//
// 上面那条只证明了「现在是好的」。这条复刻 V 0.5.2 里 `mut x := <引用>` 的真实语义
// ——生成的是结构体副本、副本自带一份计数——用来钉住「为什么这里必须传指针」。
// 断言：原等待组清零后，副本上的 wait() 仍然不返回。
struct WgCopyHolder {
mut:
	wg sync.WaitGroup
}

fn test_waitgroup_copy_does_not_share_counter() {
	mut original := sync.WaitGroup{}
	original.add(1)
	mut copy := original

	// 不能用 `spawn fn (mut wg sync.WaitGroup, ...)`：V 不允许 spawn 的实参里
	// 出现「可变的非引用类型」，整条用例连编译都过不去 —— 于是它长期以来
	// 既不是红的也不是绿的，只是不存在。
	// 把副本塞进 @[heap] 结构体、只传指针，同样是「协程持有自己那份计数」，
	// 语义等价，且能被编译器接受。
	holder := &WgCopyHolder{ wg: copy }
	done := chan bool{cap: 1}
	spawn fn (h &WgCopyHolder, d chan bool) {
		unsafe { h.wg.wait() }
		d <- true
	}(holder, done)

	original.done()
	time.sleep(100 * time.millisecond)

	mut finished := false
	select {
		_ := <-done {
			finished = true
		}
		else {
		}
	}
	assert !finished, '副本上的 wait() 等到了原等待组的 done() —— 前提不成立'
	// 收尾：别把这个协程留到进程退出
	unsafe { holder.wg.done() }
}

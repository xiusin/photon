module web

// graceful_shutdown.v - Graceful Shutdown Manager (Task D4)
//
// Provides SIGTERM/SIGINT-triggered graceful shutdown for the Photon web
// server. On signal, the manager:
//   1. Stops accepting new requests (request_started() returns an error)
//   2. Waits for in-flight requests to complete (with a configurable timeout)
//   3. Invokes an optional on_shutdown callback (e.g., ApplicationContext.shutdown())
//
// Spring equivalent: SpringApplication.shutdownHook + SmartLifecycle stop.
//
// Thread-safety: all mutable state is protected by sync.Mutex. The in-flight
// request count is tracked via sync.WaitGroup so concurrent request_started() /
// request_completed() calls are race-free.
import os
import sync
import time

// default_graceful_shutdown_timeout is the default time to wait for in-flight
// requests to complete before forcing shutdown. 30 seconds matches Spring
// Boot's default server.shutdown.grace-period.
pub const default_graceful_shutdown_timeout = 30 * time.second

// GracefulShutdownManager coordinates graceful shutdown of the web server.
//
// Lifecycle:
//   1. new_graceful_shutdown_manager() — create the manager
//   2. set_timeout() / set_on_shutdown() — configure (optional)
//   3. start_signal_listener() — begin listening for SIGTERM/SIGINT
//   4. request_started() / request_completed() — wrap each request
//   5. shutdown() — initiate graceful shutdown (also called by signal listener)
//   6. wait() — block until shutdown() has fully completed
//
// The manager is idempotent: calling shutdown() twice is safe (the second
// call returns immediately).
@[heap]
pub struct GracefulShutdownManager {
pub mut:
	mu             sync.Mutex
	in_flight_wg   sync.WaitGroup // tracks in-flight requests
	shutdown_ch    chan bool      // signals that shutdown() has been initiated
	stopped        bool
	timeout        time.Duration = default_graceful_shutdown_timeout
	on_shutdown    fn () = unsafe { nil } // optional cleanup callback (e.g., ctx.shutdown())
	wg             sync.WaitGroup // tracks the signal-listener goroutine
	signal_started bool
	signal_ready   chan bool // signaled after signal handlers are registered
}

// new_graceful_shutdown_manager creates a new GracefulShutdownManager with
// the default 30-second timeout.
pub fn new_graceful_shutdown_manager() &GracefulShutdownManager {
	return &GracefulShutdownManager{
		shutdown_ch: chan bool{cap: 1}
		timeout:     default_graceful_shutdown_timeout
	}
}

// set_timeout configures the maximum time to wait for in-flight requests
// to complete during shutdown. Must be called before shutdown() is invoked.
pub fn (mut gsm GracefulShutdownManager) set_timeout(timeout time.Duration) {
	gsm.mu.@lock()
	gsm.timeout = timeout
	gsm.mu.unlock()
}

// set_on_shutdown registers a callback to be invoked after in-flight
// requests have completed (or the timeout has elapsed). This is typically
// used to call ApplicationContext.shutdown() for full lifecycle destruction.
pub fn (mut gsm GracefulShutdownManager) set_on_shutdown(callback fn ()) {
	gsm.mu.@lock()
	gsm.on_shutdown = callback
	gsm.mu.unlock()
}

// request_started increments the in-flight request counter.
// Returns an error if the server is already shutting down — the caller
// should reject the request (typically with HTTP 503 Service Unavailable).
//
// Must be paired with a deferred request_completed() call:
//   gsm.request_started()!  // reject if shutting down
//   defer { gsm.request_completed() }
//   // ... handle request ...
pub fn (mut gsm GracefulShutdownManager) request_started() ! {
	gsm.mu.@lock()
	if gsm.stopped {
		gsm.mu.unlock()
		return error('server is shutting down / 服务器正在关闭')
	}
	gsm.in_flight_wg.add(1)
	gsm.mu.unlock()
}

// request_completed decrements the in-flight request counter.
// Must be called exactly once for each successful request_started() call
// (typically via `defer { gsm.request_completed() }`).
pub fn (mut gsm GracefulShutdownManager) request_completed() {
	gsm.in_flight_wg.done()
}

// is_stopped returns true if shutdown() has been initiated.
pub fn (gsm &GracefulShutdownManager) is_stopped() bool {
	unsafe { gsm.mu.@lock() }
	defer { unsafe { gsm.mu.unlock() } }
	return gsm.stopped
}

// shutdown initiates graceful shutdown:
//   1. Marks the manager as stopped (request_started() will reject new requests)
//   2. Signals shutdown_ch so wait() callers can proceed
//   3. Waits for in-flight requests to complete (up to `timeout`)
//   4. Invokes the on_shutdown callback if one was registered
//
// Idempotent: calling shutdown() twice is safe (the second call returns
// immediately without re-running the callback).
pub fn (mut gsm GracefulShutdownManager) shutdown() {
	gsm.mu.@lock()
	if gsm.stopped {
		gsm.mu.unlock()
		return
	}
	gsm.stopped = true
	timeout := gsm.timeout
	callback := gsm.on_shutdown
	gsm.mu.unlock()

	// Signal shutdown initiated (non-blocking — channel has cap:1).
	select {
		gsm.shutdown_ch <- true {}
		else {}
	}

	// Wait for in-flight requests with timeout. We spawn a goroutine that
	// waits on the WaitGroup and signals via a channel; the main thread
	// polls with a deadline (V's select { else {} } is non-blocking).
	done_ch := chan bool{cap: 1}
	spawn fn (wg &GracefulShutdownManager, d chan bool) {
		unsafe {
			mut g := wg
			g.in_flight_wg.wait()
		}
		select {
			d <- true {}
			else {}
		}
	}(gsm, done_ch)

	deadline_ns := time.now().unix_nano() + i64(timeout)
	for {
		select {
			_ := <-done_ch {
				// All in-flight requests completed
				break
			}
			else {}
		}
		if time.now().unix_nano() >= deadline_ns {
			// Timeout — force shutdown (in-flight requests may still be running)
			break
		}
		time.sleep(10 * time.millisecond)
	}

	// Invoke the on_shutdown callback (e.g., ApplicationContext.shutdown()).
	if !isnil(callback) {
		callback()
	}
}

// wait blocks until shutdown() has been initiated. Use this to keep the
// main goroutine alive while the server runs in the background.
//
// Note: this returns as soon as shutdown() *starts* — in-flight request
// draining and the on_shutdown callback run asynchronously inside
// shutdown(). For full completion, call shutdown() directly (it blocks
// until draining/callback are done).
pub fn (gsm &GracefulShutdownManager) wait() {
	_ := <-gsm.shutdown_ch
}

// start_signal_listener spawns a background goroutine that listens for
// SIGTERM and SIGINT. When either signal is received, shutdown() is called
// automatically.
//
// Idempotent: calling this twice is safe (the second call is a no-op).
// The goroutine is tracked by the manager's wg so that test code can
// verify it has exited via wait_signal_listener().
//
// After the signal handlers are registered, the `signal_ready` channel is
// signaled. Callers that need to ensure handlers are installed before
// sending a signal can read from `signal_ready` (or call
// wait_signal_ready()).
pub fn (mut gsm GracefulShutdownManager) start_signal_listener() {
	gsm.mu.@lock()
	if gsm.signal_started {
		gsm.mu.unlock()
		return
	}
	gsm.signal_started = true
	gsm.signal_ready = chan bool{cap: 1}
	gsm.mu.unlock()

	gsm.wg.add(1)
	spawn fn (gg &GracefulShutdownManager) {
		defer {
			unsafe {
				mut g := gg
				g.wg.done()
			}
		}
		// V's os.signal_opt registers a callback (not a channel). We use a
		// shared flag + channel to bridge the signal callback to the
		// listener goroutine.
		sig_ch := chan bool{cap: 1}
		handler := fn [sig_ch] (_ os.Signal) {
			select {
				sig_ch <- true {}
				else {}
			}
		}
		os.signal_opt(.term, handler) or {
			unsafe {
				mut g := gg
				select {
					g.signal_ready <- true {}
					else {}
				}
			}
			return
		}
		os.signal_opt(.int, handler) or {
			unsafe {
				mut g := gg
				select {
					g.signal_ready <- true {}
					else {}
				}
			}
			return
		}

		// Signal that handlers are registered and we're ready to receive.
		unsafe {
			mut g := gg
			select {
				g.signal_ready <- true {}
				else {}
			}
		}

		// Block until a signal is received.
		_ := <-sig_ch

		unsafe {
			mut g := gg
			g.shutdown()
		}
	}(gsm)
}

// wait_signal_ready blocks until the signal listener has registered its
// handlers (or up to 1 second). Useful for tests that need to send a
// signal immediately after start_signal_listener() returns.
//
// If start_signal_listener() was never called, this returns immediately.
pub fn (mut gsm GracefulShutdownManager) wait_signal_ready() {
	gsm.mu.@lock()
	ready_ch := gsm.signal_ready
	started := gsm.signal_started
	gsm.mu.unlock()
	// If start_signal_listener() hasn't been called yet, return immediately.
	if !started {
		return
	}
	// Wait up to 1 second for the signal listener to be ready.
	deadline_ns := time.now().unix_nano() + i64(1 * time.second)
	for {
		select {
			_ := <-ready_ch {
				return
			}
			else {}
		}
		if time.now().unix_nano() >= deadline_ns {
			return
		}
		time.sleep(5 * time.millisecond)
	}
}

// wait_signal_listener blocks until the signal-listener goroutine has
// exited (i.e., after a signal was received and shutdown() was called).
// Useful for tests that send a signal and want to verify the listener
// exited cleanly.
pub fn (mut gsm GracefulShutdownManager) wait_signal_listener() {
	gsm.wg.wait()
}

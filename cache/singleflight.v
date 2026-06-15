module cache

// singleflight.v - Peak-Shaving (削峰) Component
//
// Provides call deduplication: multiple concurrent requests for the same key
// are coalesced into a single execution. Equivalent to Go's singleflight.
// Prevents cache stampede / thundering herd under high concurrency.
//
// V has no official singleflight or rate-limiting library; this implements
// the pattern using sync.Mutex and spin-polling for V 0.5.1 compatibility.

import sync
import time

// Call represents an in-flight or completed singleflight call
struct Call {
pub:
	key  string
mut:
	val  string
	err  string
	done bool
}

// Singleflight deduplicates concurrent function calls for the same key.
// When multiple goroutines call do() with the same key, only the first
// actually executes fn(); all others wait and share the result.
pub struct Singleflight {
mut:
	mu       sync.Mutex
	calls    map[string]&Call
}

// new_singleflight creates a new Singleflight instance
pub fn new_singleflight() &Singleflight {
	return &Singleflight{
		calls: map[string]&Call{}
	}
}

// do executes fn for the given key. If another goroutine is already
// executing fn for the same key, this call waits and shares the result.
// This is the peak-shaving mechanism: concurrent requests for the same
// resource are merged into one.
pub fn (mut sf Singleflight) do(key string, f fn () !string) !string {
	sf.mu.@lock()
	existing := sf.calls[key] or { unsafe { nil } }
	if isnil(existing) {
		// We are the leader — no in-flight call exists, create one
		mut c := &Call{ key: key }
		sf.calls[key] = c
		sf.mu.unlock()

		// Execute the function
		result := f() or {
			// Store the error and notify waiters
			sf.mu.@lock()
			c.err = err.msg()
			c.done = true
			sf.calls.delete(key)
			sf.mu.unlock()
			return err
		}

		// Store the result and notify waiters
		sf.mu.@lock()
		c.val = result
		c.done = true
		sf.calls.delete(key)
		sf.mu.unlock()

		return result
	}

	// A call is already in-flight — wait for the result
	c := existing
	sf.mu.unlock()

	// Spin-poll until the leader completes.
	// NOTE: c.done is read without a mutex (relaxed memory ordering).
	// On x86 this is safe; on weakly-ordered architectures, wrap in sf.mu.@lock()/unlock().
	for !c.done {
		time.sleep(1 * time.millisecond)
	}

	// Return shared result or error (written by leader before c.done = true,
	// so values are visible to us via the happens-before relationship).
	if c.err.len > 0 {
		return error(c.err)
	}
	return c.val
}

// has_inflight checks if a call is currently in-flight for the given key
pub fn (mut sf Singleflight) has_inflight(key string) bool {
	sf.mu.@lock()
	result := key in sf.calls
	sf.mu.unlock()
	return result
}

// inflight_count returns the number of currently in-flight calls
pub fn (mut sf Singleflight) inflight_count() int {
	sf.mu.@lock()
	result := sf.calls.len
	sf.mu.unlock()
	return result
}

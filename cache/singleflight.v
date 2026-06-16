module cache

// singleflight.v - Peak-Shaving (削峰) Component
//
// Provides call deduplication: multiple concurrent requests for the same key
// are coalesced into a single execution. Equivalent to Go's singleflight.
// Prevents cache stampede / thundering herd under high concurrency.

import sync
import time

// Call represents an in-flight or completed singleflight call
struct Call {
	key  string
mut:
	val  string
	err  string
	done bool
}

// Singleflight deduplicates concurrent function calls for the same key.
// When multiple goroutines call do() with the same key, only the first
// actually executes fn(); all others wait and share the result.
//
// Thread-safety: all accesses to Call.done/val/err are protected by
// sf.mu to ensure correct memory ordering on all architectures
// (including ARM/Apple Silicon, which have relaxed memory ordering).
pub struct Singleflight {
mut:
	mu    sync.Mutex
	calls map[string]&Call
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
		// Leader — create in-flight Call and execute fn
		mut c := &Call{ key: key }
		sf.calls[key] = c
		sf.mu.unlock()

		// Execute the function; on error, store it for followers
		result := f() or {
			sf.mu.@lock()
			c.err = err.msg()
			c.done = true
			sf.calls.delete(key)
			sf.mu.unlock()
			return err
		}

		// Store result and notify followers under lock
		sf.mu.@lock()
		c.val = result
		c.done = true
		sf.calls.delete(key)
		sf.mu.unlock()

		return result
	}

	// Follower — leader is already executing for this key
	sf.mu.unlock()

	// Wait for leader with lock-protected polling to ensure
	// memory ordering on all architectures
	for {
		sf.mu.@lock()
		done := existing.done
		sf.mu.unlock()
		if done {
			break
		}
		time.sleep(1 * time.millisecond)
	}

	// Read final result under lock for memory ordering
	sf.mu.@lock()
	get_val := existing.val
	get_err := existing.err
	sf.mu.unlock()

	if get_err.len > 0 {
		return error(get_err)
	}
	return get_val
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

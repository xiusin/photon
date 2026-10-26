module cache

// singleflight.v - Peak-Shaving (削峰) Component
//
// Provides call deduplication: multiple concurrent requests for the same key
// are coalesced into a single execution. Equivalent to Go's singleflight.
// Prevents cache stampede / thundering herd under high concurrency.
//
// Notification mechanism:
//   - Each Call carries a `done_ch` that the leader *closes* when finished.
//     Closing wakes every follower at once (a broadcast); sending on a
//     buffered channel would only wake one and leave the rest polling.
//   - Followers block on `<-done_ch` with no timeout and no fallback sleep:
//     a waiting follower costs zero CPU, and the wakeup is immediate.
import sync

// Call represents an in-flight or completed singleflight call
struct Call {
	key string
mut:
	val     string
	err     string
	done    bool
	done_ch chan bool // closed by the leader when the call completes
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
		// Leader — create the in-flight Call and execute f outside the lock.
		mut c := &Call{
			key:     key
			done_ch: chan bool{}
		}
		sf.calls[key] = c
		sf.mu.unlock()

		mut failed := false
		result := f() or {
			failed = true
			err.msg()
		}
		sf.mu.@lock()
		if failed {
			c.err = result
		} else {
			c.val = result
		}
		c.done = true
		sf.calls.delete(key)
		sf.mu.unlock()

		// Broadcast to every follower. Closing after the state is published
		// (under the lock) guarantees followers see the final val/err.
		c.done_ch.close()
		if failed {
			return error(result)
		}
		return result
	}
	sf.mu.unlock()

	// Follower — block until the leader broadcasts. No polling, no timeout.
	_ := <-existing.done_ch

	// Publish-and-read: the leader wrote val/err before closing done_ch, and
	// close/recv are a happens-before pair, so no lock is needed to read them.
	if existing.err.len > 0 {
		return error(existing.err)
	}
	return existing.val
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

module web

// ratelimit.v - Rate Limiting (Laravel RateLimiter inspired)
//
// Performance design:
//   - Uses sharded locks (default 64 shards) instead of a single global lock.
//   - Each key is hashed to a shard, so different keys never contend.
//   - This allows thousands of concurrent rate-limit checks with minimal contention.
//   - Read-only operations (remaining, retry_after) use the same shard lock
//     but complete in O(1) without iterating the full map.
import time
import sync
import support

// shard_count is the default number of lock shards.
// Must be a power of 2 for fast modulo via bitwise AND.
const shard_count = 64

// RateLimiter implements rate limiting with attempt tracking (thread-safe).
// Uses sharded locking for high-concurrency performance.
@[heap]
pub struct RateLimiter {
pub mut:
	attempts map[string][]i64
mut:
	shards []sync.Mutex
}

// new_rate_limiter creates a new RateLimiter with sharded locks.
pub fn new_rate_limiter() &RateLimiter {
	mut shards := []sync.Mutex{len: shard_count}
	return &RateLimiter{
		attempts: map[string][]i64{}
		shards:   shards
	}
}

// shard_for returns the shard index for a given key.
// Uses FNV-1a hash for fast, uniform distribution.
@[inline]
fn (r &RateLimiter) shard_for(key string) int {
	// FNV-1a 64-bit hash, zero-allocation via support.fnv1a_str
	return int(support.fnv1a_str(key) & u64(shard_count - 1))
}

// too_many_attempts checks if the key has exceeded the max attempts
// within the decay window (in seconds). Expired attempts are automatically
// cleaned from the attempt list.
//
// Only locks the shard for this key — other keys are unaffected.
pub fn (mut r RateLimiter) too_many_attempts(key string, max_attempts int, decay_seconds i64) bool {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	mut attempts := r.attempts[key] or { return false }
	now := time.now().unix()

	// Filter out expired attempts (outside the decay window)
	mut valid := []i64{cap: attempts.len}
	for ts in attempts {
		if now - ts < decay_seconds {
			valid << ts
		}
	}

	if valid.len == 0 {
		r.attempts.delete(key)
		return false
	}

	r.attempts[key] = valid
	return valid.len >= max_attempts
}

// hit records an attempt for the given key.
// Only locks the shard for this key.
pub fn (mut r RateLimiter) hit(key string) {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	now := time.now().unix()
	mut attempts := r.attempts[key] or { []i64{} }
	attempts << now
	r.attempts[key] = attempts
}

// remaining returns the number of remaining attempts.
// Only locks the shard for this key.
pub fn (mut r RateLimiter) remaining(key string, max_attempts int) int {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	attempts := r.attempts[key] or { return max_attempts }
	remaining := max_attempts - attempts.len
	if remaining < 0 {
		return 0
	}
	return remaining
}

// retry_after returns seconds until the earliest attempt decays.
// Only locks the shard for this key.
pub fn (mut r RateLimiter) retry_after(key string, decay_seconds i64) i64 {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	attempts := r.attempts[key] or { return 0 }
	if attempts.len == 0 {
		return 0
	}
	now := time.now().unix()
	earliest := attempts[0]
	decay_time := earliest + decay_seconds
	if now >= decay_time {
		return 0
	}
	return decay_time - now
}

// clear removes rate limit data for a key.
// Only locks the shard for this key.
pub fn (mut r RateLimiter) clear(key string) {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }
	r.attempts.delete(key)
}

// clear_all removes all rate limit data.
// Acquires all shard locks in order to prevent deadlock.
pub fn (mut r RateLimiter) clear_all() {
	for i in 0 .. shard_count {
		r.shards[i].@lock()
	}
	// Clear the entire map at once
	r.attempts = map[string][]i64{}
	for i in 0 .. shard_count {
		r.shards[shard_count - 1 - i].unlock()
	}
}

// clear_expired removes expired attempts from all keys.
// Acquires all shard locks in order to prevent deadlock.
pub fn (mut r RateLimiter) clear_expired(decay_seconds i64) {
	for i in 0 .. shard_count {
		r.shards[i].@lock()
	}
	now := time.now().unix()
	mut keys_to_delete := []string{}
	for key, attempts in r.attempts {
		mut valid := []i64{}
		for ts in attempts {
			if now - ts < decay_seconds {
				valid << ts
			}
		}
		if valid.len == 0 {
			keys_to_delete << key
		} else {
			r.attempts[key] = valid
		}
	}
	for key in keys_to_delete {
		r.attempts.delete(key)
	}
	for i in 0 .. shard_count {
		r.shards[shard_count - 1 - i].unlock()
	}
}

// attempts returns the number of attempts for a key.
// Only locks the shard for this key.
pub fn (mut r RateLimiter) attempts(key string) int {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }
	a := r.attempts[key] or { return 0 }
	return a.len
}

// key_count returns the total number of tracked keys.
// Acquires all shard locks for a consistent snapshot.
pub fn (mut r RateLimiter) key_count() int {
	for i in 0 .. shard_count {
		r.shards[i].@lock()
	}
	count := r.attempts.len
	for i in 0 .. shard_count {
		r.shards[shard_count - 1 - i].unlock()
	}
	return count
}

// hit_and_record records a hit and checks if the limit is exceeded in one operation.
// More efficient than separate hit() + too_many_attempts() — only acquires the shard lock once.
pub fn (mut r RateLimiter) hit_and_record(key string, max_attempts int, decay_seconds i64) bool {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	now := time.now().unix()

	// Record the hit
	mut attempts := r.attempts[key] or { []i64{} }
	attempts << now
	r.attempts[key] = attempts

	// Check if limit exceeded (filter expired)
	mut valid := []i64{cap: attempts.len}
	for ts in attempts {
		if now - ts < decay_seconds {
			valid << ts
		}
	}
	if valid.len > 0 {
		r.attempts[key] = valid
	}

	return valid.len < max_attempts
}

// resolve_rate_limit_key builds a rate limit key from prefix, user ID, and IP.
// Priority: user_id > ip > anonymous.
pub fn resolve_rate_limit_key(prefix string, user_id string, ip string) string {
	if user_id.len > 0 {
		return '${prefix}:${user_id}'
	}
	if ip.len > 0 {
		return '${prefix}:ip:${ip}'
	}
	return '${prefix}:anonymous'
}

// ── Fixed Window Rate Limiter ──

// FixedWindowEntry tracks a single fixed window.
pub struct FixedWindowEntry {
pub mut:
	count   int
	expires i64
}

// FixedWindowLimiter implements fixed-window rate limiting.
// Uses sharded locking for high-concurrency performance.
@[heap]
pub struct FixedWindowLimiter {
pub mut:
	windows map[string]FixedWindowEntry
mut:
	shards []sync.Mutex
}

// new_fixed_window_limiter creates a new FixedWindowLimiter.
pub fn new_fixed_window_limiter() &FixedWindowLimiter {
	return &FixedWindowLimiter{
		windows: map[string]FixedWindowEntry{}
		shards:  []sync.Mutex{len: shard_count}
	}
}

// shard_for returns the shard index for a given key.
@[inline]
fn (fw &FixedWindowLimiter) shard_for(key string) int {
	return int(support.fnv1a_str(key) & u64(shard_count - 1))
}

// check returns true if the request is allowed within the rate limit.
// Only locks the shard for this key.
pub fn (mut fw FixedWindowLimiter) check(key string, max_requests int, window_seconds i64) bool {
	idx := fw.shard_for(key)
	fw.shards[idx].@lock()
	defer { fw.shards[idx].unlock() }

	now := time.now().unix()
	mut entry := fw.windows[key] or { FixedWindowEntry{} }

	// Reset if window expired
	if now >= entry.expires {
		entry.count = 0
		entry.expires = now + window_seconds
	}

	entry.count++
	fw.windows[key] = entry

	return entry.count <= max_requests
}

// get_remaining returns the remaining requests in the current window.
// Only locks the shard for this key.
pub fn (mut fw FixedWindowLimiter) get_remaining(key string, max_requests int, window_seconds i64) int {
	idx := fw.shard_for(key)
	fw.shards[idx].@lock()
	defer { fw.shards[idx].unlock() }

	now := time.now().unix()
	entry := fw.windows[key] or { return max_requests }

	if now >= entry.expires {
		return max_requests
	}
	remaining := max_requests - entry.count
	if remaining < 0 {
		return 0
	}
	return remaining
}

// clear removes rate limit data for a key.
// Only locks the shard for this key.
pub fn (mut fw FixedWindowLimiter) clear(key string) {
	idx := fw.shard_for(key)
	fw.shards[idx].@lock()
	defer { fw.shards[idx].unlock() }
	fw.windows.delete(key)
}

module web

// ratelimit.v - Rate Limiting (Laravel RateLimiter inspired)

import time

// RateLimiter implements rate limiting with attempt tracking
@[heap]
pub struct RateLimiter {
pub mut:
	attempts map[string][]i64
}

// new_rate_limiter creates a new RateLimiter
pub fn new_rate_limiter() &RateLimiter {
	return &RateLimiter{}
}

// too_many_attempts checks if the key has exceeded the max attempts
pub fn (mut r RateLimiter) too_many_attempts(key string, max_attempts int) bool {
	attempts := r.attempts[key] or { return false }
	return attempts.len >= max_attempts
}

// hit records an attempt for the given key
pub fn (mut r RateLimiter) hit(key string) {
	now := time.now().unix()
	mut attempts := r.attempts[key] or { []i64{} }
	attempts << now
	r.attempts[key] = attempts
}

// remaining returns the number of remaining attempts
pub fn (r &RateLimiter) remaining(key string, max_attempts int) int {
	attempts := r.attempts[key] or { return max_attempts }
	remaining := max_attempts - attempts.len
	if remaining < 0 {
		return 0
	}
	return remaining
}

// retry_after returns seconds until the earliest attempt decays
pub fn (r &RateLimiter) retry_after(key string, decay_seconds i64) i64 {
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

// clear removes rate limit data for a key
pub fn (mut r RateLimiter) clear(key string) {
	r.attempts.delete(key)
}

// clear_expired removes expired attempts from all keys
pub fn (mut r RateLimiter) clear_expired(decay_seconds i64) {
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
}

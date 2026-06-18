module web

// ── RateLimiter (Sliding Window) Tests ──

fn test_new_rate_limiter() {
	mut limiter := new_rate_limiter()
	assert limiter.key_count() == 0
}

fn test_hit_and_attempts() {
	mut limiter := new_rate_limiter()
	limiter.hit('user:1')
	limiter.hit('user:1')
	limiter.hit('user:1')

	assert limiter.attempts('user:1') == 3
}

fn test_too_many_attempts_under_limit() {
	mut limiter := new_rate_limiter()
	for _ in 0 .. 5 {
		limiter.hit('api:key')
	}
	assert limiter.too_many_attempts('api:key', 10, 3600) == false
}

fn test_too_many_attempts_over_limit() {
	mut limiter := new_rate_limiter()
	for _ in 0 .. 5 {
		limiter.hit('api:key')
	}
	assert limiter.too_many_attempts('api:key', 5, 3600) == true
}

fn test_remaining_attempts() {
	mut limiter := new_rate_limiter()
	assert limiter.remaining('key', 10) == 10

	limiter.hit('key')
	assert limiter.remaining('key', 10) == 9

	limiter.hit('key')
	limiter.hit('key')
	assert limiter.remaining('key', 10) == 7
}

fn test_remaining_does_not_go_negative() {
	mut limiter := new_rate_limiter()
	for _ in 0 .. 15 {
		limiter.hit('key')
	}
	assert limiter.remaining('key', 10) == 0
}

fn test_clear_key() {
	mut limiter := new_rate_limiter()
	limiter.hit('key1')
	limiter.hit('key2')
	assert limiter.key_count() == 2

	limiter.clear('key1')
	assert limiter.key_count() == 1
	assert limiter.attempts('key1') == 0
	assert limiter.attempts('key2') == 1
}

fn test_clear_all() {
	mut limiter := new_rate_limiter()
	limiter.hit('a')
	limiter.hit('b')
	limiter.hit('c')
	assert limiter.key_count() == 3

	limiter.clear_all()
	assert limiter.key_count() == 0
}

fn test_clear_expired_basic() {
	mut limiter := new_rate_limiter()
	// These will be "expired" since decay is 0 seconds
	limiter.hit('old_key')
	assert limiter.attempts('old_key') == 1

	// clear_expired with decay=0 should remove all
	limiter.clear_expired(0)
	assert limiter.attempts('old_key') == 0
}

fn test_retry_after_no_attempts() {
	mut limiter := new_rate_limiter()
	assert limiter.retry_after('nonexistent', 3600) == 0
}

fn test_hit_and_record_allowed() {
	mut limiter := new_rate_limiter()
	allowed := limiter.hit_and_record('key', 5, 3600)
	assert allowed == true // first hit should be allowed
}

fn test_multiple_keys_independent() {
	mut limiter := new_rate_limiter()
	limiter.hit('user:a')
	limiter.hit('user:a')
	limiter.hit('user:b')

	assert limiter.attempts('user:a') == 2
	assert limiter.attempts('user:b') == 1
	assert limiter.too_many_attempts('user:a', 5, 3600) == false
	assert limiter.too_many_attempts('user:b', 1, 3600) == true
}

// ── FixedWindowLimiter Tests ──

fn test_fixed_window_creation() {
	mut fw := new_fixed_window_limiter()
	assert fw.get_remaining('key', 5, 60) == 5 // verify it works
}

fn test_fixed_window_check_under_limit() {
	mut fw := new_fixed_window_limiter()
	assert fw.check('key', 5, 60) == true
	assert fw.check('key', 5, 60) == true
	assert fw.check('key', 5, 60) == true
}

fn test_fixed_window_check_over_limit() {
	mut fw := new_fixed_window_limiter()
	assert fw.check('key', 3, 60) == true
	assert fw.check('key', 3, 60) == true
	assert fw.check('key', 3, 60) == true
	assert fw.check('key', 3, 60) == false // 4th attempt denied
}

fn test_fixed_window_remaining() {
	mut fw := new_fixed_window_limiter()
	assert fw.get_remaining('key', 5, 60) == 5

	fw.check('key', 5, 60)
	assert fw.get_remaining('key', 5, 60) == 4

	fw.check('key', 5, 60)
	fw.check('key', 5, 60)
	assert fw.get_remaining('key', 5, 60) == 2
}

fn test_fixed_window_clear() {
	mut fw := new_fixed_window_limiter()
	fw.check('key', 5, 60)
	fw.check('key', 5, 60)

	fw.clear('key')
	// After clearing, should have full remaining again
	assert fw.get_remaining('key', 5, 60) == 5
}

fn test_fixed_window_independent_keys() {
	mut fw := new_fixed_window_limiter()
	fw.check('a', 2, 60)
	fw.check('a', 2, 60)
	assert fw.check('a', 2, 60) == false

	// Key b should still be allowed
	assert fw.check('b', 2, 60) == true
}

// ── Helper Function Tests ──

fn test_resolve_rate_limit_key_with_user_id() {
	key := resolve_rate_limit_key('api', 'user123', '')
	assert key == 'api:user123'
	assert key.contains('ip:') == false
}

fn test_resolve_rate_limit_key_with_ip() {
	key := resolve_rate_limit_key('api', '', '192.168.1.1')
	assert key == 'api:ip:192.168.1.1'
}

fn test_resolve_rate_limit_key_anonymous() {
	key := resolve_rate_limit_key('api', '', '')
	assert key == 'api:anonymous'
}

fn test_resolve_rate_limit_key_user_preferred_over_ip() {
	key := resolve_rate_limit_key('api', 'user123', '10.0.0.1')
	assert key == 'api:user123'
	assert key.contains('10.0.0.1') == false
}
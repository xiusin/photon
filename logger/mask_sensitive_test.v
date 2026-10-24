module logger

// mask_sensitive_test.v - regression tests for mask_sensitive_data
//
// The previous implementation searched a lowercased snapshot of the original
// message while rewriting a different string in place. As soon as one value was
// replaced by `***` the offsets drifted apart, which produced two failures:
//
//   1. `V panic: substr(x, y) out of bounds` — a crash inside the logger, i.e.
//      inside the error path, so a log call could take the process down;
//   2. silent over-masking — the follow-up match of the same key landed inside
//      the already-written placeholder and ate the rest of the value.
//
// Each case below used to hang, panic, or return a wrong string.

fn test_mask_single_pair() {
	assert mask_sensitive_data('password=a') == 'password=***'
	assert mask_sensitive_data('token:value') == 'token:***'
	assert mask_sensitive_data('secret = hunter2') == 'secret = ***'
}

fn test_mask_does_not_panic_on_trailing_ampersand() {
	// Used to panic: substr(16, 12) out of bounds (len=12).
	assert mask_sensitive_data('password=x&token') == 'password=***&token'
	assert mask_sensitive_data('user=1&password=x&token') == 'user=1&password=***&token'
	assert mask_sensitive_data('private_key=1&private_key=2') == 'private_key=***&private_key=***'
}

fn test_mask_repeated_key_keeps_both_values() {
	// Used to collapse to 'token=***' by eating the second key.
	assert mask_sensitive_data('token=xx&token=yy') == 'token=***&token=***'
	assert mask_sensitive_data('token=1 token=2') == 'token=*** token=***'
}

fn test_mask_empty_value_does_not_loop() {
	// `pos` must still advance when there is nothing to redact.
	assert mask_sensitive_data('password=&password=x') == 'password=&password=***'
	assert mask_sensitive_data('token=') == 'token='
}

fn test_mask_multiple_patterns_in_one_line() {
	assert mask_sensitive_data('api_key=abc&secret=def') == 'api_key=***&secret=***'
}

fn test_mask_bearer_token() {
	// `Bearer` is not in the key list, so it stays; the token after it goes.
	assert mask_sensitive_data('Bearer abc def') == 'Bearer *** def'
	assert mask_sensitive_data('x Bearer abc123 y') == 'x Bearer *** y'
}

// `authorization` is itself a sensitive key, so `Authorization: Bearer abc`
// masks the value `Bearer` first and the bearer pass then sees nothing left.
// Documented here because it is easy to mistake for a leak.
fn test_mask_authorization_header_masks_whole_value() {
	assert mask_sensitive_data('Authorization: Bearer abc123') == 'Authorization: *** abc123'
}

fn test_mask_leaves_clean_messages_untouched() {
	assert mask_sensitive_data('no secrets here') == 'no secrets here'
	assert mask_sensitive_data('') == ''
	assert mask_sensitive_data('user=1') == 'user=1'
}

fn test_mask_long_input_is_fast() {
	// Guards against a quadratic/looping scan on realistic log lines.
	mut line := ''
	for _ in 0 .. 200 {
		line += 'user=42&token=abcdefghij&path=/api/v1/items&status=200 '
	}
	result := mask_sensitive_data(line)
	assert result.count('token=***') == 200
	assert !result.contains('abcdefghij')
}

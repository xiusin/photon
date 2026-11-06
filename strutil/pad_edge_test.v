module strutil

// Regression: pad_left_str / pad_right_str looped forever on an empty pad —
// `result.len` never reached `length`.
fn test_pad_with_empty_pad_returns_input() {
	assert pad_left_str('ab', 5, '') == 'ab'
	assert pad_right_str('ab', 5, '') == 'ab'
}

fn test_pad_multi_byte_pad() {
	assert pad_left_str('ab', 6, 'xy') == 'xyxyab'
	assert pad_right_str('ab', 6, 'xy') == 'abxyxy'
	// 目标长度无法被 pad 整除时截断：长度优先，不做半个 pad
	assert pad_right_str('ab', 5, '<>') == 'ab<><'
}

fn test_pad_noop_and_exact() {
	assert pad_left_str('abcdef', 3, ' ') == 'abcdef'
	assert pad_right_str('abcdef', 6, ' ') == 'abcdef'
	assert pad_left_str('ab', 4, ' ') == '  ab'
}

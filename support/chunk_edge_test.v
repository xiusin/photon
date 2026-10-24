module support

// Regression: chunk(items, 0) used to loop forever — `i` never advanced
// because end == i, so the caller hung with no way out.
fn test_chunk_non_positive_size_returns_nothing() {
	assert chunk([1, 2, 3], 0).len == 0
	assert chunk([1, 2, 3], -1).len == 0
	assert chunk([]int{}, 2).len == 0
}

fn test_chunk_normal() {
	r := chunk([1, 2, 3, 4, 5], 2)
	assert r.len == 3
	assert r[0] == [1, 2]
	assert r[2] == [5]
}

fn test_get_uses_literal_key() {
	m := {
		'user.name': 'Alice'
		'user':      'root'
	}
	assert get_string(m, 'user.name', '') == 'Alice'
	assert get_string(m, 'user', '') == 'root'
	assert get_string(m, 'missing', 'def') == 'def'
	assert has_string(m, 'user') == true
	assert has_string(m, 'nope') == false
}

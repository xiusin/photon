module support

// support_ext_test.v - Extended tests for collection gaps, arr gaps

// ============================================================
// Collection gap tests
// ============================================================

fn test_collect_new_empty() {
	c := new_collection[int]()
	assert c.is_empty()
	assert c.count() == 0
}

fn test_collect_is_not_empty() {
	c := collect([1])
	assert c.is_not_empty()
}

fn test_collect_each() {
	mut tracker := &SumTracker{}
	c := collect([1, 2, 3])
	c.each(fn [mut tracker](n int) { tracker.sum += n })
	assert tracker.sum == 6
}

@[heap]
struct SumTracker {
mut:
	sum int
}

fn test_collect_transform() {
	mut c := collect([1, 2, 3])
	c.transform(fn (n int) int { return n * 10 })
	assert c.all() == [10, 20, 30]
}

fn test_collect_get_with_index() {
	c := collect(['a', 'b', 'c'])
	assert c.get(0, 'x') == 'a'
	assert c.get(1, 'x') == 'b'
	assert c.get(5, 'default') == 'default'
	assert c.get(-1, 'negative') == 'negative'
}

fn test_collect_chunk_method() {
	c := collect([1, 2, 3, 4, 5])
	chunks := c.chunk(2)
	assert chunks.len == 3
	assert chunks[0] == [1, 2]
	assert chunks[2] == [5]
}

fn test_collect_slice() {
	c := collect([1, 2, 3, 4, 5])
	mid := c.slice(1, 4)
	assert mid.all() == [2, 3, 4]
}

fn test_collect_slice_out_of_bounds() {
	c := collect([1, 2, 3])
	empty := c.slice(5, 10)
	assert empty.is_empty()
}

fn test_collect_key_by() {
	c := collect(['Alice', 'Bob'])
	by_first := c.key_by(fn (s string) string { return s[0..1] })
	assert by_first['A'] == 'Alice'
	assert by_first['B'] == 'Bob'
}

fn test_collect_concat() {
	c := collect([1, 2])
	d := c.concat([3, 4])
	assert d.all() == [1, 2, 3, 4]
}

fn test_collect_push_pop() {
	mut c := collect([1, 2])
	c.push(3)
	assert c.all() == [1, 2, 3]
	last := c.pop()
	assert last == 3
	assert c.all() == [1, 2]
}

fn test_collect_tap() {
	c := collect([1, 2, 3])
	result := c.tap(fn (col &Collection[int]) int { return col.count() })
	assert result.all() == [1, 2, 3] // tap returns self
}

fn test_collect_to_vec() {
	c := collect([1, 2, 3])
	v := c.to_vec()
	assert v == [1, 2, 3]
}

fn test_collect_to_json() {
	c := collect(['a', 'b'])
	js := c.to_json()
	assert js.contains('a')
	assert js.contains('b')
}

fn test_collect_empty_json() {
	c := new_collection[int]()
	js := c.to_json()
	assert js == '[]'
}

// ============================================================
// Arr gap tests
// ============================================================

fn test_arr_forget() {
	mut m := {'key': 'value'}
	forget_string(mut m, 'key')
	assert has_string(m, 'key') == false
}

fn test_arr_set() {
	mut m := map[string]string{}
	set_string(mut m, 'key', 'value')
	assert get_string(m, 'key', '') == 'value'
}

fn test_arr_last() {
	items := [1, 2, 3, 4, 5]
	result := last(items, fn (n int) bool { return n > 2 }, 0)
	assert result == 5
}

fn test_arr_last_not_found() {
	items := [1, 2, 3]
	result := last(items, fn (n int) bool { return n > 10 }, -1)
	assert result == -1
}

fn test_arr_filter_items() {
	items := [1, 2, 3, 4, 5]
	result := filter_items(items, fn (n int) bool { return n % 2 == 0 })
	assert result == [2, 4]
}

fn test_arr_collapse() {
	items := [[1, 2], [3, 4]]
	result := collapse(items)
	assert result == [1, 2, 3, 4]
}

fn test_arr_keys_values() {
	mut m := {'a': '1', 'b': '2'}
	keys := keys_string(m)
	vals := values_string(m)
	assert keys.len == 2
	assert vals.len == 2
}

fn test_arr_take_empty() {
	items := [1, 2, 3]
	result := take(items, 0)
	assert result == []
}

fn test_arr_skip_all() {
	items := [1, 2, 3]
	result := skip(items, 10)
	assert result == []
}

fn test_arr_take_more_than_len() {
	items := [1, 2]
	result := take(items, 10)
	assert result == [1, 2]
}

// ============================================================
// Str gap tests
// ============================================================

fn test_str_words() {
	result := words('hello world foo bar', 2)
	assert result == 'hello world'
}

fn test_str_words_zero() {
	result := words('hello world', 0)
	assert result == ''
}

fn test_str_words_all() {
	result := words('one two three', 10)
	assert result == 'one two three'
}

fn test_str_random() {
	r1 := random(16)
	assert r1.len == 16

	r2 := random(8)
	assert r2.len == 8
}

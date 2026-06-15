module support

// support_test.v - Tests for the support module

// ============================================================
// String Helper Tests
// ============================================================

fn test_str_slug() {
	assert slug('Hello World') == 'hello-world'
	assert slug('Hello   World') == 'hello-world'
	assert slug('Hello-World') == 'hello-world'
	assert slug('Hello_World') == 'hello-world'
	assert slug('Hello123 World') == 'hello123-world'
}

fn test_str_snake() {
	assert snake('HelloWorld') == 'hello_world'
	assert snake('helloWorld') == 'hello_world'
	assert snake('Hello') == 'hello'
	assert snake('') == ''
}

fn test_str_camel() {
	assert camel('hello_world') == 'helloWorld'
	assert camel('hello-world') == 'helloWorld'
	assert camel('HelloWorld') == 'helloWorld'
}

fn test_str_studly() {
	assert studly('hello_world') == 'HelloWorld'
	assert studly('hello-world') == 'HelloWorld'
	assert studly('hello') == 'Hello'
}

fn test_str_kebab() {
	assert kebab('HelloWorld') == 'hello-world'
	assert kebab('hello_world') == 'hello-world'
}

fn test_str_limit() {
	assert limit('Hello World', 5) == 'He...'
	assert limit('Hello World', 20) == 'Hello World'
}

fn test_str_contains() {
	assert contains('Hello World', 'World') == true
	assert contains('Hello World', 'xyz') == false
}

fn test_str_starts_with() {
	assert starts_with('Hello', 'He') == true
	assert starts_with('Hello', 'he') == false
}

fn test_str_ends_with() {
	assert ends_with('Hello', 'lo') == true
	assert ends_with('Hello', 'La') == false
}

fn test_str_after() {
	assert after('hello world', 'hello ') == 'world'
	assert after('hello', 'xyz') == ''
}

fn test_str_before() {
	assert before('hello world', ' world') == 'hello'
	assert before('hello', 'xyz') == 'hello'
}

fn test_str_between() {
	assert between('hello [world] here', '[', ']') == 'world'
}

fn test_str_finish() {
	assert finish('hello', '/') == 'hello/'
	assert finish('hello/', '/') == 'hello/'
}

fn test_str_start() {
	assert start_str('hello', '/') == '/hello'
	assert start_str('/hello', '/') == '/hello'
}

fn test_str_replace_first() {
	assert replace_first('hello hello', 'hello', 'hi') == 'hi hello'
}

fn test_str_replace_last() {
	assert replace_last('hello hello', 'hello', 'hi') == 'hello hi'
}

fn test_str_lower() {
	assert lower('HELLO') == 'hello'
}

fn test_str_upper() {
	assert upper('hello') == 'HELLO'
}

fn test_str_title() {
	assert title('hello_world') == 'Hello World'
	assert title('hello world') == 'Hello World'
}

fn test_str_repeat() {
	assert repeat_str('abc', 3) == 'abcabcabc'
	assert repeat_str('x', 0) == ''
}

fn test_str_pad_left() {
	result := pad_left_str('42', 5, '0')
	assert result.len == 5
	assert result.starts_with('000')
}

fn test_str_pad_right() {
	result := pad_right_str('42', 5, ' ')
	assert result.len == 5
	assert result.starts_with('42')
}

fn test_str_is_json() {
	assert is_json('{"key":"value"}') == true
	assert is_json('[1,2,3]') == true
	assert is_json('not json') == false
}

fn test_str_mask() {
	assert mask('1234567890', '*', 2, 6) == '12******90'
}

// ============================================================
// Array Helper Tests
// ============================================================

fn test_arr_get_string() {
	mut m := map[string]string{}
	m['name'] = 'Alice'
	assert get_string(m, 'name', '') == 'Alice'
	assert get_string(m, 'missing', 'default') == 'default'
}

fn test_arr_has_string() {
	mut m := map[string]string{}
	m['key'] = 'value'
	assert has_string(m, 'key') == true
	assert has_string(m, 'missing') == false
}

fn test_arr_only_string() {
	mut m := map[string]string{}
	m['a'] = '1'
	m['b'] = '2'
	m['c'] = '3'
	result := only_string(m, ['a', 'c'])
	assert result.len == 2
	assert get_string(result, 'a', '') == '1'
	assert get_string(result, 'c', '') == '3'
}

fn test_arr_except_string() {
	mut m := map[string]string{}
	m['a'] = '1'
	m['b'] = '2'
	result := except_string(m, ['b'])
	assert result.len == 1
	assert get_string(result, 'a', '') == '1'
}

fn test_arr_pluck() {
	maps := [
		{'name': 'Alice', 'age': '30'}
		{'name': 'Bob', 'age': '25'}
	]
	names := pluck(maps, 'name')
	assert names.len == 2
	assert names[0] == 'Alice'
	assert names[1] == 'Bob'
}

fn test_arr_first() {
	items := [1, 2, 3, 4, 5]
	result := first(items, fn (n int) bool { return n > 3 }, 0)
	assert result == 4
}

fn test_arr_chunk() {
	items := [1, 2, 3, 4, 5]
	chunks := chunk(items, 2)
	assert chunks.len == 3
	assert chunks[0] == [1, 2]
	assert chunks[2] == [5]
}

fn test_arr_flatten() {
	items := [[1, 2], [3, 4], [5]]
	flat := flatten(items)
	assert flat.len == 5
	assert flat == [1, 2, 3, 4, 5]
}

fn test_arr_unique_string() {
	items := ['a', 'b', 'a', 'c', 'b']
	result := unique_string(items)
	assert result.len == 3
}

fn test_arr_merge_string() {
	a := {'x': '1'}
	b := {'y': '2'}
	result := merge_string(a, b)
	assert result.len == 2
}

fn test_arr_reverse() {
	items := [1, 2, 3]
	result := reverse(items)
	assert result.len == 3
	assert result[0] == 3
	assert result[2] == 1
}

fn test_arr_take_skip() {
	items := [1, 2, 3, 4, 5]
	first3 := take(items, 3)
	assert first3 == [1, 2, 3]
	rest := skip(items, 3)
	assert rest == [4, 5]
}

// ============================================================
// Collection Tests
// ============================================================

fn test_collect_basic() {
	col := collect([1, 2, 3, 4, 5])
	assert col.count() == 5
	assert col.is_empty() == false
	assert col.first(0) == 1
	assert col.last(0) == 5
}

fn test_collect_map() {
	col := collect([1, 2, 3])
	doubled := col.map(fn (n int) int { return n * 2 })
	items := doubled.all()
	assert items == [2, 4, 6]
}

fn test_collect_filter() {
	col := collect([1, 2, 3, 4, 5])
	even := col.filter(fn (n int) bool { return n % 2 == 0 })
	assert even.all() == [2, 4]
}

fn test_collect_reject() {
	col := collect([1, 2, 3, 4, 5])
	not_even := col.reject(fn (n int) bool { return n % 2 == 0 })
	assert not_even.all() == [1, 3, 5]
}

fn test_collect_reduce() {
	col := collect([1, 2, 3])
	sum := col.reduce(0, fn (acc int, n int) int { return acc + n })
	assert sum == 6
}

fn test_collect_contains() {
	col := collect([1, 2, 3])
	assert col.contains(fn (n int) bool { return n == 2 }) == true
	assert col.contains(fn (n int) bool { return n == 99 }) == false
}

fn test_collect_every_some() {
	col := collect([2, 4, 6])
	assert col.every(fn (n int) bool { return n % 2 == 0 }) == true
	assert col.some(fn (n int) bool { return n > 4 }) == true
}

fn test_collect_take_skip() {
	col := collect([1, 2, 3, 4, 5])
	assert col.take(2).all() == [1, 2]
	assert col.skip(3).all() == [4, 5]
}

fn test_collect_sort_by() {
	col := collect([3, 1, 2])
	sorted := col.sort_by(fn (n int) int { return n })
	assert sorted.all() == [1, 2, 3]
}

fn test_collect_reverse_col() {
	col := collect([1, 2, 3])
	assert col.reverse().all() == [3, 2, 1]
}

fn test_collect_group_by() {
	col := collect(['Alice', 'Bob', 'Ann'])
	groups := col.group_by(fn (s string) string { return s[0].ascii_str() })
	assert groups.len > 0
}

fn test_collect_merge() {
	a := collect([1, 2])
	b := collect([3, 4])
	c := a.merge(b)
	assert c.all() == [1, 2, 3, 4]
}

fn test_collect_is_empty() {
	assert collect([]int{}).is_empty() == true
	assert collect([1]).is_empty() == false
}

fn test_collect_join() {
	col := collect(['a', 'b', 'c'])
	assert col.join(',') == 'a,b,c'
}

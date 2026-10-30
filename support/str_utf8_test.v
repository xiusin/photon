module support

// str_utf8_test.v - 字符语义 vs 字节语义
//
// 这一组函数都在「按字节切」和「按字符切」之间做选择。选错的代价不是
// 抛异常，而是产出一段看起来被处理过、实际已经坏掉的文本：非法 UTF-8
// 进了 HTTP 响应体，或者一个带空格的「标识符」被当成类名写进模板。
import encoding.utf8

fn test_limit_counts_characters_not_bytes() {
	// '中文测试字符串' 是 7 个字符（21 字节）
	assert limit('中文测试字符串', 10) == '中文测试字符串'
	assert limit('中文测试字符串', 6) == '中文测...'
	assert limit('中文测试字符串', 4) == '中...'
	assert utf8.validate_str(limit('中文测试字符串', 4))
	assert utf8.validate_str(limit('中文测试字符串', 3))
	assert limit('hello', 10) == 'hello'
	assert limit('hello', 0) == ''
	assert limit('hello', -5) == ''
}

fn test_mask_offsets_are_characters() {
	// idx / length 是字符偏移：1 开始遮 3 个字符，多字节字符不能被切开
	out := mask('用户名abc', '*', 1, 3)
	assert out == '用***bc'
	assert utf8.validate_str(out)
}

fn test_mask_collapses_multichar_pad() {
	// 参数名是 ch（一个字符），多字符 pad 现在只取首字符，
	// 而不是每个位置都塞进去整个字符串
	assert mask('abcdef', '##', 1, 3) == 'a###ef'
	assert mask('abcdef', '', 1, 3) == 'a***ef'
	assert mask('abcdef', '*', 1, 100) == 'a*****'
	assert mask('abcdef', '*', 10, 3) == 'abcdef'
	assert mask('abcdef', '*', -1, 3) == 'abcdef'
	assert mask('abcdef', '*', 1, 0) == 'abcdef'
}

fn test_kebab_normalises_all_separators() {
	// 空格原本被原样保留，`kebab('Hello World')` → `hello world`
	assert kebab('Hello World') == 'hello-world'
	assert kebab('a b') == 'a-b'
	assert kebab('a  b') == 'a-b'
	assert kebab('a\tb') == 'a-b'
	assert kebab('  leading') == 'leading'
	assert kebab('trailing  ') == 'trailing'
	assert kebab('foo_bar') == 'foo-bar'
	assert kebab('HTTPServer') == 'http-server'
	assert kebab('already-kebab') == 'already-kebab'
}

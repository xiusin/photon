module support

// str_case_test.v — 命名转换与截断的边界行为
//
// 这几条都是「输入退化或含缩写时静默给出错结果」的类型：没有 panic、
// 没有编译错误，只是界面上的标签变成 h_t_t_p_server，或者 limit 直接
// 把内容吃光。

// ── snake / kebab：连续大写（缩写）不应被逐字母拆开 ──

fn test_snake_keeps_acronym_together() {
	assert snake('HTTPServer') == 'http_server'
	assert snake('getHTTPResponseCode') == 'get_http_response_code'
	assert snake('XMLHttpRequest') == 'xml_http_request'
	assert snake('ID') == 'id'
	assert snake('userID') == 'user_id'
}

fn test_snake_numeric_boundary() {
	// 数字开头的新词需要下划线，否则 api_v2 与 api_v_2 无法区分
	assert snake('apiV2Service') == 'api_v2_service'
	assert snake('V2') == 'v2'
}

fn test_kebab_keeps_acronym_together() {
	assert kebab('HTTPServer') == 'http-server'
	assert kebab('XMLHttpRequest') == 'xml-http-request'
}

// ── camel：只有真正的首字母被降级 ──

fn test_camel_leading_separator() {
	assert camel('_user_name') == 'userName'
	assert camel('--user-name') == 'userName'
}

fn test_camel_leaves_inner_case_alone() {
	// 中间的大写本来就是驼峰，不应该被改写
	assert camel('HTTPServer') == 'hTTPServer'
}

// ── limit：n 是结果总长度，且小 n 不能把内容吃光 ──

fn test_limit_small_n_keeps_payload() {
	// 原实现返回 '...'，等于内容全丢
	assert limit('hello', 3) == 'hel'
	assert limit('hello', 1) == 'h'
}

fn test_limit_non_positive() {
	assert limit('hello', 0) == ''
	assert limit('hello', -1) == ''
}

fn test_limit_within_bound() {
	assert limit('hello', 5) == 'hello'
	assert limit('hello', 6) == 'hello'
	assert limit('hello world', 8) == 'hello...'
}

// ── words：任意空白都分词，前导空白不算词 ──

fn test_words_whitespace_variants() {
	assert words('a\tb c', 2) == 'a\tb'
	assert words('a\nb', 1) == 'a'
	assert words('  a b  c d ', 2) == '  a b'
}

fn test_words_boundaries() {
	assert words('', 3) == ''
	assert words('   ', 3) == '   '
	assert words('one', 1) == 'one'
}

// ── title：保持非首字母的原始大小写，分隔符折叠 ──

fn test_title_preserves_inner_case() {
	assert title('HELLO world') == 'HELLO World'
	assert title('apiResponse') == 'ApiResponse'
}

fn test_title_collapses_separators() {
	assert title('hello--world') == 'Hello World'
	assert title('hello___world') == 'Hello World'
	assert title('hello\tworld') == 'Hello World'
}

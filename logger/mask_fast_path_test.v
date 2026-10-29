module logger

// mask_fast_path_test.v — 脱敏的「无关行不付出代价」快路径。
//
// mask_sensitive_data() 以前无条件 to_lower() 整条日志。绝大多数日志行里
// 没有任何敏感 key，这一次全量拷贝纯属白付。快路径必须在**不改变结果**的
// 前提下跳过它：任何含敏感键的行仍然走完整扫描。

fn test_line_without_sensitive_key_is_untouched() {
	lines := [
		'GET /api/users 200 12ms',
		'',
		'Application started on port 8080',
		'tokenizer initialised',
		'user=1&page=2',
	]
	for line in lines {
		assert mask_sensitive_data(line) == line
	}
}

fn test_sensitive_key_is_still_masked() {
	assert mask_sensitive_data('password=a') == 'password=***'
	assert mask_sensitive_data('token:value') == 'token:***'
	assert mask_sensitive_data('api_key=abc&secret=def') == 'api_key=***&secret=***'
	assert mask_sensitive_data('private_key=1&private_key=2') == 'private_key=***&private_key=***'
}

fn test_bearer_token_is_still_masked() {
	assert mask_sensitive_data('Bearer abc def') == 'Bearer *** def'
	assert mask_sensitive_data('x Bearer abc123 y') == 'x Bearer *** y'
	// 键值路径先命中 `Authorization:`，这时必须把整个凭据一起遮掉，
	// 只遮 scheme 词等于没遮。
	assert mask_sensitive_data('Authorization: Bearer abc123') == 'Authorization: ***'
}

fn test_bearer_masking_keeps_surrounding_text() {
	// 一条日志里多个 bearer、且首尾都有普通文本：重建时不能吃掉任何一段
	assert mask_sensitive_data('a Bearer t1 b Bearer t2 c') == 'a Bearer *** b Bearer *** c'
}

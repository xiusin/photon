module logger

// 脱敏是「看起来做了、实际没做」这类缺陷的高发区：输出里出现了 `***`，
// 人就不再细看，而真正的凭据可能就贴在它旁边。下面每一条都对应一种
// 「日志里明明白白写着密码」的形态。

fn test_json_value_is_redacted() {
	// 键值扫描过去把 `"` 当值终止符，于是 JSON 里的值一直是空 span ——
	// 「没有东西要遮」，整条密码原样留在日志里。
	assert mask_sensitive_data('{"password":"s3cret"}') == '{"password":"***"}'
	assert mask_sensitive_data('{"user":"bob","password":"p@ss word"}') == '{"user":"bob","password":"***"}'
	assert mask_sensitive_data('{"token":"abcdefgh"}') == '{"token":"***"}'
}

fn test_quoted_value_is_redacted() {
	assert mask_sensitive_data("password='s3cret'") == "password='***'"
	assert mask_sensitive_data('password="my secret"') == 'password="***"'
}

fn test_header_style_keys_are_recognised() {
	// HTTP header 写的是 X-Api-Key，下划线形式永远匹配不到它 ——
	// 而 header 恰恰是 API Key 最常出现的形态。
	assert mask_sensitive_data('X-Api-Key: ABC123') == 'X-Api-Key: ***'
	assert mask_sensitive_data('X-Api-Key=ABC123') == 'X-Api-Key=***'
	assert mask_sensitive_data('api-key: ABC123') == 'api-key: ***'
	assert mask_sensitive_data('api_key: ABC123') == 'api_key: ***'
}

fn test_authorization_bearer_does_not_leak_the_token() {
	// 过去这里输出 `Authorization: *** abc123` —— scheme 词被遮了，
	// 凭据一字未动，靠 `***` 让人以为已经处理过。
	assert mask_sensitive_data('Authorization: Bearer abc123') == 'Authorization: ***'
	assert mask_sensitive_data('authorization:bearer abc123') == 'authorization:***'
}

fn test_unrelated_dashed_words_are_left_alone() {
	// 放宽 key 之后不能把普通连字符单词误伤
	assert mask_sensitive_data('api-gateway: prod') == 'api-gateway: prod'
	assert mask_sensitive_data('no secrets here') == 'no secrets here'
	assert mask_sensitive_data('api.key: ABC') == 'api.key: ABC'
}

fn test_empty_values_are_left_alone() {
	assert mask_sensitive_data('password=') == 'password='
	assert mask_sensitive_data('token:  ') == 'token:  '
}

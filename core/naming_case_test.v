module core

// naming_case_test.v — 名字在「字段名风格」与「类型名风格」之间的转换。
//
// 这个文件的存在理由：框架里曾经同时用到 capitalize_first 和
// 「把 snake_case 转成 PascalCase」，而前者被当成了后者。两者只差
// 一个下划线，但匹配结果差了整整一类 bean。
//
// capitalize_first('proto_bean') == 'Proto_bean'  ≠  'ProtoBean'
//
// 这不是风格偏好问题 —— 后者是容器里真实存在的键，前者永远不是。

fn test_snake_to_pascal_case() {
	assert snake_to_pascal_case('proto_bean') == 'ProtoBean'
	assert snake_to_pascal_case('user_service') == 'UserService'
	assert snake_to_pascal_case('repo') == 'Repo'
	assert snake_to_pascal_case('a_b_c') == 'ABC'
	assert snake_to_pascal_case('') == ''
	// 连续下划线与首尾下划线不应产生空片段
	assert snake_to_pascal_case('user__service') == 'UserService'
	assert snake_to_pascal_case('_repo') == 'Repo'
	assert snake_to_pascal_case('repo_') == 'Repo'
}

// test_capitalize_first_is_not_pascal_case 钉住两者的区别。
//
// 谁要是想用 capitalize_first 做类型名推导，这条会立刻拦下来。
fn test_capitalize_first_is_not_pascal_case() {
	assert capitalize_first('proto_bean') == 'Proto_bean'
	assert capitalize_first('proto_bean') != snake_to_pascal_case('proto_bean')
	assert capitalize_first('repo') == snake_to_pascal_case('repo')
}

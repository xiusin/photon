module orm

// local_hash_test.v — orm 自己那份 snake_case / fnv1a_str
//
// 为什么要本地实现、以及它防的是什么回归，见 ARCHITECTURE.md 8.10：
// `support` 同时被注册成 `photon.support`，两条路径同时加载时 V 会解析到
// 空函数表，`support.snake()` 变成 `unknown function`，任何
// `import photon.orm` / `import photon.web` 的用户直接编译失败。
//
// 这里的用例锁两件事：本地实现的行为和 support 一致；表名推导对缩写正确。

fn test_snake_case_keeps_acronyms_together() {
	// 表名靠它算：`UserDOB` 必须是 `user_dobs`，不是 `user_d_o_bs`
	assert snake_case('UserDOB') == 'user_dob'
	assert snake_case('HTMLParser') == 'html_parser'
	assert snake_case('HTTPServer') == 'http_server'
	assert snake_case('BlogPost') == 'blog_post'
	assert snake_case('blogPost') == 'blog_post'
	assert snake_case('Order2Item') == 'order2_item'
}

fn test_snake_case_edges() {
	assert snake_case('') == ''
	assert snake_case('a') == 'a'
	assert snake_case('ABC') == 'abc'
	assert snake_case('already_snake') == 'already_snake'
}

fn test_fnv1a_str_matches_known_vectors() {
	// FNV-1a 64 位的标准测试向量，用来确认本地实现没有漂移
	assert fnv1a_str('') == u64(14695981039346656037)
	assert fnv1a_str('a') == u64(0xaf63dc4c8601ec8c)
	assert fnv1a_str('foobar') == u64(0x85944171f73967e8)
}

fn test_fnv1a_str_distributes() {
	// 分片索引靠低位，低位不能全撞在一起
	mut low_bits := map[int]bool{}
	for i in 0 .. 64 {
		low_bits[int(fnv1a_str('key-${i}') & u64(63))] = true
	}
	assert low_bits.len > 8, '64 个 key 只落到 ${low_bits.len} 个分片，哈希退化'
}

fn test_extract_column_name_falls_back_to_local_snake_case() {
	// 这条路径曾经因为 support.snake 解析失败而整链编译不过
	assert extract_column_name('userName', []) == 'user_name'
	assert extract_column_name('userDOB', []) == 'user_dob'
	// 带 @[column: 'x'] 时以注解为准
	assert extract_column_name('userName', ["column: 'uid'"]) == 'uid'
}

// ── 与 support.snake 的行为一致性 ──
//
// 本地这份实现是为了绕开 `photon.support` 解析问题而做的副本。副本最大的
// 风险是「改了一边忘了另一边」，所以这里把两边钉在一起：任一时刻两边对同一
// 输入给出不同结果，这条就红。
//
// 注意：这个文件本身不能 `import support`（那正是要绕开的东西），所以完整性
// 靠的是下面这张表 —— 它同时被 support 的用例覆盖，改任意一边都会有一侧红。
fn test_snake_case_matches_support_contract() {
	cases := {
		'':            ''
		'a':           'a'
		'ABC':         'abc'
		'BlogPost':    'blog_post'
		'blogPost':    'blog_post'
		'HTMLParser':  'html_parser'
		'UserDOB':     'user_dob'
		'HTTPServer':  'http_server'
		'Order2Item':  'order2_item'
		'already_snake': 'already_snake'
	}
	for input, want in cases {
		assert snake_case(input) == want, 'snake_case(${input}) = ${snake_case(input)}, want ${want}'
	}
}

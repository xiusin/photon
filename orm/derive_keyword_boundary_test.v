module orm

import strings

// derive_keyword_boundary_test.v — 派生查询关键字的边界与「认不出就说」
//
// 这组用例盯的不是「解析成功」，是**解析失败长什么样**。
//
// 上一版 match_keyword() 只认 11 个关键字，其余的一律被当成属性名的一部分：
//
//   findByAgeBetween      → WHERE age_between = ?
//   findByActiveTrue      → WHERE active_true = ?
//   findByNameIgnoreCase  → WHERE name_ignore_case = ?
//
// 三条都不报错。它们把「我写了一个关键字」翻译成「我要查一列叫
// age_between 的字段」——到了驱动层变成 `no such column: age_between`，
// 和「方法名打错了一个字母」是同一句话。错误发生在方法签名与数据库之间
// 那段谁也看不见的地方。
//
// 所以这里有两类断言：
//   1. 表里有的关键字，必须改成对的 SQL，而且 `?` 的个数必须和
//      to_where_param_count() 说的一致；
//   2. 表里没有的关键字，必须报错并**说出是哪一个**，不许静默拼出一个列名。

// ── 一、曾经被当成属性名的关键字 ──

fn test_between_maps_to_two_placeholders() {
	parts := parse_method_name('findByAgeBetween') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == 'BETWEEN'
	assert parts.to_where_cond() == 'age BETWEEN ? AND ?'
	// BETWEEN 吃两个值。少算一个，第二个值就会被绑到别的条件上。
	assert parts.to_where_param_count() == 2
}

fn test_not_between() {
	parts := parse_method_name('findByNameNotBetween') or { panic(err) }
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'NOT BETWEEN'
	assert parts.to_where_cond() == 'name NOT BETWEEN ? AND ?'
	assert parts.to_where_param_count() == 2
}

fn test_true_false_consume_no_placeholders() {
	t := parse_method_name('findByActiveTrue') or { panic(err) }
	assert t.conditions[0].property == 'active'
	assert t.conditions[0].operator == 'TRUE'
	assert t.to_where_cond() == 'active = 1'
	// 布尔字面量不需要绑定值。曾经的 `active_true = ?` 要多传一个参数，
	// 于是紧随其后的条件整体错位一格。
	assert t.to_where_param_count() == 0

	f := parse_method_name('findByActiveFalse') or { panic(err) }
	assert f.conditions[0].operator == 'FALSE'
	assert f.to_where_cond() == 'active = 0'
	assert f.to_where_param_count() == 0
}

fn test_ignore_case_keeps_equality() {
	parts := parse_method_name('findByNameIgnoreCase') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'name'
	// IgnoreCase 不改变 SQL 形状，只是告诉调用方要做大小写折叠。
	assert parts.conditions[0].operator == '='
	assert parts.to_where_cond() == 'name = ?'
	assert parts.to_where_param_count() == 1
}

fn test_not_like() {
	parts := parse_method_name('findByNameNotLike') or { panic(err) }
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'NOT LIKE'
	assert parts.to_where_cond() == 'name NOT LIKE ?'
}

fn test_not_containing_keeps_property_clean() {
	parts := parse_method_name('findByNameNotContaining') or { panic(err) }
	assert parts.conditions.len == 1
	// 修之前这里是 `name_not LIKE ...` —— 属性名被吃掉了一段。
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'NOT_LIKE_CONTAINING'
	assert parts.to_where_cond() == "name NOT LIKE '%' || ? || '%'"
}

fn test_not_null_short_form() {
	parts := parse_method_name('findByAgeNotNull') or { panic(err) }
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == 'IS NOT NULL'
	assert parts.to_where_cond() == 'age IS NOT NULL'
	assert parts.to_where_param_count() == 0
}

// ── 二、认不出来的关键字必须报错，并点名 ──

fn assert_rejected(method string, keyword string) {
	mut msg := ''
	mut parsed := true
	if _ := parse_method_name(method) {
		parsed = true
	} else {
		parsed = false
		msg = err.msg()
	}
	assert !parsed, '${method} 应该报错，而不是解析成 ${keyword} 这一列'
	// 报错必须点名到「哪个词」，否则用户只会看到「方法名有问题」。
	assert msg.contains(keyword), '报错里应点名 ${keyword}，实为: ${msg}'
	// 两种拒绝措辞：「不认识的关键字」和「关键字后面跟着一串读不懂的」。
	// 两条都算合格，但必须明确说了是哪种。
	assert msg.contains('unsupported keyword') || msg.contains('unexpected'), msg
}

fn test_suffix_not_is_rejected_with_name() {
	// `Not` 单独作后缀在 Spring Data 里是「不等于」，语义上要求一个操作数，
	// 而 `findByAgeNot` 无法表达「age != ?」还是「NOT (age)」。
	// 不实现可以，但要说出来，不能拼成 age_not 这一列。
	assert_rejected('findByAgeNot', 'Not')
}

fn test_like_keyword_takes_a_pattern() {
	// `Like` 在 Spring Data 里是「模式由调用方给」，与 Containing 的
	// 「自动加 %」不同。要区分开，否则 `findByNameLike('a%')` 会变成
	// `LIKE '%a%%%'`。
	parts := parse_method_name('findByNameLike') or { panic(err) }
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'LIKE'
	assert parts.to_where_cond() == 'name LIKE ?'
	assert parts.to_where_param_count() == 1
}

fn test_unknown_suffix_is_rejected_with_name() {
	assert_rejected('findByAgeGreaterThanX', 'X')
}

fn test_multi_word_property_still_allowed() {
	// 报错不能开得太宽：`CreatedAt` 是两个普通单词，不是关键字。
	parts := parse_method_name('findByCreatedAtGreaterThan') or { panic(err) }
	assert parts.conditions[0].property == 'created_at'
	assert parts.conditions[0].operator == '>'
	parts2 := parse_method_name('findByFirstNameContaining') or { panic(err) }
	assert parts2.conditions[0].property == 'first_name'
}

// ── 三、`?` 的个数必须和 to_where_param_count() 一致 ──
//
// 这一条是整组的核心。占位符和参数数量对不上时，SQL 本身合法、
// 参数也不用报错 —— 只是从某一位开始全部串位。

fn assert_params_match_sql(method string) {
	parts := parse_method_name(method) or {
		assert false, '${method} 解析失败: ${err}'
		return
	}
	q := parts.to_where_cond()
	qa := parts.to_where_cond_with_arrays({})
	expected := parts.to_where_param_count()
	assert q.count('?') == expected, '${method}: to_where_cond 有 ${q.count('?')} 个 ? 但声称 ${expected} 个'
	assert qa.count('?') == expected, '${method}: to_where_cond_with_arrays 有 ${qa.count('?')} 个 ? 但声称 ${expected} 个'
}

fn test_placeholder_count_matches_param_count() {
	methods := [
		'findByAgeBetween',
		'findByActiveTrue',
		'findByActiveFalse',
		'findByNameIgnoreCase',
		'findByNameNotLike',
		'findByNameNotBetween',
		'findByAgeNotNull',
		'findByAgeBetweenAndNameContaining',
		'findByDeletedAtIsNull',
		'findByName',
		'findByNameAndAge',
		'findByAgeGreaterThanOrEqual',
		'findByIdIn',
		'findByNameStartingWith',
	]
	for m in methods {
		assert_params_match_sql(m)
	}
}

// ── 四、关键字表本身的结构约束 ──

fn test_keyword_table_order_is_longest_first() {
	// 贪婪匹配完全依赖「长词在前」。有人往表里插一行顺序错了，
	// 所有行为用例都可能碰巧还是绿的（只要没人用那个前缀）。
	//
	// 只比词长不够：`GreaterThan`(2) 与 `LongerThan`(2) 同长，可
	// `GreaterThan` 是 `GreaterThanOrEqual`(4) 的前缀 —— 把它挪到前面，
	// 后者就永远匹配不到。所以这里比对的是「行序 == 按词长降序稳定排序后的行序」。
	table := keyword_table()
	mut sorted_names := []string{cap: table.len}
	mut by_len := []int{cap: table.len}
	for _, spec in table {
		by_len << spec.tokens.len
	}
	// 稳定的降序索引（词长相同时保持原序）。
	mut taken := []bool{len: table.len, init: false}
	for _ in 0 .. table.len {
		mut best := -1
		for idx, n in by_len {
			if taken[idx] {
				continue
			}
			if best == -1 || n > by_len[best] {
				best = idx
			}
		}
		taken[best] = true
		sorted_names << table[best].name
	}
	for i, spec in table {
		assert spec.name == sorted_names[i], 'keyword_table() 第 ${i} 行应是 ${sorted_names[i]}（按词长降序），实为 ${spec.name}：更短的关键字会抢走更长的前缀'
	}
}

fn test_keyword_table_covers_spring_data_vocabulary() {
	// 少一个关键字不是「功能少一点」，是「静默拼出不存在的列」。
	required := [
		'Between', 'LessThan', 'GreaterThan', 'LessThanOrEqual', 'GreaterThanOrEqual',
		'IsNull', 'IsNotNull', 'NotNull', 'In', 'NotIn', 'Containing', 'NotContaining',
		'StartingWith', 'EndingWith', 'Like', 'NotLike', 'True', 'False', 'IgnoreCase',
	]
	mut names := []string{cap: keyword_table().len}
	for spec in keyword_table() {
		names << spec.name
	}
	for r in required {
		assert r in names, '关键字表里缺少 ${r}'
	}
}

fn test_keyword_table_has_no_duplicate_name() {
	// `NotNull` 曾经被我顺手加进 1-token 区又被挪走。表里两行同名时，
	// 先出现的那行永远赢，另一行变成永远读不到的死数据。
	mut seen := map[string]bool{}
	for spec in keyword_table() {
		assert !seen[spec.name], '关键字表里 ${spec.name} 出现了两次'
		seen[spec.name] = true
	}
}

fn test_operator_param_count_is_consistent_with_sql() {
	// operator_param_count() 和 write_condition() 是同一个事实的两个读者。
	// 两边各写一遍就会漂，所以这条直接拿表里每个操作符渲染一次对数。
	ops := {
		'=':                 1
		'>':                 1
		'IS NULL':           0
		'IS NOT NULL':       0
		'TRUE':              0
		'FALSE':             0
		'BETWEEN':           2
		'NOT BETWEEN':       2
		'LIKE_CONTAINING':   1
		'NOT_LIKE_CONTAINING': 1
		'IN':                -1
		'NOT IN':            -1
	}
	for op, want in ops {
		assert operator_param_count(op) == want, '${op} 的参数个数应为 ${want}，实为 ${operator_param_count(op)}'
		// 渲染出来的 `?` 个数（IN 按单占位符渲染）必须能对上。
		mut sb := strings.new_builder(64)
		write_condition(mut sb, QueryCondition{
			property: 'x'
			operator: op
		}, map[string]int{})
		rendered := sb.str().count('?')
		expect_render := if want == -1 { 1 } else { want }
		assert rendered == expect_render, '${op} 渲染出 ${rendered} 个 ?，应为 ${expect_render}'
	}
}

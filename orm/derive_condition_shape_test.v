module orm

// derive_condition_shape_test.v — WHERE 那半句的「形状」边界
//
// 前三轮把 WHERE 侧的两件事收干净了：关键字认不认识（keyword_table）、
// 参数个数与 `?` 同不同源（operator_param_count）、ORDER BY 是不是按词判定。
// 但还有一层从没被碰过 —— **条件的形状**。
//
// 拆 token 的那个循环（derive.v:119）对 `And` / `Or` 的处理是：
//
//   if tokens[i] == 'And' { logic = 'AND'; i++; continue }
//
// 这是一条「跳过」分支，不是「消费一个分隔符」的分支。两者的区别在于：
// 它不知道自己前面有没有条件、后面会不会有条件，也不需要知道 —— 因为它
// 从不报错。于是下面这些都解析成功：
//
//   findByAndAge            → WHERE age = ?
//   findByAndAndName        → WHERE name = ?
//   findByAnd               → 无 WHERE（一个空方法名）
//   findByNameAndAndAge     → WHERE name = ? AND age = ?   （两个条件，三个词）
//   findTop10DistinctByName → DISTINCT 被当成属性的一部分，静默丢掉
//   findByDistinctName      → WHERE distinct_name = ?
//
// 前三条里，调用方写的词被吃掉了却没人说话 —— 和 `findByAgeBetween` 是
// 同一个形状的失败，只是这次吃掉的不是列名，是一个分隔符。
//
// `findByAnd` 尤其值得看一眼：解析出零个条件，`to_where_cond()` 返回 `''`，
// 而调用方（orm.v / repository.v 文档里的用法）写的是
//
//   if parts.to_where_cond().len > 0 { qb.where(...) }
//
// 于是没有任何 WHERE —— 「按一个不存在的条件查」变成了「查全表」。
// 反过来若不加这个判断直接 `qb.where('')`，QueryBuilder 会无条件写下
// `" WHERE "` 前缀，得到 `SELECT * FROM users WHERE  AND age = ?`。

// ── 一、分隔符必须真的在分隔东西 ──

fn test_leading_separator_is_refused() {
	// `findByAndAge`：`And` 前面没有条件。
	if _ := parse_method_name('findByAndAge') {
		assert false, 'findByAndAge 应当被拒绝：开头的 And 前面没有条件'
	}
	if _ := parse_method_name('findByOrAge') {
		assert false, 'findByOrAge 应当被拒绝：开头的 Or 前面没有条件'
	}
}

fn test_trailing_separator_is_refused() {
	// `findByNameAnd`：`And` 后面没有条件。静默丢掉等于「按一半条件查」。
	if _ := parse_method_name('findByNameAnd') {
		assert false, 'findByNameAnd 应当被拒绝：结尾的 And 后面没有条件'
	}
	if _ := parse_method_name('findByNameOr') {
		assert false, 'findByNameOr 应当被拒绝：结尾的 Or 后面没有条件'
	}
}

fn test_doubled_separator_is_refused() {
	// `findByNameAndAndAge`：两个分隔符并排，中间那条条件不存在。
	if _ := parse_method_name('findByNameAndAndAge') {
		assert false, 'findByNameAndAndAge 应当被拒绝：两个 And 之间没有条件'
	}
	if _ := parse_method_name('findByNameAndOrAge') {
		assert false, 'findByNameAndOrAge 应当被拒绝：And 与 Or 紧挨着'
	}
}

fn test_empty_condition_body_is_refused() {
	// `findBy` 没有任何条件，`countBy` 同理。零条件是「查全表」，
	// 而一个派生查询方法名的存在本身就声称有过滤 —— 报错比默认全表安全。
	if _ := parse_method_name('findBy') {
		assert false, 'findBy 应当被拒绝：没有条件'
	}
	if _ := parse_method_name('countBy') {
		assert false, 'countBy 应当被拒绝：没有条件'
	}
	if _ := parse_method_name('deleteBy') {
		assert false, 'deleteBy 应当被拒绝：没有条件'
	}
}

// ── 二、报错要指名是哪一个词 ──

fn test_separator_error_names_the_separator() {
	// 报错必须说清是哪个 `And` / `Or`、以及它缺了哪一侧，
	// 否则「派生查询不合法」和「方法名打错」还是分不开。
	msg := err_msg('findByNameAnd') or { '' }
	assert msg.contains('And'), '报错应当点名 And：${msg}'
	msg2 := err_msg('findByAndAge') or { '' }
	assert msg2.contains('And'), '报错应当点名 And：${msg2}'
}

// err_msg 跑一次解析并返回错误文本，解析成功时返回 none。
fn err_msg(method string) ?string {
	if _ := parse_method_name(method) {
		return none
	} else {
		return err.msg()
	}
}

// ── 三、本来就是对的写法不能被误伤 ──

fn test_legal_separator_shapes_still_parse() {
	// 这四条是分隔符的正常用法：两侧都有条件。
	cases := {
		'findByNameAndAge':     ['name', 'age']
		'findByNameOrAge':      ['name', 'age']
		'findByNameAndAgeOrId': ['name', 'age', 'id']
	}
	for method, want in cases {
		parts := parse_method_name(method) or { panic('${method} 应当解析成功，却报错：${err}') }
		got := parts.conditions.map(it.property)
		assert got == want, '${method} 解析出的属性是 ${got}，期望 ${want}'
	}
	// `And` / `Or` 的第二种用法：`GreaterThanOrEqual` 里的 `Or` 属于关键字，
	// 不是条件分隔符。这条是防止上面的检查把关键字内部也当成空条件。
	between := parse_method_name('findByAgeGreaterThanOrEqualAndName') or {
		panic('GreaterThanOrEqual 里的 Or 被误判成条件分隔符：${err}')
	}
	assert between.conditions.len == 2
	assert between.conditions[0].operator == '>='
	assert between.conditions[1].property == 'name'
}

// ── 四、Distinct 的位置 ──

fn test_distinct_only_right_after_operation() {
	// 文档（docs/ORM_使用指南.md §9.1）写的是 `findDistinctByName`，
	// 解析器也只认这个位置。`findTop10DistinctByName` 是 Spring Data
	// 里的合法写法（Distinct 在 TopN 之后），旧代码把它当成普通属性词，
	// 于是 distinct=false、条件变成 `top10_distinct_by_name`？—— 不是，
	// 因为 Top 已经先吃掉 10，剩下的 `DistinctByName` 里 `Distinct` 落进
	// 属性词被 camel_to_snake 化成 `distinct_by_name` 的一部分。
	//
	// 无论细节如何，结果是 Distinct 静默消失。这里钉住两种可能：
	// 要么认它，要么拒绝它 —— 不许当没看见。
	r := parse_method_name('findTop10DistinctByName')
	if r != none {
		parts := r or { panic(err) }
		assert parts.distinct, 'findTop10DistinctByName 解析成功却不带 distinct 标记'
	} else {
		assert err_msg('findTop10DistinctByName') or { '' } != ''
	}
}

fn test_distinct_after_by_is_a_property() {
	// `findByDistinctName` 里的 `Distinct` 出现在 `By` 之后，
	// 那个位置只可能是属性。它必须变成一个属性名，不能改 distinct 标志。
	parts := parse_method_name('findByDistinctName') or { panic(err) }
	assert !parts.distinct
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'distinct_name'
}

// ── 五、TopN / FirstN 与属性名的分界 ──

fn test_top_n_and_first_n() {
	// `Top` / `First` 后跟数字是占位符（LIMIT N）；单独出现是 LIMIT 1。
	cases := {
		'findTop10ByName':  10
		'findFirst3ByName': 3
		'findTopByName':    1
		'findFirstByName':  1
	}
	for method, want in cases {
		parts := parse_method_name(method) or { panic('${method} 应当解析成功：${err}') }
		assert parts.limit_val == want, '${method} 的 limit 是 ${parts.limit_val}，期望 ${want}'
		assert parts.conditions.len == 1
		assert parts.conditions[0].property == 'name'
	}
}

fn test_top_prefixed_property_is_not_a_placeholder() {
	// `TopScore` / `TopRated` 是普通属性，不是「LIMIT 但没有数字」。
	// 旧实现只判 `remaining.len > 3`，把 `TopScore` 切出一个 `TopS`，
	// 最后 limit 是 0（`int()` 失败），属性被吃掉。
	r := parse_method_name('findTopScoreByName')
	if r != none {
		parts := r or { panic(err) }
		assert parts.limit_val == 0
		assert parts.conditions.len == 1
		assert parts.conditions[0].property == 'top_score_by_name' || parts.conditions[0].property == 'top_score'
	}
	r2 := parse_method_name('findTopRated') or { QueryParts{} }
	_ = r2
}

// ── 六、Distinct 的位置（也是「关键字不能被当属性吃掉」） ──

fn test_distinct_after_placeholder() {
	// Spring Data 把 Distinct 写在占位符之后：`findTop10DistinctBy…`。
	// 旧代码只在最开头找 Distinct，这一个写法里它被并进属性名，静默消失。
	parts := parse_method_name('findTop10DistinctByName') or { panic(err) }
	assert parts.distinct, 'findTop10DistinctByName 丢了 distinct 标记'
	assert parts.limit_val == 10
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'name'

	parts2 := parse_method_name('findTopDistinctByName') or { panic(err) }
	assert parts2.distinct
	assert parts2.limit_val == 1
	assert parts2.conditions[0].property == 'name'
}

fn test_doubled_distinct_is_refused() {
	// 两个 Distinct 是打字错误，不是「更 distinct」。
	if _ := parse_method_name('findDistinctDistinctByName') {
		assert false, '重复的 Distinct 应当被拒绝'
	}
}

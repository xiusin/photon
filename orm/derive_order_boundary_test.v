module orm

// derive_order_boundary_test.v — `ORDER BY` 那半句的解析边界
//
// 条件那半句（`WHERE`）已经收进一张 keyword_table()，认不出就报错。
// `ORDER BY` 这半句还留在 parse_method_name() 里的另一段代码：
//
//   order_part.split('And')
//   然后 prop.to_lower().ends_with('desc') / ('asc')
//
// 两个字段、两次判断、一个 `if/else if`。它比条件那半句更短，也更容易
// 被漏掉 —— 因为它「看起来只是排个序」，出了错最坏也就是顺序不对。
//
// 实测的是四种出错姿势，全都是「解析成功」，没有一种会报错：
//
//   findByOrderByAgeDescOrName   → ORDER BY age_desc_or_name ASC
//   findByOrderByAgeDescName     → ORDER BY age_desc_name ASC
//   findByOrderByAndName         → ORDER BY "" ASC, name ASC
//   findByOrderByAgeDescAnd      → ORDER BY age DESC, "" ASC
//
// 第一条最贵：`Or` 在条件那半句是逻辑连接词，在这里不会被识别，于是整个
// `AgeDescOrName` 被 snake_case 成**一个列名**。第四、五行的 `''` 会一路
// 走到 `qb.order('', .asc)` —— 排序静默失效，返回顺序变成「数据库愿意给的
// 那个顺序」，而调用方以为自己指定了。
//
// 所以这里的断言分成四组：见过的写法必须解析对；写错的必须报错并点名；
// 每个方向关键字只认一份拼写；不存在的 ORDER BY 子句不能凭空长出来。

fn order_of(method string) []string {
	parts := parse_method_name(method) or {
		assert false, '${method} 解析失败: ${err}'
		return []
	}
	mut out := []string{cap: parts.order_by.len}
	for p in parts.order_by {
		out << '${p.property}/${p.direction}'
	}
	return out
}

// ── 一、本来就该解析对的写法 ──

fn test_order_by_single_field() {
	assert order_of('findByOrderByAgeDesc') == ['age/DESC']
	assert order_of('findByOrderByAgeAsc') == ['age/ASC']
	// 不带方向 = ASC（Spring Data 的约定，方向后缀可省）。
	assert order_of('findByOrderByAge') == ['age/ASC']
}

fn test_order_by_multiple_fields() {
	assert order_of('findByOrderByAgeDescAndNameAsc') == ['age/DESC', 'name/ASC']
	assert order_of('findByOrderByAgeAscAndNameDesc') == ['age/ASC', 'name/DESC']
	// 三个字段：`split('And')` 的那份实现也能过，留着防止新实现只处理两段。
	assert order_of('findByOrderByAgeDescAndNameAscAndIdDesc') == ['age/DESC', 'name/ASC', 'id/DESC']
}

fn test_order_by_with_conditions() {
	// 条件与排序共存：`OrderBy` 之前的部分归条件，之后归排序。
	parts := parse_method_name('findByNameLikeOrderByAgeDesc') or { panic(err) }
	assert parts.to_where_cond() == 'name LIKE ?'
	assert parts.order_by[0].property == 'age'
	assert parts.order_by[0].direction == 'DESC'
}

fn test_order_by_multi_word_property() {
	assert order_of('findByOrderByCreatedAtDesc') == ['created_at/DESC']
	assert order_of('findByOrderByLastNameDesc') == ['last_name/DESC']
	assert order_of('findByOrderByUserDOBDesc') == ['user_dob/DESC']
}

// ── 二、方向后缀只认完整单词 ──
//
// 方向判断用的是「属性名以 Desc 结尾」。`Desc` 是个普通词，可以是别的词的
// 前缀（`Descending`）或结尾（`UserDesc` 之类）。这里钉住的是：
// **方向只能来自出现在属性名之后的、完整的 `Asc` / `Desc` 词**。

fn test_direction_word_is_a_camel_word() {
	// `Desc` 必须是 camel 切分出来的一个完整词。`Descending` 切出来是
	// 一个词，不是 `Desc` + `ending` —— 老实现用 `ends_with('desc')` 判方向，
	// 对 `Descending` 不成立（它不以 desc 结尾），于是静默 ASC；
	// 对 `UserDesc` 成立，于是把属性剥成 `user`。两个都错在同一个地方：
	// 拿「字符串结尾」当「词」。
	assert order_of('findByOrderByUserDesc') == ['user/DESC']
	assert order_of('findByOrderByAgeDesc') == ['age/DESC']
	// 切分成一个词的 `Descending` 不是方向，整串是属性名。
	assert order_of('findByOrderByDescending') == ['descending/ASC']
}

// ── 三、写错了要报错，而不是拼出一个列名 ──

fn test_order_by_rejects_condition_keyword() {
	// `Or`/`And` 在 `ORDER BY` 里是分隔符，但 `AgeDescOrName` 这种
	// 「忘了写 And」的写法会把两个字段吞成一个列名。
	// `Or` 在这里能拆开，`Name` 却是一个没有方向的字段 —— 说不清是有意
	// 写成两列还是一列，报错比猜安全。
	assert_order_rejected('findByOrderByAgeDescOrName', 'Or')
}

fn test_order_by_rejects_trailing_junk() {
	// `ageDescName`：方向消费完之后还跟着一个 token。条件那半句里
	// 同样的位置会报 `unexpected "X" after keyword "GreaterThan"`。
	assert_order_rejected('findByOrderByAgeDescName', 'Name')
}

fn test_order_by_rejects_empty_element() {
	// 空元素会一路变成 `ORDER BY "" ASC`。
	assert_order_rejected('findByOrderBy', 'OrderBy')
	assert_order_rejected('findByOrderByAndName', 'OrderBy')
	assert_order_rejected('findByOrderByAgeDescAnd', 'OrderBy')
	assert_order_rejected('findByOrderByAgeDescAndOrderBy', 'OrderBy')
}

// ── 四、ORDER BY 之后的一切都是排序字段 ──

fn test_order_by_consumes_the_whole_tail() {
	// ORDER BY 是最后一个子句，它后面只可能是排序字段。`And` 在这里是
	// 排序分隔符，不是条件分隔符 —— 所以 `...DescAndUserID` 只能读成
	// 「第二个排序字段 user_id」，不能读成「再按 user_id 过滤」。
	//
	// 老实现按子串截断，于是同一句话变成：条件里多出 `user_dob`、
	// 排序里只剩 `user_id` 一个字段、`created_at DESC` 整个消失。
	// 三个子句同时错位，没有一个报错。
	parts := parse_method_name('findByUserDOBOrderByCreatedAtDescAndUserID') or { panic(err) }
	// `UserDOB` 是唯一一条条件（`user_dob = ?`），不能被拆进排序里；
	// `CreatedAtDesc` 与 `UserID` 是两个排序字段。
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'user_dob'
	assert parts.order_by.len == 2
	assert parts.order_by[0].property == 'created_at'
	assert parts.order_by[0].direction == 'DESC'
	assert parts.order_by[1].property == 'user_id'
	assert parts.order_by[1].direction == 'ASC'
}

fn test_order_by_cannot_appear_twice() {
	assert_order_rejected('findByOrderByAgeDescAndOrderByNameAsc', 'OrderBy')
}

// ── 五、尾部读不成排序子句时要说出来 ──

fn test_order_by_tail_must_be_a_sort_clause() {
	// `OrderBy` 之后只能是 `<属性> [Asc|Desc]` 用 `And` 连接。出现别的东西
	// 时（关键词、大小写方向写错），不能猜 —— 一猜就是把属性名拼成一列。
	assert_order_rejected('findByOrderByAgeBetween', 'Between')
	assert_order_rejected('findByOrderByAgeDescContaining', 'Containing')
	assert_order_rejected('findByOrderByGreaterThan', 'GreaterThan')
}

fn test_direction_cannot_open_a_field() {
	// `OrderByDesc` 没有属性。老实现剥掉 `Desc` 得到空列名，一路传成
	// `ORDER BY "" DESC`。
	assert_order_rejected('findByOrderByDesc', 'Desc')
	assert_order_rejected('findByOrderByAgeDescAndDesc', 'Desc')
}

// ── 六、条件里不许凭空长出一个 OrderBy 子句 ──

fn test_condition_value_named_order_by_is_not_a_clause() {
	// `OrderBy` 是字符串搜索出来的，出现在 `And`/`Or` 之后、作为属性名的
	// 一部分时，会把条件整个截断：`name = ?` 之后的 `And` 后面空无一物。
	// 这跟上一轮 `findByAgeGreaterThanX` 多出一条 WHERE 是同一类：
	// 一个不属于这里的词被当成了子句边界。
	assert_order_rejected('findByNameAndOrderByAge', 'OrderBy')
}

fn assert_order_rejected(method string, word string) {
	mut parsed := false
	mut msg := ''
	if parts := parse_method_name(method) {
		parsed = true
		mut cols := []string{}
		for p in parts.order_by {
			cols << '${p.property}/${p.direction}'
		}
		msg = '解析成了 order=[${cols.join(', ')}] cond="${parts.to_where_cond()}"'
	} else {
		msg = err.msg()
	}
	assert !parsed, '${method} 应该报错，实际 ${msg}'
	assert msg.contains(word), '报错里应点名 ${word}，实为: ${msg}'
}

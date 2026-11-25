module orm

// derive_snake_boundary_test.v —— 派生查询的列名转换
//
// `parse_method_name()` 把方法名里的属性名转成列名，用的是 camel_to_snake。
// 早先的实现在**每个大写字母前插一个下划线**：
//
//   UserDOB    → user_d_o_b        ← 模型里叫 user_dob
//   HTMLParser → h_t_m_l_parser    ← 模型里叫 html_parser
//
// 于是 `findByUserDOB` 查询一个不存在的列：派生查询在运行时失败，而方法名
// 本身完全合法。这和 cli/make_commands.v 里那处 `to_snake_case` 是同一个
// bug（§8.9），当时只在脚手架一侧修掉了 —— 第二份副本还在 ORM 里。
//
// 这一组用例锁两件事：
//   1. 缩写的连读规则（DOB / HTML / URL / ID）；
//   2. 与 orm 模块自己的 snake_case 同源，别又长回第二份实现。

fn ds_props(method string) []string {
	p := parse_method_name(method) or { return []string{} }
	mut out := []string{cap: p.conditions.len}
	for c in p.conditions {
		out << c.property
	}
	return out
}

fn test_abbreviations_stay_together() {
	assert ds_props('findByUserDOB') == ['user_dob']
	assert ds_props('findByHTMLParser') == ['html_parser']
	assert ds_props('findByURLPath') == ['url_path']
	assert ds_props('findByID') == ['id']
}

fn test_multi_word_camel_case() {
	assert ds_props('findByNameAndAge') == ['name', 'age']
	assert ds_props('findByCreatedAt') == ['created_at']
	assert ds_props('countByUserEmail') == ['user_email']
}

// 与模块内 snake_case 的字符向量表逐个对齐 —— 两处如果又分叉，这条会红。
fn test_same_word_boundaries_as_orm_snake_case() {
	for s in ['UserDOB', 'HTMLParser', 'URLPath', 'ID', 'CreatedAt', 'userDOB', 'A', 'ABc', 'abc2Def'] {
		assert ds_props('findBy${s}') == [snake_case(s)], 'findBy${s} 的列名与 snake_case 不一致'
	}
}

// ORDER BY 的字段走的是同一条转换：多字段之间用 `And` 分隔，
// 那个 `And` 只是分隔符，不能变成列名的一部分。
//
// 原来这里写的是 `findByUserDOBOrderByCreatedAtDescAndUserID`，断言它
// 解析成「created_at DESC + user_id ASC」。那条断言是错的：那串名字想
// 表达的是「按 created_at 降序，再按 user_id 过滤」—— ORDER BY 之后
// 不可能再接条件，Spring Data 也没有这种写法。当时的实现把 `OrderBy`
// 当子串截断，才让这个形状「解析成功」：属性里凭空多出一列
// `user_dob_order_by_created_at_desc`，`user_id` 又变成排序字段。
// 用例把它钉成了事实。现在这种形状被拒绝（见 derive_order_boundary_test.v
// 的 test_order_by_cannot_resume_conditions），这条只钉多字段的转换。
fn test_order_by_fields_use_the_same_conversion() {
	p := parse_method_name('findByOrderByCreatedAtDescAndUserDOBAsc') or { panic(err) }
	assert p.order_by.len == 2
	assert p.order_by[0].property == 'created_at'
	assert p.order_by[0].direction == 'DESC'
	// `UserDOB` 是一串缩写，必须还是一个列名 `user_dob`，方向是 ASC。
	assert p.order_by[1].property == 'user_dob'
	assert p.order_by[1].direction == 'ASC'
}

// 一条查询里混着缩写属性和排序：两处都得用同一套词边界。
fn test_acronym_property_then_order_by() {
	p := parse_method_name('findByUserDOBOrderByCreatedAtDesc') or { panic(err) }
	assert p.conditions.len == 1
	assert p.conditions[0].property == 'user_dob'
	assert p.order_by.len == 1
	assert p.order_by[0].property == 'created_at'
	assert p.order_by[0].direction == 'DESC'
}

// 结构断言：只允许有一个词边界实现。camel_to_snake 里再出现手写循环，
// 就等于再造了一份迟早会分叉的副本。
fn test_camel_to_snake_delegates_to_snake_case() {
	src := $embed_file('derive.v').to_string()
	at := src.index('fn camel_to_snake(s string) string {') or {
		assert false, '找不到 camel_to_snake'
		return
	}
	rest := src[at..]
	end := rest.index('\n}') or { panic('camel_to_snake 没有结束括号') }
	body := rest[..end]
	assert body.contains('snake_case('), 'camel_to_snake 必须委托给 snake_case()，不许再手写一份词边界规则：${body}'

	assert !body.contains('for '), 'camel_to_snake 里不该再有手写循环：${body}'
}

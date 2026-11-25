module orm

import strings

// derive.v - Derived Repository Queries (Spring Data inspired)
//
// Parses Spring Data-style method names into query components
// compatible with V's official ORM QueryBuilder[T].
//
// Examples:
//   findByName(String)    → .where('name = ?', value)
//   findByNameAndAge      → .where('name = ? AND age = ?', name, age)
//   findTop10ByOrderByCreatedAtDesc → .order(.desc, 'created_at') + .limit(10)
//   countByStatus         → .where('status = ?', status) + .count()
//
// Use with the OrmAdapter (see adapter/):
//   parts := parse_method_name('findByNameAndAge')!
//   adapter.find_where(parts.to_where_cond(), ...params)!

// QueryOperation represents the type of query
pub enum QueryOperation {
	find       // SELECT
	count      // SELECT COUNT(*)
	exists     // SELECT EXISTS(...)
	delete_all // DELETE
}

// QueryCondition represents a parsed WHERE condition from method name
pub struct QueryCondition {
pub:
	property string
	// SQL operator, or one of the internal spellings used by
	// to_where_cond(): 'LIKE_CONTAINING' / 'LIKE_STARTING' / 'LIKE_ENDING'
	// (LIKE with a `%` pattern), 'BETWEEN' / 'NOT BETWEEN' (two `?`),
	// 'IN' / 'NOT IN' (expanded by to_where_cond_with_arrays()),
	// 'IS NULL' / 'IS NOT NULL' (no `?`), and 'TRUE' / 'FALSE'
	// (no `?`, renders as `column = 1` / `column = 0`).
	operator string = '='
	logic    string = 'AND'
}

// OrderPart represents ORDER BY from method name
pub struct OrderPart {
pub:
	property  string
	direction string = 'ASC'
}

// QueryParts holds all extracted query components
pub struct QueryParts {
pub mut:
	operation  QueryOperation = .find
	distinct   bool
	limit_val  int
	conditions []QueryCondition
	order_by   []OrderPart
}

// parse_method_name parses a Spring Data-style method name into query parts
pub fn parse_method_name(method string) !QueryParts {
	mut parts := QueryParts{}

	mut remaining := method

	// Extract operation prefix
	if remaining.starts_with('find') {
		parts.operation = .find
		remaining = remaining[4..]
	} else if remaining.starts_with('count') {
		parts.operation = .count
		remaining = remaining[5..]
	} else if remaining.starts_with('exists') {
		parts.operation = .exists
		remaining = remaining[6..]
	} else if remaining.starts_with('delete') {
		parts.operation = .delete_all
		remaining = remaining[6..]
	} else {
		return error('unknown query operation in: ${method}')
	}

	// Extract TopN
	if remaining.starts_with('Top') && remaining.len > 3 {
		end_idx := remaining.index('By') or { return error('TopN requires By: ${method}') }
		num_str := remaining[3..end_idx]
		parts.limit_val = num_str.int()
		remaining = remaining[end_idx..]
	}

	// Extract Distinct
	if remaining.starts_with('Distinct') {
		parts.distinct = true
		remaining = remaining[8..]
	}

	// Must have By keyword
	if !remaining.starts_with('By') {
		return error('method name must contain "By": ${method}')
	}
	remaining = remaining[2..]

	// Handle OrderBy as the last clause
	if remaining.contains('OrderBy') {
		order_idx := remaining.index('OrderBy') or { 0 }
		order_part := remaining[order_idx + 7..]
		remaining = remaining[..order_idx]

		for prop in order_part.split('And') {
			mut direction := 'ASC'
			mut prop_name := prop
			if prop.to_lower().ends_with('desc') {
				direction = 'DESC'
				prop_name = prop[..prop.len - 4]
			} else if prop.to_lower().ends_with('asc') {
				prop_name = prop[..prop.len - 3]
			}
			parts.order_by << OrderPart{
				property:  camel_to_snake(prop_name)
				direction: direction
			}
		}
	}

	// Parse conditions (split by camelCase, then detect keywords)
	if remaining.len > 0 {
		// Split by camelCase into tokens
		mut tokens := []string{}
		mut sb := strings.new_builder(64)
		for ch in remaining {
			if ch.is_capital() && sb.len > 0 {
				tokens << sb.str()
				sb = strings.new_builder(64)
			}
			sb.write_byte(ch)
		}
		if sb.len > 0 {
			tokens << sb.str()
		}

		// Parse tokens into conditions, recognizing multi-word keywords
		// such as GreaterThan, GreaterThanOrEqual, IsNotNull, etc.
		mut i := 0
		mut logic := 'AND'

		for i < tokens.len {
			// Logic operators set the logic for the NEXT condition
			if tokens[i] == 'And' {
				logic = 'AND'
				i++
				continue
			}
			if tokens[i] == 'Or' {
				logic = 'OR'
				i++
				continue
			}

			// Collect property name (at least one token).
			//
			// The FIRST token is a property name by construction: the loop
			// above already consumed `And`/`Or`, so a keyword cannot open a
			// condition. That is what keeps `findByInName` a property
			// (`in_name`) rather than an `IN` with no column.
			mut property_tokens := [tokens[i]]
			i++
			mut operator := '='

			// Look for keyword or more property tokens
			for i < tokens.len {
				// Check for keyword FIRST (before logic operator check)
				// because GreaterThanOrEqual contains 'Or'
				keyword, consumed := match_keyword(tokens, i)
				if keyword != '' {
					operator = keyword_to_operator(keyword)
					i += consumed
					// A keyword ends the condition. Anything that follows
					// must be `And` / `Or` (checked by the outer loop) or it
					// is an operator this parser does not understand —
					// `findByAgeGreaterThanX` used to become
					// `age > ? AND x = ?`, quietly adding a column to the
					// WHERE clause that the caller never asked for.
					if i < tokens.len && tokens[i] != 'And' && tokens[i] != 'Or' {
						hint := unsupported_keyword_hint([tokens[i]])
						word := if hint != '' { hint } else { tokens[i] }
						return error('unexpected "${word}" after keyword "${keyword}" in derived query "${method}" / 派生查询在关键字 "${keyword}" 之后出现无法解析的 "${word}"')
					}
					break
				}
				// Check for logic operator — ends the current condition.
				// The token is deliberately NOT consumed here: the outer
				// loop re-reads it to set `logic` for the next condition.
				if tokens[i] == 'And' || tokens[i] == 'Or' {
					break
				}
				// `IgnoreCase` can sit directly after the property with no
				// operator in between (`findByNameIgnoreCase`). The camel
				// splitter cuts it into `Ignore` + `Case`, so match both and
				// consume them — otherwise the property becomes
				// `name_ignore_case`, a column that never existed.
				if i + 1 < tokens.len && tokens[i] == 'Ignore' && tokens[i + 1] == 'Case' {
					i += 2
					break
				}
				// A Spring Data keyword with no operator we can express, or a
				// plain multi-word property (`CreatedAt` → created_at)?
				//
				// Guessing wrong here is expensive: `findByAgeBetween` used to
				// absorb `Between` into the column name and query
				// `age_between`, which the driver reports as "no such column" —
				// the same message a typo in the method name produces. Refuse
				// instead, and say which keyword is missing.
				hint := unsupported_keyword_hint([tokens[i]])
				if hint != '' {
					return error('unsupported keyword "${hint}" in derived query "${method}" / 派生查询不支持关键字 "${hint}"')
				}
				// Another property token (multi-word property name)
				property_tokens << tokens[i]
				i++
			}

			// Join property tokens and convert to snake_case
			property_name := property_tokens.join('')
			parts.conditions << QueryCondition{
				property: camel_to_snake(property_name)
				operator: operator
				logic:    logic
			}
		}
	}

	return parts
}

// ── V ORM-compatible output ──

// to_where_cond builds a WHERE condition string for V's
// official QueryBuilder.where().
//
// Example: 'name = ? AND age = ?'
//
// Operators that do not take a single value:
//
//   findByAgeBetween     → age BETWEEN ? AND ?          (2 placeholders)
//   findByActiveTrue     → active = 1                   (0 placeholders)
//   findByNameIgnoreCase → name = ?                     (1, case folded by the caller)
//   findByIdIn           → id IN (?)                    (expanded separately)
//
// For IN/NOT IN conditions, this generates a single `?` placeholder.
// Use to_where_cond_with_arrays() when you need to expand IN clauses
// with the correct number of placeholders based on array length.
//
// NOTE: the `?` produced here is meant for V's own QueryBuilder
// (`qb.where(cond, ...args)`), which parenthesises consecutive OR runs.
// Concatenating another `to_where_cond()` fragment onto it by hand loses
// that parenthesisation.
pub fn (qp QueryParts) to_where_cond() string {
	if qp.conditions.len == 0 {
		return ''
	}
	mut sb := strings.new_builder(64)
	for i, c in qp.conditions {
		if i > 0 {
			sb.write_string(' ${c.logic} ')
		}
		write_condition(mut sb, c, map[string]int{})
	}
	return sb.str()
}

// to_where_cond_with_arrays builds a WHERE condition string, expanding
// IN/NOT IN clauses with the correct number of `?` placeholders based
// on the provided array lengths.
//
// `array_lengths` maps property names to their array length. For
// conditions whose property is not in the map, a single placeholder
// is used.
//
// Example:
//   parts := parse_method_name('findByIdIn')!
//   sql := parts.to_where_cond_with_arrays({'id': 3})
//   // → 'id IN (?, ?, ?)'
pub fn (qp QueryParts) to_where_cond_with_arrays(array_lengths map[string]int) string {
	if qp.conditions.len == 0 {
		return ''
	}
	mut sb := strings.new_builder(64)
	for i, c in qp.conditions {
		if i > 0 {
			sb.write_string(' ${c.logic} ')
		}
		write_condition(mut sb, c, array_lengths)
	}
	return sb.str()
}

// write_condition renders one condition into `sb`.
//
// Both to_where_cond() and to_where_cond_with_arrays() go through here so
// that adding an operator cannot be done in one place and forgotten in the
// other — the previous shape had the same match duplicated verbatim, which
// is exactly how `LIKE_CONTAINING` and its neighbours drifted apart from
// the keyword table.
//
// `array_lengths` empty means "IN gets a single `?`" (the default of
// to_where_cond()).
fn write_condition(mut sb strings.Builder, c QueryCondition, array_lengths map[string]int) {
	match c.operator {
		'IS NULL' { sb.write_string('${c.property} IS NULL') }
		'IS NOT NULL' { sb.write_string('${c.property} IS NOT NULL') }
		'TRUE' { sb.write_string('${c.property} = 1') }
		'FALSE' { sb.write_string('${c.property} = 0') }
		'LIKE_CONTAINING' { sb.write_string("${c.property} LIKE '%' || ? || '%'") }
		'LIKE_STARTING' { sb.write_string("${c.property} LIKE ? || '%'") }
		'LIKE_ENDING' { sb.write_string("${c.property} LIKE '%' || ?") }
		'NOT_LIKE_CONTAINING' { sb.write_string("${c.property} NOT LIKE '%' || ? || '%'") }
		'NOT_LIKE_STARTING' { sb.write_string("${c.property} NOT LIKE ? || '%'") }
		'NOT_LIKE_ENDING' { sb.write_string("${c.property} NOT LIKE '%' || ?") }
		'BETWEEN', 'NOT BETWEEN' {
			sb.write_string('${c.property} ${c.operator} ? AND ?')
		}
		'IN', 'NOT IN' {
			n := array_lengths[c.property] or { 1 }
			sb.write_string('${c.property} ${c.operator} (')
			for j in 0 .. n {
				if j > 0 {
					sb.write_string(', ')
				}
				sb.write_string('?')
			}
			sb.write_string(')')
		}
		else { sb.write_string('${c.property} ${c.operator} ?') }
	}
}

// to_where_params returns the number of `?` placeholders
// in the WHERE condition (useful for validating callers).
//
// For IN/NOT IN conditions, this counts 1 placeholder (the single
// `?` produced by to_where_cond()). Use to_where_param_count_with_arrays()
// when expanding IN clauses with to_where_cond_with_arrays().
//
// The per-operator counts come from operator_param_count(), the same rule
// write_condition() renders from. Letting the two drift is what turns a
// bound value into `status = <tenant_id>`.
pub fn (qp QueryParts) to_where_param_count() int {
	mut count := 0
	for c in qp.conditions {
		n := operator_param_count(c.operator)
		if n == -1 {
			// IN / NOT IN keep to_where_cond()'s single `?`.
			count++
		} else if n > 0 {
			count += n
		}
	}
	return count
}

// to_where_param_count_with_arrays returns the number of `?` placeholders
// when using to_where_cond_with_arrays(), expanding IN/NOT IN clauses
// based on the provided array lengths.
pub fn (qp QueryParts) to_where_param_count_with_arrays(array_lengths map[string]int) int {
	mut count := 0
	for c in qp.conditions {
		n := operator_param_count(c.operator)
		if n == -1 {
			// IN / NOT IN: one placeholder per element.
			count += array_lengths[c.property] or { 1 }
		} else if n > 0 {
			count += n
		}
	}
	return count
}

// to_order_direction returns the sort direction for the first
// OrderPart (if any).  Returns 'asc' or 'desc'.
pub fn (qp QueryParts) to_order_direction() string {
	if qp.order_by.len == 0 {
		return 'asc'
	}
	return qp.order_by[0].direction.to_lower()
}

// to_order_field returns the field name for the first OrderPart.
pub fn (qp QueryParts) to_order_field() string {
	if qp.order_by.len == 0 {
		return ''
	}
	return qp.order_by[0].property
}

// camel_to_snake converts CamelCase to snake_case.
//
// "CreatedAt"  → "created_at"
// "UserDOB"    → "user_dob"      （不是 user_d_o_b）
// "HTMLParser" → "html_parser"   （不是 h_t_m_l_parser）
//
// 早先这里是「每个大写字母前插一个下划线」。那样 `findByUserDOB` 会去查
// `user_d_o_b` 这一列 —— 模型里叫 `user_dob`，于是派生查询在运行时
// 报「列不存在」。这和 cli/make_commands.v 里那处 to_snake_case 是同一个
// bug（§8.9），当时只在脚手架一侧修掉了，第二份副本留在这里。
//
// 现在委托给本模块的 snake_case（orm/local_hash.v）：缩写连读，与
// strutil.snake 用同一套词边界规则，两边各有字符向量表互相钉住。
fn camel_to_snake(s string) string {
	return snake_case(s)
}

// to_limit returns the limit value (0 = no limit).
pub fn (qp QueryParts) to_limit() int {
	return qp.limit_val
}

// is_count returns true if the derived query is a COUNT.
pub fn (qp QueryParts) is_count() bool {
	return qp.operation == .count
}

// is_delete returns true if the derived query is a DELETE.
pub fn (qp QueryParts) is_delete() bool {
	return qp.operation == .delete_all
}

// ── Derived query keyword table ──
//
// The table below is the single source of truth for both questions the
// parser has to answer: "does this token sequence start a keyword?" and
// "how many `?` does that keyword consume?".
//
// Why one table and not two functions
// -----------------------------------
// It used to be a hand-written chain of `if` blocks plus a separate
// `keyword_to_operator()` match. The chain covered 11 of Spring Data's ~20
// keywords, and anything it did not know was silently absorbed into the
// property name:
//
//   findByAgeBetween     → WHERE age_between = ?     (a column that does not exist)
//   findByActiveTrue     → WHERE active_true = ?
//   findByNameIgnoreCase → WHERE name_ignore_case = ?
//   findByNameNot        → WHERE name_not = ?
//
// Every one of those is a *parse success* that turns into a driver-level
// "no such column" — indistinguishable from a typo in the method name.
// The table owns the whole vocabulary now, so a keyword either resolves
// or the parser refuses.
//
// Ordering: longest-first, so `GreaterThanOrEqual` (4 tokens) wins over
// `GreaterThan` (2), `IsNotNull` (3) over `IsNull` (2), and
// `NotContaining` (2) over `Containing` (1). Emitting `ordered` in the
// wrong order silently degrades to the shorter keyword.
fn keyword_table() []KeywordSpec {
	return [
		// 4 tokens
		KeywordSpec{'GreaterThanOrEqual', ['Greater', 'Than', 'Or', 'Equal'], '>='},
		KeywordSpec{'LessThanOrEqual', ['Less', 'Than', 'Or', 'Equal'], '<='},
		// 3 tokens
		KeywordSpec{'IsNotNull', ['Is', 'Not', 'Null'], 'IS NOT NULL'},
		KeywordSpec{'NotStartingWith', ['Not', 'Starting', 'With'], 'NOT_LIKE_STARTING'},
		KeywordSpec{'NotEndingWith', ['Not', 'Ending', 'With'], 'NOT_LIKE_ENDING'},
		// 2 tokens
		KeywordSpec{'GreaterThan', ['Greater', 'Than'], '>'},
		KeywordSpec{'LessThan', ['Less', 'Than'], '<'},
		KeywordSpec{'StartingWith', ['Starting', 'With'], 'LIKE_STARTING'},
		KeywordSpec{'EndingWith', ['Ending', 'With'], 'LIKE_ENDING'},
		KeywordSpec{'IsNull', ['Is', 'Null'], 'IS NULL'},
		// `NotNull` is the short form of `IsNotNull` — Spring Data accepts
		// both, and `findByAgeNotNull` used to become `age_not_null = ?`.
		KeywordSpec{'NotNull', ['Not', 'Null'], 'IS NOT NULL'},
		KeywordSpec{'NotIn', ['Not', 'In'], 'NOT IN'},
		KeywordSpec{'NotBetween', ['Not', 'Between'], 'NOT BETWEEN'},
		KeywordSpec{'NotLike', ['Not', 'Like'], 'NOT LIKE'},
		KeywordSpec{'NotContaining', ['Not', 'Containing'], 'NOT_LIKE_CONTAINING'},
		// The camel splitter cuts `IgnoreCase` into two tokens, so the
		// table has to spell it the same way.
		KeywordSpec{'IgnoreCase', ['Ignore', 'Case'], '='},
		// 1 token
		KeywordSpec{'Like', ['Like'], 'LIKE'},
		KeywordSpec{'Containing', ['Containing'], 'LIKE_CONTAINING'},
		KeywordSpec{'Between', ['Between'], 'BETWEEN'},
		KeywordSpec{'True', ['True'], 'TRUE'},
		KeywordSpec{'False', ['False'], 'FALSE'},
		KeywordSpec{'In', ['In'], 'IN'},
	]
}

// KeywordSpec is one row of the derived-query keyword table: the
// Spring Data name, the token sequence that spells it, and the SQL
// operator it maps to.
//
// exposed as a struct rather than a tuple so that a test can walk
// keyword_table() and assert every row is (a) reachable from a real
// method name and (b) consuming the number of `?` its operator implies.
struct KeywordSpec {
	name   string
	tokens []string
	op     string
}

// unsupported_keyword_hint names the Spring Data keyword that shares a
// prefix with the property tokens the parser gave up on, or '' when the
// tokens look like an ordinary multi-word property.
//
// This is what turns "silently query a column that does not exist" into
// "say which keyword is missing". `findByAgeBetween` with no `Between`
// branch used to become `age_between = ?`; now it points at the keyword.
fn unsupported_keyword_hint(tokens []string) string {
	known := [
		'Between', 'IgnoreCase', 'Like', 'Not', 'True', 'False', 'Null',
		'In', 'Greater', 'Less', 'Starting', 'Ending', 'Containing', 'After',
		'Before', 'Regex', 'Exists', 'Empty', 'Near', 'Within',
	]
	mut hint := ''
	for t in tokens {
		if t in known {
			// 只报告第一次出现，报错信息里给一个就够。
			hint = t
			break
		}
	}
	return hint
}

// match_keyword checks if the tokens at position `start` form a known
// Spring Data-style keyword. Returns (keyword_name, num_tokens_consumed)
// or ('', 0) if no match.
//
// Keywords are checked longest-first (see keyword_table()).
fn match_keyword(tokens []string, start int) (string, int) {
	for spec in keyword_table() {
		if start + spec.tokens.len > tokens.len {
			continue
		}
		mut hit := true
		for j, t in spec.tokens {
			if tokens[start + j] != t {
				hit = false
				break
			}
		}
		if hit {
			return spec.name, spec.tokens.len
		}
	}
	return '', 0
}

// keyword_operator returns the operator spelling for a keyword name, or
// '' when the keyword is not in the table.
fn keyword_operator(keyword string) string {
	for spec in keyword_table() {
		if spec.name == keyword {
			return spec.op
		}
	}
	return ''
}

// keyword_to_operator maps a keyword name to its SQL operator
// representation used in QueryCondition.operator.
//
// Kept as a thin wrapper over the table so there is exactly one place
// that knows the mapping.
fn keyword_to_operator(keyword string) string {
	op := keyword_operator(keyword)
	if op == '' {
		return '='
	}
	return op
}

// operator_param_count reports how many `?` placeholders an operator
// consumes in to_where_cond(), or -1 when a single value cannot express
// the operator at all (IN / NOT IN take a list).
//
// to_where_param_count() and to_where_cond() must agree on this number —
// a mismatch is what makes bound values land in the wrong slot.
fn operator_param_count(op string) int {
	return match op {
		'IS NULL', 'IS NOT NULL', 'TRUE', 'FALSE' { 0 }
		'IN', 'NOT IN' { -1 }
		'BETWEEN', 'NOT BETWEEN' { 2 }
		else { 1 }
	}
}

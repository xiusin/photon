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

	// Split off the ORDER BY clause, if any (see split_order_clause()).
	remaining = split_order_clause(remaining, method, mut parts)!

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

// ── ORDER BY clause ──
//
// The `ORDER BY` half of a derived query is parsed by its own small grammar:
//
//   orderBody := orderField ( 'And' orderField )*
//   orderField := property [ 'Asc' | 'Desc' ]
//
// There are exactly two keywords (`Asc` / `Desc`) and one separator (`And`),
// and all of them are *words* in the camel-split sense, not substrings.
// That distinction is the whole point of this section: the previous version
// looked for `OrderBy` as a substring and then asked `ends_with('desc')`,
// which accepts four spellings of "I don't understand you" without ever
// saying so:
//
//   findByOrderByAgeDescOrName  → ORDER BY age_desc_or_name ASC
//   findByOrderByAgeDescName    → ORDER BY age_desc_name ASC
//   findByOrderByAndName        → ORDER BY "" ASC, name ASC
//   findByOrderByAgeDescAnd     → ORDER BY age DESC, "" ASC
//
// The first two are the same failure as `findByAgeBetween` from the WHERE
// side: a keyword written by the caller becomes part of a column name, and
// the driver reports "no such column" — the message a typo produces. The
// empty names in the last two reach `qb.order('', .asc)` and silently drop
// the ordering, which is worse: the query succeeds and the rows come back
// in whatever order the database felt like.
//
// So: an order field is one property plus an optional direction, `OrderBy`
// only counts when it starts a clause, and anything left over is refused
// by name.
//
// Ordering keys the WHERE side already uses: `Newest`/`Oldest` are Spring
// Data 3.x aliases for `Desc`/`Asc`. They are NOT accepted here yet, and
// being unaccepted means an error, not a column called `created_at_newest`.

// order_direction_keywords returns the direction suffixes, longest first,
// together with the direction each one means. Two entries today; kept as a
// table so that adding an alias forces the two questions ("is this a
// direction?" and "which one?") to be answered in one place, the same way
// keyword_table() does for the WHERE side.
fn order_direction_keywords() []OrderDirectionSpec {
	return [
		OrderDirectionSpec{'Desc', 'DESC'},
		OrderDirectionSpec{'Asc', 'ASC'},
	]
}

// OrderDirectionSpec is one row of the ORDER BY direction table.
// Exposed as a struct so a test can walk the table.
struct OrderDirectionSpec {
	name string
	dir  string
}

// split_order_clause cuts the `OrderBy` tail off `remaining`, fills
// `parts.order_by`, and returns the condition part.
//
// The clause starts at an `OrderBy` that appears at the head or right after
// `And` / `Or` — that is, where a clause is allowed to start. A bare
// substring search would also cut inside `findByNameAndOrderByAge`, where
// `OrderBy` sits in the position of an (oddly named) property, turning
// `name = ? AND` into a WHERE ending in a dangling separator.
//
// A second `OrderBy` after the first is refused rather than truncated:
// silently keeping the tail of a tail is how a clause quietly loses its
// first field.
fn split_order_clause(remaining string, method string, mut parts QueryParts) !string {
	mut kept := remaining
	body := if at := order_by_clause_start(remaining) {
		tmp := remaining[at..]
		kept = remaining[..at - 7]
		tmp
	} else {
		// No candidate at a word boundary. A plain `contains` is then the
		// only reason to complain — and when it fires, the message has to
		// say that `OrderBy` cannot be read as one of these things, because
		// that is the whole diagnosis.
		if remaining.contains('OrderBy') {
			return error('unsupported "OrderBy" in derived query "${method}" / 派生查询里的 "OrderBy" 既不是排序列也不是合法子句')
		}
		return kept
	}

	if classify_order_body(body) == .refused {
		return error('"OrderBy" must be the last clause, followed only by properties and Asc/Desc, in derived query "${method}" / 派生查询中的 "OrderBy" 必须位于末尾，其后只能跟属性和 Asc/Desc')
	}

	// `findByOrderByAndName`: `OrderByAndName` is a sorting clause whose
	// FIRST field is empty — the `And` there is the sort separator, not a
	// condition separator. Checked before the parse because the strict
	// parser would read `And` `Name` as one field with a leading `And`.
	if body.starts_with('And') {
		return error('"And" right after "OrderBy" has no property in derived query "${method}" / 派生查询中 "OrderBy" 之后紧跟的 "And" 前没有属性')
	}
	parse_order_part(body, method, mut parts)!

	if kept.len == 0 {
		return kept
	}
	// The `And`/`Or` that introduced the clause joined nothing: its
	// condition is missing (`findByAgeAndOrderByAgeDesc`).
	if kept.ends_with('And') || kept.ends_with('Or') {
		sep := if kept.ends_with('And') { 'And' } else { 'Or' }
		return error('"${sep}" before "OrderBy" has no condition in derived query "${method}" / 派生查询中 "OrderBy" 之前的 "${sep}" 没有对应条件')
	}
	return kept
}

// order_by_clause_start returns the index just past `OrderBy`, or an error
// when there is no clause.
//
// `OrderBy` is treated as a clause start unconditionally. That is Spring
// Data's contract: the word is reserved, and a property named
// `existing_order_by_code` is written `ExistingOrderbyCode` (or mapped with
// `@[column]`) by everyone who has hit this. Modelling it as "a word
// boundary that is not inside an acronym" was tried and does not hold:
// `ExistingOrderByCode` and `NameOrderByAgeDesc` differ only in what follows
// the `OrderBy`, and `Code` is a perfectly valid sort field with the
// direction omitted — the two are the same string shape from the parser's
// point of view. Reserving the word is the only rule that never guesses.
//
// The one thing still checked is that the tail *can* be a sort clause; when
// it cannot, saying so beats inventing a column. See classify_order_body().
fn order_by_clause_start(s string) ?int {
	idx := s.index('OrderBy') or { return none }
	return idx + 7
}

// order_body_kind classifies the text after `OrderBy`. See the call site
// for why the answer has three values and not two.
enum OrderBodyKind {
	clause  // a sorting clause: <property> [Asc|Desc] (And ...)*
	refused // not a sorting clause: refuse and name the reason
}

fn classify_order_body(body string) OrderBodyKind {
	spans := camel_token_spans(body)
	if spans.len == 0 {
		return .refused
	}
	mut i := 0
	for i < spans.len {
		if i > 0 {
			if spans[i].text != 'And' {
				return .refused
			}
			i++
			if i >= spans.len {
				return .refused
			}
		}
		// A second `OrderBy` in the tail: the tail of a tail.
		if spans[i].text == 'Order' && i + 1 < spans.len && spans[i + 1].text == 'By' {
			return .refused
		}
		// A direction cannot open a field.
		if is_direction_token(body, spans, i) || spans[i].text in order_direction_names() {
			return .refused
		}
		// A WHERE keyword cannot be an order field either. `OrderByAgeBetween`
		// reads as "sort by age_between" — a column that only exists if the
		// model has one, which is the same silent degrade the WHERE side
		// already refuses to make.
		if spans[i].text in order_forbidden_words() {
			return .refused
		}
		i++
		mut dir_seen := false
		for i < spans.len && spans[i].text != 'And' {
			if is_direction_token(body, spans, i) {
				dir_seen = true
				i++
				// Anything after a direction that is not `And` cannot be
				// sorting. It could still be the tail of a longer property
				// (`OrderBy` nested inside one), which is a different story.
				if i < spans.len && spans[i].text != 'And' {
					return .refused
				}
				break
			}
			if dir_seen {
				return .refused
			}
			if spans[i].text in order_forbidden_words() {
				return .refused
			}
			i++
		}
	}
	return .clause
}

// is_direction_token reports whether spans[i] is a direction suffix for the
// property word(s) in front of it.
//
// `AgeDesc` and `UserDesc` split identically — `Age` `Desc`, `User` `Desc` —
// but only the first is a direction. The difference is where the `D` sits:
// `UserDesc` has it mid-word, right after a capital that ends the preceding
// run (`UserD`), while `AgeDesc` starts a fresh word. The camel splitter
// cannot see that on its own, which is why it hands back the offsets.
//
// The old `ends_with('desc')` had the opposite problem: it accepted
// `UserDesc` (stripping `User` down to `user`) and also accepted
// `Descending`'s first four characters, quietly turning a misspelling into
// ASC. A direction is a whole word, and this is the test for "whole".
fn is_direction_token(body string, spans []CamelToken, i int) bool {
	if spans[i].text !in order_direction_names() {
		return false
	}
	// A direction is a *whole word*, and "whole" is answered by the same
	// boundary rule that snake_case uses — the one place that knows where
	// a camel word starts. `AgeDesc` splits cleanly (`e` + `D` is a normal
	// bump); `UserDOBDesc` does not (`B` + `D` is the middle of an acronym
	// run, so `Desc` is part of the property name).
	if spans[i].start == 0 {
		return false
	}
	return snake_word_boundary(body, spans[i].start)
}

// order_forbidden_words lists the tokens that never belong to an order
// field: the WHERE keywords and the logical connectives that only exist
// between fields.
//
// Order fields are property names, so almost anything is allowed — which is
// exactly why the handful of words that mean something else elsewhere have
// to be refused explicitly. `Between` in a sort body is a keyword the
// caller put in the wrong half of the method name, not a column.
fn order_forbidden_words() []string {
	return [
		'Between',
		'Containing',
		'Like',
		'IgnoreCase',
		'Null',
		'True',
		'False',
		'Greater',
		'Less',
		'Starting',
		'Ending',
		'In',
		'Not',
		'Regex',
		'Exists',
	]
}

// order_direction_names lists the direction suffixes in one place.
fn order_direction_names() []string {
	mut names := []string{cap: 2}
	for spec in order_direction_keywords() {
		names << spec.name
	}
	return names
}

// parse_order_part parses `AgeDescAndNameAsc` into OrderParts.
//
// Called only after classify_order_body() has agreed that the tail is a
// sorting clause, so every shape reaching here is already well-formed —
// which is why the guard clauses below do not have a mutation that turns
// them red: they are a second copy of a decision already made upstream.
//
// They stay anyway, and not out of habit. `classify` answers "may this be a
// sort clause"; this answers "build the parts", and the two must agree. When
// they disagree the failure is a column called `age_desc_name` — the shape
// mutation 6 in the commit message could not break precisely because the
// first line of defence held. A second check that never fires is cheap; a
// missing one is the bug this whole file is about.
fn parse_order_part(body string, method string, mut parts QueryParts) ! {
	spans := camel_token_spans(body)
	mut i := 0
	mut expect_field := true
	for i < spans.len {
		if spans[i].text == 'And' {
			i++
			expect_field = true
			continue
		}
		if !expect_field {
			return error('missing "And" between order properties in derived query "${method}" / 派生查询的 ORDER BY 里两个属性之间缺少 "And"')
		}
		mut property_tokens := []string{cap: 4}
		property_tokens << spans[i].text
		i++
		mut direction := 'ASC'
		for i < spans.len && spans[i].text != 'And' {
			if is_direction_token(body, spans, i) {
				if spans[i].text == 'Desc' {
					direction = 'DESC'
				}
				i++
				break
			}
			property_tokens << spans[i].text
			i++
		}
		parts.order_by << OrderPart{
			property:  camel_to_snake(property_tokens.join(''))
			direction: direction
		}
		expect_field = false
	}
}

// camel_tokens splits CamelCase into words, the same way the WHERE side
// does. Kept as a function so the two halves cannot disagree about where a
// word starts — they used to (`ords.split('And')` for ORDER BY,
// `is_capital()` for WHERE).
fn camel_tokens(s string) []string {
	return camel_token_spans(s).map(it.text)
}

// CamelToken is one word of a camelCase string, with the index its first
// character had in the original. The index is what tells `UserDesc` from
// `AgeDesc`: both split into two tokens, but in the first the `Desc` starts
// mid-word (`User` ended with a capital run into it), in the second it does
// not. Direction suffixes are decided by that, not by the token alone.
struct CamelToken {
	text  string
	start int
}

fn camel_token_spans(s string) []CamelToken {
	mut tokens := []CamelToken{cap: 8}
	mut sb := strings.new_builder(16)
	mut start := 0
	for i, ch in s {
		if ch.is_capital() && sb.len > 0 {
			tokens << CamelToken{sb.str(), start}
			sb = strings.new_builder(16)
			start = i
		}
		if sb.len == 0 {
			start = i
		}
		sb.write_byte(ch)
	}
	if sb.len > 0 {
		tokens << CamelToken{sb.str(), start}
	}
	return tokens
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
		'IS NULL' {
			sb.write_string('${c.property} IS NULL')
		}
		'IS NOT NULL' {
			sb.write_string('${c.property} IS NOT NULL')
		}
		'TRUE' {
			sb.write_string('${c.property} = 1')
		}
		'FALSE' {
			sb.write_string('${c.property} = 0')
		}
		'LIKE_CONTAINING' {
			sb.write_string("${c.property} LIKE '%' || ? || '%'")
		}
		'LIKE_STARTING' {
			sb.write_string("${c.property} LIKE ? || '%'")
		}
		'LIKE_ENDING' {
			sb.write_string("${c.property} LIKE '%' || ?")
		}
		'NOT_LIKE_CONTAINING' {
			sb.write_string("${c.property} NOT LIKE '%' || ? || '%'")
		}
		'NOT_LIKE_STARTING' {
			sb.write_string("${c.property} NOT LIKE ? || '%'")
		}
		'NOT_LIKE_ENDING' {
			sb.write_string("${c.property} NOT LIKE '%' || ?")
		}
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
		else {
			sb.write_string('${c.property} ${c.operator} ?')
		}
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
		'Between',
		'IgnoreCase',
		'Like',
		'Not',
		'True',
		'False',
		'Null',
		'In',
		'Greater',
		'Less',
		'Starting',
		'Ending',
		'Containing',
		'After',
		'Before',
		'Regex',
		'Exists',
		'Empty',
		'Near',
		'Within',
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

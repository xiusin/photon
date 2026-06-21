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
	operator string = '=' // =, >, <, >=, <=, IN, NOT IN, IS NULL, IS NOT NULL,
	//   LIKE_CONTAINING, LIKE_STARTING, LIKE_ENDING
	logic string = 'AND'
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

			// Collect property name (at least one token)
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
					break
				}
				// Check for logic operator — ends the current condition
				if tokens[i] == 'And' || tokens[i] == 'Or' {
					break
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
// For IN/NOT IN conditions, this generates a single `?` placeholder.
// Use to_where_cond_with_arrays() when you need to expand IN clauses
// with the correct number of placeholders based on array length.
pub fn (qp QueryParts) to_where_cond() string {
	if qp.conditions.len == 0 {
		return ''
	}
	mut sb := strings.new_builder(64)
	for i, c in qp.conditions {
		if i > 0 {
			sb.write_string(' ${c.logic} ')
		}
		match c.operator {
			'=' { sb.write_string('${c.property} = ?') }
			'IS NULL' { sb.write_string('${c.property} IS NULL') }
			'IS NOT NULL' { sb.write_string('${c.property} IS NOT NULL') }
			'LIKE_CONTAINING' { sb.write_string("${c.property} LIKE '%' || ? || '%'") }
			'LIKE_STARTING' { sb.write_string("${c.property} LIKE ? || '%'") }
			'LIKE_ENDING' { sb.write_string("${c.property} LIKE '%' || ?") }
			'IN' { sb.write_string('${c.property} IN (?)') }
			'NOT IN' { sb.write_string('${c.property} NOT IN (?)') }
			else { sb.write_string('${c.property} ${c.operator} ?') }
		}
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
		match c.operator {
			'=' { sb.write_string('${c.property} = ?') }
			'IS NULL' { sb.write_string('${c.property} IS NULL') }
			'IS NOT NULL' { sb.write_string('${c.property} IS NOT NULL') }
			'LIKE_CONTAINING' { sb.write_string("${c.property} LIKE '%' || ? || '%'") }
			'LIKE_STARTING' { sb.write_string("${c.property} LIKE ? || '%'") }
			'LIKE_ENDING' { sb.write_string("${c.property} LIKE '%' || ?") }
			'IN' {
				n := array_lengths[c.property] or { 1 }
				sb.write_string('${c.property} IN (')
				for j in 0 .. n {
					if j > 0 {
						sb.write_string(', ')
					}
					sb.write_string('?')
				}
				sb.write_string(')')
			}
			'NOT IN' {
				n := array_lengths[c.property] or { 1 }
				sb.write_string('${c.property} NOT IN (')
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
	return sb.str()
}

// to_where_params returns the number of `?` placeholders
// in the WHERE condition (useful for validating callers).
//
// For IN/NOT IN conditions, this counts 1 placeholder (the single
// `?` produced by to_where_cond()). Use to_where_param_count_with_arrays()
// when expanding IN clauses with to_where_cond_with_arrays().
pub fn (qp QueryParts) to_where_param_count() int {
	mut count := 0
	for c in qp.conditions {
		if c.operator == 'IS NULL' || c.operator == 'IS NOT NULL' {
			continue
		}
		count++
	}
	return count
}

// to_where_param_count_with_arrays returns the number of `?` placeholders
// when using to_where_cond_with_arrays(), expanding IN/NOT IN clauses
// based on the provided array lengths.
pub fn (qp QueryParts) to_where_param_count_with_arrays(array_lengths map[string]int) int {
	mut count := 0
	for c in qp.conditions {
		if c.operator == 'IS NULL' || c.operator == 'IS NOT NULL' {
			continue
		}
		if c.operator == 'IN' || c.operator == 'NOT IN' {
			count += array_lengths[c.property] or { 1 }
		} else {
			count++
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
// Example: "CreatedAt" → "created_at"
// Uses a strings.Builder to avoid O(n²) string concatenation.
fn camel_to_snake(s string) string {
	mut sb := strings.new_builder(s.len * 2)
	for i, ch in s {
		if ch.is_capital() && i > 0 {
			sb.write_string('_')
		}
		sb.write_string(ch.ascii_str().to_lower())
	}
	return sb.str()
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

// ── Derived query keyword matching (Task B5) ──
//
// match_keyword checks if the tokens at position `start` form a known
// Spring Data-style keyword. Returns (keyword_name, num_tokens_consumed)
// or ('', 0) if no match.
//
// Keywords are checked longest-first to ensure greedy matching, so
// `GreaterThanOrEqual` (4 tokens) is matched before `GreaterThan`
// (2 tokens), and `IsNotNull` (3 tokens) before `IsNull` (2 tokens).
fn match_keyword(tokens []string, start int) (string, int) {
	n := tokens.len

	// GreaterThanOrEqual (4 tokens: Greater, Than, Or, Equal)
	if start + 4 <= n &&
		tokens[start] == 'Greater' &&
		tokens[start + 1] == 'Than' &&
		tokens[start + 2] == 'Or' &&
		tokens[start + 3] == 'Equal' {
		return 'GreaterThanOrEqual', 4
	}

	// LessThanOrEqual (4 tokens: Less, Than, Or, Equal)
	if start + 4 <= n &&
		tokens[start] == 'Less' &&
		tokens[start + 1] == 'Than' &&
		tokens[start + 2] == 'Or' &&
		tokens[start + 3] == 'Equal' {
		return 'LessThanOrEqual', 4
	}

	// IsNotNull (3 tokens: Is, Not, Null)
	if start + 3 <= n &&
		tokens[start] == 'Is' &&
		tokens[start + 1] == 'Not' &&
		tokens[start + 2] == 'Null' {
		return 'IsNotNull', 3
	}

	// GreaterThan (2 tokens: Greater, Than)
	if start + 2 <= n &&
		tokens[start] == 'Greater' &&
		tokens[start + 1] == 'Than' {
		return 'GreaterThan', 2
	}

	// LessThan (2 tokens: Less, Than)
	if start + 2 <= n &&
		tokens[start] == 'Less' &&
		tokens[start + 1] == 'Than' {
		return 'LessThan', 2
	}

	// StartingWith (2 tokens: Starting, With)
	if start + 2 <= n &&
		tokens[start] == 'Starting' &&
		tokens[start + 1] == 'With' {
		return 'StartingWith', 2
	}

	// EndingWith (2 tokens: Ending, With)
	if start + 2 <= n &&
		tokens[start] == 'Ending' &&
		tokens[start + 1] == 'With' {
		return 'EndingWith', 2
	}

	// IsNull (2 tokens: Is, Null)
	if start + 2 <= n &&
		tokens[start] == 'Is' &&
		tokens[start + 1] == 'Null' {
		return 'IsNull', 2
	}

	// NotIn (2 tokens: Not, In)
	if start + 2 <= n &&
		tokens[start] == 'Not' &&
		tokens[start + 1] == 'In' {
		return 'NotIn', 2
	}

	// Containing (1 token)
	if tokens[start] == 'Containing' {
		return 'Containing', 1
	}

	// In (1 token)
	if tokens[start] == 'In' {
		return 'In', 1
	}

	return '', 0
}

// keyword_to_operator maps a keyword name to its SQL operator
// representation used in QueryCondition.operator.
//
// The returned values are matched in to_where_cond() and
// to_where_cond_with_arrays() to generate the correct SQL fragment.
fn keyword_to_operator(keyword string) string {
	return match keyword {
		'GreaterThan' { '>' }
		'LessThan' { '<' }
		'GreaterThanOrEqual' { '>=' }
		'LessThanOrEqual' { '<=' }
		'Containing' { 'LIKE_CONTAINING' }
		'StartingWith' { 'LIKE_STARTING' }
		'EndingWith' { 'LIKE_ENDING' }
		'In' { 'IN' }
		'NotIn' { 'NOT IN' }
		'IsNull' { 'IS NULL' }
		'IsNotNull' { 'IS NOT NULL' }
		else { '=' }
	}
}

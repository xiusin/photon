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
	operator string = '=' // =, <, >, LIKE, BETWEEN, IN, IS NULL
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

	// Parse conditions (split by camelCase)
	if remaining.len > 0 {
		mut conds := []string{}
		mut sb := strings.new_builder(64)
		for ch in remaining {
			if ch.is_capital() && sb.len > 0 {
				conds << sb.str()
				sb = strings.new_builder(64)
			}
			sb.write_byte(ch)
		}
		if sb.len > 0 {
			conds << sb.str()
		}

		mut i := 0
		for i < conds.len {
			cond := conds[i]
			if cond == 'And' && i + 1 < conds.len {
				// "And" keyword followed by a property
				i++
				parts.conditions << QueryCondition{
					property: conds[i].to_lower()
				}
			} else if cond == 'Or' && i + 1 < conds.len {
				// "Or" keyword followed by a property
				i++
				parts.conditions << QueryCondition{
					property: conds[i].to_lower()
					logic:    'OR'
				}
			} else if cond == 'And' || cond == 'Or' {
				// Keyword at end — ignore
			} else {
				// Plain property name
				parts.conditions << QueryCondition{
					property: cond.to_lower()
				}
			}
			i++
		}
	}

	return parts
}

// ── V ORM-compatible output ──

// to_where_cond builds a WHERE condition string for V's
// official QueryBuilder.where().
//
// Example: 'name = ? AND age = ?'
pub fn (qp QueryParts) to_where_cond() string {
	if qp.conditions.len == 0 {
		return ''
	}
	mut sb := strings.new_builder(64)
	for i, c in qp.conditions {
		if i > 0 {
			sb.write_string(' ${c.logic} ')
		}
		if c.operator == '=' {
			sb.write_string('${c.property} = ?')
		} else {
			sb.write_string('${c.property} ${c.operator} ?')
		}
	}
	return sb.str()
}

// to_where_params returns the number of `?` placeholders
// in the WHERE condition (useful for validating callers).
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

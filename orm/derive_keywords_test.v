module orm

// derive_keywords_test.v - Tests for expanded derived query keywords (Task B5)
//
// Covers:
//   B5.1: GreaterThan / LessThan / GreaterThanOrEqual / LessThanOrEqual
//   B5.2: Containing / StartingWith / EndingWith (LIKE patterns)
//   B5.3: In / NotIn (IN (...) / NOT IN (...))
//   B5.4: IsNull / IsNotNull (IS NULL / IS NOT NULL)
//   B5.5: OrderBy / TopN (combined with new keywords)
//
// Each test verifies:
//   1. Method name parsing produces correct QueryParts (property + operator)
//   2. SQL generation (to_where_cond) produces correct SQL fragment
//   3. Parameter count is correct (to_where_param_count)
//   4. For IN/NotIn: to_where_cond_with_arrays expands placeholders

// ════════════════════════════════════════════════════════════════
// B5.1: Comparison keywords
// ════════════════════════════════════════════════════════════════

fn test_parse_greater_than() {
	parts := parse_method_name('findByAgeGreaterThan') or { panic(err) }
	assert parts.operation == .find
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == '>'
	where_sql := parts.to_where_cond()
	assert where_sql == 'age > ?'
	assert parts.to_where_param_count() == 1
}

fn test_parse_less_than() {
	parts := parse_method_name('findByAgeLessThan') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == '<'
	where_sql := parts.to_where_cond()
	assert where_sql == 'age < ?'
	assert parts.to_where_param_count() == 1
}

fn test_parse_greater_than_or_equal() {
	parts := parse_method_name('findByAgeGreaterThanOrEqual') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == '>='
	where_sql := parts.to_where_cond()
	assert where_sql == 'age >= ?'
	assert parts.to_where_param_count() == 1
}

fn test_parse_less_than_or_equal() {
	parts := parse_method_name('findByAgeLessThanOrEqual') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == '<='
	where_sql := parts.to_where_cond()
	assert where_sql == 'age <= ?'
	assert parts.to_where_param_count() == 1
}

// Verify that GreaterThanOrEqual is matched greedily (not GreaterThan + Or + Equal)
fn test_greater_than_or_equal_greedy_match() {
	parts := parse_method_name('findByAgeGreaterThanOrEqual') or { panic(err) }
	// Should be a single condition, not split into multiple
	assert parts.conditions.len == 1
	assert parts.conditions[0].operator == '>='
}

// ════════════════════════════════════════════════════════════════
// B5.2: LIKE keywords
// ════════════════════════════════════════════════════════════════

fn test_parse_containing() {
	parts := parse_method_name('findByNameContaining') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'LIKE_CONTAINING'
	where_sql := parts.to_where_cond()
	assert where_sql == "name LIKE '%' || ? || '%'"
	assert parts.to_where_param_count() == 1
}

fn test_parse_starting_with() {
	parts := parse_method_name('findByNameStartingWith') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'LIKE_STARTING'
	where_sql := parts.to_where_cond()
	assert where_sql == "name LIKE ? || '%'"
	assert parts.to_where_param_count() == 1
}

fn test_parse_ending_with() {
	parts := parse_method_name('findByNameEndingWith') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'LIKE_ENDING'
	where_sql := parts.to_where_cond()
	assert where_sql == "name LIKE '%' || ?"
	assert parts.to_where_param_count() == 1
}

// ════════════════════════════════════════════════════════════════
// B5.3: IN keywords
// ════════════════════════════════════════════════════════════════

fn test_parse_in() {
	parts := parse_method_name('findByIdIn') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'id'
	assert parts.conditions[0].operator == 'IN'
	// Basic to_where_cond produces a single placeholder
	where_sql := parts.to_where_cond()
	assert where_sql == 'id IN (?)'
	assert parts.to_where_param_count() == 1
}

fn test_parse_in_with_arrays_expands_placeholders() {
	parts := parse_method_name('findByIdIn') or { panic(err) }
	// to_where_cond_with_arrays expands based on array length
	where_sql := parts.to_where_cond_with_arrays({'id': 3})
	assert where_sql == 'id IN (?, ?, ?)'
	assert parts.to_where_param_count_with_arrays({'id': 3}) == 3
}

fn test_parse_in_with_arrays_single_element() {
	parts := parse_method_name('findByIdIn') or { panic(err) }
	where_sql := parts.to_where_cond_with_arrays({'id': 1})
	assert where_sql == 'id IN (?)'
}

fn test_parse_not_in() {
	parts := parse_method_name('findByIdNotIn') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'id'
	assert parts.conditions[0].operator == 'NOT IN'
	where_sql := parts.to_where_cond()
	assert where_sql == 'id NOT IN (?)'
	assert parts.to_where_param_count() == 1
}

fn test_parse_not_in_with_arrays_expands_placeholders() {
	parts := parse_method_name('findByIdNotIn') or { panic(err) }
	where_sql := parts.to_where_cond_with_arrays({'id': 2})
	assert where_sql == 'id NOT IN (?, ?)'
	assert parts.to_where_param_count_with_arrays({'id': 2}) == 2
}

// ════════════════════════════════════════════════════════════════
// B5.4: NULL keywords
// ════════════════════════════════════════════════════════════════

fn test_parse_is_null() {
	parts := parse_method_name('findByDeletedAtIsNull') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'deleted_at'
	assert parts.conditions[0].operator == 'IS NULL'
	where_sql := parts.to_where_cond()
	assert where_sql == 'deleted_at IS NULL'
	// IS NULL takes no parameter
	assert parts.to_where_param_count() == 0
}

fn test_parse_is_not_null() {
	parts := parse_method_name('findByDeletedAtIsNotNull') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'deleted_at'
	assert parts.conditions[0].operator == 'IS NOT NULL'
	where_sql := parts.to_where_cond()
	assert where_sql == 'deleted_at IS NOT NULL'
	// IS NOT NULL takes no parameter
	assert parts.to_where_param_count() == 0
}

// Verify that IsNotNull is matched greedily (not Is + Not + Null split)
fn test_is_not_null_greedy_match() {
	parts := parse_method_name('findByDeletedAtIsNotNull') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].operator == 'IS NOT NULL'
}

// ════════════════════════════════════════════════════════════════
// B5.5: OrderBy / TopN combined with new keywords
// ════════════════════════════════════════════════════════════════

fn test_parse_combined_greater_than_order_by_name() {
	parts := parse_method_name('findByAgeGreaterThanOrderByName') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == '>'
	assert parts.order_by.len == 1
	assert parts.order_by[0].property == 'name'
	assert parts.order_by[0].direction == 'ASC'
}

fn test_parse_combined_greater_than_order_by_name_desc() {
	parts := parse_method_name('findByAgeGreaterThanOrderByNameDesc') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == '>'
	assert parts.order_by.len == 1
	assert parts.order_by[0].property == 'name'
	assert parts.order_by[0].direction == 'DESC'
}

fn test_parse_top5_order_by_age_desc() {
	parts := parse_method_name('findTop5ByOrderByAgeDesc') or { panic(err) }
	assert parts.operation == .find
	assert parts.limit_val == 5
	assert parts.order_by.len == 1
	assert parts.order_by[0].property == 'age'
	assert parts.order_by[0].direction == 'DESC'
	assert parts.conditions.len == 0
}

fn test_parse_top10_order_by_created_at_desc() {
	parts := parse_method_name('findTop10ByOrderByCreatedAtDesc') or { panic(err) }
	assert parts.limit_val == 10
	assert parts.order_by.len == 1
	assert parts.order_by[0].property == 'created_at'
	assert parts.order_by[0].direction == 'DESC'
}

fn test_parse_order_by_multiple_fields() {
	parts := parse_method_name('findByOrderByLastNameAndFirstNameAsc') or { panic(err) }
	assert parts.order_by.len == 2
	assert parts.order_by[0].property == 'last_name'
	assert parts.order_by[0].direction == 'ASC'
	assert parts.order_by[1].property == 'first_name'
	assert parts.order_by[1].direction == 'ASC'
}

// ════════════════════════════════════════════════════════════════
// Combined: And/Or with new keywords
// ════════════════════════════════════════════════════════════════

fn test_parse_and_with_containing_and_greater_than() {
	parts := parse_method_name('findByNameContainingAndAgeGreaterThan') or { panic(err) }
	assert parts.conditions.len == 2
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'LIKE_CONTAINING'
	assert parts.conditions[0].logic == 'AND'
	assert parts.conditions[1].property == 'age'
	assert parts.conditions[1].operator == '>'
	assert parts.conditions[1].logic == 'AND'
	where_sql := parts.to_where_cond()
	assert where_sql == "name LIKE '%' || ? || '%' AND age > ?"
	assert parts.to_where_param_count() == 2
}

fn test_parse_or_with_starting_and_ending_with() {
	parts := parse_method_name('findByNameStartingWithOrNameEndingWith') or { panic(err) }
	assert parts.conditions.len == 2
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == 'LIKE_STARTING'
	assert parts.conditions[0].logic == 'AND'
	assert parts.conditions[1].property == 'name'
	assert parts.conditions[1].operator == 'LIKE_ENDING'
	assert parts.conditions[1].logic == 'OR'
	where_sql := parts.to_where_cond()
	assert where_sql == "name LIKE ? || '%' OR name LIKE '%' || ?"
}

fn test_parse_or_with_greater_than_or_equal() {
	// Tests that 'Or' inside 'GreaterThanOrEqual' is not mistaken for logic Or
	parts := parse_method_name('findByAgeGreaterThanOrEqualOrAgeLessThan') or { panic(err) }
	assert parts.conditions.len == 2
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == '>='
	assert parts.conditions[0].logic == 'AND'
	assert parts.conditions[1].property == 'age'
	assert parts.conditions[1].operator == '<'
	assert parts.conditions[1].logic == 'OR'
	where_sql := parts.to_where_cond()
	assert where_sql == 'age >= ? OR age < ?'
}

fn test_parse_and_with_is_null_and_is_not_null() {
	parts := parse_method_name('findByDeletedAtIsNullAndCreatedAtIsNotNull') or { panic(err) }
	assert parts.conditions.len == 2
	assert parts.conditions[0].property == 'deleted_at'
	assert parts.conditions[0].operator == 'IS NULL'
	assert parts.conditions[1].property == 'created_at'
	assert parts.conditions[1].operator == 'IS NOT NULL'
	where_sql := parts.to_where_cond()
	assert where_sql == 'deleted_at IS NULL AND created_at IS NOT NULL'
	// No params for IS NULL / IS NOT NULL
	assert parts.to_where_param_count() == 0
}

fn test_parse_and_with_in_and_not_in() {
	parts := parse_method_name('findByIdInAndStatusNotIn') or { panic(err) }
	assert parts.conditions.len == 2
	assert parts.conditions[0].property == 'id'
	assert parts.conditions[0].operator == 'IN'
	assert parts.conditions[1].property == 'status'
	assert parts.conditions[1].operator == 'NOT IN'
	// Expand with array lengths
	where_sql := parts.to_where_cond_with_arrays({'id': 3, 'status': 2})
	assert where_sql == 'id IN (?, ?, ?) AND status NOT IN (?, ?)'
	assert parts.to_where_param_count_with_arrays({'id': 3, 'status': 2}) == 5
}

// ════════════════════════════════════════════════════════════════
// Multi-word property names with keywords
// ════════════════════════════════════════════════════════════════

fn test_parse_multi_word_property_with_greater_than() {
	parts := parse_method_name('findByCreatedAtGreaterThan') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'created_at'
	assert parts.conditions[0].operator == '>'
	where_sql := parts.to_where_cond()
	assert where_sql == 'created_at > ?'
}

fn test_parse_multi_word_property_with_is_null() {
	parts := parse_method_name('findByDeletedAtIsNull') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'deleted_at'
	assert parts.conditions[0].operator == 'IS NULL'
}

fn test_parse_multi_word_property_with_containing() {
	parts := parse_method_name('findByFirstNameContaining') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'first_name'
	assert parts.conditions[0].operator == 'LIKE_CONTAINING'
	where_sql := parts.to_where_cond()
	assert where_sql == "first_name LIKE '%' || ? || '%'"
}

// ════════════════════════════════════════════════════════════════
// Backward compatibility: plain equality (no keyword)
// ════════════════════════════════════════════════════════════════

fn test_parse_plain_equality_backward_compat() {
	parts := parse_method_name('findByName') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == '='
	where_sql := parts.to_where_cond()
	assert where_sql == 'name = ?'
}

fn test_parse_and_plain_equality_backward_compat() {
	parts := parse_method_name('findByNameAndAge') or { panic(err) }
	assert parts.conditions.len == 2
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == '='
	assert parts.conditions[1].property == 'age'
	assert parts.conditions[1].operator == '='
	where_sql := parts.to_where_cond()
	assert where_sql == 'name = ? AND age = ?'
}

fn test_parse_or_plain_equality_backward_compat() {
	parts := parse_method_name('findByNameOrEmail') or { panic(err) }
	assert parts.conditions.len == 2
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[0].operator == '='
	assert parts.conditions[0].logic == 'AND'
	assert parts.conditions[1].property == 'email'
	assert parts.conditions[1].operator == '='
	assert parts.conditions[1].logic == 'OR'
	where_sql := parts.to_where_cond()
	assert where_sql == 'name = ? OR email = ?'
}

// ════════════════════════════════════════════════════════════════
// Count/Exists/Delete operations with new keywords
// ════════════════════════════════════════════════════════════════

fn test_count_with_greater_than() {
	parts := parse_method_name('countByAgeGreaterThan') or { panic(err) }
	assert parts.operation == .count
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'age'
	assert parts.conditions[0].operator == '>'
	assert parts.is_count() == true
}

fn test_exists_with_is_null() {
	parts := parse_method_name('existsByDeletedAtIsNull') or { panic(err) }
	assert parts.operation == .exists
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'deleted_at'
	assert parts.conditions[0].operator == 'IS NULL'
}

fn test_delete_with_in() {
	parts := parse_method_name('deleteByIdIn') or { panic(err) }
	assert parts.operation == .delete_all
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'id'
	assert parts.conditions[0].operator == 'IN'
	assert parts.is_delete() == true
}

// ════════════════════════════════════════════════════════════════
// Edge cases
// ════════════════════════════════════════════════════════════════

fn test_parse_in_not_confused_with_property() {
	// 'In' as the first token should be treated as a property, not a keyword
	parts := parse_method_name('findByInName') or { panic(err) }
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'in_name'
	assert parts.conditions[0].operator == '='
}

fn test_to_where_cond_empty_conditions() {
	parts := QueryParts{}
	assert parts.to_where_cond() == ''
	assert parts.to_where_cond_with_arrays({}) == ''
}

fn test_to_where_cond_with_arrays_no_in_conditions() {
	// to_where_cond_with_arrays should work like to_where_cond for non-IN conditions
	parts := parse_method_name('findByAgeGreaterThan') or { panic(err) }
	where_sql1 := parts.to_where_cond()
	where_sql2 := parts.to_where_cond_with_arrays({})
	assert where_sql1 == where_sql2
	assert where_sql1 == 'age > ?'
}

fn test_param_count_with_arrays_no_in_conditions() {
	parts := parse_method_name('findByAgeGreaterThanAndNameContaining') or { panic(err) }
	count1 := parts.to_where_param_count()
	count2 := parts.to_where_param_count_with_arrays({})
	assert count1 == count2
	assert count1 == 2
}

fn test_combined_in_and_is_null_with_arrays() {
	parts := parse_method_name('findByIdInAndDeletedAtIsNull') or { panic(err) }
	assert parts.conditions.len == 2
	assert parts.conditions[0].operator == 'IN'
	assert parts.conditions[1].operator == 'IS NULL'
	where_sql := parts.to_where_cond_with_arrays({'id': 4})
	// IS NULL contributes no placeholder
	assert where_sql == 'id IN (?, ?, ?, ?) AND deleted_at IS NULL'
	assert parts.to_where_param_count_with_arrays({'id': 4}) == 4
}

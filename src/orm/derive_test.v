module orm

// derive_test.v - Tests for derived query method name parsing

fn test_parse_find_by() {
	parts := parse_method_name('findByName') or { panic(err) }
	assert parts.operation == .find
}

fn test_parse_count_by() {
	parts := parse_method_name('countByStatus') or { panic(err) }
	assert parts.operation == .count
}

fn test_parse_exists_by() {
	parts := parse_method_name('existsByEmail') or { panic(err) }
	assert parts.operation == .exists
}

fn test_parse_delete_by() {
	parts := parse_method_name('deleteByExpired') or { panic(err) }
	assert parts.operation == .delete_all
}

fn test_parse_invalid() {
	_ = parse_method_name('invalidMethod') or { QueryParts{} }
}

fn test_parse_missing_by() {
	_ = parse_method_name('findAll') or { QueryParts{} }
}

fn test_query_parts_to_where_cond() {
	parts := QueryParts{
		operation:  .find
		conditions: [
			QueryCondition{
				property: 'name'
				operator: '='
			},
			QueryCondition{
				property: 'age'
				operator: '>'
				logic:    'AND'
			},
		]
	}
	result := parts.to_where_cond()
	assert result.contains('name = ?')
	assert result.contains('age > ?')
}

fn test_query_parts_to_order() {
	parts := QueryParts{
		operation: .find
		order_by:  [
			OrderPart{
				property:  'created_at'
				direction: 'DESC'
			},
		]
	}
	assert parts.to_order_field() == 'created_at'
	assert parts.to_order_direction() == 'desc'
}

fn test_query_parts_to_limit() {
	parts := QueryParts{
		limit_val: 10
	}
	assert parts.to_limit() == 10
}

fn test_query_parts_no_limit() {
	parts := QueryParts{}
	assert parts.to_limit() == 0
}

fn test_query_parts_empty_where() {
	parts := QueryParts{}
	assert parts.to_where_cond() == ''
	assert parts.to_order_field() == ''
	assert parts.to_limit() == 0
}

fn test_query_parts_param_count() {
	parts := QueryParts{
		conditions: [
			QueryCondition{
				property: 'name'
			},
			QueryCondition{
				property: 'age'
				operator: '>'
			},
		]
	}
	assert parts.to_where_param_count() == 2
}

fn test_query_parts_is_count() {
	parts := QueryParts{
		operation: .count
	}
	assert parts.is_count() == true
}

fn test_query_parts_is_delete() {
	parts := QueryParts{
		operation: .delete_all
	}
	assert parts.is_delete() == true
}

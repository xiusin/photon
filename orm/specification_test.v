module orm

// specification_test.v - Tests for Specification Pattern

fn test_where_eq() {
	spec := where_eq('status', 'active')
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 1
	assert criteria.conditions[0].column == 'status'
	assert criteria.conditions[0].operator == '='
	assert criteria.conditions[0].value == 'active'
}

fn test_where_neq() {
	spec := where_neq('status', 'deleted')
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 1
	assert criteria.conditions[0].operator == '!='
}

fn test_where_gt() {
	spec := where_gt('age', '18')
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == '>'
	assert criteria.conditions[0].value == '18'
}

fn test_where_gte() {
	spec := where_gte('age', '18')
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == '>='
}

fn test_where_lt() {
	spec := where_lt('age', '65')
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == '<'
}

fn test_where_lte() {
	spec := where_lte('age', '65')
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == '<='
}

fn test_where_like() {
	spec := where_like('name', '%Alice%')
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == 'LIKE'
	assert criteria.conditions[0].value == '%Alice%'
}

fn test_where_in() {
	spec := where_in('status', ['active', 'pending'])
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == 'IN'
	assert criteria.conditions[0].value == 'active,pending'
}

fn test_where_null() {
	spec := where_null('deleted_at')
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == 'IS NULL'
}

fn test_where_not_null() {
	spec := where_not_null('email')
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == 'IS NOT NULL'
}

fn test_where_between() {
	spec := where_between('age', '18', '65')
	criteria := spec.to_criteria()
	assert criteria.conditions[0].operator == 'BETWEEN'
	assert criteria.conditions[0].value == '18,65'
}

fn test_spec_and() {
	left := where_eq('status', 'active')
	right := where_gte('age', '18')
	spec := spec_and(left, right)
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 2
	assert criteria.conditions[0].column == 'status'
	assert criteria.conditions[1].column == 'age'
}

fn test_spec_or() {
	left := where_eq('status', 'active')
	right := where_eq('status', 'pending')
	spec := spec_or(left, right)
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 2
	assert criteria.conditions[1].conjunction == .or_
}

fn test_spec_not() {
	inner := where_eq('status', 'deleted')
	spec := spec_not(inner)
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 1
	// NOT wraps the operator, not the column
	assert criteria.conditions[0].column == 'status'
	assert criteria.conditions[0].operator == 'NOT(=)'
	assert criteria.conditions[0].value == 'deleted'
}

fn test_spec_complex() {
	// (status = 'active' AND age >= 18) OR status = 'admin'
	active := where_eq('status', 'active')
	adult := where_gte('age', '18')
	admin := where_eq('status', 'admin')

	spec := spec_or(spec_and(active, adult), admin)
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 3
	assert criteria.conditions[0].column == 'status'
	assert criteria.conditions[0].value == 'active'
	assert criteria.conditions[1].column == 'age'
	assert criteria.conditions[2].column == 'status'
	assert criteria.conditions[2].value == 'admin'
	assert criteria.conditions[2].conjunction == .or_
}

fn test_criteria_to_where_clause() {
	criteria := Criteria{
		conditions: [
			Condition{ column: 'status', operator: '=', value: 'active' },
			Condition{ column: 'age', operator: '>=', value: '18', conjunction: .and_ },
		]
	}

	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE status = ? AND age >= ?'
}

fn test_criteria_params() {
	criteria := Criteria{
		conditions: [
			Condition{ column: 'status', operator: '=', value: 'active' },
			Condition{ column: 'age', operator: '>=', value: '18' },
		]
	}

	params := criteria.params()
	assert params.len == 2
	assert params[0] == 'active'
	assert params[1] == '18'
}

fn test_criteria_empty() {
	criteria := new_criteria()
	assert criteria.is_empty() == true
	assert criteria.to_where_clause() == ''
	assert criteria.params().len == 0
}

fn test_criteria_not_empty() {
	criteria := where_eq('status', 'active').to_criteria()
	assert criteria.is_empty() == false
	assert criteria.to_where_clause() == 'WHERE status = ?'
}

fn test_specification_executor_find() {
	mut executor := new_specification_executor[User](
		fn (criteria Criteria) ![]User {
			assert criteria.conditions.len == 1
			assert criteria.conditions[0].column == 'status'
			return [User{ id: 1, name: 'Alice', status: 'active' }]
		},
		fn (criteria Criteria) !int {
			return 1
		}
	)

	spec := where_eq('status', 'active')
	users := executor.find(spec)!
	assert users.len == 1
	assert users[0].name == 'Alice'
}

fn test_specification_executor_count() {
	mut executor := new_specification_executor[User](
		fn (criteria Criteria) ![]User {
			return []
		},
		fn (criteria Criteria) !int {
			return 42
		}
	)

	spec := where_eq('status', 'active')
	count := executor.count(spec)!
	assert count == 42
}

fn test_specification_executor_exists() {
	mut executor := new_specification_executor[User](
		fn (criteria Criteria) ![]User {
			return []
		},
		fn (criteria Criteria) !int {
			return 1
		}
	)

	spec := where_eq('status', 'active')
	exists := executor.exists(spec)!
	assert exists == true
}

// Test helper struct
struct User {
	id     int
	name   string
	status string
}

// ════════════════════════════════════════════════════════════════
// SQL generation tests for special operators
// ════════════════════════════════════════════════════════════════

fn test_where_clause_is_null() {
	spec := where_null('deleted_at')
	criteria := spec.to_criteria()
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE deleted_at IS NULL'
	params := criteria.params()
	assert params.len == 0 // IS NULL has no parameters
}

fn test_where_clause_is_not_null() {
	spec := where_not_null('email')
	criteria := spec.to_criteria()
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE email IS NOT NULL'
	params := criteria.params()
	assert params.len == 0
}

fn test_where_clause_in() {
	spec := where_in('status', ['active', 'pending', 'review'])
	criteria := spec.to_criteria()
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE status IN (?, ?, ?)'
	params := criteria.params()
	assert params.len == 3
	assert params[0] == 'active'
	assert params[1] == 'pending'
	assert params[2] == 'review'
}

fn test_where_clause_between() {
	spec := where_between('age', '18', '65')
	criteria := spec.to_criteria()
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE age BETWEEN ? AND ?'
	params := criteria.params()
	assert params.len == 2
	assert params[0] == '18'
	assert params[1] == '65'
}

fn test_where_clause_not_eq() {
	spec := spec_not(where_eq('status', 'deleted'))
	criteria := spec.to_criteria()
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE NOT (status = ?)'
	params := criteria.params()
	assert params.len == 1
	assert params[0] == 'deleted'
}

fn test_where_clause_not_is_null() {
	// NOT(IS NULL) should produce IS NOT NULL
	spec := spec_not(where_null('deleted_at'))
	criteria := spec.to_criteria()
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE deleted_at IS NOT NULL'
	params := criteria.params()
	assert params.len == 0
}

fn test_where_clause_not_in() {
	// NOT(IN) should produce NOT IN
	spec := spec_not(where_in('status', ['deleted', 'banned']))
	criteria := spec.to_criteria()
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE status NOT IN (?, ?)'
	params := criteria.params()
	assert params.len == 2
	assert params[0] == 'deleted'
	assert params[1] == 'banned'
}

fn test_where_clause_not_between() {
	spec := spec_not(where_between('age', '18', '65'))
	criteria := spec.to_criteria()
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE NOT (age BETWEEN ? AND ?)'
	params := criteria.params()
	assert params.len == 2
	assert params[0] == '18'
	assert params[1] == '65'
}

fn test_where_clause_combined_special_operators() {
	// Combine IS NULL, BETWEEN, and IN in one criteria
	criteria := Criteria{
		conditions: [
			Condition{ column: 'email', operator: 'IS NOT NULL' },
			Condition{ column: 'age', operator: 'BETWEEN', value: '18,65' },
			Condition{ column: 'status', operator: 'IN', value: 'active,pending' },
		]
	}
	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE email IS NOT NULL AND age BETWEEN ? AND ? AND status IN (?, ?)'
	params := criteria.params()
	assert params.len == 4
	assert params == ['18', '65', 'active', 'pending']
}

// ════════════════════════════════════════════════════════════════
// Composite specification conjunction preservation tests
// ════════════════════════════════════════════════════════════════

fn test_or_with_and_right_side() {
	// A OR (B AND C) → should produce: a = ? OR b = ? AND c = ?
	// NOT: a = ? OR b = ? OR c = ?  (bug would override inner AND to OR)
	a := where_eq('a', '1')
	b := where_eq('b', '2')
	c := where_eq('c', '3')
	spec := spec_or(a, spec_and(b, c))
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 3
	// First condition: a (no conjunction needed, it's first)
	// Second condition: b, joined with OR (first of right side)
	assert criteria.conditions[1].conjunction == .or_
	// Third condition: c, should keep its original AND from inner AndSpec
	assert criteria.conditions[2].conjunction == .and_

	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE a = ? OR b = ? AND c = ?'
}

fn test_and_with_or_left_side() {
	// (A OR B) AND C → should produce: a = ? OR b = ? AND c = ?
	// NOT: a = ? AND b = ? AND c = ?  (bug would override inner OR to AND)
	a := where_eq('a', '1')
	b := where_eq('b', '2')
	c := where_eq('c', '3')
	spec := spec_and(spec_or(a, b), c)
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 3
	// First condition: a (no conjunction, it's first)
	// Second condition: b, should keep its OR from inner OrSpec
	assert criteria.conditions[1].conjunction == .or_
	// Third condition: c, joined with AND (first of right side)
	assert criteria.conditions[2].conjunction == .and_

	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE a = ? OR b = ? AND c = ?'
}

fn test_or_with_and_both_sides() {
	// (A AND B) OR (C AND D) → should produce: a = ? AND b = ? OR c = ? AND d = ?
	// NOT: a = ? AND b = ? OR c = ? OR d = ?  (bug would override right inner ANDs)
	a := where_eq('a', '1')
	b := where_eq('b', '2')
	c := where_eq('c', '3')
	d := where_eq('d', '4')
	spec := spec_or(spec_and(a, b), spec_and(c, d))
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 4
	// 0: a (first, no conjunction)
	// 1: b, AND from inner AndSpec
	assert criteria.conditions[1].conjunction == .and_
	// 2: c, OR (first of right side, joins with left)
	assert criteria.conditions[2].conjunction == .or_
	// 3: d, AND from inner AndSpec (NOT overridden to OR)
	assert criteria.conditions[3].conjunction == .and_

	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE a = ? AND b = ? OR c = ? AND d = ?'
}

fn test_and_with_or_both_sides() {
	// (A OR B) AND (C OR D) → should produce: a = ? OR b = ? AND c = ? OR d = ?
	a := where_eq('a', '1')
	b := where_eq('b', '2')
	c := where_eq('c', '3')
	d := where_eq('d', '4')
	spec := spec_and(spec_or(a, b), spec_or(c, d))
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 4
	// 0: a (first)
	// 1: b, OR from inner OrSpec
	assert criteria.conditions[1].conjunction == .or_
	// 2: c, AND (first of right side, joins with left)
	assert criteria.conditions[2].conjunction == .and_
	// 3: d, OR from inner OrSpec (NOT overridden to AND)
	assert criteria.conditions[3].conjunction == .or_

	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE a = ? OR b = ? AND c = ? OR d = ?'
}

fn test_nested_or_in_and_in_or() {
	// A OR (B AND (C OR D)) → a = ? OR b = ? AND c = ? OR d = ?
	a := where_eq('a', '1')
	b := where_eq('b', '2')
	c := where_eq('c', '3')
	d := where_eq('d', '4')
	spec := spec_or(a, spec_and(b, spec_or(c, d)))
	criteria := spec.to_criteria()
	assert criteria.conditions.len == 4
	// 0: a (first)
	// 1: b, OR (first of right side of outer OrSpec)
	assert criteria.conditions[1].conjunction == .or_
	// 2: c, AND (first of right side of inner AndSpec)
	assert criteria.conditions[2].conjunction == .and_
	// 3: d, OR from innermost OrSpec
	assert criteria.conditions[3].conjunction == .or_

	where_clause := criteria.to_where_clause()
	assert where_clause == 'WHERE a = ? OR b = ? AND c = ? OR d = ?'
}

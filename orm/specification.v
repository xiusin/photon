module orm

// specification.v - Specification Pattern for Dynamic Queries
//
// Provides a composable, type-safe query specification pattern inspired by
// Spring Data JPA's Specification API and the Domain-Driven Design
// Specification pattern.
//
// ── Design ──
//
// A Specification encapsulates a query predicate that can be combined
// with other specifications using logical operators (AND, OR, NOT).
// The specification is translated to a Criteria object containing
// WHERE clause fragments and bound parameters.
//
// Spring equivalent: org.springframework.data.jpa.domain.Specification
// DDD equivalent: Specification pattern (Eric Evans, Martin Fowler)
//
// ── Usage ──
//
//   // Define specifications:
//   fn active_users() orm.Specification {
//       return orm.where_eq('status', 'active')
//   }
//
//   fn users_by_age(min int, max int) orm.Specification {
//       return orm.spec_and(orm.where_gte('age', min.str()), orm.where_lte('age', max.str()))
//   }
//
//   // Combine specifications:
//   spec := orm.spec_and(active_users(), users_by_age(18, 65))
//
//   // Execute via repository:
//   users := executor.find(spec)!

// ── Criteria ──

// Conjunction defines how multiple conditions are joined.
pub enum Conjunction {
	and_ // logical AND (default)
	or_  // logical OR
}

// str returns a human-readable conjunction name.
pub fn (c Conjunction) str() string {
	return match c {
		.and_ { 'AND' }
		.or_ { 'OR' }
	}
}

// Condition represents a single WHERE clause fragment.
pub struct Condition {
pub mut:
	column      string // e.g., 'status', 'age'
	operator    string // e.g., '=', '>=', 'LIKE', 'IN'
	value       string // the bound parameter value (as string)
	conjunction Conjunction = .and_ // how this condition joins with the previous one
}

// Criteria is the compiled output of a Specification — a list of
// conditions with their bound parameters, ready to be translated
// into a SQL WHERE clause.
pub struct Criteria {
pub mut:
	conditions []Condition
}

// new_criteria creates an empty Criteria.
pub fn new_criteria() Criteria {
	return Criteria{
		conditions: []Condition{}
	}
}

// is_empty returns true if no conditions are defined.
pub fn (c &Criteria) is_empty() bool {
	return c.conditions.len == 0
}

// to_where_clause converts the criteria to a SQL WHERE clause string
// with positional ? placeholders. Returns empty string if no conditions.
//
// Handles special operators:
//   - IS NULL / IS NOT NULL: no ? placeholder
//   - IN: generates (?, ?, ...) with one ? per value
//   - BETWEEN: generates BETWEEN ? AND ?
//
// Example output: "WHERE status = ? AND age >= ? AND age <= ?"
pub fn (c &Criteria) to_where_clause() string {
	if c.conditions.len == 0 {
		return ''
	}
	mut result := 'WHERE '
	for i, cond in c.conditions {
		if i > 0 {
			result += ' ${cond.conjunction.str()} '
		}
		if cond.operator == 'IS NULL' || cond.operator == 'IS NOT NULL' {
			result += '${cond.column} ${cond.operator}'
		} else if cond.operator == 'IN' {
			vals := cond.value.split(',')
			placeholders := vals.map(it.trim_space()).filter(it.len > 0).map(|_| '?').join(', ')
			result += '${cond.column} IN (${placeholders})'
		} else if cond.operator == 'BETWEEN' {
			result += '${cond.column} BETWEEN ? AND ?'
		} else if cond.operator.starts_with('NOT(') {
			// NotSpecification: operator is 'NOT(<original_op>)'
			inner_op := cond.operator[4..cond.operator.len - 1]
			if inner_op == 'IS NULL' {
				result += '${cond.column} IS NOT NULL'
			} else if inner_op == 'IS NOT NULL' {
				result += '${cond.column} IS NULL'
			} else if inner_op == 'IN' {
				vals := cond.value.split(',')
				placeholders := vals.map(it.trim_space()).filter(it.len > 0).map(|_| '?').join(', ')
				result += '${cond.column} NOT IN (${placeholders})'
			} else if inner_op == 'BETWEEN' {
				result += 'NOT (${cond.column} BETWEEN ? AND ?)'
			} else {
				result += 'NOT (${cond.column} ${inner_op} ?)'
			}
		} else {
			result += '${cond.column} ${cond.operator} ?'
		}
	}
	return result
}

// params returns the list of parameter values in order.
// Handles special operators:
//   - IS NULL / IS NOT NULL: no parameter added
//   - IN: multiple parameters (one per value)
//   - BETWEEN: two parameters (low, high)
pub fn (c &Criteria) params() []string {
	mut result := []string{cap: c.conditions.len}
	for cond in c.conditions {
		if cond.operator == 'IS NULL' || cond.operator == 'IS NOT NULL' {
			continue // no parameter for IS NULL / IS NOT NULL
		}
		if cond.operator == 'IN' {
			vals := cond.value.split(',').map(it.trim_space()).filter(it.len > 0)
			result << vals
		} else if cond.operator == 'BETWEEN' {
			parts := cond.value.split(',')
			if parts.len >= 2 {
				result << parts[0].trim_space()
				result << parts[1].trim_space()
			}
		} else if cond.operator.starts_with('NOT(') {
			// NotSpecification: extract inner operator and handle params
			inner_op := cond.operator[4..cond.operator.len - 1]
			if inner_op == 'IS NULL' || inner_op == 'IS NOT NULL' {
				continue // NOT(IS NULL) → IS NOT NULL, no param
			} else if inner_op == 'IN' {
				vals := cond.value.split(',').map(it.trim_space()).filter(it.len > 0)
				result << vals
			} else if inner_op == 'BETWEEN' {
				parts := cond.value.split(',')
				if parts.len >= 2 {
					result << parts[0].trim_space()
					result << parts[1].trim_space()
				}
			} else {
				result << cond.value
			}
		} else {
			result << cond.value
		}
	}
	return result
}

// ── Specification Interface ──

// Specification is the interface for composable query predicates.
//
// Note: This interface is intentionally non-generic. The `to_criteria()`
// method returns a `Criteria` which is type-agnostic — the entity type
// safety is enforced by `SpecificationExecutor[T]` which knows the
// concrete entity type.
//
// Spring equivalent: org.springframework.data.jpa.domain.Specification<T>
pub interface Specification {
	to_criteria() Criteria
}

// ── Built-in Specification Implementations ──

// EqSpecification matches entities where column = value.
@[heap]
pub struct EqSpecification {
pub:
	column string
	value  string
}

pub fn (s &EqSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: '='
			value:    s.value
		}]
	}
}

// NotEqSpecification matches entities where column != value.
@[heap]
pub struct NotEqSpecification {
pub:
	column string
	value  string
}

pub fn (s &NotEqSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: '!='
			value:    s.value
		}]
	}
}

// GtSpecification matches entities where column > value.
@[heap]
pub struct GtSpecification {
pub:
	column string
	value  string
}

pub fn (s &GtSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: '>'
			value:    s.value
		}]
	}
}

// GteSpecification matches entities where column >= value.
@[heap]
pub struct GteSpecification {
pub:
	column string
	value  string
}

pub fn (s &GteSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: '>='
			value:    s.value
		}]
	}
}

// LtSpecification matches entities where column < value.
@[heap]
pub struct LtSpecification {
pub:
	column string
	value  string
}

pub fn (s &LtSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: '<'
			value:    s.value
		}]
	}
}

// LteSpecification matches entities where column <= value.
@[heap]
pub struct LteSpecification {
pub:
	column string
	value  string
}

pub fn (s &LteSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: '<='
			value:    s.value
		}]
	}
}

// LikeSpecification matches entities where column LIKE pattern.
@[heap]
pub struct LikeSpecification {
pub:
	column  string
	pattern string
}

pub fn (s &LikeSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: 'LIKE'
			value:    s.pattern
		}]
	}
}

// InSpecification matches entities where column IN (values).
@[heap]
pub struct InSpecification {
pub:
	column string
	values []string
}

pub fn (s &InSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: 'IN'
			value:    s.values.join(',')
		}]
	}
}

// IsNullSpecification matches entities where column IS NULL.
@[heap]
pub struct IsNullSpecification {
pub:
	column string
}

pub fn (s &IsNullSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: 'IS NULL'
			value:    ''
		}]
	}
}

// IsNotNullSpecification matches entities where column IS NOT NULL.
@[heap]
pub struct IsNotNullSpecification {
pub:
	column string
}

pub fn (s &IsNotNullSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: 'IS NOT NULL'
			value:    ''
		}]
	}
}

// BetweenSpecification matches entities where column BETWEEN low AND high.
@[heap]
pub struct BetweenSpecification {
pub:
	column string
	low    string
	high   string
}

pub fn (s &BetweenSpecification) to_criteria() Criteria {
	return Criteria{
		conditions: [Condition{
			column:   s.column
			operator: 'BETWEEN'
			value:    '${s.low},${s.high}'
		}]
	}
}

// ── Composite Specifications ──

// AndSpecification combines two specifications with logical AND.
@[heap]
pub struct AndSpecification {
pub:
	left  &Specification = unsafe { nil }
	right &Specification = unsafe { nil }
}

pub fn (s &AndSpecification) to_criteria() Criteria {
	mut result := new_criteria()
	if !isnil(s.left) {
		left_criteria := s.left.to_criteria()
		for cond in left_criteria.conditions {
			result.conditions << cond
		}
	}
	if !isnil(s.right) {
		right_criteria := s.right.to_criteria()
		for i, cond in right_criteria.conditions {
			mut c := cond
			// Only the first condition from the right side gets AND
			// to join with the left side. Subsequent conditions keep
			// their original conjunctions (e.g., OR from an inner OrSpec).
			if i == 0 && result.conditions.len > 0 {
				c.conjunction = .and_
			}
			result.conditions << c
		}
	}
	return result
}

// OrSpecification combines two specifications with logical OR.
@[heap]
pub struct OrSpecification {
pub:
	left  &Specification = unsafe { nil }
	right &Specification = unsafe { nil }
}

pub fn (s &OrSpecification) to_criteria() Criteria {
	mut result := new_criteria()
	if !isnil(s.left) {
		left_criteria := s.left.to_criteria()
		for cond in left_criteria.conditions {
			result.conditions << cond
		}
	}
	if !isnil(s.right) {
		right_criteria := s.right.to_criteria()
		for i, cond in right_criteria.conditions {
			mut c := cond
			// Only the first condition from the right side gets OR
			// to join with the left side. Subsequent conditions keep
			// their original conjunctions (e.g., AND from an inner AndSpec).
			if i == 0 && result.conditions.len > 0 {
				c.conjunction = .or_
			}
			result.conditions << c
		}
	}
	return result
}

// NotSpecification negates a specification.
@[heap]
pub struct NotSpecification {
pub:
	inner &Specification = unsafe { nil }
}

pub fn (s &NotSpecification) to_criteria() Criteria {
	if isnil(s.inner) {
		return new_criteria()
	}
	inner_criteria := s.inner.to_criteria()
	mut result := new_criteria()
	for cond in inner_criteria.conditions {
		// Wrap the operator in NOT(...) to indicate negation.
		// The to_where_clause() and params() methods handle this
		// specially to produce correct SQL.
		// Examples: '=' → 'NOT(=)' → 'NOT (column = ?)'
		//           'IS NULL' → 'NOT(IS NULL)' → 'IS NOT NULL'
		result.conditions << Condition{
			column:      cond.column
			operator:    'NOT(${cond.operator})'
			value:       cond.value
			conjunction: cond.conjunction
		}
	}
	return result
}

// ── Fluent Specification Builders ──

// where_eq creates a specification matching column = value.
pub fn where_eq(column string, value string) &EqSpecification {
	return &EqSpecification{ column: column, value: value }
}

// where_neq creates a specification matching column != value.
pub fn where_neq(column string, value string) &NotEqSpecification {
	return &NotEqSpecification{ column: column, value: value }
}

// where_gt creates a specification matching column > value.
pub fn where_gt(column string, value string) &GtSpecification {
	return &GtSpecification{ column: column, value: value }
}

// where_gte creates a specification matching column >= value.
pub fn where_gte(column string, value string) &GteSpecification {
	return &GteSpecification{ column: column, value: value }
}

// where_lt creates a specification matching column < value.
pub fn where_lt(column string, value string) &LtSpecification {
	return &LtSpecification{ column: column, value: value }
}

// where_lte creates a specification matching column <= value.
pub fn where_lte(column string, value string) &LteSpecification {
	return &LteSpecification{ column: column, value: value }
}

// where_like creates a specification matching column LIKE pattern.
pub fn where_like(column string, pattern string) &LikeSpecification {
	return &LikeSpecification{ column: column, pattern: pattern }
}

// where_in creates a specification matching column IN (values).
pub fn where_in(column string, values []string) &InSpecification {
	return &InSpecification{ column: column, values: values }
}

// where_null creates a specification matching column IS NULL.
pub fn where_null(column string) &IsNullSpecification {
	return &IsNullSpecification{ column: column }
}

// where_not_null creates a specification matching column IS NOT NULL.
pub fn where_not_null(column string) &IsNotNullSpecification {
	return &IsNotNullSpecification{ column: column }
}

// where_between creates a specification matching column BETWEEN low AND high.
pub fn where_between(column string, low string, high string) &BetweenSpecification {
	return &BetweenSpecification{ column: column, low: low, high: high }
}

// ── Composition Helpers ──

// spec_and combines two specifications with AND.
pub fn spec_and(left &Specification, right &Specification) &AndSpecification {
	return &AndSpecification{ left: left, right: right }
}

// spec_or combines two specifications with OR.
pub fn spec_or(left &Specification, right &Specification) &OrSpecification {
	return &OrSpecification{ left: left, right: right }
}

// spec_not negates a specification.
pub fn spec_not(inner &Specification) &NotSpecification {
	return &NotSpecification{ inner: inner }
}

// ── Specification Executor ──
//
// SpecificationExecutor provides methods for executing queries with
// specifications. It is designed to be embedded in repository structs.
//
// Spring equivalent: org.springframework.data.jpa.repository.JpaSpecificationExecutor

pub struct SpecificationExecutor[T] {
pub mut:
	exec_find_by_criteria fn (criteria Criteria) ![]T = unsafe { nil }
	exec_count_by_criteria fn (criteria Criteria) !int  = unsafe { nil }
}

// new_specification_executor creates a SpecificationExecutor with
// the given callback functions.
pub fn new_specification_executor[T](find_fn fn (criteria Criteria) ![]T, count_fn fn (criteria Criteria) !int) SpecificationExecutor[T] {
	return SpecificationExecutor[T]{
		exec_find_by_criteria: find_fn
		exec_count_by_criteria: count_fn
	}
}

// find retrieves all entities matching the specification.
pub fn (mut se SpecificationExecutor[T]) find(spec &Specification) ![]T {
	if isnil(se.exec_find_by_criteria) {
		return error('SpecificationExecutor.find: exec_find_by_criteria callback not configured')
	}
	criteria := spec.to_criteria()
	return se.exec_find_by_criteria(criteria)
}

// find_all retrieves all entities matching the criteria directly.
pub fn (mut se SpecificationExecutor[T]) find_all(criteria Criteria) ![]T {
	if isnil(se.exec_find_by_criteria) {
		return error('SpecificationExecutor.find_all: exec_find_by_criteria callback not configured')
	}
	return se.exec_find_by_criteria(criteria)
}

// count returns the number of entities matching the specification.
pub fn (mut se SpecificationExecutor[T]) count(spec &Specification) !int {
	if isnil(se.exec_count_by_criteria) {
		return error('SpecificationExecutor.count: exec_count_by_criteria callback not configured')
	}
	criteria := spec.to_criteria()
	return se.exec_count_by_criteria(criteria)
}

// exists returns true if any entity matches the specification.
pub fn (mut se SpecificationExecutor[T]) exists(spec &Specification) !bool {
	count := se.count(spec)!
	return count > 0
}

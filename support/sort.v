module support

// sort.v - Sort + Pageable (Spring Data inspired)

// Direction for sorting
pub enum Direction {
	asc
	desc
}

// SortOrder represents a single sort ordering
pub struct SortOrder {
pub mut:
	property  string
	direction Direction = .asc
}

// Sort collects multiple SortOrder entries
pub struct Sort {
pub:
	orders []SortOrder
}

// by creates a Sort for a single property ascending
pub fn by(property string) Sort {
	return Sort{
		orders: [SortOrder{ property: property, direction: .asc }]
	}
}

// by_desc creates a Sort for a single property descending
pub fn by_desc(property string) Sort {
	return Sort{
		orders: [SortOrder{ property: property, direction: .desc }]
	}
}

// ascending returns a copy with all orders set to ascending
pub fn (s Sort) ascending() Sort {
	mut orders := s.orders.clone()
	mut i := 0
	for i < orders.len {
		orders[i].direction = .asc
		i++
	}
	return Sort{
		orders: orders
	}
}

// descending returns a copy with all orders set to descending
pub fn (s Sort) descending() Sort {
	mut orders := s.orders.clone()
	mut i := 0
	for i < orders.len {
		orders[i].direction = .desc
		i++
	}
	return Sort{
		orders: orders
	}
}

// and combines two sorts
pub fn (s Sort) and(other Sort) Sort {
	mut orders := s.orders.clone()
	orders << other.orders
	return Sort{
		orders: orders
	}
}

// is_empty checks if no orders are defined
pub fn (s Sort) is_empty() bool {
	return s.orders.len == 0
}

// is_sorted checks if any orders are defined
pub fn (s Sort) is_sorted() bool {
	return s.orders.len > 0
}

// to_sql converts sort orders to SQL ORDER BY clause
pub fn (s Sort) to_sql() string {
	if s.orders.len == 0 {
		return ''
	}
	mut result := ' ORDER BY '
	for i, order in s.orders {
		if i > 0 {
			result += ', '
		}
		dir := if order.direction == .asc { 'ASC' } else { 'DESC' }
		result += '${order.property} ${dir}'
	}
	return result
}

// Pageable is the interface for pagination requests.
// PageRequest implements this interface.
//
// Spring equivalent: org.springframework.data.domain.Pageable
pub interface Pageable {
	get_page_number() int
	get_page_size() int
	get_offset() int
	get_sort() Sort
	has_previous() bool
}

// unsorted creates a Sort with no orders (empty sort).
pub fn unsorted() Sort {
	return Sort{
		orders: []
	}
}

// and_sort returns a new Sort combining this sort with another.
// Alias for and() — provides a more readable DSL.
pub fn (s Sort) and_sort(other Sort) Sort {
	return s.and(other)
}

// PageRequest represents a pagination request
pub struct PageRequest {
pub:
	page int
	size int
	sort Sort
}

// page_request creates a PageRequest
pub fn page_request(page int, size int) PageRequest {
	return PageRequest{
		page: page
		size: size
	}
}

// page_request_with_sort creates a PageRequest with sort
pub fn page_request_with_sort(page int, size int, sort Sort) PageRequest {
	return PageRequest{
		page: page
		size: size
		sort: sort
	}
}

// of creates a PageRequest (Spring-style static factory)
pub fn (pr PageRequest) of(page int, size int, sort Sort) PageRequest {
	return page_request_with_sort(page, size, sort)
}

// get_offset returns the SQL offset
pub fn (pr PageRequest) get_offset() int {
	if pr.page < 1 {
		return 0
	}
	return (pr.page - 1) * pr.size
}

// get_page_number returns the 1-based page number
pub fn (pr PageRequest) get_page_number() int {
	return pr.page
}

// get_page_size returns the page size
pub fn (pr PageRequest) get_page_size() int {
	return pr.size
}

// get_sort returns the sort configuration
pub fn (pr PageRequest) get_sort() Sort {
	return pr.sort
}

// has_previous checks if there's a previous page
pub fn (pr PageRequest) has_previous() bool {
	return pr.page > 1
}

// next returns a PageRequest for the next page
pub fn (pr PageRequest) next() PageRequest {
	return PageRequest{
		page: pr.page + 1
		size: pr.size
		sort: pr.sort
	}
}

// previous returns a PageRequest for the previous page
pub fn (pr PageRequest) previous() PageRequest {
	mut p := pr.page - 1
	if p < 1 {
		p = 1
	}
	return PageRequest{
		page: p
		size: pr.size
		sort: pr.sort
	}
}

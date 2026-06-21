module support

// sort_test.v - Tests for Sort and PageRequest

fn test_sort_by_asc() {
	s := by('name')
	assert s.is_sorted()
	assert s.orders.len == 1
	assert s.orders[0].property == 'name'
	assert s.orders[0].direction == .asc
}

fn test_sort_by_desc() {
	s := by_desc('created_at')
	assert s.orders[0].direction == .desc
}

fn test_sort_ascending() {
	s := by_desc('price').ascending()
	assert s.orders[0].direction == .asc
}

fn test_sort_descending() {
	s := by('name').descending()
	assert s.orders[0].direction == .desc
}

fn test_sort_and() {
	s := by('name').and(by_desc('age'))
	assert s.orders.len == 2
	assert s.orders[0].property == 'name'
	assert s.orders[1].property == 'age'
}

fn test_sort_is_empty() {
	s := Sort{}
	assert s.is_empty()
	assert s.is_sorted() == false
}

fn test_sort_to_string() {
	s := by('name')
	result := s.to_sql()
	assert result.contains('ORDER BY')
	assert result.contains('name')
}

fn test_sort_to_string_multi() {
	s := by('name').and(by_desc('created_at'))
	result := s.to_sql()
	assert result.contains('name ASC')
	assert result.contains('created_at DESC')
}

fn test_page_request_new() {
	pr := page_request(1, 10)
	assert pr.page == 1
	assert pr.size == 10
	assert pr.get_offset() == 0
}

fn test_page_request_offset() {
	pr := page_request(3, 10)
	assert pr.get_offset() == 20
}

fn test_page_request_with_sort() {
	pr := page_request_with_sort(1, 20, by_desc('id'))
	assert pr.sort.is_sorted()
}

fn test_page_request_next_previous() {
	pr := page_request(2, 10)
	assert pr.next().page == 3
	assert pr.previous().page == 1
}

fn test_page_request_first_page() {
	pr := page_request(1, 10)
	assert pr.has_previous() == false
}

fn test_page_request_zero_page() {
	pr := page_request(0, 10)
	assert pr.get_offset() == 0
}

module support

// pagination_test.v - Tests for LengthAwarePaginator

fn test_paginator_new() {
	items := ['a', 'b', 'c']
	p := new_paginator(items, 30, 10, 1)
	assert p.total == 30
	assert p.per_page == 10
	assert p.current_page == 1
	assert p.last_page == 3
	assert p.count() == 3
}

fn test_paginator_single_page() {
	items := ['x', 'y']
	p := new_paginator(items, 2, 10, 1)
	assert p.total == 2
	assert p.last_page == 1
	assert p.has_more_pages() == false
	assert p.on_first_page()
	assert p.on_last_page()
}

fn test_paginator_has_more() {
	p := new_paginator(['a'], 25, 10, 1)
	assert p.has_more_pages()
	assert p.on_last_page() == false
	assert p.from() == 1
	assert p.to() == 1
}

fn test_paginator_last_page() {
	p := new_paginator(['a', 'b'], 25, 10, 3)
	assert p.on_last_page()
	assert p.has_more_pages() == false
	assert p.current_page == 3
}

fn test_paginator_from_to() {
	p := new_paginator(['a', 'b', 'c'], 25, 10, 2)
	assert p.from() == 11
	assert p.to() == 13
}

fn test_paginator_empty_page() {
	items := []string{}
	p := new_paginator(items, 25, 10, 1)
	assert p.from() == 0
	assert p.to() == 0
	assert p.count() == 0
}

fn test_paginator_next_prev_urls() {
	mut p := new_paginator(['a'], 30, 10, 2)
	p.path = '/api/users'
	assert p.next_page_url() == '/api/users?page=3&per_page=10'
	assert p.prev_page_url() == '/api/users?page=1&per_page=10'
}

fn test_paginator_first_page_no_prev() {
	mut p := new_paginator(['a', 'b'], 30, 10, 1)
	p.path = '/api/items'
	assert p.prev_page_url() == ''
	assert p.next_page_url().len > 0
}

fn test_paginator_last_page_no_next() {
	mut p := new_paginator(['a'], 30, 10, 3)
	p.path = '/api/items'
	assert p.next_page_url() == ''
	assert p.prev_page_url().len > 0
}

fn test_paginator_to_json() {
	p := new_paginator(['item1', 'item2'], 10, 5, 1)
	json_result := p.to_json()
	assert json_result.contains('"total":10')
	assert json_result.contains('"per_page":5')
	assert json_result.contains('"current_page":1')
	assert json_result.contains('"last_page":2')
	assert json_result.contains('"data"')
}

fn test_paginator_exact_division() {
	// total = 50, per_page = 10 => exactly 5 pages
	p := new_paginator(['x'], 50, 10, 1)
	assert p.last_page == 5
}

fn test_paginator_uneven_division() {
	// total = 51, per_page = 10 => 6 pages
	p := new_paginator(['x'], 51, 10, 1)
	assert p.last_page == 6
}

fn test_simple_paginator_new() {
	items := ['a', 'b']
	p := new_simple_paginator(items, 10, 1, true)
	assert p.per_page == 10
	assert p.current_page == 1
	assert p.has_more
	assert p.items.len == 2
}

fn test_simple_paginator_no_more() {
	p := new_simple_paginator(['x'], 10, 1, false)
	assert p.has_more == false
}

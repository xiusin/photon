module support

// pagination.v - Pagination (Laravel Paginator inspired)

// LengthAwarePaginator provides full pagination with total count
pub struct LengthAwarePaginator[T] {
pub:
	items       []T
	total       int
	per_page    int
	current_page int
	last_page   int
pub mut:
	path        string
}

// new_paginator creates a new LengthAwarePaginator
pub fn new_paginator[T](items []T, total int, per_page int, current_page int) &LengthAwarePaginator[T] {
	mut last := total / per_page
	if total % per_page != 0 {
		last++
	}
	if last < 1 {
		last = 1
	}
	return &LengthAwarePaginator[T]{
		items: items
		total: total
		per_page: per_page
		current_page: current_page
		last_page: last
	}
}

// has_more_pages checks if there are more pages
pub fn (p &LengthAwarePaginator[T]) has_more_pages() bool {
	return p.current_page < p.last_page
}

// on_first_page checks if on the first page
pub fn (p &LengthAwarePaginator[T]) on_first_page() bool {
	return p.current_page == 1
}

// on_last_page checks if on the last page
pub fn (p &LengthAwarePaginator[T]) on_last_page() bool {
	return p.current_page >= p.last_page
}

// count returns the number of items on this page
pub fn (p &LengthAwarePaginator[T]) count() int {
	return p.items.len
}

// from returns the starting index
pub fn (p &LengthAwarePaginator[T]) from() int {
	if p.items.len == 0 {
		return 0
	}
	return (p.current_page - 1) * p.per_page + 1
}

// to returns the ending index
pub fn (p &LengthAwarePaginator[T]) to() int {
	if p.items.len == 0 {
		return 0
	}
	return p.from() + p.items.len - 1
}

// next_page_url returns the URL for the next page
pub fn (p &LengthAwarePaginator[T]) next_page_url() string {
	if !p.has_more_pages() {
		return ''
	}
	return '${p.path}?page=${p.current_page + 1}&per_page=${p.per_page}'
}

// prev_page_url returns the URL for the previous page
pub fn (p &LengthAwarePaginator[T]) prev_page_url() string {
	if p.on_first_page() {
		return ''
	}
	return '${p.path}?page=${p.current_page - 1}&per_page=${p.per_page}'
}

// to_json serializes to a JSON pagination response
pub fn (p &LengthAwarePaginator[T]) to_json() string {
	items_json := items_to_json(p.items)
	return '{"data":${items_json},"total":${p.total},"per_page":${p.per_page},"current_page":${p.current_page},"last_page":${p.last_page},"from":${p.from()},"to":${p.to()}}'
}

// SimplePaginator provides simple prev/next pagination without total
pub struct SimplePaginator[T] {
pub:
	items       []T
	per_page    int
	current_page int
	has_more    bool
}

// new_simple_paginator creates a SimplePaginator
pub fn new_simple_paginator[T](items []T, per_page int, current_page int, has_more bool) &SimplePaginator[T] {
	return &SimplePaginator[T]{
		items: items
		per_page: per_page
		current_page: current_page
		has_more: has_more
	}
}

// items_to_json converts items to JSON string
fn items_to_json[T](items []T) string {
	if items.len == 0 {
		return '[]'
	}
	mut result := '['
	for i, item in items {
		if i > 0 {
			result += ','
		}
		result += '${item}'
	}
	result += ']'
	return result
}

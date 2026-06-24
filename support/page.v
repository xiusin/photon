module support

// page.v - Page[T] result container for pagination
//
// Pairs with PageRequest (defined in sort.v) to provide a Spring
// Data-style pagination result.  JpaRepository[T].find_all_paged()
// returns a Page[T] containing the page items plus total count and
// navigation metadata.
//
//   page_request := support.page_request(1, 10)
//   page := repo.find_all_paged(page_request)!
//   assert page.items.len == 10
//   assert page.total == 25
//   assert page.total_pages == 3

// Slice[T] is the interface for a slice of data with pagination metadata.
// Page[T] implements this interface.
//
// Spring equivalent: org.springframework.data.domain.Slice<T>
pub interface Slice[T] {
	has_content() bool
	has_next() bool
	has_previous() bool
	get_number() int
	get_size() int
	get_number_of_elements() int
}

// Page[T] represents a single page of results with pagination metadata.
//
// Fields:
//   items        - the entities on this page (may be empty)
//   total        - total number of entities across all pages
//   page_number  - current page number (1-based)
//   page_size    - number of items requested per page
//   total_pages  - total number of pages (ceil(total / page_size), 0 if total == 0)
pub struct Page[T] {
pub:
	items       []T
	total       i64
	page_number int
	page_size   int
	total_pages int
}

// new_page constructs a Page[T] from items, total count, and page info.
// Computes total_pages via ceiling division: (total + page_size - 1) / page_size.
// Returns total_pages = 0 when total == 0.
pub fn new_page[T](items []T, total i64, page_number int, page_size int) Page[T] {
	mut total_pages := 0
	if total > 0 && page_size > 0 {
		total_pages = int((total + page_size - 1) / page_size)
	}
	return Page[T]{
		items:       items
		total:       total
		page_number: page_number
		page_size:   page_size
		total_pages: total_pages
	}
}

// has_content returns true if this page has any items.
pub fn (p Page[T]) has_content() bool {
	return p.items.len > 0
}

// has_next returns true if there is a page after this one.
pub fn (p Page[T]) has_next() bool {
	return p.page_number < p.total_pages
}

// has_previous returns true if there is a page before this one.
pub fn (p Page[T]) has_previous() bool {
	return p.page_number > 1
}

// is_first returns true if this is the first page.
pub fn (p Page[T]) is_first() bool {
	return p.page_number <= 1
}

// is_last returns true if this is the last page.
pub fn (p Page[T]) is_last() bool {
	return p.page_number >= p.total_pages
}

// get_number returns the current page number (1-based).
// Spring equivalent: Slice.getNumber()
pub fn (p Page[T]) get_number() int {
	return p.page_number
}

// get_size returns the requested page size.
// Spring equivalent: Slice.getSize()
pub fn (p Page[T]) get_size() int {
	return p.page_size
}

// get_number_of_elements returns the actual number of elements in this page
// (may be less than page_size on the last page).
// Spring equivalent: Slice.getNumberOfElements()
pub fn (p Page[T]) get_number_of_elements() int {
	return p.items.len
}

// get_total_elements returns the total number of elements across all pages.
// Spring equivalent: Page.getTotalElements()
pub fn (p Page[T]) get_total_elements() i64 {
	return p.total
}

// get_total_pages returns the total number of pages.
// Spring equivalent: Page.getTotalPages()
pub fn (p Page[T]) get_total_pages() int {
	return p.total_pages
}

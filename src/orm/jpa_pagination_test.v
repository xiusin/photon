module orm

import support

// jpa_pagination_test.v - Tests for JpaRepository[T].find_all_paged() (Task B1)
//
// Verifies Spring Data-style pagination:
//   - First / middle / last page content and metadata
//   - Out-of-bounds page returns empty items with correct total
//   - Single-page case (page_size >= total)
//   - ORDER BY sort (ascending and descending)
//   - Edge cases: page_number = 0 (normalized to 1), page_size = 0 (error)
//
// Since photon/orm cannot import db.sqlite (module-name collision with
// V's standard `orm`), these tests use a mock in-memory database backed
// by __global state (compiled with -enable-globals, matching CI).
// The mock handles COUNT(*), SELECT with ORDER BY + LIMIT + OFFSET,
// and INSERT (for test-data setup).

// ── Test entity ──

struct PageTestUser {
pub mut:
	id   i64
	name string
}

// ── Mock in-memory database ──
//
// V function-type callbacks cannot capture state, so the mock uses
// __global variables.  Each test resets state via page_mock_reset().
// The mock is self-contained (does not share state with
// jpa_repository_test.v's mock).

struct PageMockRow {
mut:
	cols   []string
	values []string
}

fn (mut r PageMockRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r PageMockRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_page_rows []PageMockRow
__global g_page_next_id i64
__global g_page_last_query string

fn page_mock_reset() {
	unsafe {
		g_page_rows = []PageMockRow{}
		g_page_next_id = 1
		g_page_last_query = ''
	}
}

fn page_mock_setup[T]() !JpaRepository[T] {
	page_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	return new_jpa_repository[T](om, 'default', 'page_test_table', page_mock_exec, page_mock_query)!
}

// page_mock_exec handles INSERT / CREATE TABLE statements.
fn page_mock_exec(db voidptr, query string, args []string) ! {
	_ = db
	unsafe {
		g_page_last_query = query
	}
	q := query.to_lower()
	if q.starts_with('create table') {
		return
	}
	if q.starts_with('insert into') {
		page_mock_handle_insert(query, args)!
		return
	}
}

fn page_mock_handle_insert(query string, args []string) ! {
	open_paren := query.index('(') or { return error('page_mock: cannot parse INSERT columns') }
	rest := query[open_paren + 1..]
	close_offset := rest.index(')') or { return error('page_mock: cannot parse INSERT columns') }
	cols_str := rest[..close_offset]
	cols := cols_str.split(',').map(it.trim_space())
	mut row := PageMockRow{}
	for i, col in cols {
		if i < args.len {
			row.set(col, args[i])
		}
	}
	// Auto-assign PK if missing or zero
	pk_val := row.get('id')
	if pk_val == '' || pk_val == '0' {
		next := g_page_next_id
		row.set('id', '${next}')
		unsafe {
			g_page_next_id = next + 1
		}
	}
	unsafe {
		g_page_rows << row
	}
}

// page_mock_query handles SELECT statements (including COUNT).
// Supports: SELECT <cols> FROM <table> [ORDER BY <col> <dir>] LIMIT ? OFFSET ?
fn page_mock_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_page_last_query = query
	}
	q := query.to_lower()

	// COUNT(*) query
	if q.contains('count(*)') {
		count := g_page_rows.len
		return [['${count}']]
	}

	// Parse: SELECT <cols> FROM <table> [ORDER BY ...] LIMIT ? OFFSET ?
	after_select := query[7..] // after "SELECT "
	from_idx := after_select.to_lower().index(' from ') or {
		return error('page_mock: cannot parse SELECT: no FROM clause')
	}
	cols_str := after_select[..from_idx]
	cols := cols_str.split(',').map(it.trim_space())

	// Parse ORDER BY clause (if present)
	mut order_col := ''
	mut order_dir := 'asc'
	order_idx := q.index(' order by ') or { -1 }
	if order_idx != -1 {
		order_str := query[order_idx + 10..] // after " order by "
		// ORDER BY clause ends at LIMIT or end of string
		limit_pos := order_str.to_lower().index(' limit ') or { order_str.len }
		order_clause := order_str[..limit_pos].trim_space()
		parts := order_clause.split(' ')
		if parts.len >= 1 {
			order_col = parts[0]
		}
		if parts.len >= 2 {
			order_dir = parts[1].to_lower()
		}
	}

	// Parse LIMIT and OFFSET values from args.
	// Query shape: ... LIMIT ? OFFSET ?  → args = [limit_value, offset_value]
	mut limit := -1
	mut offset := 0
	limit_idx := q.index(' limit ') or { -1 }
	if limit_idx != -1 && args.len >= 1 {
		limit = args[0].int()
		if q.contains(' offset ') && args.len >= 2 {
			offset = args[1].int()
		}
	}

	// Build a mutable copy of rows (apply ordering + slicing)
	mut all_rows := []PageMockRow{cap: g_page_rows.len}
	for row in g_page_rows {
		all_rows << row
	}

	// Apply ORDER BY (simple string-based sort on the order column)
	if order_col != '' {
		page_mock_sort(mut all_rows, order_col, order_dir)
	}

	// Apply OFFSET and LIMIT
	mut result := [][]string{}
	if offset >= all_rows.len {
		return result
	}
	mut end := all_rows.len
	if limit > 0 && offset + limit < end {
		end = offset + limit
	}
	for i in offset .. end {
		row := all_rows[i]
		mut vals := []string{}
		for col in cols {
			vals << row.get(col)
		}
		result << vals
	}
	return result
}

// page_mock_sort sorts rows in-place by the given column.
// Uses a simple insertion sort to avoid closure-capture limitations.
fn page_mock_sort(mut rows []PageMockRow, col string, dir string) {
	n := rows.len
	if n < 2 {
		return
	}
	for i in 1 .. n {
		key := rows[i]
		mut j := i - 1
		for j >= 0 {
			av := rows[j].get(col)
			kv := key.get(col)
			// Compare as integers if both look numeric, else as strings
			mut should_move := false
			if av.len > 0 && av[0].is_digit() && kv.len > 0 && kv[0].is_digit() {
				ai := av.i64()
				ki := kv.i64()
				should_move = if dir == 'desc' { ai < ki } else { ai > ki }
			} else {
				should_move = if dir == 'desc' { av < kv } else { av > kv }
			}
			if should_move {
				rows[j + 1] = rows[j]
				j--
			} else {
				break
			}
		}
		rows[j + 1] = key
	}
}

// ── Test data helper ──
//
// Inserts `count` test users with names 'User1', 'User2', ..., 'UserN'.
// Returns the populated repository.

fn page_setup_with_users(count int) !JpaRepository[PageTestUser] {
	mut repo := page_mock_setup[PageTestUser]()!
	repo.create_table()!
	for i in 1 .. count + 1 {
		repo.save(&PageTestUser{
			name: 'User${i}'
		})!
	}
	return repo
}

// ════════════════════════════════════════════════════════════════
// First page (SubTask B1.4)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_first_page() {
	mut repo := page_setup_with_users(25)!
	page := repo.find_all_paged(support.page_request(1, 10))!
	assert page.items.len == 10
	assert page.total == 25
	assert page.page_number == 1
	assert page.page_size == 10
	assert page.total_pages == 3
	// First page should contain User1..User10
	assert page.items[0].id == 1
	assert page.items[0].name == 'User1'
	assert page.items[9].id == 10
	assert page.items[9].name == 'User10'
	// Navigation helpers
	assert page.is_first()
	assert page.has_next()
	assert !page.has_previous()
}

// ════════════════════════════════════════════════════════════════
// Middle page (SubTask B1.4)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_middle_page() {
	mut repo := page_setup_with_users(25)!
	page := repo.find_all_paged(support.page_request(2, 10))!
	assert page.items.len == 10
	assert page.total == 25
	assert page.page_number == 2
	assert page.total_pages == 3
	// Middle page should contain User11..User20
	assert page.items[0].id == 11
	assert page.items[0].name == 'User11'
	assert page.items[9].id == 20
	assert page.items[9].name == 'User20'
	// Navigation helpers
	assert !page.is_first()
	assert !page.is_last()
	assert page.has_next()
	assert page.has_previous()
}

// ════════════════════════════════════════════════════════════════
// Last page (partial) (SubTask B1.4)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_last_page_partial() {
	mut repo := page_setup_with_users(25)!
	page := repo.find_all_paged(support.page_request(3, 10))!
	assert page.items.len == 5
	assert page.total == 25
	assert page.page_number == 3
	assert page.total_pages == 3
	// Last page should contain User21..User25
	assert page.items[0].id == 21
	assert page.items[0].name == 'User21'
	assert page.items[4].id == 25
	assert page.items[4].name == 'User25'
	// Navigation helpers
	assert page.is_last()
	assert !page.has_next()
	assert page.has_previous()
}

// ════════════════════════════════════════════════════════════════
// Out-of-bounds page (SubTask B1.4)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_out_of_bounds() {
	mut repo := page_setup_with_users(25)!
	page := repo.find_all_paged(support.page_request(4, 10))!
	// Out of bounds: empty items, but total/total_pages still correct
	assert page.items.len == 0
	assert page.total == 25
	assert page.page_number == 4
	assert page.total_pages == 3
	assert !page.has_content()
}

// ════════════════════════════════════════════════════════════════
// Single page (page_size >= total)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_single_page() {
	mut repo := page_setup_with_users(25)!
	page := repo.find_all_paged(support.page_request(1, 25))!
	assert page.items.len == 25
	assert page.total == 25
	assert page.page_number == 1
	assert page.total_pages == 1
	assert page.is_first()
	assert page.is_last()
}

// ════════════════════════════════════════════════════════════════
// Exact division (total % page_size == 0)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_exact_division() {
	mut repo := page_setup_with_users(20)!
	page := repo.find_all_paged(support.page_request(2, 10))!
	assert page.items.len == 10
	assert page.total == 20
	assert page.total_pages == 2
	// Last page of exact division should be full
	assert page.is_last()
	assert !page.has_next()
}

// ════════════════════════════════════════════════════════════════
// Empty table
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_empty_table() {
	mut repo := page_mock_setup[PageTestUser]()!
	repo.create_table()!
	page := repo.find_all_paged(support.page_request(1, 10))!
	assert page.items.len == 0
	assert page.total == 0
	assert page.total_pages == 0
	assert !page.has_content()
}

// ════════════════════════════════════════════════════════════════
// Sorting: ORDER BY id DESC
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_sort_desc() {
	mut repo := page_setup_with_users(25)!
	pr := support.page_request_with_sort(1, 10, support.by_desc('id'))
	page := repo.find_all_paged(pr)!
	assert page.items.len == 10
	assert page.total == 25
	// DESC order: first page should have User25..User16
	assert page.items[0].id == 25
	assert page.items[0].name == 'User25'
	assert page.items[9].id == 16
	assert page.items[9].name == 'User16'
}

// ════════════════════════════════════════════════════════════════
// Sorting: ORDER BY id ASC (explicit)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_sort_asc() {
	mut repo := page_setup_with_users(25)!
	pr := support.page_request_with_sort(1, 10, support.by('id'))
	page := repo.find_all_paged(pr)!
	assert page.items.len == 10
	// ASC order: first page should have User1..User10
	assert page.items[0].id == 1
	assert page.items[9].id == 10
}

// ════════════════════════════════════════════════════════════════
// Sorting: ORDER BY name DESC across pages
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_sort_desc_second_page() {
	mut repo := page_setup_with_users(25)!
	pr := support.page_request_with_sort(2, 10, support.by_desc('id'))
	page := repo.find_all_paged(pr)!
	assert page.items.len == 10
	// DESC order page 2: User15..User6
	assert page.items[0].id == 15
	assert page.items[9].id == 6
}

// ════════════════════════════════════════════════════════════════
// Edge case: page_number = 0 (normalized to page 1)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_page_number_zero() {
	mut repo := page_setup_with_users(25)!
	page := repo.find_all_paged(support.page_request(0, 10))!
	// page_number 0 is normalized to 1
	assert page.page_number == 1
	assert page.items.len == 10
	assert page.items[0].id == 1
}

// ════════════════════════════════════════════════════════════════
// Edge case: page_number negative (normalized to page 1)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_page_number_negative() {
	mut repo := page_setup_with_users(25)!
	page := repo.find_all_paged(support.page_request(-5, 10))!
	assert page.page_number == 1
	assert page.items.len == 10
	assert page.items[0].id == 1
}

// ════════════════════════════════════════════════════════════════
// Edge case: page_size = 0 (error)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_page_size_zero_error() {
	mut repo := page_setup_with_users(25)!
	if _ := repo.find_all_paged(support.page_request(1, 0)) {
		assert false, 'expected error: page size must be positive'
	} else {
		assert true
	}
}

// ════════════════════════════════════════════════════════════════
// Edge case: page_size negative (error)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_page_size_negative_error() {
	mut repo := page_setup_with_users(25)!
	if _ := repo.find_all_paged(support.page_request(1, -1)) {
		assert false, 'expected error: page size must be positive'
	} else {
		assert true
	}
}

// ════════════════════════════════════════════════════════════════
// Page size 1 (smallest valid page)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_page_size_one() {
	mut repo := page_setup_with_users(3)!
	page := repo.find_all_paged(support.page_request(1, 1))!
	assert page.items.len == 1
	assert page.total == 3
	assert page.total_pages == 3
	assert page.items[0].id == 1

	page2 := repo.find_all_paged(support.page_request(3, 1))!
	assert page2.items.len == 1
	assert page2.items[0].id == 3
	assert page2.is_last()
}

// ════════════════════════════════════════════════════════════════
// SQL uses parameterized LIMIT/OFFSET (no injection)
// ════════════════════════════════════════════════════════════════

fn test_jpa_paged_uses_parameterized_limit_offset() {
	mut repo := page_setup_with_users(5)!
	_ := repo.find_all_paged(support.page_request(1, 2))!
	// The last SELECT query should use ? placeholders for LIMIT and OFFSET
	// (not interpolated integers), confirming parameterized queries.
	assert g_page_last_query.contains('LIMIT ? OFFSET ?')
}

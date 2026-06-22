module orm

// jpa_enhanced_test.v - Tests for JpaRepository enhanced methods (Task 3)
//
// Verifies find_by_field, exists_by_field, count_by_field, paginate,
// and PageResult[T] using a self-contained mock in-memory database.

// ════════════════════════════════════════════════════════════════
// Test entity
// ════════════════════════════════════════════════════════════════

struct EnhTestUser {
pub mut:
	id     int    @[id]
	name   string
	email  string
	status string
}

// ════════════════════════════════════════════════════════════════
// Self-contained mock in-memory database
// ════════════════════════════════════════════════════════════════

struct EnhMockRow {
mut:
	cols   []string
	values []string
}

fn (mut r EnhMockRow) set(col string, val string) {
	for i, c in r.cols {
		if c == col {
			r.values[i] = val
			return
		}
	}
	r.cols << col
	r.values << val
}

fn (r EnhMockRow) get(col string) string {
	for i, c in r.cols {
		if c == col {
			return r.values[i]
		}
	}
	return ''
}

__global g_enh_rows []EnhMockRow
__global g_enh_next_id i64
__global g_enh_last_query string
__global g_enh_ddl []string
__global g_enh_pk_col string

fn enh_mock_reset() {
	unsafe {
		g_enh_rows = []EnhMockRow{}
		g_enh_next_id = 1
		g_enh_last_query = ''
		g_enh_ddl = []string{}
		g_enh_pk_col = 'id'
	}
}

fn enh_mock_setup[T]() !JpaRepository[T] {
	enh_mock_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	repo := new_jpa_repository[T](om, 'default', 'enh_test_users', enh_mock_exec, enh_mock_query)!
	unsafe {
		g_enh_pk_col = repo.primary_key_column
	}
	return repo
}

fn enh_mock_exec(db voidptr, query string, args []string) ! {
	_ = db
	unsafe {
		g_enh_last_query = query
	}
	q := query.to_lower()
	if q.starts_with('create table') {
		unsafe {
			g_enh_ddl << query
		}
		return
	}
	if q.starts_with('insert into') {
		enh_handle_insert(query, args)!
		return
	}
	if q.starts_with('delete from') {
		enh_handle_delete(args)
		return
	}
}

fn enh_handle_insert(query string, args []string) ! {
	open_paren := query.index('(') or { return error('mock: cannot parse INSERT columns') }
	rest := query[open_paren + 1..]
	close_offset := rest.index(')') or { return error('mock: cannot parse INSERT columns') }
	cols_str := rest[..close_offset]
	cols := cols_str.split(',').map(it.trim_space())
	mut row := EnhMockRow{}
	for i, col in cols {
		if i < args.len {
			row.set(col, args[i])
		}
	}
	// Auto-assign PK if missing or zero
	pk_val := row.get(g_enh_pk_col)
	if pk_val == '' || pk_val == '0' {
		next := g_enh_next_id
		row.set(g_enh_pk_col, '${next}')
		unsafe {
			g_enh_next_id = next + 1
		}
	}
	unsafe {
		g_enh_rows << row
	}
}

fn enh_handle_delete(args []string) {
	if args.len == 0 {
		return
	}
	target := args[0]
	pk_col := g_enh_pk_col
	mut kept := []EnhMockRow{}
	for row in g_enh_rows {
		if row.get(pk_col) != target {
			kept << row
		}
	}
	unsafe {
		g_enh_rows = kept
	}
}

fn enh_mock_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_enh_last_query = query
	}
	q := query.to_lower()
	if q.contains('count(*)') {
		// Parse WHERE clause for count_by_field support
		mut filter_col := ''
		mut target := ''
		where_idx := q.index(' where ') or { -1 }
		if where_idx != -1 && args.len > 0 {
			where_str := query[where_idx + 7..]
			eq_idx := where_str.index('=') or { where_str.len }
			filter_col = where_str[..eq_idx].trim_space()
			target = args[0]
		}
		if filter_col != '' {
			mut count := 0
			for row in g_enh_rows {
				if row.get(filter_col) == target {
					count++
				}
			}
			return [['${count}']]
		}
		count := g_enh_rows.len
		return [['${count}']]
	}
	// Parse: SELECT <cols> FROM <table> [WHERE <col> = ?] [LIMIT ? OFFSET ?]
	after_select := query[7..] // after "SELECT "
	from_idx := after_select.to_lower().index(' from ') or {
		return error('mock: cannot parse SELECT: no FROM clause')
	}
	cols_str := after_select[..from_idx]
	cols := cols_str.split(',').map(it.trim_space())
	// Parse WHERE filter if present
	mut filter_col := ''
	mut target := ''
	where_idx := q.index(' where ') or { -1 }
	if where_idx != -1 && args.len > 0 {
		where_str := query[where_idx + 7..]
		eq_idx := where_str.index('=') or { where_str.len }
		filter_col = where_str[..eq_idx].trim_space()
		target = args[0]
	}
	// Parse LIMIT/OFFSET for pagination
	mut limit_val := g_enh_rows.len
	mut offset_val := 0
	limit_idx := q.index(' limit ') or { -1 }
	if limit_idx != -1 {
		// args layout: [where_val?, limit, offset] or [limit, offset]
		// Find limit and offset in args based on query structure
		if filter_col != '' {
			// args: [where_val, limit, offset]
			if args.len >= 3 {
				limit_val = args[args.len - 2].int()
				offset_val = args[args.len - 1].int()
			}
		} else {
			// args: [limit, offset]
			if args.len >= 2 {
				limit_val = args[0].int()
				offset_val = args[1].int()
			}
		}
	}
	mut result := [][]string{}
	mut row_idx := 0
	for row in g_enh_rows {
		if filter_col != '' && row.get(filter_col) != target {
			continue
		}
		if row_idx >= offset_val && row_idx < offset_val + limit_val {
			mut vals := []string{}
			for col in cols {
				vals << row.get(col)
			}
			result << vals
		}
		row_idx++
	}
	return result
}

// ════════════════════════════════════════════════════════════════
// find_by_field Tests
// ════════════════════════════════════════════════════════════════

fn test_find_by_field_returns_matching_entities() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'alice@test.com', status: 'active' })!
	repo.save(&EnhTestUser{ id: 2, name: 'Bob', email: 'bob@test.com', status: 'active' })!
	repo.save(&EnhTestUser{ id: 3, name: 'Carol', email: 'carol@test.com', status: 'inactive' })!

	users := repo.find_by_field('status', 'active')!
	assert users.len == 2
}

fn test_find_by_field_returns_empty_when_no_match() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'alice@test.com', status: 'active' })!

	users := repo.find_by_field('status', 'deleted')!
	assert users.len == 0
}

fn test_find_by_field_uses_column_name_resolution() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'alice@test.com', status: 'active' })!

	// Using V field name 'email' should resolve to DB column 'email'
	users := repo.find_by_field('email', 'alice@test.com')!
	assert users.len == 1
	assert users[0].name == 'Alice'
}

// ════════════════════════════════════════════════════════════════
// exists_by_field Tests
// ════════════════════════════════════════════════════════════════

fn test_exists_by_field_returns_true() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'alice@test.com', status: 'active' })!

	assert repo.exists_by_field('email', 'alice@test.com') == true
}

fn test_exists_by_field_returns_false() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'alice@test.com', status: 'active' })!

	assert repo.exists_by_field('email', 'nonexistent@test.com') == false
}

// ════════════════════════════════════════════════════════════════
// count_by_field Tests
// ════════════════════════════════════════════════════════════════

fn test_count_by_field_returns_correct_count() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'alice@test.com', status: 'active' })!
	repo.save(&EnhTestUser{ id: 2, name: 'Bob', email: 'bob@test.com', status: 'active' })!
	repo.save(&EnhTestUser{ id: 3, name: 'Carol', email: 'carol@test.com', status: 'inactive' })!

	count := repo.count_by_field('status', 'active')!
	assert count == 2
}

fn test_count_by_field_returns_zero_when_no_match() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'alice@test.com', status: 'active' })!

	count := repo.count_by_field('status', 'deleted')!
	assert count == 0
}

// ════════════════════════════════════════════════════════════════
// paginate Tests
// ════════════════════════════════════════════════════════════════

fn test_paginate_first_page() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	for i in 0 .. 15 {
		repo.save(&EnhTestUser{ id: i + 1, name: 'User${i}', email: 'u${i}@test.com', status: 'active' })!
	}

	result := repo.paginate(1, 10)!
	assert result.items.len == 10
	assert result.total == 15
	assert result.page == 1
	assert result.page_size == 10
	assert result.total_pages == 2
}

fn test_paginate_second_page() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	for i in 0 .. 15 {
		repo.save(&EnhTestUser{ id: i + 1, name: 'User${i}', email: 'u${i}@test.com', status: 'active' })!
	}

	result := repo.paginate(2, 10)!
	assert result.items.len == 5
	assert result.total == 15
	assert result.page == 2
	assert result.total_pages == 2
}

fn test_paginate_empty_table() {
	mut repo := enh_mock_setup[EnhTestUser]()!

	result := repo.paginate(1, 10)!
	assert result.items.len == 0
	assert result.total == 0
	assert result.total_pages == 0
}

fn test_paginate_invalid_page_size() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'a@b.com', status: 'active' })!

	result := repo.paginate(1, 0) or { return }
	_ = result
	assert false // should not reach here
}

fn test_paginate_negative_page_normalized() {
	mut repo := enh_mock_setup[EnhTestUser]()!
	repo.save(&EnhTestUser{ id: 1, name: 'Alice', email: 'a@b.com', status: 'active' })!

	result := repo.paginate(-1, 10)!
	assert result.page == 1
	assert result.items.len == 1
}

// ════════════════════════════════════════════════════════════════
// PageResult[T] Tests
// ════════════════════════════════════════════════════════════════

fn test_page_result_has_next() {
	pr := PageResult[EnhTestUser]{
		items: []EnhTestUser{cap: 1}
		total: 20
		page: 1
		page_size: 10
		total_pages: 2
	}
	assert pr.has_next() == true
	assert pr.has_previous() == false
}

fn test_page_result_has_previous() {
	pr := PageResult[EnhTestUser]{
		items: []EnhTestUser{cap: 1}
		total: 20
		page: 2
		page_size: 10
		total_pages: 2
	}
	assert pr.has_next() == false
	assert pr.has_previous() == true
}

fn test_page_result_is_empty() {
	pr := PageResult[EnhTestUser]{
		items: []EnhTestUser{}
		total: 0
		page: 1
		page_size: 10
		total_pages: 0
	}
	assert pr.is_empty() == true
}

fn test_new_page_result_computes_total_pages() {
	pr := new_page_result[EnhTestUser]([]EnhTestUser{}, 25, 1, 10)
	assert pr.total_pages == 3
}

fn test_new_page_result_zero_total() {
	pr := new_page_result[EnhTestUser]([]EnhTestUser{}, 0, 1, 10)
	assert pr.total_pages == 0
}
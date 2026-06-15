module orm

// repository_test.v - Tests for Repository interface and derive parsing

// ── Test entity ──

struct RepoTestEntity {
pub mut:
	id         int
	name       string
	created_at i64
	updated_at i64
	version    int
}

fn (mut e RepoTestEntity) touch() {
	if e.created_at == 0 { e.created_at = 100 }
	e.updated_at = 200
	e.version++
}

fn (e &RepoTestEntity) id() int { return e.id }
fn (e &RepoTestEntity) is_new() bool { return e.id == 0 }

// ── Stub ORM callbacks (return sentinel values) ──

fn stub_find[T](conn voidptr, id int) !T {
	mut e := T{}
	return e
}

fn stub_find_all[T](conn voidptr) ![]T {
	return []T{}
}

fn stub_insert[T](conn voidptr, entity T) ! {
}

fn stub_update[T](conn voidptr, entity T) ! {
}

fn stub_delete(conn voidptr, id int) ! {
}

fn stub_count(conn voidptr) !int {
	return 0
}

fn stub_exists(conn voidptr, id int) bool {
	return false
}

fn setup_repo[T]() !(&OrmManager, &BaseRepository[T]) {
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	mut repo := new_repository[T](om, 'default', stub_find[T], stub_find_all[T], stub_insert[T], stub_update[T], stub_delete, stub_count, stub_exists)!
	return om, repo
}

// ── Construction tests ──

fn test_new_repository_succeeds() {
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!

	repo := new_repository[RepoTestEntity](om, 'default', stub_find[RepoTestEntity], stub_find_all[RepoTestEntity], stub_insert[RepoTestEntity], stub_update[RepoTestEntity], stub_delete, stub_count, stub_exists)!
	assert true // reached without crash
	_ = repo
}

fn test_new_repository_missing_connection() {
	om := new_orm_manager()
	if _ := new_repository[RepoTestEntity](om, 'missing', stub_find[RepoTestEntity], stub_find_all[RepoTestEntity], stub_insert[RepoTestEntity], stub_update[RepoTestEntity], stub_delete, stub_count, stub_exists) {
		assert false, 'expected error'
	} else {
		assert true
	}
}

// ── CRUD operations ──

fn test_repository_find_by_id() {
	_, mut repo := setup_repo[RepoTestEntity]()!
	entity := repo.find_by_id(1)!
	// Returns entity from stub callback
	assert true
	_ = entity
}

fn test_repository_find_all() {
	_, mut repo := setup_repo[RepoTestEntity]()!
	entities := repo.find_all()!
	assert entities.len == 0 // stub returns empty
}

fn test_repository_save_new_entity() {
	_, mut repo := setup_repo[RepoTestEntity]()!
	mut e := RepoTestEntity{}
	result := repo.save(mut e)!
	// Auto-touch via Touchable: created_at/updated_at set
	assert result.created_at == 100
	assert result.updated_at == 200
	assert result.version == 1
}

fn test_repository_update() {
	_, mut repo := setup_repo[RepoTestEntity]()!
	mut e := RepoTestEntity{id: 5}
	result := repo.update(mut e)!
	// Auto-touch via Touchable
	assert result.updated_at == 200
	assert result.version == 1
}

fn test_repository_delete_by_id() {
	_, repo := setup_repo[RepoTestEntity]()!
	repo.delete_by_id(42)!
	assert true // no error from stub
}

fn test_repository_delete_entity() {
	_, mut repo := setup_repo[RepoTestEntity]()!
	e := RepoTestEntity{id: 99}
	repo.delete(e)!
	assert true
}

fn test_repository_count() {
	_, repo := setup_repo[RepoTestEntity]()!
	n := repo.count()!
	assert n == 0 // stub returns 0
}

fn test_repository_exists_by_id() {
	_, repo := setup_repo[RepoTestEntity]()!
	assert repo.exists_by_id(1) == false // stub returns false
}

// --- Repository interface is just a contract ---

fn test_repository_interface_exists() {
	// Verify the interface compiles — no construction needed
	assert true
}

// --- Derived query parsing tests ---

fn test_parse_find_by() {
	parts := parse_method_name('findByName')!
	assert parts.operation == .find
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'name'
}

fn test_parse_find_by_and() {
	parts := parse_method_name('findByNameAndAge')!
	assert parts.operation == .find
	assert parts.conditions.len == 2
	assert parts.conditions[0].property == 'name'
	assert parts.conditions[1].property == 'age'
}

fn test_parse_count_by() {
	parts := parse_method_name('countByStatus')!
	assert parts.operation == .count
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'status'
}

fn test_parse_delete_by() {
	parts := parse_method_name('deleteByStatus')!
	assert parts.operation == .delete_all
	assert parts.conditions.len == 1
	assert parts.conditions[0].property == 'status'
}

fn test_parse_find_top_by() {
	parts := parse_method_name('findTop10ByName')!
	assert parts.operation == .find
	assert parts.limit_val == 10
}

fn test_parse_find_with_order_by() {
	parts := parse_method_name('findByNameOrderByCreatedAtDesc')!
	assert parts.operation == .find
	assert parts.order_by.len == 1
	assert parts.order_by[0].property == 'created_at'
	assert parts.order_by[0].direction == 'DESC'
}

fn test_to_where_cond_single() {
	parts := parse_method_name('findByName')!
	cond := parts.to_where_cond()
	assert cond.contains('name = ?')
}

fn test_to_where_cond_multi() {
	parts := parse_method_name('findByNameAndAge')!
	cond := parts.to_where_cond()
	assert cond.contains('name = ?')
	assert cond.contains('AND')
	assert cond.contains('age = ?')
}

fn test_to_where_cond_or() {
	parts := parse_method_name('findByNameOrAge')!
	cond := parts.to_where_cond()
	assert cond.contains('OR')
}

fn test_to_where_param_count() {
	parts := parse_method_name('findByNameAndAge')!
	assert parts.to_where_param_count() == 2
}

fn test_to_order_direction_asc() {
	parts := parse_method_name('findByNameOrderByNameAsc')!
	assert parts.to_order_direction() == 'asc'
}

fn test_to_order_direction_desc() {
	parts := parse_method_name('findByNameOrderByNameDesc')!
	assert parts.to_order_direction() == 'desc'
}

fn test_parse_exists_by() {
	parts := parse_method_name('existsByName')!
	assert parts.operation == .exists
}

// ── DerivedRepository tests ──

fn stub_derived_find(conn voidptr, parts QueryParts, params []voidptr) ![]RepoTestEntity {
	mut results := []RepoTestEntity{}
	for _ in 0 .. params.len {
		results << RepoTestEntity{name: 'found'}
	}
	return results
}

fn stub_derived_count(conn voidptr, parts QueryParts, params []voidptr) !int {
	return params.len * 10
}

fn stub_derived_exists(conn voidptr, parts QueryParts, params []voidptr) bool {
	return params.len > 0
}

fn stub_derived_delete(conn voidptr, parts QueryParts, params []voidptr) ! {
}

fn setup_derived_repo[T]() !(&OrmManager, &DerivedRepository[T]) {
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99))!
	mut dr := new_derived_repository[T](om, 'default',
		stub_find[T], stub_find_all[T], stub_insert[T],
		stub_update[T], stub_delete, stub_count, stub_exists,
		stub_derived_find, stub_derived_count,
		stub_derived_exists, stub_derived_delete)!
	return om, dr
}

fn test_derived_repository_new() {
	_, _ := setup_derived_repo[RepoTestEntity]()!
	assert true
}

fn test_derived_repo_find() {
	_, mut dr := setup_derived_repo[RepoTestEntity]()!
	results := dr.find('findByName', voidptr('Alice'.str))!
	assert results.len == 1
	assert results[0].name == 'found'
}

fn test_derived_repo_find_multi_params() {
	_, mut dr := setup_derived_repo[RepoTestEntity]()!
	results := dr.find('findByNameAndAge', voidptr('Alice'.str), voidptr(30))!
	assert results.len == 2
}

fn test_derived_repo_find_wrong_operation() {
	_, mut dr := setup_derived_repo[RepoTestEntity]()!
	mut failed := false
	dr.find('countByStatus', voidptr('active'.str)) or { failed = true }
	assert failed
}

fn test_derived_repo_count() {
	_, dr := setup_derived_repo[RepoTestEntity]()!
	n := dr.count('countByStatus', voidptr('active'.str))!
	assert n == 10
}

fn test_derived_repo_count_wrong_operation() {
	_, dr := setup_derived_repo[RepoTestEntity]()!
	mut failed := false
	dr.count('findByName', voidptr('Alice'.str)) or { failed = true }
	assert failed
}

fn test_derived_repo_exists() {
	_, dr := setup_derived_repo[RepoTestEntity]()!
	assert dr.exists('existsByEmail', voidptr('a@b.com'.str)) == true
}

fn test_derived_repo_exists_no_params() {
	_, dr := setup_derived_repo[RepoTestEntity]()!
	assert dr.exists('existsByEmail') == false
}

fn test_derived_repo_exists_invalid_method() {
	_, dr := setup_derived_repo[RepoTestEntity]()!
	assert dr.exists('invalidMethod') == false
}

fn test_derived_repo_delete_by() {
	_, dr := setup_derived_repo[RepoTestEntity]()!
	dr.delete_by('deleteByStatus', voidptr('expired'.str))!
	assert true
}

fn test_derived_repo_delete_by_wrong_operation() {
	_, dr := setup_derived_repo[RepoTestEntity]()!
	mut failed := false
	dr.delete_by('findByName', voidptr('Alice'.str)) or { failed = true }
	assert failed
}

fn test_derived_repo_find_param_count_mismatch() {
	_, mut dr := setup_derived_repo[RepoTestEntity]()!
	// findByNameAndAge expects 2 params, pass only 1
	mut failed := false
	dr.find('findByNameAndAge', voidptr('Alice'.str)) or { failed = true }
	assert failed
}

fn test_derived_repo_count_param_count_mismatch() {
	_, dr := setup_derived_repo[RepoTestEntity]()!
	// countByStatus expects 1 param, pass 0
	mut failed := false
	dr.count('countByStatus') or { failed = true }
	assert failed
}

fn test_derived_repo_wraps_base_repository() {
	_, mut dr := setup_derived_repo[RepoTestEntity]()!
	mut e := RepoTestEntity{}
	result := dr.repo.save(mut e)!
	assert result.created_at == 100
	assert result.updated_at == 200
}

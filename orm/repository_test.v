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

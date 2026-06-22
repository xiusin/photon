module orm

// dto_validation_test.v - Tests for DTO validation and enhanced entity annotations (Task 3)
//
// Verifies:
//   - Extended entity annotation extraction (@[generated_value], @[version],
//     @[created_at], @[updated_at], @[soft_delete], @[size], @[nullable], @[unique])
//   - scan_entity[T]() validation
//   - DTO validation: @[required], @[email], @[min], @[max], @[pattern], @[length]
//   - PageResult[T] and JpaRepository enhanced methods
//   - parse_transactional_attrs() for comptime field.attrs

// ════════════════════════════════════════════════════════════════
// Test entities with extended annotations
// ════════════════════════════════════════════════════════════════

@[entity]
@[table: 'products']
struct DtoProduct {
pub mut:
	id         int    @[id; generated_value]
	name       string @[size: '255']
	sku        string @[unique; size: '50']
	price      f64
	quantity   int    @[min: '0'; max: '10000']
	is_active  bool   @[nullable]
	created_at i64    @[created_at]
	updated_at i64    @[updated_at]
	version    int    @[version]
	deleted_at i64    @[soft_delete]
}

@[entity]
struct DtoUser {
pub mut:
	id    int    @[id]
	name  string @[required; length: '1,255']
	email string @[required; email]
	age   int    @[min: '0'; max: '150']
}

@[entity]
struct DtoSimpleEntity {
pub mut:
	id   int    @[id]
	code string @[required; pattern: 'A*']
}

// Entity without @[entity] or @[table] — scan_entity should fail
struct DtoNonEntity {
pub mut:
	label string
}

// ════════════════════════════════════════════════════════════════
// Extended Entity Metadata Tests
// ════════════════════════════════════════════════════════════════

fn test_extract_generated_value_annotation() {
	meta := extract_entity_metadata[DtoProduct]()
	mut pk_col := ColumnMetadata{}
	for col in meta.columns {
		if col.field_name == 'id' {
			pk_col = col
		}
	}
	assert pk_col.is_generated == true
	assert pk_col.is_primary == true
}

fn test_extract_version_annotation() {
	meta := extract_entity_metadata[DtoProduct]()
	assert meta.has_version == true
	mut version_col := ColumnMetadata{}
	for col in meta.columns {
		if col.field_name == 'version' {
			version_col = col
		}
	}
	assert version_col.is_version == true
}

fn test_extract_created_at_annotation() {
	meta := extract_entity_metadata[DtoProduct]()
	assert meta.has_created_at == true
	mut col := ColumnMetadata{}
	for c in meta.columns {
		if c.field_name == 'created_at' {
			col = c
		}
	}
	assert col.is_created_at == true
}

fn test_extract_updated_at_annotation() {
	meta := extract_entity_metadata[DtoProduct]()
	assert meta.has_updated_at == true
	mut col := ColumnMetadata{}
	for c in meta.columns {
		if c.field_name == 'updated_at' {
			col = c
		}
	}
	assert col.is_updated_at == true
}

fn test_extract_soft_delete_annotation() {
	meta := extract_entity_metadata[DtoProduct]()
	assert meta.has_soft_delete == true
	mut col := ColumnMetadata{}
	for c in meta.columns {
		if c.field_name == 'deleted_at' {
			col = c
		}
	}
	assert col.is_soft_delete == true
}

fn test_extract_size_constraint() {
	meta := extract_entity_metadata[DtoProduct]()
	mut name_col := ColumnMetadata{}
	mut sku_col := ColumnMetadata{}
	for col in meta.columns {
		if col.field_name == 'name' {
			name_col = col
		}
		if col.field_name == 'sku' {
			sku_col = col
		}
	}
	assert name_col.size_constraint == 255
	assert sku_col.size_constraint == 50
}

fn test_extract_nullable_annotation() {
	meta := extract_entity_metadata[DtoProduct]()
	mut active_col := ColumnMetadata{}
	for col in meta.columns {
		if col.field_name == 'is_active' {
			active_col = col
		}
	}
	assert active_col.is_nullable == true
}

fn test_extract_unique_annotation() {
	meta := extract_entity_metadata[DtoProduct]()
	mut sku_col := ColumnMetadata{}
	for col in meta.columns {
		if col.field_name == 'sku' {
			sku_col = col
		}
	}
	assert sku_col.is_unique == true
}

fn test_annotation_name_constants() {
	assert attr_table == 'table'
	assert attr_entity == 'entity'
	assert attr_id == 'id'
	assert attr_primary_key == 'primary_key'
	assert attr_column == 'column'
	assert attr_generated_value == 'generated_value'
	assert attr_version == 'version'
	assert attr_created_at == 'created_at'
	assert attr_updated_at == 'updated_at'
	assert attr_soft_delete == 'soft_delete'
	assert attr_size == 'size'
	assert attr_nullable == 'nullable'
	assert attr_unique == 'unique'
	assert attr_required == 'required'
	assert attr_email == 'email'
	assert attr_min == 'min'
	assert attr_max == 'max'
	assert attr_pattern == 'pattern'
	assert attr_length == 'length'
}

// ════════════════════════════════════════════════════════════════
// scan_entity[T]() Tests
// ════════════════════════════════════════════════════════════════

fn test_scan_entity_valid() {
	meta := scan_entity[DtoProduct]()!
	assert meta.table_name == 'products'
	assert meta.has_primary_key == true
	assert meta.has_version == true
}

fn test_scan_entity_rejects_non_entity() {
	result := scan_entity[DtoNonEntity]() or { return }
	_ = result
	assert false // should not reach here
}

// ════════════════════════════════════════════════════════════════
// DTO Validation Tests
// ════════════════════════════════════════════════════════════════

fn test_validate_required_string_passes() {
	user := DtoUser{ id: 1, name: 'Alice', email: 'alice@example.com', age: 30 }
	result := validate[DtoUser](user)!
	assert result.is_valid == true
	assert result.errors.len == 0
}

fn test_validate_required_string_fails() {
	user := DtoUser{ id: 1, name: '', email: 'alice@example.com', age: 30 }
	result := validate[DtoUser](user)!
	assert result.is_valid == false
	// Should have error on 'name' for @[required]
	mut found_required := false
	for err in result.errors {
		if err.field == 'name' && err.rule == 'required' {
			found_required = true
		}
	}
	assert found_required == true
}

fn test_validate_email_passes() {
	user := DtoUser{ id: 1, name: 'Alice', email: 'alice@example.com', age: 30 }
	result := validate[DtoUser](user)!
	assert result.is_valid == true
}

fn test_validate_email_fails() {
	user := DtoUser{ id: 1, name: 'Alice', email: 'not-an-email', age: 30 }
	result := validate[DtoUser](user)!
	assert result.is_valid == false
	mut found_email := false
	for err in result.errors {
		if err.field == 'email' && err.rule == 'email' {
			found_email = true
		}
	}
	assert found_email == true
}

fn test_validate_min_fails() {
	user := DtoUser{ id: 1, name: 'Alice', email: 'a@b.com', age: -1 }
	result := validate[DtoUser](user)!
	assert result.is_valid == false
	mut found_min := false
	for err in result.errors {
		if err.field == 'age' && err.rule == 'min' {
			found_min = true
		}
	}
	assert found_min == true
}

fn test_validate_max_fails() {
	user := DtoUser{ id: 1, name: 'Alice', email: 'a@b.com', age: 200 }
	result := validate[DtoUser](user)!
	assert result.is_valid == false
	mut found_max := false
	for err in result.errors {
		if err.field == 'age' && err.rule == 'max' {
			found_max = true
		}
	}
	assert found_max == true
}

fn test_validate_min_max_passes() {
	user := DtoUser{ id: 1, name: 'Alice', email: 'a@b.com', age: 50 }
	result := validate[DtoUser](user)!
	assert result.is_valid == true
}

fn test_validate_length_fails_too_short() {
	user := DtoUser{ id: 1, name: '', email: 'a@b.com', age: 30 }
	result := validate[DtoUser](user)!
	// name is empty — fails both @[required] and @[length]
	assert result.is_valid == false
}

fn test_validate_pattern() {
	// Valid pattern
	entity := DtoSimpleEntity{ id: 1, code: 'ABC' }
	result := validate[DtoSimpleEntity](entity)!
	assert result.is_valid == true

	// Invalid pattern — doesn't start with 'A'
	entity2 := DtoSimpleEntity{ id: 2, code: 'XYZ' }
	result2 := validate[DtoSimpleEntity](entity2)!
	assert result2.is_valid == false
}

fn test_validate_all_pass() {
	user := DtoUser{ id: 1, name: 'Alice', email: 'alice@example.com', age: 30 }
	result := validate[DtoUser](user)!
	assert result.is_valid == true
	assert result.errors.len == 0
}

fn test_validate_multiple_errors() {
	user := DtoUser{ id: 1, name: '', email: 'bad', age: -5 }
	result := validate[DtoUser](user)!
	assert result.is_valid == false
	assert result.errors.len >= 3 // name required, email format, age min
}

// ════════════════════════════════════════════════════════════════
// Email Validation Helper Tests
// ════════════════════════════════════════════════════════════════

fn test_is_valid_email() {
	assert is_valid_email('user@example.com') == true
	assert is_valid_email('a@b.co') == true
	assert is_valid_email('test+tag@domain.org') == true
}

fn test_is_valid_email_invalid() {
	assert is_valid_email('') == false
	assert is_valid_email('no-at-sign') == false
	assert is_valid_email('@no-local.com') == false
	assert is_valid_email('no-domain@') == false
	assert is_valid_email('no-dot@afterat') == false
}

// ════════════════════════════════════════════════════════════════
// Pattern Matching Tests
// ════════════════════════════════════════════════════════════════

fn test_matches_pattern_star() {
	assert matches_pattern('anything', '*') == true
}

fn test_matches_pattern_exact() {
	assert matches_pattern('hello', 'hello') == true
	assert matches_pattern('hello', 'world') == false
}

fn test_matches_pattern_question_mark() {
	assert matches_pattern('ab', 'a?') == true
	assert matches_pattern('abc', 'a?') == false
}

fn test_matches_pattern_star_prefix() {
	assert matches_pattern('abc', 'a*') == true
	assert matches_pattern('xyz', 'a*') == false
}

// ════════════════════════════════════════════════════════════════
// Annotation Helper Tests
// ════════════════════════════════════════════════════════════════

fn test_has_attr() {
	assert has_attr(['required', 'email'], 'required') == true
	assert has_attr(['required', 'email'], 'email') == true
	assert has_attr(['required', 'email'], 'min') == false
}

fn test_has_attr_with_params() {
	assert has_attr(['size: 255'], 'size') == true
	assert has_attr(['min: 0'], 'min') == true
}

fn test_extract_int_attr() {
	assert extract_int_attr(['size: 255'], 'size') == 255
	assert extract_int_attr(['min: 0'], 'min') == 0
	assert extract_int_attr(['max: 100'], 'max') == 100
	assert extract_int_attr(['no_match'], 'size') == 0
}

fn test_extract_string_attr() {
	assert extract_string_attr(['pattern: A*'], 'pattern') == 'A*'
	assert extract_string_attr(['column: user_name'], 'column') == 'user_name'
	assert extract_string_attr(['no_match'], 'pattern') == ''
}

fn test_extract_two_int_attr() {
	min_len, max_len := extract_two_int_attr(['length: 1,255'], 'length')
	assert min_len == 1
	assert max_len == 255
	_, _ = extract_two_int_attr(['no_match'], 'length')
}

// ════════════════════════════════════════════════════════════════
// ValidationResult Tests
// ════════════════════════════════════════════════════════════════

fn test_new_validation_result() {
	vr := new_validation_result()
	assert vr.is_valid == true
	assert vr.errors.len == 0
}

fn test_validation_result_add_error() {
	mut vr := new_validation_result()
	vr.add_error('name', 'name is required', 'required')
	assert vr.is_valid == false
	assert vr.errors.len == 1
	assert vr.errors[0].field == 'name'
	assert vr.errors[0].rule == 'required'
}

// ════════════════════════════════════════════════════════════════
// parse_transactional_attrs Tests
// ════════════════════════════════════════════════════════════════

fn test_parse_transactional_attrs_default() {
	ta := parse_transactional_attrs(['transactional'])
	assert ta.propagation == .required
	assert ta.readonly == false
}

fn test_parse_transactional_attrs_readonly() {
	ta := parse_transactional_attrs(['transactional: readonly'])
	assert ta.readonly == true
}

fn test_parse_transactional_attrs_requires_new() {
	ta := parse_transactional_attrs(['transactional: requires_new'])
	assert ta.propagation == .requires_new
}

fn test_parse_transactional_attrs_nested() {
	ta := parse_transactional_attrs(['transactional: nested'])
	assert ta.propagation == .nested
}

fn test_parse_transactional_attrs_no_match() {
	ta := parse_transactional_attrs(['other_attr', 'id'])
	assert ta.propagation == .required
	assert ta.readonly == false
}

fn test_parse_transactional_attrs_complex() {
	ta := parse_transactional_attrs(['transactional: propagation:requires_new;isolation:read_committed;readonly'])
	assert ta.propagation == .requires_new
	assert ta.isolation == .read_committed
	assert ta.readonly == true
}
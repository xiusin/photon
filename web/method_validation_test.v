module web

// method_validation_test.v - Tests for method-level validation via @[valid]
//
// Covers ConstraintViolationException, validate_field, validate_params,
// validate_method_params (comptime), and the is_valid_email helper.

// ── Test Fixtures ──

// UserService is the fixture struct carrying @[valid]-annotated methods.
struct UserService {
mut:
	last_name string
	last_age  int
}

// create_user validates name (required, min_len 2), age (min 1, max 150),
// and email (email format). Uses the colon form of @[valid].
@[valid: 'name:required|min_len:2; age:min:1|max:150; email:email']
fn (mut s UserService) create_user(name string, age int, email string) {
	s.last_name = name
	s.last_age = age
	_ = email
}

// update_email validates only the email parameter.
@[valid: 'email:email']
fn (mut s UserService) update_email(email string) {
	_ = email
}

// no_param_method has @[valid] but no constraint string and no params.
@[valid]
fn (mut s UserService) no_param_method() {
}

// unannotated_method has no @[valid] attribute — validation should be skipped.
fn (mut s UserService) unannotated_method(name string, age int) {
	_ = name
	_ = age
}

// bare_valid_method uses the bare @[valid] marker with no constraint string.
@[valid]
fn (mut s UserService) bare_valid_method(name string) {
	_ = name
}

// paren_form_method uses the @[valid('...')] parenthesised form.
@[valid('name:required; age:min:1|max:150')]
fn (mut s UserService) paren_form_method(name string, age int) {
	_ = name
	_ = age
}

// ── ConstraintViolationException Tests ──

fn test_constraint_violation_exception_msg() {
	exc := ConstraintViolationException{
		violations: [
			ConstraintViolation{
				field:      'name'
				value:      ''
				constraint: 'required'
				message:    'name is required'
			},
			ConstraintViolation{
				field:      'age'
				value:      '0'
				constraint: 'min'
				message:    'age must be at least 1'
			},
		]
	}
	msg := exc.msg()
	assert msg.contains('name: name is required'), 'msg should contain name violation, got: ${msg}'
	assert msg.contains('age: age must be at least 1'), 'msg should contain age violation, got: ${msg}'
	assert msg.contains('validation failed'), 'msg should contain "validation failed", got: ${msg}'
	assert msg.contains('校验失败'), 'msg should contain bilingual text, got: ${msg}'
}

fn test_constraint_violation_exception_code() {
	exc := ConstraintViolationException{
		violations: [
			ConstraintViolation{
				field:      'name'
				value:      ''
				constraint: 'required'
				message:    'name is required'
			},
		]
	}
	assert exc.code() == 400, 'default code should be 400, got: ${exc.code()}'
}

fn test_constraint_violation_exception_default_code() {
	exc := ConstraintViolationException{}
	assert exc.code() == 400, 'default code should be 400, got: ${exc.code()}'
}

fn test_constraint_violation_exception_empty_violations() {
	exc := ConstraintViolationException{
		violations: []
	}
	msg := exc.msg()
	assert msg.contains('validation failed'), 'msg should contain "validation failed", got: ${msg}'
}

fn test_constraint_violation_exception_custom_code() {
	exc := ConstraintViolationException{
		violations: [
			ConstraintViolation{
				field:      'x'
				value:      'y'
				constraint: 'required'
				message:    'x is required'
			},
		]
		code: 422
	}
	assert exc.code() == 422, 'custom code should be 422, got: ${exc.code()}'
}

fn test_constraint_violation_exception_str() {
	exc := ConstraintViolationException{
		violations: [
			ConstraintViolation{
				field:      'name'
				value:      ''
				constraint: 'required'
				message:    'name is required'
			},
		]
	}
	assert exc.str() == exc.msg(), 'str() should equal msg()'
}

// ── validate_field Tests ──

fn test_validate_field_required_pass() {
	violations := validate_field('name', 'John', ['required'])
	assert violations.len == 0, 'required should pass for non-empty value'
}

fn test_validate_field_required_fail() {
	violations := validate_field('name', '', ['required'])
	assert violations.len == 1, 'required should fail for empty value'
	assert violations[0].field == 'name'
	assert violations[0].constraint == 'required'
	assert violations[0].value == ''
}

fn test_validate_field_min_pass() {
	violations := validate_field('age', '5', ['min:1'])
	assert violations.len == 0, 'min:1 should pass for value 5'
}

fn test_validate_field_min_fail() {
	violations := validate_field('age', '0', ['min:1'])
	assert violations.len == 1, 'min:1 should fail for value 0'
	assert violations[0].constraint == 'min'
}

fn test_validate_field_max_pass() {
	violations := validate_field('age', '50', ['max:150'])
	assert violations.len == 0, 'max:150 should pass for value 50'
}

fn test_validate_field_max_fail() {
	violations := validate_field('age', '200', ['max:150'])
	assert violations.len == 1, 'max:150 should fail for value 200'
	assert violations[0].constraint == 'max'
}

fn test_validate_field_min_len_fail() {
	violations := validate_field('name', 'A', ['min_len:2'])
	assert violations.len == 1, 'min_len:2 should fail for "A"'
	assert violations[0].constraint == 'min_len'
}

fn test_validate_field_min_len_pass() {
	violations := validate_field('name', 'John', ['min_len:2'])
	assert violations.len == 0, 'min_len:2 should pass for "John"'
}

fn test_validate_field_max_len_fail() {
	violations := validate_field('name', 'VeryLongName', ['max_len:10'])
	assert violations.len == 1, 'max_len:10 should fail for "VeryLongName"'
	assert violations[0].constraint == 'max_len'
}

fn test_validate_field_max_len_pass() {
	violations := validate_field('name', 'John', ['max_len:10'])
	assert violations.len == 0, 'max_len:10 should pass for "John"'
}

fn test_validate_field_email_pass() {
	violations := validate_field('email', 'user@example.com', ['email'])
	assert violations.len == 0, 'email should pass for valid email'
}

fn test_validate_field_email_fail() {
	violations := validate_field('email', 'not-an-email', ['email'])
	assert violations.len == 1, 'email should fail for invalid email'
	assert violations[0].constraint == 'email'
}

fn test_validate_field_email_empty_passes() {
	// Empty value passes email check (use 'required' to reject empty)
	violations := validate_field('email', '', ['email'])
	assert violations.len == 0, 'email should pass for empty value'
}

fn test_validate_field_multiple_rules() {
	// Empty string fails both 'required' and 'min_len:2'
	violations := validate_field('name', '', ['required', 'min_len:2'])
	assert violations.len == 2, 'both required and min_len:2 should fail for empty string, got: ${violations.len}'
	mut constraints := map[string]bool{}
	for v in violations {
		constraints[v.constraint] = true
	}
	assert constraints['required'] == true, 'should have required violation'
	assert constraints['min_len'] == true, 'should have min_len violation'
}

fn test_validate_field_multiple_violations() {
	violations := validate_field('name', 'A', ['required', 'min_len:2'])
	assert violations.len == 1, 'required passes, min_len:2 fails for "A"'
	assert violations[0].constraint == 'min_len'
}

fn test_validate_field_no_rules() {
	violations := validate_field('name', 'John', [])
	assert violations.len == 0, 'no rules means no violations'
}

// ── parse_param_constraints Tests ──

fn test_parse_param_constraints_basic() {
	result := parse_param_constraints('name:required|min_len:2; age:min:1|max:150')
	assert result.len == 2, 'should have 2 params, got: ${result.len}'
	assert 'name' in result
	assert 'age' in result
	assert result['name'].len == 2, 'name should have 2 rules'
	assert result['name'][0] == 'required'
	assert result['name'][1] == 'min_len:2'
	assert result['age'].len == 2, 'age should have 2 rules'
	assert result['age'][0] == 'min:1'
	assert result['age'][1] == 'max:150'
}

fn test_parse_param_constraints_single_param() {
	result := parse_param_constraints('email:email')
	assert result.len == 1
	assert result['email'].len == 1
	assert result['email'][0] == 'email'
}

fn test_parse_param_constraints_empty() {
	result := parse_param_constraints('')
	assert result.len == 0
}

fn test_parse_param_constraints_with_spaces() {
	result := parse_param_constraints('name: required | min_len:2 ; age: min:1')
	assert result.len == 2, 'should have 2 params after trimming, got: ${result.len}'
	assert result['name'].len == 2
}

// ── validate_params Tests ──

fn test_validate_params_all_pass() {
	validate_params('name:required|min_len:2; age:min:1|max:150', {
		'name': 'John'
		'age':  '5'
	}) or {
		assert false, 'should not fail validation: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_params_required_fail() {
	mut failed := false
	validate_params('name:required', {
		'name': ''
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len == 1
		assert exc.violations[0].field == 'name'
		assert exc.violations[0].constraint == 'required'
		return
	}
	assert failed, 'should have failed validation'
}

fn test_validate_params_multiple_violations() {
	mut failed := false
	validate_params('name:required|min_len:2; age:min:1|max:150; email:email', {
		'name':  ''
		'age':   '0'
		'email': 'bad'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len >= 3, 'should have at least 3 violations, got: ${exc.violations.len}'
		return
	}
	assert failed, 'should have failed validation'
}

fn test_validate_params_missing_param() {
	// Missing param is treated as empty string
	validate_params('name:required', {}) or {
		exc := err as ConstraintViolationException
		assert exc.violations.len == 1
		assert exc.violations[0].field == 'name'
		assert exc.violations[0].constraint == 'required'
		return
	}
	assert false, 'should have failed for missing required param'
}

fn test_validate_params_empty_constraints() {
	// Empty constraint string means no validation
	validate_params('', {
		'name': ''
	}) or {
		assert false, 'empty constraints should not fail'
		return
	}
	assert true
}

// ── validate_method_params (Comptime) Tests ──

fn test_validate_method_params_required_pass() {
	validate_method_params[UserService]('create_user', {
		'name':  'John'
		'age':   '5'
		'email': 'user@example.com'
	}) or {
		assert false, 'should not fail: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_required_fail() {
	mut failed := false
	validate_method_params[UserService]('create_user', {
		'name':  ''
		'age':   '5'
		'email': 'user@example.com'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		// name='' fails both 'required' and 'min_len:2'
		assert exc.violations.len == 2, 'should have 2 violations (required + min_len), got: ${exc.violations.len}'
		mut has_required := false
		for v in exc.violations {
			if v.field == 'name' && v.constraint == 'required' {
				has_required = true
			}
		}
		assert has_required, 'should have required violation on name'
		return
	}
	assert failed, 'should have failed for empty name'
}

fn test_validate_method_params_min_fail() {
	mut failed := false
	validate_method_params[UserService]('create_user', {
		'name':  'John'
		'age':   '0'
		'email': 'user@example.com'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len == 1, 'should have 1 violation, got: ${exc.violations.len}'
		assert exc.violations[0].field == 'age'
		assert exc.violations[0].constraint == 'min'
		return
	}
	assert failed, 'should have failed for age=0 with min:1'
}

fn test_validate_method_params_min_pass() {
	validate_method_params[UserService]('create_user', {
		'name':  'John'
		'age':   '1'
		'email': 'user@example.com'
	}) or {
		assert false, 'should not fail for age=1 with min:1: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_max_fail() {
	mut failed := false
	validate_method_params[UserService]('create_user', {
		'name':  'John'
		'age':   '200'
		'email': 'user@example.com'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len == 1
		assert exc.violations[0].field == 'age'
		assert exc.violations[0].constraint == 'max'
		return
	}
	assert failed, 'should have failed for age=200 with max:150'
}

fn test_validate_method_params_max_pass() {
	validate_method_params[UserService]('create_user', {
		'name':  'John'
		'age':   '50'
		'email': 'user@example.com'
	}) or {
		assert false, 'should not fail for age=50 with max:150: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_min_len_fail() {
	mut failed := false
	validate_method_params[UserService]('create_user', {
		'name':  'A'
		'age':   '5'
		'email': 'user@example.com'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len == 1
		assert exc.violations[0].field == 'name'
		assert exc.violations[0].constraint == 'min_len'
		return
	}
	assert failed, 'should have failed for name="A" with min_len:2'
}

fn test_validate_method_params_no_max_len_constraint() {
	// create_user has name:required|min_len:2 — no max_len, so a long name passes
	validate_method_params[UserService]('create_user', {
		'name':  'VeryLongName'
		'age':   '5'
		'email': 'user@example.com'
	}) or {
		assert false, 'should not fail — create_user has no max_len on name: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_email_valid() {
	validate_method_params[UserService]('create_user', {
		'name':  'John'
		'age':   '5'
		'email': 'user@example.com'
	}) or {
		assert false, 'should not fail for valid email: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_email_invalid() {
	mut failed := false
	validate_method_params[UserService]('create_user', {
		'name':  'John'
		'age':   '5'
		'email': 'not-an-email'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len == 1
		assert exc.violations[0].field == 'email'
		assert exc.violations[0].constraint == 'email'
		return
	}
	assert failed, 'should have failed for invalid email'
}

fn test_validate_method_params_email_empty_passes() {
	// email is not required, so empty should pass
	validate_method_params[UserService]('create_user', {
		'name':  'John'
		'age':   '5'
		'email': ''
	}) or {
		assert false, 'should not fail for empty email (not required): ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_multiple_violations() {
	mut failed := false
	validate_method_params[UserService]('create_user', {
		'name':  ''
		'age':   '0'
		'email': 'bad'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len >= 3, 'should have at least 3 violations, got: ${exc.violations.len}'
		// Verify all three fields are present
		mut fields := map[string]bool{}
		for v in exc.violations {
			fields[v.field] = true
		}
		assert fields['name'] == true, 'should have name violation'
		assert fields['age'] == true, 'should have age violation'
		assert fields['email'] == true, 'should have email violation'
		return
	}
	assert failed, 'should have failed with multiple violations'
}

fn test_validate_method_params_no_valid_annotation() {
	// unannotated_method has no @[valid] — validation should be skipped (no error)
	validate_method_params[UserService]('unannotated_method', {
		'name': ''
		'age':  '0'
	}) or {
		assert false, 'unannotated method should not trigger validation: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_bare_valid_no_constraints() {
	// bare_valid_method has @[valid] but no constraint string — no validation
	validate_method_params[UserService]('bare_valid_method', {
		'name': ''
	}) or {
		assert false, 'bare @[valid] with no constraints should not fail: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_no_param_method() {
	// no_param_method has @[valid] and no params — validation passes
	validate_method_params[UserService]('no_param_method', {}) or {
		assert false, 'no-param method should not fail: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_paren_form() {
	// paren_form_method uses @[valid('...')] syntax
	mut failed := false
	validate_method_params[UserService]('paren_form_method', {
		'name': ''
		'age':  '0'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len >= 2, 'should have at least 2 violations, got: ${exc.violations.len}'
		return
	}
	assert failed, 'paren form should trigger validation'
}

fn test_validate_method_params_paren_form_pass() {
	validate_method_params[UserService]('paren_form_method', {
		'name': 'John'
		'age':  '5'
	}) or {
		assert false, 'should not fail for valid params: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_update_email() {
	validate_method_params[UserService]('update_email', {
		'email': 'user@example.com'
	}) or {
		assert false, 'should not fail for valid email: ${err.msg()}'
		return
	}
	assert true
}

fn test_validate_method_params_update_email_fail() {
	mut failed := false
	validate_method_params[UserService]('update_email', {
		'email': 'bad'
	}) or {
		failed = true
		exc := err as ConstraintViolationException
		assert exc.violations.len == 1
		assert exc.violations[0].field == 'email'
		return
	}
	assert failed, 'should fail for invalid email'
}

fn test_validate_method_params_nonexistent_method() {
	// Nonexistent method — no validation, no error
	validate_method_params[UserService]('nonexistent_method', {
		'name': ''
	}) or {
		assert false, 'nonexistent method should not fail: ${err.msg()}'
		return
	}
	assert true
}

// ── has_valid_annotation Tests ──

fn test_has_valid_annotation_true() {
	assert has_valid_annotation[UserService]('create_user') == true
	assert has_valid_annotation[UserService]('no_param_method') == true
	assert has_valid_annotation[UserService]('bare_valid_method') == true
	assert has_valid_annotation[UserService]('paren_form_method') == true
	assert has_valid_annotation[UserService]('update_email') == true
}

fn test_has_valid_annotation_false() {
	assert has_valid_annotation[UserService]('unannotated_method') == false
}

fn test_has_valid_annotation_nonexistent() {
	assert has_valid_annotation[UserService]('nonexistent_method') == false
}

// ── extract_valid_constraints Tests ──

fn test_extract_valid_constraints_create_user() {
	constraints := extract_valid_constraints[UserService]('create_user')
	assert constraints.contains('name:required'), 'should contain name:required, got: ${constraints}'
	assert constraints.contains('age:min:1'), 'should contain age:min:1, got: ${constraints}'
	assert constraints.contains('email:email'), 'should contain email:email, got: ${constraints}'
}

fn test_extract_valid_constraints_bare_valid() {
	// bare @[valid] has no constraint string
	constraints := extract_valid_constraints[UserService]('bare_valid_method')
	assert constraints == '', 'bare @[valid] should return empty string, got: ${constraints}'
}

fn test_extract_valid_constraints_unannotated() {
	constraints := extract_valid_constraints[UserService]('unannotated_method')
	assert constraints == '', 'unannotated method should return empty string'
}

fn test_extract_valid_constraints_paren_form() {
	constraints := extract_valid_constraints[UserService]('paren_form_method')
	assert constraints.contains('name:required'), 'paren form should extract constraints, got: ${constraints}'
	assert constraints.contains('age:min:1'), 'paren form should extract age constraints, got: ${constraints}'
}

// ── is_valid_email Tests ──

fn test_is_valid_email_valid() {
	assert is_valid_email('user@example.com') == true
	assert is_valid_email('john.doe@company.co.uk') == true
}

fn test_is_valid_email_invalid() {
	assert is_valid_email('not-an-email') == false
	assert is_valid_email('@example.com') == false
	assert is_valid_email('user@') == false
}

fn test_is_valid_email_empty() {
	// Empty is considered valid (use 'required' rule to reject)
	assert is_valid_email('') == true
}

// ── ConstraintViolation struct Tests ──

fn test_constraint_violation_fields() {
	v := ConstraintViolation{
		field:      'email'
		value:      'bad'
		constraint: 'email'
		message:    'invalid email'
	}
	assert v.field == 'email'
	assert v.value == 'bad'
	assert v.constraint == 'email'
	assert v.message == 'invalid email'
}

// ── Integration: actual method call after validation ──

fn test_validate_then_call_method() {
	params := {
		'name':  'Alice'
		'age':   '30'
		'email': 'alice@example.com'
	}
	validate_method_params[UserService]('create_user', params) or {
		assert false, 'validation should pass: ${err.msg()}'
		return
	}
	// Validation passed — now actually call the method
	mut service := UserService{}
	service.create_user(params['name'] or { '' }, params['age'] or { '0' }.int(),
		params['email'] or { '' })
	assert service.last_name == 'Alice'
	assert service.last_age == 30
}

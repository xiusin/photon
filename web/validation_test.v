module web

// ── Basic Validation Tests ──

fn test_parse_rules() {
	rules := parse_rules('required|min_len:3|max_len:20|email')
	assert rules.len == 4
	assert rules[0] == 'required'
	assert rules[1] == 'min_len:3'
	assert rules[2] == 'max_len:20'
	assert rules[3] == 'email'
}

fn test_parse_rule() {
	name, arg := parse_rule('min_len:3')
	assert name == 'min_len'
	assert arg == '3'

	name2, arg2 := parse_rule('required')
	assert name2 == 'required'
	assert arg2.len == 0
}

fn test_validate_required() {
	assert validate_required('hello') == true
	assert validate_required('') == false
	assert validate_required('   ') == true // non-empty
}

fn test_validate_min() {
	assert validate_min('10', '5') == true
	assert validate_min('3', '5') == false
	assert validate_min('', '5') == false
}

fn test_validate_max() {
	assert validate_max('3', '5') == true
	assert validate_max('10', '5') == false
	assert validate_max('', '5') == true // empty passes max
}

fn test_validate_min_len() {
	assert validate_min_len('hello', '3') == true
	assert validate_min_len('hi', '3') == false
	assert validate_min_len('', '0') == true
}

fn test_validate_max_len() {
	assert validate_max_len('hi', '5') == true
	assert validate_max_len('hello world', '5') == false
}

fn test_validate_email() {
	assert validate_email('user@example.com') == true
	assert validate_email('invalid') == false
	assert validate_email('') == true // empty passes
	assert validate_email('@example.com') == false
}

fn test_validate_url() {
	assert validate_url('https://example.com') == true
	assert validate_url('http://test.com/path') == true
	assert validate_url('ftp://wrong.com') == false
	assert validate_url('') == true
}

fn test_validate_alpha() {
	assert validate_alpha('hello') == true
	assert validate_alpha('hello123') == false
	assert validate_alpha('') == true
}

fn test_validate_alpha_num() {
	assert validate_alpha_num('hello_123') == true
	assert validate_alpha_num('hello-123') == false
	assert validate_alpha_num('') == true
}

fn test_validate_numeric() {
	assert validate_numeric('123.45') == true
	assert validate_numeric('-42') == true
	assert validate_numeric('abc') == false
	assert validate_numeric('') == true
}

fn test_validate_in() {
	assert validate_in('admin', 'ADMIN,USER,GUEST') == true
	assert validate_in('super', 'ADMIN,USER,GUEST') == false
	assert validate_in('x', '') == true
}

fn test_validate_not_in() {
	assert validate_not_in('super', 'ADMIN,USER,GUEST') == true
	assert validate_not_in('admin', 'ADMIN,USER,GUEST') == false
}

fn test_validate_between() {
	assert validate_between('5', '1,10') == true
	assert validate_between('15', '1,10') == false
	assert validate_between('', '1,10') == true
}

fn test_validate_integer() {
	assert validate_integer('42') == true
	assert validate_integer('-10') == true
	assert validate_integer('3.14') == false
	assert validate_integer('') == true
}

fn test_validate_boolean() {
	assert validate_boolean('true') == true
	assert validate_boolean('false') == true
	assert validate_boolean('1') == true
	assert validate_boolean('0') == true
	assert validate_boolean('yes') == true
	assert validate_boolean('maybe') == false
}

fn test_validate_starts_with() {
	assert validate_starts_with('hello world', 'hello') == true
	assert validate_starts_with('world', 'hello') == false
}

fn test_validate_ends_with() {
	assert validate_ends_with('hello.txt', '.txt') == true
	assert validate_ends_with('hello', '.txt') == false
}

fn test_validate_digits() {
	assert validate_digits('12345', '5') == true
	assert validate_digits('12345', '3') == false
	assert validate_digits('abcde', '5') == false
}

fn test_validate_ip() {
	assert validate_ip('192.168.1.1') == true
	assert validate_ip('255.255.255.255') == true
	assert validate_ip('256.1.1.1') == false
	assert validate_ip('1.2.3') == false
	assert validate_ip('') == true
}

fn test_validate_vjson() {
	assert validate_vjson('{"key": "value"}') == true
	assert validate_vjson('[1, 2, 3]') == true
	assert validate_vjson('not json') == false
}

// ── New Validation Rules Tests ──

fn test_validate_uuid() {
	assert validate_uuid('550e8400-e29b-41d4-a716-446655440000') == true
	assert validate_uuid('invalid') == false
	assert validate_uuid('550e8400-e29b-51d4-a716-446655440000') == false
	assert validate_uuid('550e8400-e29b-41d4-c716-446655440000') == false
	assert validate_uuid('') == true
}

fn test_validate_date() {
	assert validate_date('2024-01-15') == true
	assert validate_date('1999-12-31') == true
	assert validate_date('2024-13-01') == false
	assert validate_date('2024-00-15') == false
	assert validate_date('2024-01-32') == false
	assert validate_date('24-01-15') == false
	assert validate_date('') == true
}

fn test_validate_timezone() {
	assert validate_timezone('UTC') == true
	assert validate_timezone('GMT') == true
	assert validate_timezone('America/New_York') == true
	assert validate_timezone('Europe/London') == true
	assert validate_timezone('Invalid') == false
	assert validate_timezone('') == true
}

fn test_validate_phone() {
	assert validate_phone('+1 (555) 123-4567') == true
	assert validate_phone('555-123-4567') == true
	assert validate_phone('5551234567') == true
	assert validate_phone('123') == false
	assert validate_phone('abc') == false
	assert validate_phone('') == true
}

fn test_validate_password_strength() {
	assert validate_password_strength('Abc123!@', '8,1,1,1,2') == true
	assert validate_password_strength('Ab1!', '8,1,1,1,2') == false
	assert validate_password_strength('abc123!@', '8,1,1,1,2') == false
	assert validate_password_strength('Abcdef!@', '8,1,1,1,2') == false
	assert validate_password_strength('Abcdef12', '8,1,1,1,2') == false
	assert validate_password_strength('', '') == true
}

// ── ValidationError Tests ──

fn test_validation_error_str() {
	err := ValidationError{
		field: 'email'
		rule: 'email'
		message: 'email must be a valid email address'
		value: 'invalid'
	}
	assert err.str() == 'email: email must be a valid email address'
}

// ── ValidationErrors Tests ──

fn test_validation_errors_has_errors() {
	errors := new_validation_errors()
	assert errors.has_errors() == false

	mut errors2 := new_validation_errors()
	errors2['field'] = [ValidationError{}]
	assert errors2.has_errors() == true
}

fn test_validation_errors_first() {
	errors := new_validation_errors()
	assert errors.has_errors() == false

	mut errors2 := new_validation_errors()
	errors2['name'] = [ValidationError{field: 'name', rule: 'required', message: 'name is required'}]
	// Verify the error is there via all_messages
	messages := errors2.all_messages()
	assert messages.len == 1
	assert messages[0].contains('name is required')
}

fn test_validation_errors_all_messages() {
	mut errors := new_validation_errors()
	errors['email'] = [ValidationError{message: 'email is invalid'}, ValidationError{message: 'email is required'}]
	errors['name'] = [ValidationError{message: 'name is required'}]

	messages := errors.all_messages()
	assert messages.len == 3
	assert 'email is invalid' in messages
	assert 'name is required' in messages
}

fn test_validation_errors_merge() {
	mut errors := new_validation_errors()
	errors['field1'] = [ValidationError{field: 'field1', rule: 'required', message: 'field1 is required'}]

	mut other := new_validation_errors()
	other['field2'] = [ValidationError{field: 'field2', rule: 'email', message: 'field2 must be email'}]
	other['field1'] = [ValidationError{field: 'field1', rule: 'min_len', message: 'field1 too short'}]

	errors.merge(other)
	assert errors['field1'].len == 2
	assert errors['field2'].len == 1
}

fn test_validation_errors_for() {
	mut errors := new_validation_errors()
	errors['email'] = [ValidationError{field: 'email', message: 'bad email'}]
	errors['name'] = [ValidationError{field: 'name', message: 'bad name'}]

	field_errors := errors.errors_for('email')
	assert field_errors.len == 1
	assert field_errors[0].message == 'bad email'

	empty_errors := errors.errors_for('nonexistent')
	assert empty_errors.len == 0
}

// ── Apply Rule Tests ──

fn test_apply_rule_required_pass() {
	pass, _ := check_rule('username', 'john', 'required')
	assert pass == true
}

fn test_apply_rule_required_fail() {
	pass, msg := check_rule('username', '', 'required')
	assert pass == false
	assert msg.contains('required')
}

fn test_apply_rule_email_fail() {
	pass, _ := check_rule('email', 'not-an-email', 'email')
	assert pass == false
}

fn test_apply_rule_min_len_fail() {
	pass, _ := check_rule('password', 'ab', 'min_len:6')
	assert pass == false
}

fn test_apply_rule_unknown_rule() {
	pass, _ := check_rule('field', 'value', 'unknown_rule')
	assert pass == true // unknown rules pass
}

// ── Default Error Message Tests ──

fn test_default_error_message() {
	msg := default_error_message('username', 'required', '')
	assert msg == 'username is required'

	msg2 := default_error_message('age', 'min', '18')
	assert msg2 == 'age must be at least 18'

	msg3 := default_error_message('role', 'in', 'ADMIN,USER,GUEST')
	assert msg3.contains('ADMIN')

	msg4 := default_error_message('count', 'between', '1,100')
	assert msg4.contains('1 and 100')
}

// ── Custom Validator Tests ──

fn test_register_and_use_custom_validator() {
	clear_custom_validators()

	register_validator(
		'even',
		fn (value string, arg string) bool {
			if value.len == 0 { return true }
			num := value.int()
			return num % 2 == 0
		},
		fn (field string, arg string) string {
			return '${field} must be an even number'
		}
	)

	pass1, _ := check_rule('count', '4', 'even')
	assert pass1 == true // 4 is even, should pass

	pass2, msg2 := check_rule('count', '3', 'even')
	assert pass2 == false
	assert msg2.contains('even')

	clear_custom_validators()
}

fn test_multiple_custom_validators() {
	clear_custom_validators()

	register_validator(
		'positive',
		fn (value string, arg string) bool {
			if value.len == 0 { return true }
			num := value.int()
			return num > 0
		},
		fn (field string, arg string) string {
			return '${field} must be positive'
		}
	)

	register_validator(
		'multiple_of',
		fn (value string, arg string) bool {
			if value.len == 0 || arg.len == 0 { return true }
			num := value.int()
			mod := arg.int()
			return mod != 0 && num % mod == 0
		},
		fn (field string, arg string) string {
			return '${field} must be a multiple of ${arg}'
		}
	)

	pass_pos, _ := check_rule('amount', '10', 'positive')
	assert pass_pos == true
	fail_neg, _ := check_rule('amount', '-5', 'positive')
	assert fail_neg == false

	pass_mult, _ := check_rule('quantity', '9', 'multiple_of:3')
	assert pass_mult == true
	fail_mult, _ := check_rule('quantity', '10', 'multiple_of:3')
	assert fail_mult == false

	clear_custom_validators()
}

// ── Nested Validation Tests ──

fn test_nested_validation_no_errors() {
	rules := {
		'street': 'required|min_len:5'
		'city':    'required'
		'zip':     'digits:5'
	}

	params := {
		'street': '123 Main St'
		'city':    'Springfield'
		'zip':     '90210'
	}

	errors := validate_nested(params, 'address', rules)
	assert errors.has_errors() == false
}

fn test_nested_validation_with_errors() {
	rules := {
		'street': 'required|min_len:5'
		'city':    'required'
		'zip':     'digits:5'
	}

	params := {
		'street': 'St' // too short
		'zip':    'ABC' // not digits
		// city missing
	}

	errors := validate_nested(params, 'address', rules)
	assert errors.has_errors() == true
	assert errors.len == 1
	assert errors[0].path == 'address'

	// Flatten to check field-level errors (keys use dot-notation: prefix.field)
	flat := errors.flatten()
	assert flat.has_errors() == true
	assert flat['address.street'].len >= 1
	assert flat['address.city'].len >= 1
	assert flat['address.zip'].len >= 1
}

fn test_nested_validation_all_messages() {
	rules := {
		'name': 'required'
	}

	params := map[string]string{}

	errors := validate_nested(params, 'user', rules)
	messages := errors.all_nested_messages()
	assert messages.len > 0
	assert messages[0].contains('user.name')
}

fn test_nested_validation_flatten_empty() {
	errors := NestedValidationErrors{}
	flat := errors.flatten()
	assert flat.has_errors() == false
}

// ── Conditional Validation Tests ──

fn test_required_if_condition() {
	cond := required_if('account_type', 'premium')

	// When account_type is premium, condition should be true
	params_premium := {'account_type': 'premium'}
	assert cond.check(params_premium) == true

	// When account_type is not premium, condition should be false
	params_free := {'account_type': 'free'}
	assert cond.check(params_free) == false
}

fn test_required_unless_condition() {
	cond := required_unless('account_type', 'guest')

	// When account_type is guest, condition should be false (not required)
	params_guest := {'account_type': 'guest'}
	assert cond.check(params_guest) == false

	// When account_type is not guest, condition should be true (required)
	params_user := {'account_type': 'user'}
	assert cond.check(params_user) == true
}

// ── Rule Parsing Edge Cases ──

fn test_parse_rules_empty() {
	rules := parse_rules('')
	assert rules.len == 1 // split returns ['']
	assert rules[0] == ''
}

fn test_parse_rules_single() {
	rules := parse_rules('required')
	assert rules.len == 1
	assert rules[0] == 'required'
}

fn test_parse_rule_complex_arg() {
	name, arg := parse_rule('in:ADMIN,USER,GUEST')
	assert name == 'in'
	assert arg == 'ADMIN,USER,GUEST'

	name2, arg2 := parse_rule('between:1,100')
	assert name2 == 'between'
	assert arg2 == '1,100'
}

// ── Validation Error Response Helper Tests ──

fn test_validation_error_response() {
	mut errors := new_validation_errors()
	errors['email'] = [ValidationError{message: 'email is invalid'}]
	errors['name'] = [ValidationError{message: 'name is required'}]

	resp := validation_error(errors)
	assert resp.code == 422
	assert resp.message.contains('email is invalid')
	assert resp.message.contains('name is required')
}

fn test_validation_error_empty() {
	errors := new_validation_errors()
	resp := validation_error(errors)
	// Should still return a proper response structure
	assert resp.code == 422
}

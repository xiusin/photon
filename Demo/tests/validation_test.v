module main

// tests/validation_test.v — 表单验证规则测试
//
// 测试覆盖：
//   - required / min_len / max_len 字符串规则
//   - email / url / alpha / alpha_num / numeric 格式规则
//   - in / not_in / between 范围规则
//   - confirmed / different / same 比较规则
//   - DTO 级别验证（CreateUserDto / CreatePostDto / CreateCommentDto）
//
// 验证规则由 photon.web 模块提供，DTO 在 models.v 中通过
// @[validate: '...'] 注解声明规则。

import photon.web

// ═══════════════════════════════════════════════════════════
// required 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_required_empty() {
	assert web.validate_required('') == false
}

fn test_validate_required_non_empty() {
	assert web.validate_required('hello') == true
}

fn test_validate_required_whitespace() {
	// 空格不为空（required 只检查长度）
	assert web.validate_required(' ') == true
}

// ═══════════════════════════════════════════════════════════
// min_len / max_len 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_min_len_pass() {
	assert web.validate_min_len('hello', '3') == true
	assert web.validate_min_len('hello', '5') == true
}

fn test_validate_min_len_fail() {
	assert web.validate_min_len('hi', '3') == false
	assert web.validate_min_len('', '1') == false
}

fn test_validate_max_len_pass() {
	assert web.validate_max_len('hello', '10') == true
	assert web.validate_max_len('hello', '5') == true
}

fn test_validate_max_len_fail() {
	assert web.validate_max_len('hello world', '5') == false
}

fn test_validate_min_len_empty_arg() {
	// 空参数应通过
	assert web.validate_min_len('any', '') == true
}

// ═══════════════════════════════════════════════════════════
// email 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_email_valid() {
	assert web.validate_email('user@example.com') == true
	assert web.validate_email('test.user@sub.domain.com') == true
}

fn test_validate_email_invalid() {
	assert web.validate_email('notanemail') == false
	assert web.validate_email('missing@domain') == false
	assert web.validate_email('@domain.com') == false
}

fn test_validate_email_empty_passes() {
	// 空值通过 email 检查（应配合 required 使用）
	assert web.validate_email('') == true
}

// ═══════════════════════════════════════════════════════════
// alpha / alpha_num 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_alpha_valid() {
	assert web.validate_alpha('hello') == true
	assert web.validate_alpha('HelloWorld') == true
}

fn test_validate_alpha_invalid() {
	assert web.validate_alpha('hello123') == false
	assert web.validate_alpha('hello world') == false
	assert web.validate_alpha('hello!') == false
}

fn test_validate_alpha_num_valid() {
	assert web.validate_alpha_num('hello123') == true
	assert web.validate_alpha_num('user_name_42') == true
}

fn test_validate_alpha_num_invalid() {
	assert web.validate_alpha_num('hello world') == false
	assert web.validate_alpha_num('hello!') == false
	assert web.validate_alpha_num('hello-world') == false
}

// ═══════════════════════════════════════════════════════════
// numeric 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_numeric_valid() {
	assert web.validate_numeric('123') == true
	assert web.validate_numeric('12.34') == true
	assert web.validate_numeric('-42') == true
}

fn test_validate_numeric_invalid() {
	assert web.validate_numeric('12abc') == false
	assert web.validate_numeric('') == false
}

// ═══════════════════════════════════════════════════════════
// in / not_in 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_in_found() {
	assert web.validate_in('USER', 'USER,EDITOR,ADMIN') == true
	assert web.validate_in('admin', 'USER,EDITOR,ADMIN') == true // 大小写不敏感
}

fn test_validate_in_not_found() {
	assert web.validate_in('GUEST', 'USER,EDITOR,ADMIN') == false
}

fn test_validate_not_in() {
	assert web.validate_not_in('USER', 'ADMIN,ROOT') == true
	assert web.validate_not_in('ADMIN', 'ADMIN,ROOT') == false
}

// ═══════════════════════════════════════════════════════════
// between 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_between_in_range() {
	assert web.validate_between('5', '0,10') == true
	assert web.validate_between('0', '0,10') == true
	assert web.validate_between('10', '0,10') == true
}

fn test_validate_between_out_of_range() {
	assert web.validate_between('11', '0,10') == false
	assert web.validate_between('-1', '0,10') == false
}

// ═══════════════════════════════════════════════════════════
// confirmed 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_confirmed_match() {
	params := {'password': 'secret123', 'password_confirmation': 'secret123'}
	assert web.validate_confirmed('secret123', 'password', params) == true
}

fn test_validate_confirmed_mismatch() {
	params := {'password': 'secret123', 'password_confirmation': 'different'}
	assert web.validate_confirmed('secret123', 'password', params) == false
}

// ═══════════════════════════════════════════════════════════
// different / same 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_different() {
	params := {'username': 'alice', 'nickname': 'bob'}
	assert web.validate_different('bob', 'username', params) == true
	assert web.validate_different('alice', 'username', params) == false
}

fn test_validate_same() {
	params := {'email': 'a@b.com', 'email_confirm': 'a@b.com'}
	assert web.validate_same('a@b.com', 'email', params) == true
}

// ═══════════════════════════════════════════════════════════
// url 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_url_valid() {
	assert web.validate_url('http://example.com') == true
	assert web.validate_url('https://example.com/path') == true
}

fn test_validate_url_invalid() {
	assert web.validate_url('ftp://example.com') == false
	assert web.validate_url('example.com') == false
}

// ═══════════════════════════════════════════════════════════
// starts_with / ends_with 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_starts_with() {
	assert web.validate_starts_with('Hello World', 'Hello') == true
	assert web.validate_starts_with('Hello World', 'World') == false
}

fn test_validate_ends_with() {
	assert web.validate_ends_with('Hello World', 'World') == true
	assert web.validate_ends_with('Hello World', 'Hello') == false
}

// ═══════════════════════════════════════════════════════════
// UUID / date 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_uuid_valid() {
	assert web.validate_uuid('550e8400-e29b-41d4-a716-446655440000') == true
}

fn test_validate_uuid_invalid() {
	assert web.validate_uuid('not-a-uuid') == false
	assert web.validate_uuid('550e8400-e29b-41d4-a716') == false
}

fn test_validate_date_valid() {
	assert web.validate_date('2026-06-20') == true
	assert web.validate_date('2026/06/20') == true
}

fn test_validate_date_invalid() {
	assert web.validate_date('not-a-date') == false
	assert web.validate_date('2026-13-45') == false
}

// ═══════════════════════════════════════════════════════════
// password_strength 规则测试
// ═══════════════════════════════════════════════════════════

fn test_validate_password_strength_strong() {
	// 强密码：包含大小写字母、数字、特殊字符，长度 >= 8
	assert web.validate_password_strength('Password123!', 'strong') == true
}

fn test_validate_password_strength_weak() {
	assert web.validate_password_strength('weak', 'strong') == false
	assert web.validate_password_strength('password', 'strong') == false
}

// ═══════════════════════════════════════════════════════════
// DTO 验证规则注解测试（验证注解字符串解析正确）
// ═══════════════════════════════════════════════════════════

fn test_create_user_dto_validation_rules() {
	// 验证 CreateUserDto 的字段规则符合预期
	// 通过 comptime 检查注解是否存在
	$for field in CreateUserDto.fields {
		$if field.name == 'username' {
			mut has_required := false
			mut has_min_len := false
			for attr in field.attrs {
				if attr.contains('required') {
					has_required = true
				}
				if attr.contains('min_len:3') {
					has_min_len = true
				}
			}
			assert has_required
			assert has_min_len
		}
		$if field.name == 'email' {
			mut has_email_rule := false
			for attr in field.attrs {
				if attr.contains('email') {
					has_email_rule = true
				}
			}
			assert has_email_rule
		}
		$if field.name == 'password' {
			mut has_min_len_6 := false
			for attr in field.attrs {
				if attr.contains('min_len:6') {
					has_min_len_6 = true
				}
			}
			assert has_min_len_6
		}
	}
}

fn test_create_post_dto_validation_rules() {
	$for field in CreatePostDto.fields {
		$if field.name == 'title' {
			mut has_required := false
			mut has_max_len := false
			for attr in field.attrs {
				if attr.contains('required') {
					has_required = true
				}
				if attr.contains('max_len:255') {
					has_max_len = true
				}
			}
			assert has_required
			assert has_max_len
		}
		$if field.name == 'content' {
			mut has_required := false
			for attr in field.attrs {
				if attr.contains('required') {
					has_required = true
				}
			}
			assert has_required
		}
	}
}

fn test_create_comment_dto_validation_rules() {
	$for field in CreateCommentDto.fields {
		$if field.name == 'content' {
			mut has_required := false
			mut has_max_len := false
			for attr in field.attrs {
				if attr.contains('required') {
					has_required = true
				}
				if attr.contains('max_len:2000') {
					has_max_len = true
				}
			}
			assert has_required
			assert has_max_len
		}
	}
}

// ═══════════════════════════════════════════════════════════
// ValidationErrors 测试
// ═══════════════════════════════════════════════════════════

fn test_validation_errors_has_errors() {
	mut errors := web.ValidationErrors{}
	assert errors.has_errors() == false

	errors['username'] = [web.ValidationError{field: 'username', message: 'required'}]
	assert errors.has_errors() == true
}

fn test_validation_errors_count() {
	mut errors := web.ValidationErrors{}
	assert errors.count() == 0

	errors['username'] = [web.ValidationError{field: 'username', message: 'required'}]
	errors['email'] = [web.ValidationError{field: 'email', message: 'invalid'}]
	assert errors.count() == 2
}

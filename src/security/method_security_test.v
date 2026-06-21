module security

// method_security_test.v - Tests for @PreAuthorize / @PostAuthorize expression
// evaluation (Task C6). Covers hasRole, hasAnyRole, hasAuthority,
// hasAnyAuthority, hasPermission, #return (PostAuthorize), and `and` / `or`
// combinators, plus the AccessDeniedException type.

// ── hasRole ──

fn test_has_role_match() {
	ctx := MethodSecurityContext{
		user_roles: ['ADMIN']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN')", ctx)!
	assert allowed == true
}

fn test_has_role_with_role_prefix() {
	// Spring convention: hasRole('ADMIN') also matches 'ROLE_ADMIN'.
	ctx := MethodSecurityContext{
		user_roles: ['ROLE_ADMIN']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN')", ctx)!
	assert allowed == true
}

fn test_has_role_no_match() {
	ctx := MethodSecurityContext{
		user_roles: ['USER']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN')", ctx)!
	assert allowed == false
}

// ── hasAnyRole ──

fn test_has_any_role_match() {
	ctx := MethodSecurityContext{
		user_roles: ['USER']
	}
	allowed := evaluate_security_expression("hasAnyRole('ADMIN','USER')", ctx)!
	assert allowed == true
}

fn test_has_any_role_no_match() {
	ctx := MethodSecurityContext{
		user_roles: ['GUEST']
	}
	allowed := evaluate_security_expression("hasAnyRole('ADMIN','USER')", ctx)!
	assert allowed == false
}

fn test_has_any_role_with_role_prefix() {
	ctx := MethodSecurityContext{
		user_roles: ['ROLE_USER']
	}
	allowed := evaluate_security_expression("hasAnyRole('ADMIN','USER')", ctx)!
	assert allowed == true
}

// ── hasAuthority ──

fn test_has_authority_match() {
	ctx := MethodSecurityContext{
		user_authorities: ['write:users']
	}
	allowed := evaluate_security_expression("hasAuthority('write:users')", ctx)!
	assert allowed == true
}

fn test_has_authority_no_match() {
	ctx := MethodSecurityContext{
		user_authorities: ['read:users']
	}
	allowed := evaluate_security_expression("hasAuthority('write:users')", ctx)!
	assert allowed == false
}

// ── hasAnyAuthority ──

fn test_has_any_authority_match() {
	ctx := MethodSecurityContext{
		user_authorities: ['read:users']
	}
	allowed := evaluate_security_expression("hasAnyAuthority('write:users','read:users')", ctx)!
	assert allowed == true
}

fn test_has_any_authority_no_match() {
	ctx := MethodSecurityContext{
		user_authorities: ['delete:users']
	}
	allowed := evaluate_security_expression("hasAnyAuthority('write:users','read:users')", ctx)!
	assert allowed == false
}

// ── hasPermission ──

fn test_has_permission_match_two_args() {
	ctx := MethodSecurityContext{
		user_permissions: ['read']
	}
	allowed := evaluate_security_expression("hasPermission('read','user')", ctx)!
	assert allowed == true
}

fn test_has_permission_match_single_arg() {
	ctx := MethodSecurityContext{
		user_permissions: ['read']
	}
	allowed := evaluate_security_expression("hasPermission('read')", ctx)!
	assert allowed == true
}

fn test_has_permission_no_match() {
	ctx := MethodSecurityContext{
		user_permissions: ['write']
	}
	allowed := evaluate_security_expression("hasPermission('read')", ctx)!
	assert allowed == false
}

// ── and / or combinators ──

fn test_and_expression_both_true() {
	ctx := MethodSecurityContext{
		user_roles:       ['ADMIN']
		user_authorities: ['write']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN') and hasAuthority('write')", ctx)!
	assert allowed == true
}

fn test_and_expression_one_false() {
	ctx := MethodSecurityContext{
		user_roles:       ['ADMIN']
		user_authorities: ['read']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN') and hasAuthority('write')", ctx)!
	assert allowed == false
}

fn test_or_expression_either_true() {
	ctx := MethodSecurityContext{
		user_roles: ['USER']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN') or hasRole('USER')", ctx)!
	assert allowed == true
}

fn test_or_expression_both_false() {
	ctx := MethodSecurityContext{
		user_roles: ['GUEST']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN') or hasRole('USER')", ctx)!
	assert allowed == false
}

// ── Empty expression ──

fn test_empty_expression_allows() {
	ctx := MethodSecurityContext{}
	allowed := evaluate_security_expression('', ctx)!
	assert allowed == true
}

fn test_whitespace_only_expression_allows() {
	ctx := MethodSecurityContext{}
	allowed := evaluate_security_expression('   ', ctx)!
	assert allowed == true
}

// ── check_pre_authorize ──

fn test_check_pre_authorize_allowed() {
	ctx := MethodSecurityContext{
		user_roles: ['ADMIN']
	}
	check_pre_authorize("hasRole('ADMIN')", ctx)!
}

fn test_check_pre_authorize_denied() {
	ctx := MethodSecurityContext{
		user_roles: ['USER']
	}
	if _ := check_pre_authorize("hasRole('ADMIN')", ctx) {
		assert false, 'expected AccessDeniedException'
	} else {
		assert err is AccessDeniedException
		assert err.code() == 403
		assert err.msg().contains('access denied')
	}
}

// ── check_post_authorize ──

fn test_post_authorize_return_matches_allowed() {
	ctx := MethodSecurityContext{}
	check_post_authorize("#return == 'value'", ctx, 'value', false)!
}

fn test_post_authorize_return_mismatch_denied() {
	ctx := MethodSecurityContext{}
	if _ := check_post_authorize("#return == 'value'", ctx, 'other', false) {
		assert false, 'expected AccessDeniedException'
	} else {
		assert err is AccessDeniedException
		assert err.msg().contains('post-authorize denied')
	}
}

fn test_post_authorize_return_not_equals_allowed() {
	ctx := MethodSecurityContext{}
	// #return != 'value' is true when return is 'other'
	check_post_authorize("#return != 'value'", ctx, 'other', false)!
}

fn test_post_authorize_return_not_equals_denied() {
	ctx := MethodSecurityContext{}
	if _ := check_post_authorize("#return != 'value'", ctx, 'value', false) {
		assert false, 'expected AccessDeniedException'
	} else {
		assert err is AccessDeniedException
	}
}

fn test_post_authorize_return_is_null() {
	ctx := MethodSecurityContext{}
	check_post_authorize('#return == null', ctx, '', true)!
}

fn test_post_authorize_return_is_null_denied_when_not_null() {
	ctx := MethodSecurityContext{}
	if _ := check_post_authorize('#return == null', ctx, 'value', false) {
		assert false, 'expected AccessDeniedException'
	} else {
		assert err is AccessDeniedException
	}
}

fn test_post_authorize_return_is_not_null() {
	ctx := MethodSecurityContext{}
	check_post_authorize('#return != null', ctx, 'value', false)!
}

fn test_post_authorize_return_is_not_null_denied_when_null() {
	ctx := MethodSecurityContext{}
	if _ := check_post_authorize('#return != null', ctx, '', true) {
		assert false, 'expected AccessDeniedException'
	} else {
		assert err is AccessDeniedException
	}
}

// ── AccessDeniedException ──

fn test_access_denied_exception_default_code_is_403() {
	e := AccessDeniedException{
		message: 'denied'
	}
	assert e.code == 403
	assert e.code() == 403
	assert e.msg() == 'denied'
}

fn test_access_denied_exception_msg_contains_expression() {
	ctx := MethodSecurityContext{
		user_roles: ['USER']
	}
	if _ := check_pre_authorize("hasRole('ADMIN')", ctx) {
		assert false, 'expected AccessDeniedException'
	} else {
		// The error message should contain the original expression.
		assert err.msg().contains("hasRole('ADMIN')")
	}
}

// ── Multiple roles / case sensitivity ──

fn test_multiple_roles_any_match() {
	ctx := MethodSecurityContext{
		user_roles: ['USER', 'MANAGER', 'GUEST']
	}
	allowed := evaluate_security_expression("hasRole('MANAGER')", ctx)!
	assert allowed == true
}

fn test_multiple_roles_none_match() {
	ctx := MethodSecurityContext{
		user_roles: ['USER', 'GUEST']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN')", ctx)!
	assert allowed == false
}

fn test_has_role_case_sensitive() {
	// Role matching is case-sensitive by default.
	ctx := MethodSecurityContext{
		user_roles: ['admin']
	}
	allowed := evaluate_security_expression("hasRole('ADMIN')", ctx)!
	assert allowed == false
}

fn test_has_authority_case_sensitive() {
	ctx := MethodSecurityContext{
		user_authorities: ['Write:Users']
	}
	allowed := evaluate_security_expression("hasAuthority('write:users')", ctx)!
	assert allowed == false
}

// ── Double-quoted arguments ──

fn test_has_role_double_quoted_arg() {
	ctx := MethodSecurityContext{
		user_roles: ['ADMIN']
	}
	allowed := evaluate_security_expression('hasRole("ADMIN")', ctx)!
	assert allowed == true
}

// ── Unsupported expression ──

fn test_unsupported_expression_returns_error() {
	ctx := MethodSecurityContext{}
	if _ := evaluate_security_expression('isAuthenticated()', ctx) {
		assert false, 'expected error for unsupported expression'
	} else {
		// The error message should be bilingual.
		assert err.msg().contains('unsupported security expression')
	}
}

// ── parse_security_attrs integration ──

fn test_parse_pre_authorize_stores_expression() {
	config := parse_security_attrs(['pre_authorize:"hasRole(\'ADMIN\')"'])
	assert config.is_secured == true
	assert config.pre_authorize_expr == "hasRole('ADMIN')"
}

fn test_parse_post_authorize_stores_expression() {
	config := parse_security_attrs(['post_authorize:"#return == \'value\'"'])
	assert config.is_secured == true
	assert config.post_authorize_expr == "#return == 'value'"
}

fn test_parse_pre_and_post_authorize_together() {
	config := parse_security_attrs([
		"pre_authorize:\"hasRole('ADMIN')\"",
		"post_authorize:\"#return != null\"",
	])
	assert config.is_secured == true
	assert config.pre_authorize_expr == "hasRole('ADMIN')"
	assert config.post_authorize_expr == '#return != null'
}

fn test_parse_pre_authorize_has_permission_backward_compat() {
	// Existing behavior: hasPermission expressions still populate required_perms.
	config := parse_security_attrs(['pre_authorize:"hasPermission(\'read\')"'])
	assert config.is_secured == true
	assert config.pre_authorize_expr == "hasPermission('read')"
	assert config.required_perms.len == 1
	assert config.required_perms[0] == 'read'
}

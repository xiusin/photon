module security

// context_test.v - Tests for SecurityContext and SecurityContextHolder

// --- SecurityContext tests ---

fn test_new_security_context_empty() {
	sc := new_security_context()
	assert sc.is_authenticated() == false
	assert sc.get_username() == ''
	assert sc.get_roles().len == 0
}

fn test_set_and_get_authentication() {
	mut sc := new_security_context()
	mut auth := new_authentication('alice', 'secret')
	auth.mark_authenticated(['USER', 'ADMIN'])

	sc.set_authentication(auth)

	retrieved := sc.get_authentication()
	assert retrieved.principal == 'alice'
	assert retrieved.is_authenticated() == true
	assert retrieved.authorities.len == 2
}

fn test_is_authenticated_true() {
	mut sc := new_security_context()
	mut auth := new_authentication('bob', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	assert sc.is_authenticated() == true
}

fn test_is_authenticated_false_unauthenticated() {
	mut sc := new_security_context()
	// Authentication exists but isn't marked authenticated
	auth := new_authentication('carol', 'token')
	sc.set_authentication(auth)
	assert sc.is_authenticated() == false
}

fn test_is_authenticated_false_after_clear() {
	mut sc := new_security_context()
	mut auth := new_authentication('dave', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	sc.clear()
	assert sc.is_authenticated() == false
}

fn test_get_username_authenticated() {
	mut sc := new_security_context()
	mut auth := new_authentication('eve', 'token')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	assert sc.get_username() == 'eve'
}

fn test_get_username_cleared() {
	mut sc := new_security_context()
	mut auth := new_authentication('frank', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	sc.clear()
	assert sc.get_username() == ''
}

fn test_get_username_empty_context() {
	sc := new_security_context()
	assert sc.get_username() == ''
}

fn test_get_roles_authenticated() {
	mut sc := new_security_context()
	mut auth := new_authentication('grace', 'pass')
	auth.mark_authenticated(['USER', 'ADMIN', 'MANAGER'])
	sc.set_authentication(auth)
	roles := sc.get_roles()
	assert roles.len == 3
	assert roles[0] == 'USER'
	assert roles[1] == 'ADMIN'
	assert roles[2] == 'MANAGER'
}

fn test_get_roles_not_authenticated() {
	mut sc := new_security_context()
	auth := new_authentication('heidi', 'pass')
	// auth not marked as authenticated
	sc.set_authentication(auth)
	roles := sc.get_roles()
	assert roles.len == 0
}

fn test_get_roles_after_clear() {
	mut sc := new_security_context()
	mut auth := new_authentication('ivan', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	sc.clear()
	assert sc.get_roles().len == 0
}

fn test_get_roles_empty_authorities() {
	mut sc := new_security_context()
	mut auth := new_authentication('judy', 'pass')
	auth.mark_authenticated([]string{})
	sc.set_authentication(auth)
	assert sc.get_roles().len == 0
}

fn test_has_role_exact_match() {
	mut sc := new_security_context()
	mut auth := new_authentication('karl', 'pass')
	auth.mark_authenticated(['USER', 'ADMIN'])
	sc.set_authentication(auth)
	assert sc.has_role('ADMIN') == true
	assert sc.has_role('USER') == true
}

fn test_has_role_no_match() {
	mut sc := new_security_context()
	mut auth := new_authentication('lisa', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	assert sc.has_role('ADMIN') == false
}

fn test_has_role_empty_context() {
	sc := new_security_context()
	assert sc.has_role('ADMIN') == false
}

fn test_has_role_case_sensitive() {
	mut sc := new_security_context()
	mut auth := new_authentication('mike', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	assert sc.has_role('user') == false
}

fn test_has_any_role_match_found() {
	mut sc := new_security_context()
	mut auth := new_authentication('nancy', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	assert sc.has_any_role(['ADMIN', 'USER', 'MANAGER']) == true
}

fn test_has_any_role_no_match() {
	mut sc := new_security_context()
	mut auth := new_authentication('oscar', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	assert sc.has_any_role(['ADMIN', 'MANAGER', 'SUPER']) == false
}

fn test_has_any_role_role_prefix_match() {
	mut sc := new_security_context()
	mut auth := new_authentication('pat', 'pass')
	auth.mark_authenticated(['ROLE_ADMIN'])
	sc.set_authentication(auth)
	assert sc.has_any_role(['ADMIN']) == true
}

fn test_has_any_role_empty_required() {
	mut sc := new_security_context()
	mut auth := new_authentication('quinn', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	// No required roles should not match any
	assert sc.has_any_role([]string{}) == false
}

fn test_has_any_role_empty_context() {
	sc := new_security_context()
	assert sc.has_any_role(['ADMIN']) == false
}

fn test_clear_preserves_struct() {
	mut sc := new_security_context()
	mut auth := new_authentication('rachel', 'pass')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	sc.clear()
	// After clear, all accessors should return empty/default
	assert sc.is_authenticated() == false
	assert sc.get_username() == ''
	assert sc.get_roles().len == 0
	assert sc.has_role('USER') == false
}

fn test_multiple_set_authentication_overwrites() {
	mut sc := new_security_context()

	mut auth1 := new_authentication('sam', 'token1')
	auth1.mark_authenticated(['USER'])
	sc.set_authentication(auth1)
	assert sc.get_username() == 'sam'

	mut auth2 := new_authentication('tina', 'token2')
	auth2.mark_authenticated(['ADMIN'])
	sc.set_authentication(auth2)
	assert sc.get_username() == 'tina'
	assert sc.has_role('ADMIN') == true
	assert sc.has_role('USER') == false
}

// --- SecurityContextHolder tests ---

fn test_sch_new_has_context() {
	sch := SecurityContextHolder{}
	ctx := sch.get_context()
	assert ctx.is_authenticated() == false
}

fn test_sch_set_and_get_context() {
	mut sch := SecurityContextHolder{}
	mut ctx := new_security_context()
	mut auth := new_authentication('uma', 'pass')
	auth.mark_authenticated(['ADMIN'])
	ctx.set_authentication(auth)

	sch.set_context(ctx)
	assert sch.get_context().get_username() == 'uma'
}

fn test_sch_get_context_mut() {
	mut sch := SecurityContextHolder{}
	mut ctx := sch.get_context_mut()
	assert ctx.is_authenticated() == false
}

fn test_sch_clear_context() {
	mut sch := SecurityContextHolder{}
	mut ctx := new_security_context()
	mut auth := new_authentication('victor', 'pass')
	auth.mark_authenticated(['USER'])
	ctx.set_authentication(auth)
	sch.set_context(ctx)
	assert sch.get_context().is_authenticated() == true

	sch.clear_context()
	assert sch.get_context().is_authenticated() == false
}

fn test_sch_set_context_replaces_old() {
	mut sch := SecurityContextHolder{}

	mut ctx1 := new_security_context()
	mut auth1 := new_authentication('wendy', 'token1')
	auth1.mark_authenticated(['USER'])
	ctx1.set_authentication(auth1)
	sch.set_context(ctx1)
	assert sch.get_context().get_username() == 'wendy'

	mut ctx2 := new_security_context()
	mut auth2 := new_authentication('xavier', 'token2')
	auth2.mark_authenticated(['ADMIN'])
	ctx2.set_authentication(auth2)
	sch.set_context(ctx2)
	assert sch.get_context().get_username() == 'xavier'
}

fn test_sch_get_context_returns_same_ref() {
	mut sch := SecurityContextHolder{}
	ctx1 := sch.get_context()
	ctx2 := sch.get_context()
	// Both should reference the same context
	assert ctx1.is_authenticated() == ctx2.is_authenticated()
}

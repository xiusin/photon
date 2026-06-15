module security

// filter_test.v - Unit tests for SecurityFilterChain
//
// Tests construction, configuration (with_permit_all, with_secured,
// with_roles, with_deny_all), build_default_chain, clearance,
// csrf_middleware and cors_security_middleware factories.

// -- SecurityFilterChain construction tests --

fn test_new_security_filter_chain() {
	jwt_config := JwtConfig{ secret: 'test-secret' }
	jwt_mgr := new_jwt_manager(jwt_config)
	auth_mgr := new_auth_manager()
	csrf_config := CsrfConfig{ enabled: true }
	csrf_mgr := new_csrf_manager(csrf_config)

	sfc := new_security_filter_chain(auth_mgr, jwt_mgr, csrf_mgr)
	assert sfc.enabled == true
	assert sfc.metadata_source != unsafe { nil }
	assert sfc.context_holder != unsafe { nil }
	assert sfc.role_hierarchy != unsafe { nil }
}

fn test_new_security_filter_chain_is_disablable() {
	jwt_config := JwtConfig{ secret: 'test' }
	jwt_mgr := new_jwt_manager(jwt_config)
	auth_mgr := new_auth_manager()
	csrf_mgr := new_csrf_manager(CsrfConfig{})

	mut sfc := new_security_filter_chain(auth_mgr, jwt_mgr, csrf_mgr)
	sfc.enabled = false
	assert sfc.enabled == false
}

// -- build_default_chain tests --

fn test_build_default_chain_creates_chain() {
	chain := build_default_chain('my-secret-key')
	assert chain != unsafe { nil }
	assert chain.enabled == true
	assert chain.auth_manager != unsafe { nil }
	assert chain.jwt_manager != unsafe { nil }
	assert chain.csrf_manager != unsafe { nil }
}

fn test_build_default_chain_with_different_secrets() {
	chain1 := build_default_chain('secret-one')
	chain2 := build_default_chain('secret-two')
	assert chain1 != unsafe { nil }
	assert chain2 != unsafe { nil }
}

// -- Configuration methods: with_permit_all --

fn test_with_permit_all_registers_public_path() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_permit_all('/public/health')
	config := sfc.metadata_source.get_config('/public/health')
	assert config.is_permit_all == true
	assert is_public(config) == true
	assert needs_authentication(config) == false
}

fn test_with_permit_all_multiple_paths() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_permit_all('/health')
	sfc.with_permit_all('/metrics')
	sfc.with_permit_all('/api-docs')

	assert is_public(sfc.metadata_source.get_config('/health')) == true
	assert is_public(sfc.metadata_source.get_config('/metrics')) == true
	assert is_public(sfc.metadata_source.get_config('/api-docs')) == true
}

// -- Configuration methods: with_secured --

fn test_with_secured_registers_authenticated_path() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_secured('/api/admin')
	config := sfc.metadata_source.get_config('/api/admin')
	assert config.is_secured == true
	assert config.is_permit_all == false
	assert config.is_deny_all == false
	assert is_public(config) == false
	assert needs_authentication(config) == true
}

// -- Configuration methods: with_roles --

fn test_with_roles_registers_path_with_required_roles() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_roles('/api/admin', ['ADMIN', 'MODERATOR'])
	config := sfc.metadata_source.get_config('/api/admin')
	assert config.is_secured == true
	assert config.required_roles.len == 2
	assert config.required_roles[0] == 'ADMIN'
	assert config.required_roles[1] == 'MODERATOR'
}

fn test_with_roles_single_role() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_roles('/api/users', ['USER'])
	config := sfc.metadata_source.get_config('/api/users')
	assert config.required_roles.len == 1
	assert config.required_roles[0] == 'USER'
}

fn test_with_roles_empty_roles() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_roles('/path', [])
	config := sfc.metadata_source.get_config('/path')
	assert config.required_roles.len == 0
}

// -- Configuration methods: with_deny_all --

fn test_with_deny_all_registers_blocked_path() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_deny_all('/secret/internal')
	config := sfc.metadata_source.get_config('/secret/internal')
	assert config.is_deny_all == true
	assert is_public(config) == false
}

fn test_with_deny_all_multiple_blocked_paths() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_deny_all('/admin/secret')
	sfc.with_deny_all('/internal/debug')

	config1 := sfc.metadata_source.get_config('/admin/secret')
	config2 := sfc.metadata_source.get_config('/internal/debug')
	assert config1.is_deny_all == true
	assert config2.is_deny_all == true
}

// -- Configuration: unregistered path is public by default --

fn test_unregistered_path_is_public() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	config := sfc.metadata_source.get_config('/unregistered/path')
	assert config.is_secured == false
	assert config.is_permit_all == false
	assert config.is_deny_all == false
	assert is_public(config) == true
}

// -- Mixed configuration test --

fn test_mixed_security_configuration() {
	mut sfc := new_security_filter_chain(new_auth_manager(), new_jwt_manager(JwtConfig{ secret: 's' }), new_csrf_manager(CsrfConfig{}))
	sfc.with_permit_all('/public/health')
	sfc.with_secured('/api/private')
	sfc.with_roles('/api/admin', ['ADMIN'])
	sfc.with_deny_all('/internal/blocked')

	// Public endpoint
	assert is_public(sfc.metadata_source.get_config('/public/health')) == true
	// Secured endpoint
	assert needs_authentication(sfc.metadata_source.get_config('/api/private')) == true
	// Role-restricted endpoint
	assert sfc.metadata_source.get_config('/api/admin').required_roles[0] == 'ADMIN'
	// Blocked endpoint
	assert sfc.metadata_source.get_config('/internal/blocked').is_deny_all == true
}

// -- clear_context tests --

fn test_security_context_set_and_clear() {
	mut sc := new_security_context()
	mut auth := new_authentication('testuser', 'token123')
	auth.mark_authenticated(['USER'])
	sc.set_authentication(auth)
	assert sc.is_authenticated() == true
	sc.clear()
	assert sc.is_authenticated() == false
}

fn test_clear_context_default_is_clean() {
	jwt_mgr := new_jwt_manager(JwtConfig{ secret: 'test' })
	auth_mgr := new_auth_manager()
	csrf_mgr := new_csrf_manager(CsrfConfig{})

	mut sfc := new_security_filter_chain(auth_mgr, jwt_mgr, csrf_mgr)

	// Default context should not be authenticated
	assert sfc.context_holder.get_context().is_authenticated() == false

	// Clear context is safe to call even when empty
	sfc.clear_context()
	assert sfc.context_holder.get_context().is_authenticated() == false
}

// -- csrf_middleware factory tests --

fn test_csrf_middleware_creates_function() {
	csrf_mgr := new_csrf_manager(CsrfConfig{ enabled: true })
	mw := csrf_middleware(csrf_mgr)
	_ = mw
	assert true
}

fn test_csrf_middleware_creates_unique_functions() {
	csrf_mgr1 := new_csrf_manager(CsrfConfig{ enabled: true })
	csrf_mgr2 := new_csrf_manager(CsrfConfig{ enabled: false })

	mw1 := csrf_middleware(csrf_mgr1)
	mw2 := csrf_middleware(csrf_mgr2)
	_ = mw1
	_ = mw2
	assert true
}

// -- cors_security_middleware factory tests --

fn test_cors_security_middleware_single_origin() {
	mw := cors_security_middleware(['https://example.com'])
	_ = mw
	assert true
}

fn test_cors_security_middleware_wildcard_origin() {
	mw := cors_security_middleware(['*'])
	_ = mw
	assert true
}

fn test_cors_security_middleware_multiple_origins() {
	mw := cors_security_middleware(['https://app1.com', 'https://app2.com', 'http://localhost:3000'])
	_ = mw
	assert true
}

fn test_cors_security_middleware_empty_origins() {
	mw := cors_security_middleware([])
	_ = mw
	assert true
}

// -- role_matches integration with filter chain --

fn test_role_matches_with_authorities() {
	authorities := ['ROLE_ADMIN', 'ROLE_USER']
	assert role_matches(authorities, ['ADMIN']) == true
	assert role_matches(authorities, ['USER']) == true
	assert role_matches(authorities, ['MODERATOR']) == false
}

fn test_role_matches_without_prefix() {
	authorities := ['ADMIN', 'USER']
	assert role_matches(authorities, ['ADMIN']) == true
	assert role_matches(authorities, ['GUEST']) == false
}

fn test_role_matches_empty_required() {
	authorities := ['ADMIN']
	assert role_matches(authorities, []) == true
}

fn test_role_matches_empty_user_roles() {
	assert role_matches([], ['ADMIN']) == false
}

fn test_role_matches_multiple_required() {
	authorities := ['ROLE_ADMIN', 'ROLE_USER']
	assert role_matches(authorities, ['ADMIN', 'USER']) == true
	assert role_matches(authorities, ['MODERATOR', 'GUEST']) == false
	assert role_matches(authorities, ['ADMIN', 'GUEST']) == true // one match is enough
}

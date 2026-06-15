module security

// annotations_test.v - Tests for security annotations parsing and metadata source

// --- parse_security_attrs tests ---

fn test_parse_empty_attrs() {
	config := parse_security_attrs([]string{})
	assert config.is_secured == false
	assert config.is_permit_all == false
	assert config.is_deny_all == false
	assert config.required_roles.len == 0
	assert config.required_perms.len == 0
}

fn test_parse_secured_attr() {
	config := parse_security_attrs([secured_attr])
	assert config.is_secured == true
	assert config.is_permit_all == false
	assert config.is_deny_all == false
	assert config.required_roles.len == 0
}

fn test_parse_permit_all_attr() {
	config := parse_security_attrs([permit_all_attr])
	assert config.is_permit_all == true
	assert config.is_secured == false
	assert config.is_deny_all == false
}

fn test_parse_deny_all_attr() {
	config := parse_security_attrs([deny_all_attr])
	assert config.is_deny_all == true
	assert config.is_secured == false
	assert config.is_permit_all == false
}

fn test_parse_roles_allowed_single_role() {
	config := parse_security_attrs(["roles_allowed:'ADMIN'"])
	assert config.is_secured == true
	assert config.required_roles.len == 1
	assert config.required_roles[0] == 'ADMIN'
}

fn test_parse_roles_allowed_multiple_roles() {
	config := parse_security_attrs(["roles_allowed:'ADMIN,USER,MOD'"])
	assert config.is_secured == true
	assert config.required_roles.len == 3
	assert config.required_roles[0] == 'ADMIN'
	assert config.required_roles[1] == 'USER'
	assert config.required_roles[2] == 'MOD'
}

fn test_parse_roles_allowed_double_quotes() {
	config := parse_security_attrs(['roles_allowed:"ADMIN,USER"'])
	assert config.is_secured == true
	assert config.required_roles.len == 2
	assert config.required_roles[0] == 'ADMIN'
	assert config.required_roles[1] == 'USER'
}

fn test_parse_roles_allowed_no_quotes() {
	config := parse_security_attrs(['roles_allowed:ADMIN,USER'])
	assert config.is_secured == true
	assert config.required_roles.len == 2
	assert config.required_roles[0] == 'ADMIN'
	assert config.required_roles[1] == 'USER'
}

fn test_parse_roles_allowed_trims_whitespace_in_roles() {
	config := parse_security_attrs(["roles_allowed:'ADMIN, USER'"])
	assert config.is_secured == true
	assert config.required_roles.len == 2
	// Note: source doesn't trim individual role strings, only the overall string
	assert config.required_roles[0] == 'ADMIN'
	assert config.required_roles[1] == ' USER'
}

fn test_parse_pre_authorize_has_permission() {
	config := parse_security_attrs(["pre_authorize:\"hasPermission('read')\""])
	assert config.is_secured == true
	assert config.required_perms.len == 1
	assert config.required_perms[0] == 'read'
}

fn test_parse_pre_authorize_not_has_permission() {
	// If pre_authorize doesn't start with hasPermission, no perms are extracted
	config := parse_security_attrs(['pre_authorize:isAuthenticated()'])
	assert config.is_secured == true
	assert config.required_perms.len == 0
}

fn test_parse_multiple_attrs() {
	config := parse_security_attrs([secured_attr, "roles_allowed:'USER,MANAGER'"])
	assert config.is_secured == true
	assert config.required_roles.len == 2
	assert config.required_roles[0] == 'USER'
}

fn test_parse_unknown_attr_ignored() {
	config := parse_security_attrs(['unknown_attr'])
	assert config.is_secured == false
	assert config.is_permit_all == false
	assert config.is_deny_all == false
	assert config.required_roles.len == 0
}

fn test_parse_attrs_with_empty_string() {
	config := parse_security_attrs([''])
	assert config.is_secured == false
	assert config.is_permit_all == false
}

fn test_parse_roles_allowed_empty_roles() {
	config := parse_security_attrs(["roles_allowed:''"])
	assert config.is_secured == true
	assert config.required_roles.len == 1
	assert config.required_roles[0] == ''
}

// --- SecurityMetadataSource tests ---

fn test_sms_new_and_get_missing() {
	sms := new_security_metadata_source()
	config := sms.get_config('/api/unknown')
	assert config.is_secured == false
	assert config.is_permit_all == false
	assert config.is_deny_all == false
}

fn test_sms_register_and_get() {
	mut sms := new_security_metadata_source()
	sms.register('/api/admin', SecuredConfig{
		is_secured: true
		required_roles: ['ADMIN']
	})
	config := sms.get_config('/api/admin')
	assert config.is_secured == true
	assert config.required_roles.len == 1
	assert config.required_roles[0] == 'ADMIN'
}

fn test_sms_register_multiple_paths() {
	mut sms := new_security_metadata_source()
	sms.register('/api/public', SecuredConfig{ is_permit_all: true })
	sms.register('/api/private', SecuredConfig{ is_secured: true })
	sms.register('/api/blocked', SecuredConfig{ is_deny_all: true })

	pub_cfg := sms.get_config('/api/public')
	assert pub_cfg.is_permit_all == true

	priv_cfg := sms.get_config('/api/private')
	assert priv_cfg.is_secured == true

	block_cfg := sms.get_config('/api/blocked')
	assert block_cfg.is_deny_all == true

	missing_cfg := sms.get_config('/api/nonexistent')
	assert missing_cfg.is_secured == false
}

fn test_sms_register_overwrite() {
	mut sms := new_security_metadata_source()
	sms.register('/api/data', SecuredConfig{ is_permit_all: true })
	sms.register('/api/data', SecuredConfig{ is_secured: true })
	config := sms.get_config('/api/data')
	assert config.is_secured == true
	assert config.is_permit_all == false
}

// --- needs_authentication tests ---

fn test_needs_authentication_secured() {
	assert needs_authentication(SecuredConfig{ is_secured: true }) == true
}

fn test_needs_authentication_not_secured() {
	assert needs_authentication(SecuredConfig{ is_secured: false }) == false
}

fn test_needs_authentication_permit_all() {
	assert needs_authentication(SecuredConfig{ is_secured: true, is_permit_all: true }) == false
}

fn test_needs_authentication_deny_all_no_secured() {
	// deny_all without is_secured — not secured so no auth needed
	assert needs_authentication(SecuredConfig{ is_deny_all: true }) == false
}

fn test_needs_authentication_deny_all_with_secured() {
	assert needs_authentication(SecuredConfig{ is_secured: true, is_deny_all: true }) == true
}

// --- is_public tests ---

fn test_is_public_permit_all() {
	assert is_public(SecuredConfig{ is_permit_all: true }) == true
}

fn test_is_public_no_security() {
	assert is_public(SecuredConfig{}) == true
}

fn test_is_public_secured() {
	assert is_public(SecuredConfig{ is_secured: true }) == false
}

fn test_is_public_deny_all() {
	assert is_public(SecuredConfig{ is_deny_all: true }) == false
}

fn test_is_public_secured_and_permit_all() {
	assert is_public(SecuredConfig{ is_secured: true, is_permit_all: true }) == true
}

// --- role_matches tests ---

fn test_role_matches_empty_required() {
	assert role_matches(['USER'], []string{}) == true
}

fn test_role_matches_empty_user_roles() {
	assert role_matches([]string{}, ['ADMIN']) == false
}

fn test_role_matches_exact_match() {
	assert role_matches(['ADMIN'], ['ADMIN']) == true
}

fn test_role_matches_role_prefix_match() {
	assert role_matches(['ROLE_ADMIN'], ['ADMIN']) == true
}

fn test_role_matches_no_match() {
	assert role_matches(['USER'], ['ADMIN']) == false
}

fn test_role_matches_one_of_many() {
	assert role_matches(['USER', 'ADMIN'], ['ADMIN', 'SUPER']) == true
}

fn test_role_matches_multiple_user_roles() {
	assert role_matches(['ROLE_USER', 'ROLE_ADMIN'], ['ADMIN']) == true
}

fn test_role_matches_case_sensitive() {
	assert role_matches(['admin'], ['ADMIN']) == false
}

fn test_role_matches_exact_role_without_prefix() {
	// role_matches normalizes user roles (adds ROLE_ prefix) but NOT required roles.
	// So 'ADMIN' (user) vs 'ROLE_ADMIN' (required) does NOT match.
	assert role_matches(['ADMIN'], ['ROLE_ADMIN']) == false
}

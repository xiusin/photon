module security

// annotations.v - Security Annotations
//
// Defines Photon security annotations for method-level access control.
// Equivalent to Spring Security's @Secured, @RolesAllowed, @PreAuthorize.

pub const secured_attr = 'secured'
pub const roles_allowed_attr = 'roles_allowed'
pub const permit_all_attr = 'permit_all'
pub const deny_all_attr = 'deny_all'
pub const pre_authorize_attr = 'pre_authorize'

// SecuredConfig holds security configuration for an endpoint
pub struct SecuredConfig {
pub mut:
	is_secured     bool
	required_roles []string
	required_perms []string
	is_permit_all  bool
	is_deny_all    bool
}

// parse_security_attrs extracts security configuration from method attributes
pub fn parse_security_attrs(attrs []string) SecuredConfig {
	mut config := SecuredConfig{}

	for attr in attrs {
		if attr == secured_attr {
			config.is_secured = true
		} else if attr.starts_with('${roles_allowed_attr}:') {
			config.is_secured = true
			roles_str := attr['${roles_allowed_attr}:'.len..].trim("'").trim('"')
			config.required_roles = roles_str.split(',')
		} else if attr == permit_all_attr {
			config.is_permit_all = true
		} else if attr == deny_all_attr {
			config.is_deny_all = true
		} else if attr.starts_with('${pre_authorize_attr}:') {
			config.is_secured = true
			perm_str := attr['${pre_authorize_attr}:'.len..].trim("'").trim('"')
			if perm_str.starts_with('hasPermission') {
				config.required_perms = [perm_str['hasPermission('.len..perm_str.len - 1].trim("'").trim('"')]
			}
		}
	}

	return config
}

// SecurityMetadataSource provides security metadata for methods/endpoints
pub struct SecurityMetadataSource {
pub mut:
	configs map[string]SecuredConfig
}

// new_security_metadata_source creates a new SecurityMetadataSource
pub fn new_security_metadata_source() &SecurityMetadataSource {
	return &SecurityMetadataSource{
		configs: map[string]SecuredConfig{}
	}
}

// register adds security config for a path
pub fn (mut sms SecurityMetadataSource) register(path string, config SecuredConfig) {
	sms.configs[path] = config
}

// get_config retrieves security config for a path
pub fn (sms &SecurityMetadataSource) get_config(path string) SecuredConfig {
	return sms.configs[path] or { SecuredConfig{} }
}

// needs_authentication checks if the config requires authentication
pub fn needs_authentication(config SecuredConfig) bool {
	return config.is_secured && !config.is_permit_all
}

// is_public checks if the endpoint is publicly accessible
pub fn is_public(config SecuredConfig) bool {
	return config.is_permit_all || (!config.is_secured && !config.is_deny_all)
}

// role_matches checks if user roles satisfy the required roles
pub fn role_matches(user_roles []string, required_roles []string) bool {
	if required_roles.len == 0 {
		return true
	}
	for required in required_roles {
		for user_role in user_roles {
			if user_role == required || user_role == 'ROLE_${required}' {
				return true
			}
		}
	}
	return false
}

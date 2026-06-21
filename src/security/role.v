module security

// role.v - Role-Based Access Control (RBAC)
//
// Provides role and permission management with role hierarchy.
// Supports Spring Security-style role checking and method-level security.

// Role represents an application role
pub struct Role {
pub:
	name        string   // e.g., 'ADMIN', 'MODERATOR', 'USER'
	permissions []string // e.g., 'user:read', 'user:write', 'admin:settings'
	description string
}

// RoleHierarchy defines parent-child role relationships
// e.g., ADMIN > MODERATOR > USER (ADMIN inherits all MODERATOR and USER permissions)
pub struct RoleHierarchy {
pub mut:
	hierarchy map[string][]string // role_name → [parent_role_names]
}

// new_role_hierarchy creates a new RoleHierarchy
pub fn new_role_hierarchy() &RoleHierarchy {
	return &RoleHierarchy{
		hierarchy: map[string][]string{}
	}
}

// add_role adds a role with optional parent roles
pub fn (mut rh RoleHierarchy) add_role(role string, parents []string) {
	rh.hierarchy[role] = parents
}

// get_reachable_roles returns all roles reachable from the given role
// (the role itself plus all parent roles transitively)
pub fn (rh &RoleHierarchy) get_reachable_roles(role string) []string {
	mut reachable := []string{}
	rh.collect_roles(role, mut reachable)
	return reachable
}

// collect_roles recursively collects parent roles
fn (rh &RoleHierarchy) collect_roles(role string, mut collected []string) {
	// Check for duplicates
	for c in collected {
		if c == role {
			return
		}
	}
	collected << role

	parents := rh.hierarchy[role] or { return }
	for parent in parents {
		rh.collect_roles(parent, mut collected)
	}
}

// has_role checks if a user has a specific role (or inherits it)
pub fn (rh &RoleHierarchy) has_role(user_roles []string, required_role string) bool {
	for user_role in user_roles {
		reachable := rh.get_reachable_roles(user_role)
		for r in reachable {
			if r == required_role {
				return true
			}
		}
	}
	return false
}

// has_any_role checks if a user has any of the required roles
pub fn (rh &RoleHierarchy) has_any_role(user_roles []string, required_roles []string) bool {
	for required in required_roles {
		if rh.has_role(user_roles, required) {
			return true
		}
	}
	return false
}

// has_all_roles checks if a user has all of the required roles
pub fn (rh &RoleHierarchy) has_all_roles(user_roles []string, required_roles []string) bool {
	for required in required_roles {
		if !rh.has_role(user_roles, required) {
			return false
		}
	}
	return true
}

// has_permission checks if a user has a specific permission (via any of their roles)
pub fn (rh &RoleHierarchy) has_permission(user_roles []string, role_permissions map[string][]string, required_permission string) bool {
	for user_role in user_roles {
		reachable := rh.get_reachable_roles(user_role)
		for r in reachable {
			perms := role_permissions[r] or { continue }
			for p in perms {
				if p == required_permission {
					return true
				}
			}
		}
	}
	return false
}

// AccessDecisionManager makes authorization decisions
pub struct AccessDecisionManager {
pub mut:
	hierarchy        &RoleHierarchy
	role_permissions map[string][]string
}

// new_access_manager creates a new AccessDecisionManager
pub fn new_access_manager(hierarchy &RoleHierarchy) &AccessDecisionManager {
	return &AccessDecisionManager{
		hierarchy:        unsafe { hierarchy }
		role_permissions: map[string][]string{}
	}
}

// add_permission adds a permission to a role
pub fn (mut adm AccessDecisionManager) add_permission(role_name string, permission string) {
	mut perms := adm.role_permissions[role_name] or { []string{} }
	perms << permission
	adm.role_permissions[role_name] = perms
}

// decide checks if access should be granted
pub fn (adm &AccessDecisionManager) decide(user_roles []string, required_roles []string, required_permissions []string) bool {
	// Check roles
	if required_roles.len > 0 {
		if !adm.hierarchy.has_any_role(user_roles, required_roles) {
			return false
		}
	}

	// Check permissions
	if required_permissions.len > 0 {
		for perm in required_permissions {
			if !adm.hierarchy.has_permission(user_roles, adm.role_permissions, perm) {
				return false
			}
		}
	}

	return true
}

// -- Predefined Application Roles --

// build_default_hierarchy creates the standard role hierarchy: ADMIN > MODERATOR > USER > GUEST
pub fn build_default_hierarchy() &RoleHierarchy {
	mut hierarchy := new_role_hierarchy()
	hierarchy.add_role('ADMIN', ['MODERATOR'])
	hierarchy.add_role('MODERATOR', ['USER'])
	hierarchy.add_role('USER', ['GUEST'])
	hierarchy.add_role('GUEST', [])
	return hierarchy
}

// build_default_permissions creates standard CRUD permissions
pub fn build_default_permissions() map[string][]string {
	return {
		'ADMIN':     ['*', 'user:read', 'user:write', 'user:delete', 'admin:settings', 'admin:users']
		'MODERATOR': ['user:read', 'user:write']
		'USER':      ['user:read', 'self:write']
		'GUEST':     ['public:read']
	}
}

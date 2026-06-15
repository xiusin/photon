module security

// role_test.v - Unit tests for RBAC: RoleHierarchy, role checking,
// AccessDecisionManager, and permission management.
//
// Tests role hierarchy traversal, has_role/has_any_role/has_all_roles,
// permission checking, access decisions, and built-in defaults.

// -- Role struct tests --

fn test_role_struct() {
	r := Role{
		name: 'ADMIN'
		permissions: ['user:read', 'user:write']
		description: 'Administrator role'
	}
	assert r.name == 'ADMIN'
	assert r.permissions.len == 2
	assert r.permissions[0] == 'user:read'
	assert r.description == 'Administrator role'
}

// -- RoleHierarchy tests --

fn test_new_role_hierarchy_empty() {
	rh := new_role_hierarchy()
	assert rh.hierarchy.len == 0
}

fn test_add_role() {
	mut rh := new_role_hierarchy()
	rh.add_role('ADMIN', ['MODERATOR'])
	assert rh.hierarchy['ADMIN'] == ['MODERATOR']
}

fn test_add_role_no_parents() {
	mut rh := new_role_hierarchy()
	rh.add_role('GUEST', [])
	assert rh.hierarchy['GUEST'] == []
}

fn test_add_role_multiple_parents() {
	mut rh := new_role_hierarchy()
	rh.add_role('SUPERUSER', ['ADMIN', 'MODERATOR'])
	assert rh.hierarchy['SUPERUSER'].len == 2
	assert rh.hierarchy['SUPERUSER'][0] == 'ADMIN'
	assert rh.hierarchy['SUPERUSER'][1] == 'MODERATOR'
}

// -- get_reachable_roles tests --

fn test_get_reachable_roles_single() {
	mut rh := new_role_hierarchy()
	rh.add_role('GUEST', [])
	reachable := rh.get_reachable_roles('GUEST')
	assert reachable.len == 1
	assert reachable[0] == 'GUEST'
}

fn test_get_reachable_roles_with_parent() {
	mut rh := new_role_hierarchy()
	rh.add_role('USER', ['GUEST'])
	rh.add_role('GUEST', [])
	reachable := rh.get_reachable_roles('USER')
	assert reachable.len == 2
	assert reachable.contains('USER')
	assert reachable.contains('GUEST')
}

fn test_get_reachable_roles_chain() {
	mut rh := new_role_hierarchy()
	rh.add_role('ADMIN', ['MODERATOR'])
	rh.add_role('MODERATOR', ['USER'])
	rh.add_role('USER', ['GUEST'])
	rh.add_role('GUEST', [])
	reachable := rh.get_reachable_roles('ADMIN')
	assert reachable.len == 4
	assert reachable.contains('ADMIN')
	assert reachable.contains('MODERATOR')
	assert reachable.contains('USER')
	assert reachable.contains('GUEST')
}

fn test_get_reachable_roles_non_existent() {
	rh := new_role_hierarchy()
	reachable := rh.get_reachable_roles('NONEXISTENT')
	assert reachable.len == 1
	assert reachable[0] == 'NONEXISTENT'
}

// -- has_role tests --

fn test_has_role_direct_match() {
	rh := build_default_hierarchy()
	assert rh.has_role(['ADMIN'], 'ADMIN') == true
}

fn test_has_role_inherited_match() {
	// ADMIN > MODERATOR > USER > GUEST
	rh := build_default_hierarchy()
	assert rh.has_role(['ADMIN'], 'USER') == true
	assert rh.has_role(['ADMIN'], 'GUEST') == true
}

fn test_has_role_moderator_inherits_user() {
	rh := build_default_hierarchy()
	assert rh.has_role(['MODERATOR'], 'USER') == true
	assert rh.has_role(['MODERATOR'], 'GUEST') == true
	assert rh.has_role(['MODERATOR'], 'ADMIN') == false
}

fn test_has_role_user_only_guest() {
	rh := build_default_hierarchy()
	assert rh.has_role(['USER'], 'GUEST') == true
	assert rh.has_role(['USER'], 'ADMIN') == false
}

fn test_has_role_guest_only_guest() {
	rh := build_default_hierarchy()
	assert rh.has_role(['GUEST'], 'GUEST') == true
	assert rh.has_role(['GUEST'], 'USER') == false
}

fn test_has_role_multiple_user_roles() {
	rh := build_default_hierarchy()
	assert rh.has_role(['USER', 'MODERATOR'], 'GUEST') == true
}

fn test_has_role_non_existent_required() {
	rh := build_default_hierarchy()
	assert rh.has_role(['ADMIN'], 'NONEXISTENT') == false
}

// -- has_any_role tests --

fn test_has_any_role_single_match() {
	rh := build_default_hierarchy()
	assert rh.has_any_role(['ADMIN'], ['ADMIN', 'SUPERADMIN']) == true
}

fn test_has_any_role_inherited_match() {
	rh := build_default_hierarchy()
	assert rh.has_any_role(['ADMIN'], ['GUEST', 'SUPERADMIN']) == true
}

fn test_has_any_role_no_match() {
	rh := build_default_hierarchy()
	assert rh.has_any_role(['GUEST'], ['ADMIN', 'MODERATOR']) == false
}

fn test_has_any_role_one_of_many_matches() {
	rh := build_default_hierarchy()
	assert rh.has_any_role(['USER'], ['ADMIN', 'USER', 'MODERATOR']) == true
}

// -- has_all_roles tests --

fn test_has_all_roles_all_match() {
	rh := build_default_hierarchy()
	assert rh.has_all_roles(['ADMIN'], ['ADMIN', 'USER']) == true
}

fn test_has_all_roles_partial_match() {
	rh := build_default_hierarchy()
	assert rh.has_all_roles(['USER'], ['USER', 'ADMIN']) == false
}

fn test_has_all_roles_single_role() {
	rh := build_default_hierarchy()
	assert rh.has_all_roles(['MODERATOR'], ['USER']) == true
}

// -- has_permission tests --

fn test_has_permission_direct() {
	mut rh := new_role_hierarchy()
	permissions := {
		'ADMIN': ['user:delete']
	}
	rh.add_role('ADMIN', [])
	assert rh.has_permission(['ADMIN'], permissions, 'user:delete') == true
}

fn test_has_permission_not_found() {
	mut rh := new_role_hierarchy()
	permissions := {
		'USER': ['user:read']
	}
	rh.add_role('USER', [])
	assert rh.has_permission(['USER'], permissions, 'user:delete') == false
}

fn test_has_permission_inherited() {
	mut rh := new_role_hierarchy()
	rh.add_role('ADMIN', ['USER'])
	rh.add_role('USER', [])
	permissions := {
		'USER': ['user:read']
	}
	assert rh.has_permission(['ADMIN'], permissions, 'user:read') == true
}

fn test_has_permission_role_not_in_map() {
	mut rh := new_role_hierarchy()
	rh.add_role('GUEST', [])
	permissions := {
		'ADMIN': ['user:delete']
	}
	assert rh.has_permission(['GUEST'], permissions, 'user:delete') == false
}

// -- AccessDecisionManager tests --

fn test_new_access_manager() {
	rh := new_role_hierarchy()
	adm := new_access_manager(rh)
	assert adm.role_permissions.len == 0
	assert adm.hierarchy != unsafe { nil }
}

fn test_add_permission() {
	rh := new_role_hierarchy()
	mut adm := new_access_manager(rh)
	adm.add_permission('ADMIN', 'user:delete')
	adm.add_permission('ADMIN', 'user:write')
	assert adm.role_permissions['ADMIN'].len == 2
}

fn test_add_permission_new_role() {
	rh := new_role_hierarchy()
	mut adm := new_access_manager(rh)
	adm.add_permission('USER', 'self:write')
	assert adm.role_permissions['USER'].len == 1
	assert adm.role_permissions['USER'][0] == 'self:write'
}

fn test_decide_no_requirements() {
	rh := build_default_hierarchy()
	adm := new_access_manager(rh)
	assert adm.decide(['USER'], [], []) == true
}

fn test_decide_role_check_passes() {
	rh := build_default_hierarchy()
	adm := new_access_manager(rh)
	assert adm.decide(['ADMIN'], ['ADMIN'], []) == true
	assert adm.decide(['USER'], ['USER'], []) == true
}

fn test_decide_role_check_fails() {
	rh := build_default_hierarchy()
	adm := new_access_manager(rh)
	assert adm.decide(['GUEST'], ['ADMIN'], []) == false
}

fn test_decide_role_check_inherited() {
	rh := build_default_hierarchy()
	adm := new_access_manager(rh)
	// ADMIN inherits USER
	assert adm.decide(['ADMIN'], ['USER'], []) == true
}

fn test_decide_permission_check_passes() {
	rh := build_default_hierarchy()
	mut adm := new_access_manager(rh)
	adm.add_permission('ADMIN', 'admin:settings')
	assert adm.decide(['ADMIN'], [], ['admin:settings']) == true
}

fn test_decide_permission_check_fails() {
	rh := build_default_hierarchy()
	mut adm := new_access_manager(rh)
	adm.add_permission('USER', 'user:read')
	assert adm.decide(['USER'], [], ['admin:settings']) == false
}

fn test_decide_combined_role_and_permission() {
	rh := build_default_hierarchy()
	mut adm := new_access_manager(rh)
	adm.add_permission('ADMIN', 'admin:settings')
	// Both role and permission check pass
	assert adm.decide(['ADMIN'], ['ADMIN'], ['admin:settings']) == true
	// Role passes but permission fails
	assert adm.decide(['ADMIN'], ['ADMIN'], ['nonexistent:perm']) == false
}

// -- Built-in defaults tests --

fn test_build_default_hierarchy_structure() {
	rh := build_default_hierarchy()
	assert rh.hierarchy.len == 4
	assert rh.hierarchy['ADMIN'] == ['MODERATOR']
	assert rh.hierarchy['MODERATOR'] == ['USER']
	assert rh.hierarchy['USER'] == ['GUEST']
	assert rh.hierarchy['GUEST'] == []
}

fn test_build_default_hierarchy_admin_reaches_all() {
	rh := build_default_hierarchy()
	reachable := rh.get_reachable_roles('ADMIN')
	assert reachable.len == 4
}

fn test_build_default_permissions() {
	perms := build_default_permissions()
	assert perms['ADMIN'].len >= 5
	assert perms['ADMIN'].contains('*')
	assert perms['MODERATOR'].contains('user:read')
	assert perms['USER'].contains('self:write')
	assert perms['GUEST'].contains('public:read')
}

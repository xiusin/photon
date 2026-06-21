module security

// context.v - Security Context Holder
//
// Provides a request-scoped holder for the current authentication state.
// Equivalent to Spring Security's SecurityContextHolder.
// Stores the current Authentication and provides static accessors.

// SecurityContext holds the authentication for the current request/thread
pub struct SecurityContext {
pub mut:
	authentication &Authentication
}

// new_security_context creates a new SecurityContext
pub fn new_security_context() &SecurityContext {
	return &SecurityContext{
		authentication: unsafe { nil }
	}
}

// get_authentication returns the current authentication
pub fn (sc &SecurityContext) get_authentication() &Authentication {
	return sc.authentication
}

// set_authentication sets the current authentication
pub fn (mut sc SecurityContext) set_authentication(auth &Authentication) {
	unsafe {
		sc.authentication = auth
	}
}

// clear removes the current authentication
pub fn (mut sc SecurityContext) clear() {
	sc.authentication = unsafe { nil }
}

// is_authenticated checks if there is an authenticated user
pub fn (sc &SecurityContext) is_authenticated() bool {
	return sc.authentication != unsafe { nil } && sc.authentication.is_authenticated()
}

// get_username returns the current username or empty string
pub fn (sc &SecurityContext) get_username() string {
	if sc.authentication == unsafe { nil } {
		return ''
	}
	return sc.authentication.principal
}

// get_roles returns the current user's roles
pub fn (sc &SecurityContext) get_roles() []string {
	if sc.authentication == unsafe { nil } || !sc.authentication.is_authenticated() {
		return []string{}
	}
	return sc.authentication.authorities
}

// has_role checks if the current user has a specific role
pub fn (sc &SecurityContext) has_role(role string) bool {
	for r in sc.get_roles() {
		if r == role {
			return true
		}
	}
	return false
}

// has_any_role checks if the current user has any of the specified roles
pub fn (sc &SecurityContext) has_any_role(roles []string) bool {
	user_roles := sc.get_roles()
	for required in roles {
		for user_role in user_roles {
			if user_role == required || user_role == 'ROLE_${required}' {
				return true
			}
		}
	}
	return false
}

// SecurityContextHolder provides global access to the SecurityContext
// In V, this is typically managed per-request via the web module
pub struct SecurityContextHolder {
pub mut:
	context &SecurityContext = unsafe { new_security_context() }
}

// get_context returns the stored SecurityContext
pub fn (sch &SecurityContextHolder) get_context() &SecurityContext {
	return sch.context
}

// get_context_mut returns a mutable reference to the SecurityContext
pub fn (mut sch SecurityContextHolder) get_context_mut() &SecurityContext {
	return sch.context
}

// set_context replaces the SecurityContext
pub fn (mut sch SecurityContextHolder) set_context(ctx &SecurityContext) {
	unsafe {
		sch.context = ctx
	}
}

// clear_context clears the SecurityContext
pub fn (mut sch SecurityContextHolder) clear_context() {
	sch.context.clear()
}

module security

// filter.v - Web Security Filter Chain
//
// Provides the SecurityFilterChain that integrates Photon Security with
// the veb web framework. Handles JWT extraction, authentication,
// authorization, CSRF validation, and SecurityContext management.
// Compatible with V 0.5.1 veb.Context API.
import veb

// SecurityFilterChain processes security for HTTP requests
pub struct SecurityFilterChain {
pub mut:
	auth_manager    &AuthenticationManager
	jwt_manager     &JwtManager
	csrf_manager    &CsrfManager
	metadata_source &SecurityMetadataSource
	context_holder  &SecurityContextHolder
	role_hierarchy  &RoleHierarchy
	enabled         bool = true
}

// new_security_filter_chain creates a new SecurityFilterChain
pub fn new_security_filter_chain(auth_mgr &AuthenticationManager, jwt_mgr &JwtManager, csrf_mgr &CsrfManager) &SecurityFilterChain {
	return &SecurityFilterChain{
		auth_manager:    unsafe { auth_mgr }
		jwt_manager:     unsafe { jwt_mgr }
		csrf_manager:    unsafe { csrf_mgr }
		metadata_source: new_security_metadata_source()
		context_holder:  &SecurityContextHolder{}
		role_hierarchy:  build_default_hierarchy()
	}
}

// filter processes a request through the security chain
pub fn (mut sfc SecurityFilterChain) filter(mut ctx veb.Context) !bool {
	if !sfc.enabled {
		return true
	}

	method := ctx.req.method.str()
	path := ctx.req.url

	// Step 1: Check if path is public
	sec_config := sfc.metadata_source.get_config(path)
	if is_public(sec_config) {
		return true
	}

	// Step 2: Deny blocked endpoints
	if sec_config.is_deny_all {
		ctx.send_response_to_client('application/json', '{"error":"Access denied","code":403}')
		return false
	}

	// Step 3: CSRF check for state-changing methods
	if sfc.csrf_manager.is_csrf_required(method) {
		expected := unsafe { sfc.csrf_manager.get_expected_token() }
		actual_header := ctx.get_custom_header(sfc.csrf_manager.config.header_name) or { '' }
		actual_form := ctx.get_custom_header('_csrf') or { '' }
		actual := sfc.csrf_manager.get_actual_token(actual_header, actual_form)

		sfc.csrf_manager.validate(actual, expected) or {
			ctx.send_response_to_client('application/json',
				'{"error":"CSRF token invalid","code":403}')
			return false
		}
	}

	// Step 4: Extract and validate JWT from Authorization header
	auth_header := ctx.get_custom_header('Authorization') or { '' }
	if auth_header.len == 0 {
		ctx.send_response_to_client('application/json',
			'{"error":"Authentication required","code":401}')
		return false
	}

	mut auth := new_authentication('', auth_header)
	sfc.auth_manager.authenticate(mut auth) or {
		ctx.send_response_to_client('application/json',
			'{"error":"Invalid or expired token","code":401}')
		return false
	}

	// Step 5: Set security context for the request
	unsafe {
		sfc.context_holder.context.set_authentication(auth)
	}

	// Step 6: Check role-based authorization
	if sec_config.is_secured && sec_config.required_roles.len > 0 {
		if !role_matches(auth.authorities, sec_config.required_roles) {
			ctx.send_response_to_client('application/json',
				'{"error":"Insufficient privileges","code":403}')
			sfc.context_holder.clear_context()
			return false
		}
	}

	return true
}

// clear_context clears the security context (call after request completes)
pub fn (mut sfc SecurityFilterChain) clear_context() {
	sfc.context_holder.clear_context()
}

// build_default_chain creates a SecurityFilterChain with sensible defaults
pub fn build_default_chain(jwt_secret string) &SecurityFilterChain {
	jwt_config := JwtConfig{
		secret: jwt_secret
	}
	jwt_mgr := new_jwt_manager(jwt_config)

	mut auth_mgr := new_auth_manager()
	auth_mgr.add_provider(&JwtAuthenticationProvider{
		jwt_manager: jwt_mgr
	})

	csrf_config := CsrfConfig{
		enabled: true
	}
	csrf_mgr := new_csrf_manager(csrf_config)

	return new_security_filter_chain(auth_mgr, jwt_mgr, csrf_mgr)
}

// with_permit_all marks a path as publicly accessible
pub fn (mut sfc SecurityFilterChain) with_permit_all(path string) {
	sfc.metadata_source.register(path, SecuredConfig{
		is_permit_all: true
	})
}

// with_secured marks a path as requiring authentication
pub fn (mut sfc SecurityFilterChain) with_secured(path string) {
	sfc.metadata_source.register(path, SecuredConfig{
		is_secured: true
	})
}

// with_roles marks a path as requiring specific roles
pub fn (mut sfc SecurityFilterChain) with_roles(path string, roles []string) {
	sfc.metadata_source.register(path, SecuredConfig{
		is_secured:     true
		required_roles: roles
	})
}

// with_deny_all marks a path as blocked
pub fn (mut sfc SecurityFilterChain) with_deny_all(path string) {
	sfc.metadata_source.register(path, SecuredConfig{
		is_deny_all: true
	})
}

// csrf_middleware creates a CSRF-checking middleware function
pub fn csrf_middleware(mgr &CsrfManager) fn (ctx &veb.Context) !bool {
	return fn [mgr] (ctx &veb.Context) !bool {
		method := ctx.req.method.str()
		if !mgr.is_csrf_required(method) {
			return true
		}
		expected := unsafe { mgr.get_expected_token() }
		actual := mgr.get_actual_token(ctx.get_custom_header(mgr.config.header_name) or { '' }, ctx.get_custom_header('_csrf') or {
			''
		})
		mgr.validate(actual, expected) or { return false }
		return true
	}
}

// cors_security_middleware adds configurable CORS headers
pub fn cors_security_middleware(allowed_origins []string) fn (mut ctx veb.Context) !bool {
	return fn [allowed_origins] (mut ctx veb.Context) !bool {
		origin := ctx.get_custom_header('Origin') or { '' }
		mut allowed := false
		for ao in allowed_origins {
			if ao == '*' || ao == origin {
				allowed = true
				break
			}
		}
		if allowed && origin.len > 0 {
			ctx.set_custom_header('Access-Control-Allow-Origin', origin)
			ctx.set_custom_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE')
			ctx.set_custom_header('Access-Control-Allow-Headers',
				'Content-Type, Authorization, X-CSRF-TOKEN')
			ctx.set_custom_header('Access-Control-Allow-Credentials', 'true')
		}
		return true
	}
}

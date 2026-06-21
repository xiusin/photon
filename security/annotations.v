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
pub const post_authorize_attr = 'post_authorize'

// SecuredConfig holds security configuration for an endpoint
pub struct SecuredConfig {
pub mut:
	is_secured          bool
	required_roles      []string
	required_perms      []string
	is_permit_all       bool
	is_deny_all         bool
	pre_authorize_expr  string // full @PreAuthorize expression, e.g. "hasRole('ADMIN')"
	post_authorize_expr string // full @PostAuthorize expression, e.g. "#return == 'value'"
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
			config.pre_authorize_expr = perm_str
			if perm_str.starts_with('hasPermission') {
				config.required_perms = [perm_str['hasPermission('.len..perm_str.len - 1].trim("'").trim('"')]
			}
		} else if attr.starts_with('${post_authorize_attr}:') {
			config.is_secured = true
			config.post_authorize_expr = attr['${post_authorize_attr}:'.len..].trim("'").trim('"')
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

// ── Method-level Security Expression Evaluation ──
//
// Implements Spring Security-style @PreAuthorize / @PostAuthorize expression
// evaluation. Supports hasRole, hasAnyRole, hasAuthority, hasAnyAuthority,
// hasPermission, #return (PostAuthorize), and `and` / `or` combinators.
//
// The evaluator is a pure function: it has no side effects and reads only
// from the supplied MethodSecurityContext, so it is safe to call concurrently
// from multiple goroutines.

// MethodSecurityContext carries the security state used when evaluating
// @PreAuthorize / @PostAuthorize expressions. It is distinct from the
// request-scoped SecurityContext in context.v (which holds &Authentication).
pub struct MethodSecurityContext {
pub mut:
	user_roles       []string
	user_authorities []string
	user_permissions []string
	user_id          string
	// PostAuthorize: the method return value (stringified) and null flag.
	return_value   string
	is_null_return bool
}

// AccessDeniedException is raised when a @PreAuthorize or @PostAuthorize
// expression evaluates to false. Implements IError with HTTP code 403.
pub struct AccessDeniedException {
pub:
	message string
	code    int = 403
}

// msg implements IError.
pub fn (e AccessDeniedException) msg() string {
	return e.message
}

// code implements IError — returns the HTTP-style status code (403).
pub fn (e AccessDeniedException) code() int {
	return e.code
}

// evaluate_security_expression evaluates a Spring Security-style expression
// against the supplied context. Returns true if access should be granted.
// Supported expressions:
//   - hasRole('ADMIN')              — role may be auto-prefixed with ROLE_
//   - hasAnyRole('ADMIN','USER')    — any of the listed roles
//   - hasAuthority('write:users')   — exact authority match
//   - hasAnyAuthority('a','b')      — any of the listed authorities
//   - hasPermission('read','user')  — any of the listed permissions
//   - #return == 'value'            — PostAuthorize return-value check
//   - #return != 'value'
//   - #return == null
//   - #return != null
//   - <expr> and <expr>             — logical AND (higher precedence)
//   - <expr> or <expr>              — logical OR
// An empty expression is treated as "allow".
pub fn evaluate_security_expression(expr string, ctx MethodSecurityContext) !bool {
	e := expr.trim_space()
	if e == '' {
		return true // empty = allow
	}

	// `and` is checked first so compound expressions are split before
	// single-function parsing. Each part is then recursively evaluated.
	if e.contains(' and ') {
		parts := e.split(' and ')
		for part in parts {
			if !evaluate_security_expression(part, ctx)! {
				return false
			}
		}
		return true
	}

	if e.contains(' or ') {
		parts := e.split(' or ')
		for part in parts {
			if evaluate_security_expression(part, ctx)! {
				return true
			}
		}
		return false
	}

	// hasRole('ADMIN') — Spring convention: also matches 'ROLE_ADMIN'.
	if e.starts_with('hasRole(') {
		role := extract_string_arg(e, 'hasRole(')
		return ctx.user_roles.any(it == role || it == 'ROLE_${role}')
	}

	// hasAnyRole('ADMIN','USER')
	if e.starts_with('hasAnyRole(') {
		roles := extract_string_args(e, 'hasAnyRole(')
		for r in roles {
			if ctx.user_roles.any(it == r || it == 'ROLE_${r}') {
				return true
			}
		}
		return false
	}

	// hasAuthority('write:users')
	if e.starts_with('hasAuthority(') {
		auth := extract_string_arg(e, 'hasAuthority(')
		return ctx.user_authorities.any(it == auth)
	}

	// hasAnyAuthority('write:users','read:users')
	if e.starts_with('hasAnyAuthority(') {
		auths := extract_string_args(e, 'hasAnyAuthority(')
		for a in auths {
			if ctx.user_authorities.any(it == a) {
				return true
			}
		}
		return false
	}

	// hasPermission('read','user') — true if user holds any listed permission.
	if e.starts_with('hasPermission(') {
		perms := extract_string_args(e, 'hasPermission(')
		for p in perms {
			if ctx.user_permissions.any(it == p) {
				return true
			}
		}
		return false
	}

	// #return == 'value' / #return != 'value' / #return == null (PostAuthorize)
	if e.starts_with('#return') {
		return evaluate_return_expression(e, ctx)
	}

	return error('unsupported security expression: ${e} / 不支持的安全表达式: ${e}')
}

// check_pre_authorize evaluates a @PreAuthorize expression and returns
// AccessDeniedException when access is denied.
pub fn check_pre_authorize(expr string, ctx MethodSecurityContext) ! {
	allowed := evaluate_security_expression(expr, ctx)!
	if !allowed {
		return AccessDeniedException{
			message: 'access denied: ${expr} / 访问拒绝: ${expr}'
		}
	}
}

// check_post_authorize evaluates a @PostAuthorize expression after the
// method returns. The return value (stringified) and a null flag are
// injected into the context so #return expressions can be evaluated.
pub fn check_post_authorize(expr string, ctx MethodSecurityContext, return_value string, is_null bool) ! {
	mut ctx_with_return := ctx
	ctx_with_return.return_value = return_value
	ctx_with_return.is_null_return = is_null

	allowed := evaluate_security_expression(expr, ctx_with_return)!
	if !allowed {
		return AccessDeniedException{
			message: 'post-authorize denied: ${expr} / 后置鉴权拒绝: ${expr}'
		}
	}
}

// ── Expression parsing helpers ──

// extract_string_arg extracts a single quoted argument from a function-call
// expression, e.g. hasRole('ADMIN') -> ADMIN. Finds the closing ')' and
// strips surrounding single or double quotes.
fn extract_string_arg(expr string, prefix string) string {
	start := prefix.len
	end := expr.index_after(')', start) or { expr.len }
	inner := expr[start..end].trim_space()
	return strip_quotes(inner)
}

// extract_string_args extracts multiple comma-separated quoted arguments from
// a function-call expression, e.g. hasAnyRole('ADMIN','USER') -> ['ADMIN','USER'].
fn extract_string_args(expr string, prefix string) []string {
	start := prefix.len
	end := expr.index_after(')', start) or { expr.len }
	inner := expr[start..end]
	mut result := []string{}
	for part in inner.split(',') {
		p := part.trim_space()
		result << strip_quotes(p)
	}
	return result
}

// evaluate_return_expression handles #return expressions used by @PostAuthorize.
// Supports == and != comparisons against a quoted literal or the keyword null.
fn evaluate_return_expression(expr string, ctx MethodSecurityContext) !bool {
	rest := expr['#return'.len..].trim_space()
	if rest.starts_with('==') {
		rhs := rest['=='.len..].trim_space()
		if rhs == 'null' {
			return ctx.is_null_return
		}
		val := strip_quotes(rhs)
		return ctx.return_value == val
	}
	if rest.starts_with('!=') {
		rhs := rest['!='.len..].trim_space()
		if rhs == 'null' {
			return !ctx.is_null_return
		}
		val := strip_quotes(rhs)
		return ctx.return_value != val
	}
	return error('unsupported return expression: ${expr} / 不支持的返回值表达式: ${expr}')
}

// strip_quotes removes a single layer of surrounding single or double quotes.
fn strip_quotes(s string) string {
	if s.len >= 2 && s.starts_with("'") && s.ends_with("'") {
		return s[1..s.len - 1]
	}
	if s.len >= 2 && s.starts_with('"') && s.ends_with('"') {
		return s[1..s.len - 1]
	}
	return s
}

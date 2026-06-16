module web

// middleware_groups.v - Parameterized Middleware & Middleware Groups
//
// Implements Laravel-style middleware groups and parameterized middleware.
// Groups allow bundling middleware under a name (e.g., 'web', 'api').
// Parameterized middleware accepts runtime configuration.

// MiddlewareGroup bundles named middleware
pub struct MiddlewareGroup {
pub:
	name        string
	middlewares []string // middleware function names
}

// MiddlewareGroupRegistry manages named middleware groups
pub struct MiddlewareGroupRegistry {
pub mut:
	groups map[string][]MiddlewareFunc
}

// new_middleware_group_registry creates a MiddlewareGroupRegistry
pub fn new_middleware_group_registry() &MiddlewareGroupRegistry {
	return &MiddlewareGroupRegistry{
		groups: map[string][]MiddlewareFunc{}
	}
}

// register adds a named middleware group
pub fn (mut mgr MiddlewareGroupRegistry) register(name string, middlewares []MiddlewareFunc) {
	mgr.groups[name] = middlewares
}

// get retrieves middleware for a group name
pub fn (mgr &MiddlewareGroupRegistry) get(name string) []MiddlewareFunc {
	return mgr.groups[name] or { []MiddlewareFunc{} }
}

// resolve_groups resolves group names to middleware functions.
// If a name matches a registered group, its middlewares are expanded in place.
pub fn (mgr &MiddlewareGroupRegistry) resolve_groups(names []string) []MiddlewareFunc {
	mut result := []MiddlewareFunc{}
	for name in names {
		if group := mgr.groups[name] {
			result << group
		} else {
			// It's a raw middleware name — add as-is
			// (In practice, this would resolve by function pointer)
		}
	}
	return result
}

// ParameterizedMiddleware wraps a middleware with runtime parameters.
// Example: throttle:60,1 → creates a rate limiter with 60 attempts, 1 minute
pub struct ParameterizedMiddleware {
pub:
	name   string
	params map[string]string // key=value pairs
}

// parse_middleware_params parses a middleware string with parameters.
// Input: "throttle:60,1" or "auth:api"
// Output: ParameterizedMiddleware{name: "throttle", params: {"0": "60", "1": "1"}}
pub fn parse_middleware_params(spec string) ParameterizedMiddleware {
	parts := spec.split(':')
	name := parts[0]
	mut params := map[string]string{}

	if parts.len > 1 {
		param_list := parts[1].split(',')
		for i, p in param_list {
			params['${i}'] = p
			// Also parse key=value style
			kv := p.split('=')
			if kv.len == 2 {
				params[kv[0]] = kv[1]
			}
		}
	}

	return ParameterizedMiddleware{
		name: name
		params: params
	}
}

// -- Parameterized Middleware Implementations --

// throttle_middleware creates a parameterized rate-limiting middleware.
// The RateLimiter is created once and shared across all requests.
// Automatically cleans expired attempts to prevent permanent blocking.
//
// Usage: throttle_middleware(max_attempts: 60, decay_minutes: 1)
//   → Allows 60 requests per minute per key (IP or user).
pub fn throttle_middleware(max_attempts int, decay_minutes int) fn (mut &MiddlewareContext) !bool {
	// Create limiter ONCE — shared across all requests handled by this middleware
	mut limiter := new_rate_limiter()
	decay_seconds := i64(decay_minutes) * 60
	return fn [max_attempts, decay_seconds, mut limiter] (mut ctx &MiddlewareContext) !bool {
		mut key := ctx.data['user_id'] or { 'anonymous' }
		key = 'throttle_${key}'

		if limiter.too_many_attempts(key, max_attempts, decay_seconds) {
			return error('rate limit exceeded: ${max_attempts} requests per ${decay_seconds / 60} minutes')
		}

		limiter.hit(key)
		return true
	}
}

// role_middleware creates a parameterized role-based middleware
// Usage: role_middleware(['ADMIN', 'MODERATOR'])
pub fn role_middleware(allowed_roles []string) fn (mut &MiddlewareContext) !bool {
	return fn [allowed_roles] (mut ctx &MiddlewareContext) !bool {
		user_roles_str := ctx.data['user_roles'] or { '' }
		if user_roles_str.len == 0 {
			return error('access denied: no roles')
		}

		user_roles := user_roles_str.split(',')
		for allowed in allowed_roles {
			for user_role in user_roles {
				if user_role == allowed {
					return true
				}
			}
		}

		return error('access denied: insufficient role')
	}
}

// cors_configurable_middleware creates a CORS middleware with configurable origins
pub fn cors_configurable_middleware(allowed_origins []string, allowed_methods string, allowed_headers string) fn (mut &MiddlewareContext) !bool {
	return fn [allowed_origins, allowed_methods, allowed_headers] (mut ctx &MiddlewareContext) !bool {
		origin := ctx.ctx.get_custom_header('Origin') or { '' }

		mut origin_allowed := false
		for ao in allowed_origins {
			if ao == '*' || ao == origin {
				origin_allowed = true
				break
			}
		}

		if origin_allowed {
			ctx.ctx.set_custom_header('Access-Control-Allow-Origin', origin) or {}
			ctx.ctx.set_custom_header('Access-Control-Allow-Methods', allowed_methods) or {}
			ctx.ctx.set_custom_header('Access-Control-Allow-Headers', allowed_headers) or {}
			ctx.ctx.set_custom_header('Access-Control-Allow-Credentials', 'true') or {}
		}

		if ctx.route_method == 'OPTIONS' {
			ctx.ctx.send_response_to_client('text/plain', '')
			return false
		}
		return true
	}
}

// import for RateLimiter (which is in web module already)

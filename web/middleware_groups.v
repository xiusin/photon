module web

// middleware_groups.v - Parameterized Middleware & Middleware Groups
//
// Implements Laravel-style middleware groups and parameterized middleware.
// Groups allow bundling middleware under a name (e.g., 'web', 'api').
// Parameterized middleware accepts runtime configuration.
import sync

// MiddlewareGroup bundles named middleware
pub struct MiddlewareGroup {
pub:
	name        string
	middlewares []string // middleware function names
}

// MiddlewareGroupRegistry manages named middleware groups.
// Thread-safe via sync.RwMutex.
pub struct MiddlewareGroupRegistry {
pub mut:
	groups map[string][]MiddlewareFunc
mut:
	mu sync.RwMutex
}

// new_middleware_group_registry creates a MiddlewareGroupRegistry
pub fn new_middleware_group_registry() &MiddlewareGroupRegistry {
	return &MiddlewareGroupRegistry{
		groups: map[string][]MiddlewareFunc{}
	}
}

// register adds a named middleware group
pub fn (mut mgr MiddlewareGroupRegistry) register(name string, middlewares []MiddlewareFunc) {
	mgr.mu.@lock()
	defer { mgr.mu.unlock() }
	mgr.groups[name] = middlewares
}

// get retrieves middleware for a group name
pub fn (mut mgr MiddlewareGroupRegistry) get(name string) []MiddlewareFunc {
	mgr.mu.rlock()
	defer { mgr.mu.runlock() }
	return mgr.groups[name] or { []MiddlewareFunc{} }
}

// resolve_groups resolves group names to middleware functions.
// If a name matches a registered group, its middlewares are expanded in place.
pub fn (mut mgr MiddlewareGroupRegistry) resolve_groups(names []string) []MiddlewareFunc {
	mgr.mu.rlock()
	defer { mgr.mu.runlock() }
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

// has_group checks if a middleware group is registered.
pub fn (mut mgr MiddlewareGroupRegistry) has_group(name string) bool {
	mgr.mu.rlock()
	defer { mgr.mu.runlock() }
	return name in mgr.groups
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
		name:   name
		params: params
	}
}

// -- Parameterized Middleware Implementations --

// ThrottleState holds the shared rate limiter for a throttle middleware instance.
// Stored on the heap so the closure can safely share it across requests.
@[heap]
pub struct ThrottleState {
pub mut:
	limiter       RateLimiter
	max_attempts  int
	decay_seconds i64
}

// new_throttle_state creates a ThrottleState.
pub fn new_throttle_state(max_attempts int, decay_seconds i64) &ThrottleState {
	return &ThrottleState{
		limiter:       new_rate_limiter()
		max_attempts:  max_attempts
		decay_seconds: decay_seconds
	}
}

// throttle_middleware creates a parameterized rate-limiting middleware.
// The RateLimiter is created once and shared across all requests.
// Uses hit_and_record for atomic check+record — avoids the race condition
// where a request is rejected but the hit is never recorded.
//
// Usage: throttle_middleware(max_attempts: 60, decay_minutes: 1)
//   → Allows 60 requests per minute per key (IP or user).
pub fn throttle_middleware(max_attempts int, decay_minutes int) fn (mut MiddlewareContext) !bool {
	mut state := new_throttle_state(max_attempts, i64(decay_minutes) * 60)
	return fn [mut state] (mut ctx MiddlewareContext) !bool {
		// key 必须落到「同一个客户端」上。原来这里是
		//   ctx.data['user_id'] or { 'anonymous' }
		// 而 user_id 只有登录之后才被写进 data，于是所有未登录请求共用一个
		// 'anonymous' 桶：
		//   * 一个人打满配额，全站未登录用户一起被限流
		//   * 任何人都能靠刷自己的配额，把所有人挡在门外
		// 账号维度仍优先（同一账号跨 IP 才能共享配额），没有则退到客户端 IP。
		// 两者都拿不到时才用 '-' —— client_ip() 在无连接上下文时返回它。
		key := 'throttle_' + throttle_key(ctx)

		// hit_and_record atomically records the hit AND checks the limit.
		// This is critical: if we checked first and then hit, a request at
		// the exact limit boundary would be rejected without recording the hit,
		// causing the limit window to be incorrect.
		allowed := state.limiter.hit_and_record(key, state.max_attempts, state.decay_seconds)
		if !allowed {
			retry := state.limiter.retry_after(key, state.decay_seconds)
			return error('rate limit exceeded: ${state.max_attempts} requests per ${state.decay_seconds / 60} minutes, retry after ${retry}s')
		}
		return true
	}
}

// role_middleware creates a parameterized role-based middleware
// Usage: role_middleware(['ADMIN', 'MODERATOR'])
pub fn role_middleware(allowed_roles []string) fn (mut MiddlewareContext) !bool {
	return fn [allowed_roles] (mut ctx MiddlewareContext) !bool {
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
pub fn cors_configurable_middleware(allowed_origins []string, allowed_methods string, allowed_headers string) fn (mut MiddlewareContext) !bool {
	return fn [allowed_origins, allowed_methods, allowed_headers] (mut ctx MiddlewareContext) !bool {
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

// throttle_key 推导限流的分桶键。
//
// 优先 user_id（同一账号在不同网络下共享配额，这是账号维度的语义），
// 否则用客户端 IP。两者都没有才退到 '-'，此时限流退化为全局限流 ——
// 不理想，但比「把所有人塞进同一个桶」要诚实：至少它不会因为某个人
// 刷接口而误伤其他人之后还自称在按客户端限流。
fn throttle_key(ctx MiddlewareContext) string {
	if uid := ctx.data['user_id'] {
		trimmed := uid.trim_space()
		if trimmed.len > 0 && trimmed != 'anonymous' {
			return 'user:${trimmed}'
		}
	}
	ip := client_ip(ctx.ctx)
	if ip.len > 0 && ip != '-' {
		return 'ip:${ip}'
	}
	return 'global'
}

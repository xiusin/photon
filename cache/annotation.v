module cache

// annotation.v - @[cacheable]/@[cache_evict]/@[cache_put] Annotation Support
// (Spring Cache Annotations inspired)
//
// Provides annotation-based caching for repository/service methods.

// ── CacheableAttribute ──

// CacheableAttribute holds parsed attributes from @[cacheable].
pub struct CacheableAttribute {
pub mut:
	cache_name  string = 'default'
	key_pattern string
	ttl_seconds int = 300 // default 5 minutes
	condition   string
	unless      string
}

// ── CacheEvictAttribute ──

// CacheEvictAttribute holds parsed attributes from @[cache_evict].
pub struct CacheEvictAttribute {
pub mut:
	cache_name        string = 'default'
	key_pattern       string
	all_entries       bool
	before_invocation bool
}

// ── CachePutAttribute ──

// CachePutAttribute holds parsed attributes from @[cache_put].
pub struct CachePutAttribute {
pub mut:
	cache_name  string = 'default'
	key_pattern string
	ttl_seconds int = 300
	condition   string
	unless      string
}

// ── Attribute Parsing ──

// parse_cacheable_attr parses the @[cacheable] attribute string.
pub fn parse_cacheable_attr(attr string) CacheableAttribute {
	mut ca := CacheableAttribute{}

	if attr.len == 0 {
		return ca
	}

	// Simple shorthand
	if !attr.contains(':') && !attr.contains(';') {
		if attr.starts_with('key:') || attr.contains('{') {
			ca.key_pattern = attr
		} else {
			ca.cache_name = attr
		}
		return ca
	}

	// Complex: key:value pairs separated by ';'
	parts := attr.split(';')
	for part in parts {
		p := part.trim_space()
		if p.starts_with('cache:') {
			ca.cache_name = p['cache:'.len..]
		} else if p.starts_with('key:') {
			ca.key_pattern = p['key:'.len..]
		} else if p.starts_with('ttl:') {
			ca.ttl_seconds = p['ttl:'.len..].int()
		} else if p.starts_with('condition:') {
			ca.condition = p['condition:'.len..]
		} else if p.starts_with('unless:') {
			ca.unless = p['unless:'.len..]
		}
	}

	return ca
}

// parse_cache_evict_attr parses the @[cache_evict] attribute string.
pub fn parse_cache_evict_attr(attr string) CacheEvictAttribute {
	mut ca := CacheEvictAttribute{}

	if attr.len == 0 {
		return ca
	}

	if attr == 'all' {
		ca.all_entries = true
		return ca
	}

	if !attr.contains(':') && !attr.contains(';') {
		if attr.contains('{') {
			ca.key_pattern = attr
		} else {
			ca.cache_name = attr
		}
		return ca
	}

	parts := attr.split(';')
	for part in parts {
		p := part.trim_space()
		if p.starts_with('cache:') {
			ca.cache_name = p['cache:'.len..]
		} else if p.starts_with('key:') {
			ca.key_pattern = p['key:'.len..]
		} else if p == 'all' || p == 'all_entries' {
			ca.all_entries = true
		} else if p == 'before_invocation' || p == 'before' {
			ca.before_invocation = true
		}
	}

	return ca
}

// parse_cache_put_attr parses the @[cache_put] attribute string.
pub fn parse_cache_put_attr(attr string) CachePutAttribute {
	mut ca := CachePutAttribute{}

	if attr.len == 0 {
		return ca
	}

	if !attr.contains(':') && !attr.contains(';') {
		if attr.starts_with('key:') || attr.contains('{') {
			ca.key_pattern = attr
		} else {
			ca.cache_name = attr
		}
		return ca
	}

	parts := attr.split(';')
	for part in parts {
		p := part.trim_space()
		if p.starts_with('cache:') {
			ca.cache_name = p['cache:'.len..]
		} else if p.starts_with('key:') {
			ca.key_pattern = p['key:'.len..]
		} else if p.starts_with('ttl:') {
			ca.ttl_seconds = p['ttl:'.len..].int()
		} else if p.starts_with('condition:') {
			ca.condition = p['condition:'.len..]
		} else if p.starts_with('unless:') {
			ca.unless = p['unless:'.len..]
		}
	}

	return ca
}

// ── Cache Key Building ──

// build_cache_key builds a cache key from the attribute and method arguments.
pub fn build_cache_key(attr CacheableAttribute, method_name string, args ...string) string {
	if attr.key_pattern.len > 0 {
		mut key := attr.key_pattern
		for i, arg in args {
			key = key.replace('{${i}}', arg)
		}
		return '${attr.cache_name}::${key}'
	}

	if args.len > 0 {
		return '${attr.cache_name}::${method_name}::${args.join(',')}'
	}
	return '${attr.cache_name}::${method_name}'
}

// build_evict_key builds a cache key for eviction.
pub fn build_evict_key(attr CacheEvictAttribute, method_name string, args ...string) string {
	if attr.key_pattern.len > 0 {
		mut key := attr.key_pattern
		for i, arg in args {
			key = key.replace('{${i}}', arg)
		}
		return '${attr.cache_name}::${key}'
	}

	if args.len > 0 {
		return '${attr.cache_name}::${method_name}::${args.join(',')}'
	}
	return '${attr.cache_name}::${method_name}'
}

// ── Expression Evaluation (condition / unless) ──

// ExpressionContext provides values for condition/unless expression evaluation.
// #result resolves to the method return value; #param.name resolves to a named parameter.
pub struct ExpressionContext {
pub:
	result         string // #result value (empty string if null)
	params         map[string]string // #param.name → value
	is_null_result bool
}

// evaluate_condition evaluates a simple condition/unless expression.
//
// Supported syntax:
//   - #result                  → the method return value (or 'null' if is_null_result)
//   - #param.name              → named parameter value
//   - null                     → null literal
//   - 'value' / "value"        → string literal
//   - bare_token               → raw token
//   - left == right            → equality
//   - left != right            → inequality
//   - expr and expr            → logical AND (left-to-right)
//   - expr or expr             → logical OR (left-to-right)
//
// Empty expression returns true (always-pass). Unknown expressions return true
// (fail-open so a malformed condition never accidentally blocks caching).
pub fn evaluate_condition(expr string, ctx ExpressionContext) bool {
	e := expr.trim_space()
	if e == '' {
		return true
	}

	// Logical AND: all parts must be true
	if e.contains(' and ') {
		parts := e.split(' and ')
		for part in parts {
			if !evaluate_condition(part, ctx) {
				return false
			}
		}
		return true
	}

	// Logical OR: any part true → true
	if e.contains(' or ') {
		parts := e.split(' or ')
		for part in parts {
			if evaluate_condition(part, ctx) {
				return true
			}
		}
		return false
	}

	// Equality
	if e.contains('==') {
		parts := e.split('==')
		if parts.len == 2 {
			left := resolve_value(parts[0], ctx)
			right := resolve_value(parts[1], ctx)
			return left == right
		}
	}

	// Inequality
	if e.contains('!=') {
		parts := e.split('!=')
		if parts.len == 2 {
			left := resolve_value(parts[0], ctx)
			right := resolve_value(parts[1], ctx)
			return left != right
		}
	}

	return true
}

// resolve_value resolves a single token to its string value within the context.
fn resolve_value(token string, ctx ExpressionContext) string {
	t := token.trim_space()

	// #result
	if t == '#result' {
		if ctx.is_null_result {
			return 'null'
		}
		return ctx.result
	}

	// #param.name
	if t.starts_with('#param.') {
		param_name := t[7..]
		return ctx.params[param_name] or { '' }
	}

	// null literal
	if t == 'null' {
		return 'null'
	}

	// String literal 'value' or "value"
	if (t.starts_with("'") && t.ends_with("'") && t.len >= 2) ||
		(t.starts_with('"') && t.ends_with('"') && t.len >= 2) {
		return t[1..t.len - 1]
	}

	// Bare value
	return t
}

// ── CacheableInterceptor ──

// CacheableInterceptor provides around-advice for cacheable methods.
pub struct CacheableInterceptor {
pub mut:
	cache_manager &CacheRegistry = new_cache_registry()
}

// new_cacheable_interceptor creates a CacheableInterceptor.
pub fn new_cacheable_interceptor(cm &CacheRegistry) &CacheableInterceptor {
	return &CacheableInterceptor{
		cache_manager: unsafe { cm }
	}
}

// get_or_compute checks the cache first; if miss, calls the loader and caches the result.
//
// Condition/unless evaluation (Task C5):
//   - condition: evaluated AFTER compute (supports #result). If false → result is
//     returned but NOT cached.
//   - unless: evaluated AFTER compute (supports #result). If true → result is
//     returned but NOT cached.
//   - Empty condition/unless = existing behavior (always cache).
pub fn (mut ci CacheableInterceptor) get_or_compute(attr CacheableAttribute, method_name string, args []string, loader fn () !string) !string {
	cache_key := build_cache_key(attr, method_name, ...args)

	cached := ci.cache_manager.get(cache_key) or { '' }
	if cached.len > 0 {
		return cached
	}

	result := loader()!

	// Evaluate condition: if false, don't cache
	if attr.condition.len > 0 {
		ctx := ExpressionContext{
			result:         result
			is_null_result: result == ''
		}
		if !evaluate_condition(attr.condition, ctx) {
			return result
		}
	}

	// Evaluate unless: if true, don't cache
	if attr.unless.len > 0 {
		ctx := ExpressionContext{
			result:         result
			is_null_result: result == ''
		}
		if evaluate_condition(attr.unless, ctx) {
			return result
		}
	}

	ci.cache_manager.set(cache_key, result, attr.ttl_seconds) or {
		eprintln('[CacheableInterceptor] failed to set cache key "${cache_key}": ${err}')
	}

	return result
}

// evict removes an entry from the cache. Used for @[cache_evict].
pub fn (mut ci CacheableInterceptor) evict(attr CacheEvictAttribute, method_name string, args []string) ! {
	if attr.all_entries {
		mut c := ci.cache_manager.get_cache(attr.cache_name)
		c.clear()!
		return
	}

	cache_key := build_evict_key(attr, method_name, ...args)
	ci.cache_manager.delete(cache_key)!
}

// put stores a value in the cache without affecting the method return.
//
// Unless evaluation (Task C5): if unless evaluates to true (supports #result),
// the value is NOT cached. Empty unless = existing behavior (always cache).
pub fn (mut ci CacheableInterceptor) put(attr CachePutAttribute, method_name string, args []string, value string) ! {
	mut cache_key := '${attr.cache_name}::'
	if attr.key_pattern.len > 0 {
		mut key := attr.key_pattern
		for i, arg in args {
			key = key.replace('{${i}}', arg)
		}
		cache_key += key
	} else {
		cache_key += method_name
		if args.len > 0 {
			cache_key += '::${args.join(',')}'
		}
	}

	// Evaluate unless: if true, don't cache
	if attr.unless.len > 0 {
		ctx := ExpressionContext{
			result:         value
			is_null_result: value == ''
		}
		if evaluate_condition(attr.unless, ctx) {
			return
		}
	}

	ci.cache_manager.set(cache_key, value, attr.ttl_seconds)!
}

// ── CacheConfigAttribute (class-level @[cache_config] annotation) ──

// CacheConfigAttribute holds parsed attributes from @[cache_config].
pub struct CacheConfigAttribute {
pub mut:
	cache_names   []string
	key_generator string // name of KeyGenerator to use
}

// parse_cache_config_attr parses the @[cache_config] attribute string.
pub fn parse_cache_config_attr(attr string) CacheConfigAttribute {
	mut ca := CacheConfigAttribute{}
	if attr.len == 0 {
		return ca
	}
	parts := attr.split(';')
	for part in parts {
		p := part.trim_space()
		if p.starts_with('cache:') {
			// Comma-separated cache names
			names := p['cache:'.len..].split(',')
			for name in names {
				ca.cache_names << name.trim_space()
			}
		} else if p.starts_with('key_generator:') {
			ca.key_generator = p['key_generator:'.len..]
		} else {
			// Single cache name without prefix
			ca.cache_names << p
		}
	}
	return ca
}

// ── KeyGenerator Interface ──

// KeyGenerator generates cache keys from method name and arguments.
pub interface KeyGenerator {
	generate(method_name string, args ...string) string
}

// SimpleKeyGenerator generates keys as method_name::arg1,arg2,...
pub struct SimpleKeyGenerator {}

// new_simple_key_generator creates a SimpleKeyGenerator.
pub fn new_simple_key_generator() SimpleKeyGenerator {
	return SimpleKeyGenerator{}
}

pub fn (g SimpleKeyGenerator) generate(method_name string, args ...string) string {
	if args.len == 0 {
		return method_name
	}
	return method_name + '::' + args.join(',')
}

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
pub fn (mut ci CacheableInterceptor) get_or_compute(attr CacheableAttribute, method_name string, args []string, loader fn () !string) !string {
	cache_key := build_cache_key(attr, method_name, ...args)

	cached := ci.cache_manager.get(cache_key) or { '' }
	if cached.len > 0 {
		return cached
	}

	result := loader()!

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

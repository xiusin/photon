module cache

// Shared counter for cache tests (module-level to avoid closure capture issues)
__global (
	cache_call_count int
)

// ── CacheableAttribute Parsing Tests ──

fn test_parse_cacheable_attr_default() {
	attr := parse_cacheable_attr('')
	assert attr.cache_name == 'default'
	assert attr.key_pattern == ''
	assert attr.ttl_seconds == 300
}

fn test_parse_cacheable_attr_simple_name() {
	attr := parse_cacheable_attr('users')
	assert attr.cache_name == 'users'
}

fn test_parse_cacheable_attr_complex() {
	attr := parse_cacheable_attr('cache:users;key:user:{0};ttl:600;condition:enabled')
	assert attr.cache_name == 'users'
	assert attr.key_pattern == 'user:{0}'
	assert attr.ttl_seconds == 600
	assert attr.condition == 'enabled'
}

fn test_parse_cacheable_attr_unless() {
	attr := parse_cacheable_attr('cache:api;unless:result.isEmpty()')
	assert attr.cache_name == 'api'
	assert attr.unless == 'result.isEmpty()'
}

// ── CacheEvictAttribute Parsing Tests ──

fn test_parse_cache_evict_attr_default() {
	attr := parse_cache_evict_attr('')
	assert attr.cache_name == 'default'
	assert !attr.all_entries
	assert !attr.before_invocation
}

fn test_parse_cache_evict_attr_all() {
	attr := parse_cache_evict_attr('all')
	assert attr.all_entries
}

fn test_parse_cache_evict_attr_all_entries() {
	attr := parse_cache_evict_attr('cache:users;all_entries')
	assert attr.cache_name == 'users'
	assert attr.all_entries
}

fn test_parse_cache_evict_attr_before_invocation() {
	attr := parse_cache_evict_attr('cache:users;before_invocation')
	assert attr.before_invocation
}

// ── CachePutAttribute Parsing Tests ──

fn test_parse_cache_put_attr_default() {
	attr := parse_cache_put_attr('')
	assert attr.cache_name == 'default'
	assert attr.ttl_seconds == 300
}

fn test_parse_cache_put_attr_complex() {
	attr := parse_cache_put_attr('cache:users;key:user:{0};ttl:900')
	assert attr.cache_name == 'users'
	assert attr.key_pattern == 'user:{0}'
	assert attr.ttl_seconds == 900
}

// ── Cache Key Building Tests ──

fn test_build_cache_key_simple() {
	attr := CacheableAttribute{
		cache_name:  'users'
		key_pattern: ''
	}
	key := build_cache_key(attr, 'find_by_id')
	assert key == 'users::find_by_id'
}

fn test_build_cache_key_with_args() {
	attr := CacheableAttribute{
		cache_name:  'users'
		key_pattern: ''
	}
	key := build_cache_key(attr, 'find_by_id', '123')
	assert key == 'users::find_by_id::123'
}

fn test_build_cache_key_with_pattern() {
	attr := CacheableAttribute{
		cache_name:  'users'
		key_pattern: 'user:{0}'
	}
	key := build_cache_key(attr, 'find_by_id', '123')
	assert key == 'users::user:123'
}

fn test_build_cache_key_with_multiple_pattern_args() {
	attr := CacheableAttribute{
		cache_name:  'users'
		key_pattern: 'user:{0}:role:{1}'
	}
	key := build_cache_key(attr, 'find_by_role', '123', 'admin')
	assert key == 'users::user:123:role:admin'
}

// ── Build Evict Key Tests ──

fn test_build_evict_key_simple() {
	attr := CacheEvictAttribute{
		cache_name:  'users'
		key_pattern: ''
	}
	key := build_evict_key(attr, 'delete_user')
	assert key == 'users::delete_user'
}

fn test_build_evict_key_with_pattern() {
	attr := CacheEvictAttribute{
		cache_name:  'users'
		key_pattern: 'user:{0}'
	}
	key := build_evict_key(attr, 'delete_user', '123')
	assert key == 'users::user:123'
}

// ── CacheableInterceptor Tests ──

fn test_new_cacheable_interceptor() {
	ci := new_cacheable_interceptor(new_cache_registry())
	assert !isnil(ci.cache_manager)
}

fn test_cacheable_interceptor_get_or_compute() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	attr := CacheableAttribute{
		cache_name:  'default'
		ttl_seconds: 60
	}

	cache_call_count = 0
	result := ci.get_or_compute(attr, 'expensive_method', [], fn () !string {
		cache_call_count++
		return 'computed_value'
	})!

	assert result == 'computed_value'
	assert cache_call_count == 1

	// Second call should hit cache
	result2 := ci.get_or_compute(attr, 'expensive_method', [], fn () !string {
		cache_call_count++
		return 'should_not_be_called'
	})!

	assert result2 == 'computed_value'
	assert cache_call_count == 1 // loader should NOT be called again
}

fn test_cacheable_interceptor_evict() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	attr := CacheableAttribute{
		cache_name:  'default'
		ttl_seconds: 60
	}

	// Set a value first
	ci.get_or_compute(attr, 'test_method', [], fn () !string {
		return 'value_to_evict'
	})!

	// Evict it
	evict_attr := CacheEvictAttribute{
		cache_name: 'default'
	}
	ci.evict(evict_attr, 'test_method', [])!

	// Value should be gone
	cached := ci.cache_manager.get('default::test_method') or { '' }
	assert cached == ''
}

fn test_cacheable_interceptor_put() {
	mut ci := new_cacheable_interceptor(new_cache_registry())
	put_attr := CachePutAttribute{
		cache_name:  'default'
		ttl_seconds: 60
	}

	ci.put(put_attr, 'manual_method', [], 'manually_cached')!

	cached := ci.cache_manager.get('default::manual_method') or { '' }
	assert cached == 'manually_cached'
}

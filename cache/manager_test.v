module cache

// manager_test.v - Tests for the Spring-style CacheManager abstraction
// (manager.v), CacheRegistry.get_cache_names, CacheConfigAttribute parsing,
// and the KeyGenerator interface.

fn test_value_wrapper_creation() {
	vw := ValueWrapper{
		value: 'hello'
	}
	assert vw.value == 'hello'
}

fn test_cache_registry_get_cache_names_empty() {
	cm := new_cache_registry()
	assert cm.get_cache_names().len == 0
}

fn test_cache_registry_get_cache_names_with_caches() {
	mut cm := new_cache_registry()
	mut mem := new_memory_cache('users')
	unsafe {
		cm.register('users', mem)
	}
	mut mem2 := new_memory_cache('orders')
	unsafe {
		cm.register('orders', mem2)
	}

	names := cm.get_cache_names()
	assert names.len == 2
	assert 'users' in names
	assert 'orders' in names
}

fn test_cache_registry_adapter_implements_manager() {
	mut cm := new_cache_registry()
	mut mem := new_memory_cache('test')
	unsafe {
		cm.register('test', mem)
	}

	adapter := new_cache_registry_adapter(cm)
	// Verify it implements CacheManager interface
	_ := adapter
}

fn test_parse_cache_config_attr_empty() {
	attr := parse_cache_config_attr('')
	assert attr.cache_names.len == 0
	assert attr.key_generator == ''
}

fn test_parse_cache_config_attr_single_cache() {
	attr := parse_cache_config_attr('users')
	assert attr.cache_names.len == 1
	assert attr.cache_names[0] == 'users'
}

fn test_parse_cache_config_attr_multiple_caches() {
	attr := parse_cache_config_attr('cache:users,orders')
	assert attr.cache_names.len == 2
	assert 'users' in attr.cache_names
	assert 'orders' in attr.cache_names
}

fn test_parse_cache_config_attr_with_key_generator() {
	attr := parse_cache_config_attr('cache:users;key_generator:custom')
	assert attr.cache_names.len == 1
	assert attr.cache_names[0] == 'users'
	assert attr.key_generator == 'custom'
}

fn test_simple_key_generator_no_args() {
	g := new_simple_key_generator()
	key := g.generate('findUser')
	assert key == 'findUser'
}

fn test_simple_key_generator_with_args() {
	g := new_simple_key_generator()
	key := g.generate('findUser', '1', 'active')
	assert key == 'findUser::1,active'
}

fn test_simple_key_generator_implements_interface() {
	g := new_simple_key_generator()
	// Verify it implements KeyGenerator interface
	_ := g
}

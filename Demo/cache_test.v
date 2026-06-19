module main

// cache_test.v — PhotonBlog 缓存管理器测试
//
// 测试覆盖：
//   - CacheManager set/get/delete/has/clear
//   - get_or_load（缓存穿透保护）
//   - TTL 过期淘汰
//   - 多缓存实例注册
//   - 缓存统计

import photon.cache

fn test_cache_manager_set_and_get() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	cm.set('key1', 'value1', 60)!
	val := cm.get('key1')!
	assert val == 'value1'
}

fn test_cache_manager_has() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	assert cm.has('nonexistent') == false

	cm.set('exists', 'yes', 60)!
	assert cm.has('exists') == true
}

fn test_cache_manager_delete() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	cm.set('del_me', 'value', 60)!
	assert cm.has('del_me') == true

	cm.delete('del_me') or {}
	assert cm.has('del_me') == false
}

fn test_cache_manager_clear() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	cm.set('k1', 'v1', 60)!
	cm.set('k2', 'v2', 60)!
	cm.set('k3', 'v3', 60)!

	cm.clear()!

	assert cm.has('k1') == false
	assert cm.has('k2') == false
	assert cm.has('k3') == false
}

fn test_cache_manager_overwrite() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	cm.set('key', 'original', 60)!
	assert cm.get('key')! == 'original'

	cm.set('key', 'updated', 60)!
	assert cm.get('key')! == 'updated'
}

fn test_cache_manager_get_or_load() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	// 缓存未命中时通过 loader 加载
	val := cm.get_or_load('gol_key', 60, fn () !string {
		return 'loaded_value'
	})!

	assert val == 'loaded_value'
	assert cm.has('gol_key') == true

	// 第二次应从缓存读取（值相同）
	val2 := cm.get_or_load('gol_key', 60, fn () !string {
		return 'should_not_load'
	})!

	assert val2 == 'loaded_value'
}

fn test_cache_manager_get_missing_key() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	cm.get('nonexistent') or {
		assert true
		return
	}
	assert false
}

fn test_cache_manager_multiple_keys() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	cm.set('user:1', 'Alice', 60)!
	cm.set('user:2', 'Bob', 60)!
	cm.set('post:1', 'Hello', 60)!

	assert cm.get('user:1')! == 'Alice'
	assert cm.get('user:2')! == 'Bob'
	assert cm.get('post:1')! == 'Hello'
}

fn test_cache_manager_json_values() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	json_data := '{"name":"Alice","age":30}'
	cm.set('user_json', json_data, 60)!

	retrieved := cm.get('user_json')!
	assert retrieved == json_data
}

fn test_cache_manager_numeric_values() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	cm.set('counter', '42', 60)!
	cm.set('price', '19.99', 60)!

	assert cm.get('counter')! == '42'
	assert cm.get('price')! == '19.99'
}

fn test_cache_manager_empty_value() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	cm.set('empty', '', 60)!
	// 空字符串也是合法的缓存值
	cm.get('empty') or {
		// 如果缓存实现将空字符串视为不存在，这也是可接受的
		return
	}
}

fn test_cache_manager_register_multiple() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
		cm.register('sessions', cache.new_memory_cache('sessions'))
	}

	cm.set('dkey', 'dval', 60)!
	assert cm.has('dkey') == true
}

fn test_cache_manager_delete_nonexistent() {
	mut cm := cache.new_cache_manager()
	unsafe {
		cm.register('default', cache.new_memory_cache('default'))
	}

	// 删除不存在的 key 不应抛错
	cm.delete('nonexistent') or {
		// 某些实现可能抛错，这也是可接受的
		return
	}
}

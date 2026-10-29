module cache

// redis_cache_integration_test.v — RedisStore 的真连真用覆盖
//
// RedisStore 之前完全没有测试（整个 cache 模块只有内存后端的用例），
// 而它是「生产上才会跑」的那条路径。这里对真实 Redis 覆盖：
//   * 基本读写删、TTL、前缀隔离、keys()、size()、clear()
//   * 缓存未命中必须报 error（不能把 nil 当空串）
//   * 与 CacheRegistry / 链式 CacheOperation 的接线
//   * 并发借还连接不串数据
//
// Redis 不可达时整体 skip，不伪装成通过。
import net
import sync
import time

// LoadCalls 统计 loader 被调用的次数。
@[heap]
struct LoadCalls {
mut:
	n int
}

// redis_available 探测本机 Redis 是否可达。
fn redis_available() bool {
	mut conn := net.dial_tcp('127.0.0.1:6379') or { return false }
	conn.close() or {}
	return true
}

// new_test_redis_cache 返回一个连到 15 号库、已清空、带独立前缀的缓存。
// 前缀用纳秒时间戳，保证多个测试文件/并发用例之间互不干扰。
// Redis 不可达时返回 `none` 让调用方跳过，不是返回 error 让用例变红。
// 同一个文件里其它用例早已是 `if !redis_available() { return }` 的写法，
// 两套语义并存时，没装 Redis 的机器上就前 7 个红、后 4 个绿 —— 看不出谁对。
fn new_test_redis_cache() ?&RedisStore {
	if !redis_available() {
		eprintln('redis_cache_integration_test: 127.0.0.1:6379 不可达，跳过')
		return none
	}
	prefix := 'photon:test:${time.now().unix_nano()}:'
	store := new_redis_cache(RedisCacheConfig{
		host:       '127.0.0.1'
		port:       6379
		db:         15
		key_prefix: prefix
	}) or { return none }
	return store
}

fn test_redis_cache_set_get_delete() ! {
	mut c := new_test_redis_cache() or {
		return
	}
	defer {
		c.clear() or {}
		c.close()
	}

	c.set('k1', 'v1', 0)!
	assert c.get('k1')! == 'v1'
	assert c.has('k1')

	c.set('k1', 'v2', 0)!
	assert c.get('k1')! == 'v2'

	c.delete('k1')!
	assert !c.has('k1')
}

fn test_redis_cache_miss_is_error() ! {
	mut c := new_test_redis_cache() or {
		return
	}
	defer {
		c.clear() or {}
		c.close()
	}

	// 未命中必须是 error，而不是空串 —— Cache 接口靠这个区分
	// 「键不存在」和「值就是空串」。
	if v := c.get('definitely-absent') {
		assert false, 'get() on a missing key must fail, got "${v}"'
	} else {
		assert err.msg().contains('cache miss')
	}
}

fn test_redis_cache_empty_value_roundtrip() ! {
	mut c := new_test_redis_cache() or {
		return
	}
	defer {
		c.clear() or {}
		c.close()
	}

	// 空串是合法值：写进去必须能原样读出来，不能退化成「未命中」
	c.set('empty', '', 0)!
	assert c.get('empty')! == ''
	assert c.has('empty')
}

fn test_redis_cache_ttl_expires() ! {
	mut c := new_test_redis_cache() or {
		return
	}
	defer {
		c.clear() or {}
		c.close()
	}

	c.set('ttl', 'v', 1)!
	assert c.get('ttl')! == 'v'
	time.sleep(1200 * time.millisecond)
	assert !c.has('ttl'), 'key must expire after its TTL'
}

fn test_redis_cache_clear_and_size() ! {
	mut c := new_test_redis_cache() or {
		return
	}
	defer {
		c.close()
	}

	for i in 0 .. 5 {
		c.set('size:${i}', 'v', 0)!
	}
	assert c.size() == 5
	c.clear()!
	assert c.size() == 0
}

fn test_redis_cache_keys_strips_prefix() ! {
	mut c := new_test_redis_cache() or {
		return
	}
	defer {
		c.clear() or {}
		c.close()
	}

	c.set('a', '1', 0)!
	c.set('b', '2', 0)!
	keys := c.keys()
	assert 'a' in keys
	assert 'b' in keys
	// 对外暴露的键名不带内部前缀
	for k in keys {
		assert !k.starts_with('photon:test:'), 'keys() leaked the internal prefix: ${k}'
	}
}

fn test_redis_cache_prefix_isolates_instances() ! {
	if !redis_available() {
		eprintln('redis_cache_integration_test: redis 不可达，跳过')
		return
	}
	mut a := new_redis_cache(RedisCacheConfig{
		host:       '127.0.0.1'
		port:       6379
		db:         15
		key_prefix: 'photon:test:iso-a:'
	})!
	mut b := new_redis_cache(RedisCacheConfig{
		host:       '127.0.0.1'
		port:       6379
		db:         15
		key_prefix: 'photon:test:iso-b:'
	})!
	defer {
		a.clear() or {}
		a.close()
		b.clear() or {}
		b.close()
	}

	a.clear()!
	b.clear()!
	a.set('shared', 'from-a', 0)!
	b.set('shared', 'from-b', 0)!
	// 两个实例的同名键互不影响
	assert a.get('shared')! == 'from-a'
	assert b.get('shared')! == 'from-b'
}

fn test_redis_cache_ping() ! {
	mut c := new_test_redis_cache() or {
		return
	}
	defer {
		c.clear() or {}
		c.close()
	}
	assert c.ping()!
}

fn test_redis_cache_concurrent_access() ! {
	if !redis_available() {
		eprintln('redis_cache_integration_test: redis 不可达，跳过')
		return
	}
	mut c := new_redis_cache(RedisCacheConfig{
		host:       '127.0.0.1'
		port:       6379
		db:         15
		key_prefix: 'photon:test:concurrent:'
		max_active: 8
	})!
	defer {
		c.clear() or {}
		c.close()
	}
	c.clear()!

	mut wg := sync.new_waitgroup()
	for w in 0 .. 8 {
		wg.add(1)
		spawn fn (mut cc RedisStore, id int, mut wg sync.WaitGroup) {
			defer {
				wg.done()
			}
			for i in 0 .. 20 {
				key := 'w${id}:${i}'
				cc.set(key, 'v${id}-${i}', 0) or { continue }
				got := cc.get(key) or { '' }
				// 连接池串了连接就会读到别人的值 —— 这里就是回归点
				if got != 'v${id}-${i}' {
					panic('concurrent cache corruption: key=${key} got="${got}"')
				}
			}
		}(mut c, w, mut wg)
	}
	wg.wait()
	assert c.size() >= 160
}

fn test_redis_cache_wired_into_registry() ! {
	if !redis_available() {
		eprintln('redis_cache_integration_test: redis 不可达，跳过')
		return
	}
	mut store := new_redis_cache(RedisCacheConfig{
		host:       '127.0.0.1'
		port:       6379
		db:         15
		key_prefix: 'photon:test:registry:'
	})!
	defer {
		store.clear() or {}
		store.close()
	}
	store.clear()!

	// RedisStore 必须满足 Cache 接口，并且能被注册进 registry
	// （编译期就验证接口一致性，运行期验证语义）
	mut reg := new_cache_registry()
	mut as_cache := Cache(store)
	reg.register('redis', as_cache)

	assert reg.get('k') or { '' } == '' // 未命中
	reg.set('k', 'v', 0)!
	assert reg.get('k')! == 'v'
	reg.delete('k')!
}

fn test_redis_cache_via_cache_operation_chain() ! {
	if !redis_available() {
		eprintln('redis_cache_integration_test: redis 不可达，跳过')
		return
	}
	mut store := new_redis_cache(RedisCacheConfig{
		host:       '127.0.0.1'
		port:       6379
		db:         15
		key_prefix: 'photon:test:chain:'
	})!
	defer {
		store.clear() or {}
		store.close()
	}
	store.clear()!

	mut reg := new_cache_registry()
	mut as_cache := Cache(store)
	reg.register('redis', as_cache)

	// 链式 API 落到 Redis 后端
	op := reg.chain().cache('redis').put('chain:key', 'chain:value').ttl(60)
	op.save()!
	assert store.get('chain:key')! == 'chain:value'

	// remember 走 loader 只在未命中时调用。
	// 计数器必须是堆上对象：V 0.5.2 里闭包对「标量 + mut 捕获」的写回不生效。
	mut calls := &LoadCalls{}
	loader := fn [mut calls] () !string {
		calls.n++
		return 'computed'
	}
	first := reg.chain().cache('redis').remember('remember:key', 60, loader).get()!
	assert first == 'computed'
	assert calls.n == 1
	second := reg.chain().cache('redis').remember('remember:key', 60, loader).get()!
	assert second == 'computed'
	assert calls.n == 1, 'loader must not run on a cache hit'
}

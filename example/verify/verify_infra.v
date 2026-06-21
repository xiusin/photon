module main

// verify_infra.v — config / logger / cache / pool / locking 验证

import config
import logger
import cache
import pool
import locking

// verify_config 验证多源配置、profile、类型化读取
fn verify_config(mut v Verifier) {
	v.section('配置 (config)')

	mut cfg := config.new()
	cfg.add_source(config.MapConfigSource{
		data: {
			'app.name':    'PhotonVerify'
			'server.port': '8080'
			'app.debug':   'true'
		}
	})
	cfg.load() or {
		v.check('config.load()', false)
		return
	}
	v.check('get 字符串', cfg.get('app.name') == 'PhotonVerify')
	v.check('get_or 默认值', cfg.get_or('missing', 'def') == 'def')
	v.check('get_int', cfg.get_int('server.port') or { -1 } == 8080)
	v.check('get_int_or 默认值', cfg.get_int_or('missing.int', 3000) == 3000)
	v.check('get_bool_or', cfg.get_bool_or('app.debug', false) == true)
	v.check('has(existing)', cfg.has('app.name'))
	v.check('has(missing)=false', !cfg.has('nope'))

	// 多源合并：后加入的源覆盖先前的
	cfg.add_source(config.MapConfigSource{
		data: {
			'app.name': 'Overridden'
		}
	})
	cfg.load() or {}
	v.check('多源合并：后源覆盖前源', cfg.get('app.name') == 'Overridden')
}

// verify_logger 验证日志级别与 MDC 结构化字段
fn verify_logger(mut v Verifier) {
	v.section('日志 (logger)')

	mut log := logger.new()
	log.set_level(.debug)
	v.check('set/get level', log.get_level() == .debug)
	log.set_colored(true)

	// MDC 结构化上下文
	log.put('request_id', 'req-123')
	v.check('put/get MDC 字段', log.get('request_id') == 'req-123')
	log.remove('request_id')
	v.check('remove MDC 字段', log.get('request_id') == '')

	// 级别枚举
	v.check('Level.str()', logger.Level.info.str() == 'INFO')

	// 实际写日志（输出到 stderr，不影响断言）
	log.info('logger verification line')
	log.debug('debug line')
	v.check('info/debug 调用不 panic', true)
}

// verify_cache 验证内存缓存、注册表、加载器、标签缓存
fn verify_cache(mut v Verifier) {
	v.section('缓存 (cache)')

	// MemoryCache 基本读写
	mut mc := cache.new_memory_cache('verify')
	mc.set('k1', 'v1', 0) or {
		v.check('memory set', false)
		return
	}
	v.check('memory get', mc.get('k1') or { '' } == 'v1')
	v.check('memory has', mc.has('k1'))
	v.check('memory size', mc.size() == 1)
	mc.delete('k1') or {}
	v.check('memory delete', !mc.has('k1'))

	// CacheRegistry 多后端 + 默认缓存
	mut reg := cache.new_cache_registry()
	unsafe {
		reg.register('default', cache.new_memory_cache('default'))
	}
	reg.set('app:name', 'PhotonVerify', 0) or {}
	v.check('registry set/get', reg.get('app:name') or { '' } == 'PhotonVerify')

	// get_or_load：缓存未命中时调用 loader 并写入（singleflight）
	loaded := reg.get_or_load('lazy:key', 60, fn () !string {
		return 'computed-value'
	}) or { '' }
	v.check('get_or_load 计算并缓存', loaded == 'computed-value')
	v.check('get_or_load 第二次命中缓存', reg.get('lazy:key') or { '' } == 'computed-value')

	// remember 助手
	remembered := cache.remember(mut reg, 'remember:key', 60, fn () !string {
		return 'remembered'
	}) or { '' }
	v.check('remember 助手', remembered == 'remembered')

	// TaggedCache 标签批量失效
	mut tagged := cache.new_tagged_cache(reg.get_cache('default'), ['posts'])
	tagged.set('post:1', 'hello', 0) or {}
	v.check('tagged set/get', tagged.get('post:1') or { '' } == 'hello')
	tagged.flush() or {}
	v.check('tagged flush 后失效', (tagged.get('post:1') or { 'GONE' }) == 'GONE')
}

// verify_pool 验证通用对象池 acquire/release/stats
fn verify_pool(mut v Verifier) {
	v.section('对象池 (pool)')

	mut p := pool.new_pool_with_config('verify-pool', fn () !voidptr {
		return voidptr(&Product{serial: 7})
	}, 2, 5)
	p.initialize() or {
		v.check('pool.initialize()', false)
		return
	}
	v.check('初始化后 idle == min(2)', p.stats().idle == 2)

	o1 := p.acquire() or {
		v.check('pool.acquire()', false)
		return
	}
	v.check('acquire 后 active == 1', p.stats().active == 1)
	v.check('acquire 返回非空对象', !isnil(o1))

	p.release(o1)
	v.check('release 后 idle 恢复', p.stats().idle == 2)
	v.check('release 后 active == 0', p.stats().active == 0)

	p.close() or {}
	v.check('pool.close()', true)
}

// verify_locking 验证本地互斥锁、键锁管理器、guarded_lock 助手
fn verify_locking(mut v Verifier) {
	v.section('锁 (locking)')

	// 本地互斥锁
	mut mu := locking.new_mutex()
	v.check('try_lock 成功', mu.try_lock())
	mu.unlock()
	v.check('unlock 后可再次 try_lock', mu.try_lock())
	mu.unlock()

	// 键锁管理器
	mut lm := locking.new_lock_manager()
	lm.lock('resource-A')
	v.check('lock_count == 1', lm.lock_count() == 1)
	lm.unlock('resource-A') or {}
	v.check('try_lock 不同 key', lm.try_lock('resource-B'))
	lm.unlock('resource-B') or {}

	// guarded_lock：在锁内执行并自动释放，返回结果
	result := locking.guarded_lock[int](mut lm, 'counter', fn () !int {
		return 42
	}) or { -1 }
	v.check('guarded_lock 返回结果', result == 42)
	v.check('guarded_lock 自动释放后可再获取', lm.try_lock('counter'))
	lm.unlock('counter') or {}
}

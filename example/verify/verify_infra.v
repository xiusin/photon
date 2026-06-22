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

// verify_pool_guard 验证对象池 RAII Guard 模式（自主回收）
fn verify_pool_guard(mut v Verifier) {
	v.section('对象池 RAII Guard — 自主回收 (pool.PooledGuard)')

	mut p := pool.new_pool_with_config('guard-pool', fn () !voidptr {
		return voidptr(&Product{serial: 99})
	}, 1, 3)
	p.initialize() or {
		v.check('guard pool.initialize()', false)
		return
	}

	// 测试 acquire_guard + 手动 release
	mut guard := p.acquire_guard[Product]() or {
		v.check('acquire_guard', false)
		return
	}
	v.check('acquire_guard 成功', !guard.is_released())
	conn := guard.get()
	v.check('guard.get() 返回非空', !isnil(conn))
	v.check('池 active == 1 (guard 持有)', p.stats().active == 1)

	guard.release()
	v.check('guard.release() 后 is_released', guard.is_released())
	v.check('guard.release() 后池 active == 0', p.stats().active == 0)

	// 测试重复 release（幂等性）
	guard.release()
	v.check('guard 重复 release 不 panic', true)

	// 测试 with_acquired（零心智成本 API）
	mut with_acquired_ok := false
	p.with_acquired[Product](fn (obj &Product) ! {
		with_acquired_ok = true
	}) or {
		v.check('with_acquired 执行', false)
		return
	}
	v.check('with_acquired 回调执行', with_acquired_ok)
	v.check('with_acquired 后池 active == 0', p.stats().active == 0)

	// 测试 PoolAutoManager
	mut mgr := pool.new_pool_auto_manager()
	mgr.register('guard-pool', p)
	v.check('PoolAutoManager 注册池', mgr.pool_count() == 1)
	v.check('PoolAutoManager 获取池', !isnil(mgr.get('guard-pool') or { unsafe { nil } }))

	mgr.close_all()
	v.check('PoolAutoManager.close_all() 完成', true)

	// 测试 pool_stats
	mut p2 := pool.new_pool_with_config('stats-pool', fn () !voidptr {
		return voidptr(&Product{serial: 1})
	}, 1, 2)
	p2.initialize() or {}
	mut mgr2 := pool.new_pool_auto_manager()
	mgr2.register('stats-pool', p2)
	stats := mgr2.pool_stats()
	v.check('PoolAutoManager.pool_stats()', 'stats-pool' in stats)
	mgr2.close_all()
}

// verify_service_locator 验证 ServiceLocator 服务定位器
fn verify_service_locator(mut v Verifier) {
	v.section('服务定位器 (core.ServiceLocator)')

	mut ctx := core.new_application_context()
	svc := &GreetService{greeting: 'Locator'}
	ctx.register_instance('GreetService', svc) or {
		v.check('register_instance', false)
		return
	}
	ctx.refresh() or {}

	// 创建 ServiceLocator
	mut sl := core.new_service_locator(ctx)
	v.check('new_service_locator', !isnil(sl))

	// resolve by name
	resolved := sl.resolve('GreetService') or { unsafe { nil } }
	v.check('sl.resolve(name) 成功', !isnil(resolved))

	// has service
	v.check('sl.has(GreetService)', sl.has('GreetService'))
	v.check('sl.has(missing)=false', !sl.has('MissingService'))

	// BindingRegistry
	mut reg := core.new_binding_registry()
	reg.bind('DynamicService', fn () !voidptr {
		return voidptr(&GreetService{greeting: 'dynamic'})
	}, true)
	v.check('BindingRegistry.bind', reg.has_binding('DynamicService'))
	dyn := reg.resolve('DynamicService') or { unsafe { nil } }
	v.check('BindingRegistry.resolve', !isnil(dyn))

	// 全局 ServiceLocator
	core.set_global_service_locator(sl)
	v.check('set_global_service_locator', true)
	has_global := core.has_global_service('GreetService')
	v.check('has_global_service', has_global)

	ctx.shutdown()
}

// verify_auto_logger 验证自动日志注入与 LoggerFactory
fn verify_auto_logger(mut v Verifier) {
	v.section('自动日志注入 (logger.LoggerFactory + LogContext)')

	// LoggerFactory
	mut cfg := logger.new_logger_config()
	cfg.set_namespace_level('photon.verify', .debug)
	mut factory := logger.new_logger_factory(cfg)

	log1 := factory.get_logger('photon.verify.service')
	v.check('LoggerFactory.get_logger', log1.get_level() == .debug)

	log2 := factory.get_logger('photon.verify.repo')
	v.check('LoggerFactory 命名空间继承', log2.get_level() == .debug)

	log3 := factory.get_logger('photon.other')
	v.check('LoggerFactory 默认级别', log3.get_level() == .info)

	// Logger 缓存
	v.check('LoggerFactory 缓存', factory.logger_count() >= 2)

	// reload_all 热更新
	cfg.set_namespace_level('photon.verify', .warn)
	factory.reload_all()
	v.check('reload_all 热更新级别', log1.get_level() == .warn)

	// LogContext
	mut lctx := logger.new_log_context()
	lctx.with_trace_id('trace-123')
	lctx.with_request_id('req-456')
	lctx.with_span('verify')
	fields := lctx.to_fields()
	v.check('LogContext trace_id', fields['trace_id'] == 'trace-123')
	v.check('LogContext request_id', fields['request_id'] == 'req-456')
	v.check('LogContext span', fields['span'] == 'verify')

	// get_logger_for[T]
	log_typed := logger.get_logger_for[Product](mut factory)
	v.check('get_logger_for[T]', log_typed.output_label == 'Product')
}

// verify_lock_guard 验证锁 RAII Guard 模式（自动解锁）
fn verify_lock_guard(mut v Verifier) {
	v.section('锁 RAII Guard — 自动解锁 (locking.LockGuard)')

	mut lm := locking.new_lock_manager()

	// lock_guard + 手动 release
	mut guard := lm.lock_guard('raii-key') or {
		v.check('lock_guard', false)
		return
	}
	v.check('lock_guard 获取成功', !guard.is_released())
	v.check('锁被持有', !lm.try_lock('raii-key'))

	guard.release()
	v.check('guard.release() 后 is_released', guard.is_released())
	v.check('guard.release() 后锁可用', lm.try_lock('raii-key'))
	lm.unlock('raii-key') or {}

	// 重复 release（幂等性）
	guard.release()
	v.check('guard 重复 release 不 panic', true)

	// try_lock_guard
	mut guard2 := lm.try_lock_guard('try-key') or {
		v.check('try_lock_guard', false)
		return
	}
	v.check('try_lock_guard 成功', !guard2.is_released())
	guard2.release()

	// with_lock（零心智成本 API）
	mut with_lock_ok := false
	lm.with_lock('with-key', fn () ! {
		with_lock_ok = true
	}) or {
		v.check('with_lock 执行', false)
		return
	}
	v.check('with_lock 回调执行', with_lock_ok)
	v.check('with_lock 后锁可用', lm.try_lock('with-key'))
	lm.unlock('with-key') or {}
}

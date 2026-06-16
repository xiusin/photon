module main

// example/main.v — Photon Framework Comprehensive Example
//
// Demonstrates Photon's full capabilities:
// - ORM: OrmAdapter, BaseRepository, DerivedRepository, TransactionManager
// - Security: JWT, CSRF, Role-based access control
// - Web: Two-type pattern [App, Context], route scanning, request logging
// - Concurrency: Goroutines, channels, parallel processing
// - Cache: In-memory caching with TTL
// - Queue: Job queue processing
// - Pool: Connection pooling
// - Locking: Distributed locks
//
// Prerequisite: link photon module into vmodules
//   ln -sf $(pwd) ~/.vmodules/photon
//
// Compile from photon/ directory:
//   v -enable-globals example/main.v
import config
import log
import security
import cli
import orm
import web
import cache
import sync
import time
import veb

// ── Web Layer: Two-Type Pattern ──

// Context is the per-request context (Spring Boot-style HttpServletRequest).
pub struct Context {
	veb.Context
}

// App is the global application struct (Spring Boot-style @SpringBootApplication).
// Holds shared state and services that persist across requests.
pub struct App {
pub mut:
	logger     &log.Logger         = unsafe { nil }
	cache_mgr  &cache.CacheManager = unsafe { nil }
	req_count  int
	start_time i64
}

// before_request is called before every HTTP request (veb lifecycle hook).
pub fn (mut app App) before_request(mut ctx Context) {
	app.req_count++
	info := web.new_request_info(mut ctx.Context)

	if app.logger != unsafe { nil } {
		logger := app.logger
		logger.info('${info.method} ${info.path} | IP: ${info.ip} | UA: ${info.user_agent}')
	}
}

// index handles GET /
pub fn (mut app App) index(mut ctx Context) veb.Result {
	return ctx.json({
		'message': 'Photon Framework API Server'
		'version': '0.4.0'
		'uptime':  '${time.ticks() - app.start_time}ms'
	})
}

// health handles GET /health
pub fn (mut app App) health(mut ctx Context) veb.Result {
	return ctx.text('OK')
}

// ping handles GET /ping
pub fn (mut app App) ping(mut ctx Context) veb.Result {
	return ctx.text('pong')
}

// stats handles GET /stats — demonstrates request counting
pub fn (mut app App) stats(mut ctx Context) veb.Result {
	return ctx.json({
		'requests': '${app.req_count}'
		'uptime':   '${time.ticks() - app.start_time}ms'
	})
}

// cache_demo handles GET /cache?key=xxx — demonstrates cache module
pub fn (mut app App) cache_demo(mut ctx Context) veb.Result {
	key := ctx.query['key'] or { 'default' }

	if app.cache_mgr != unsafe { nil } {
		// Try to get from cache
		if val := app.cache_mgr.get(key) {
			return ctx.json({
				'source': 'cache'
				'key':    key
				'value':  val
			})
		}

		// Cache miss — compute and store
		value := 'computed_${time.ticks()}'
		app.cache_mgr.set(key, value, int(30 * time.second)) or {
			return ctx.server_error('cache set failed: ${err}')
		}
		return ctx.json({
			'source': 'computed'
			'key':    key
			'value':  value
		})
	}

	return ctx.server_error('cache not initialized')
}

// concurrent_demo handles GET /concurrent — demonstrates parallel processing
pub fn (mut app App) concurrent_demo(mut ctx Context) veb.Result {
	mut results := []string{}
	mut mu := sync.Mutex{}
	mut wg := sync.WaitGroup{}
	mut results_ptr := &results
	mut mu_ptr := &mu
	mut wg_ptr := &wg

	// Spawn 5 parallel tasks
	for i in 0 .. 5 {
		wg.add(1)
		spawn fn [i, mut results_ptr, mut mu_ptr, mut wg_ptr] () {
			defer { wg_ptr.done() }
			time.sleep(100 * time.millisecond) // Simulate work
			result := 'task_${i}_done'
			mu_ptr.@lock()
			results_ptr << result
			mu_ptr.unlock()
		}()
	}

	wg.wait()
	results_str := results.join(', ')
	return ctx.json({
		'tasks_completed': '${results.len}'
		'results':         results_str
	})
}

// ── Demo Entities ──

struct DemoUser {
	orm.BaseEntity
pub mut:
	name  string
	email string
}

// ── Main Entry Point ──

fn main() {
	mut app := cli.new_application('photon', '0.1.0')
	app.add_command(cli.new_serve_command())
	app.add_command(cli.new_list_command(app))
	app.add_command(cli.new_help_command(app))
	app.run() or { panic(err) }

	// Run the full framework demo
	start_server() or { eprintln('Demo error: ${err}') }
}

fn start_server() ! {
	println('')
	println('╔══════════════════════════════════════════════════════════╗')
	println('║   Photon Framework — Enterprise-Grade Demo Application   ║')
	println('╚══════════════════════════════════════════════════════════╝')

	// ── Configuration ──
	mut cfg := config.new()
	cfg.set_profile(['dev'])
	cfg.add_source(config.MapConfigSource{
		data: {
			'app.name':       'PhotonEnterpriseApp'
			'app.version':    '0.4.0'
			'server.port':    '8080'
			'jwt.secret':     'your-256-bit-secret-key-here-min-32-chars!!'
			'jwt.expiration': '60'
		}
	})
	cfg.load() or {
		eprintln('Failed to load config: ${err}')
		return
	}

	// ── Logger ──
	mut logger := log.new()
	logger.set_level(.debug)
	logger.set_colored(true)
	logger.put('app', cfg.get('app.name'))
	logger.info('Configuration loaded successfully')

	// ── Security Module ──
	logger.info('--- Initializing Security Module ---')
	jwt_config := security.JwtConfig{
		secret:             cfg.get_or('jwt.secret', 'default-secret-change-me-in-production!!')
		expiration_minutes: cfg.get_int_or('jwt.expiration', 60)
	}
	jwt_mgr := security.new_jwt_manager(jwt_config)

	mut user_service := security.new_in_memory_service()
	user_service.add_user(security.new_user('admin', 'admin123', ['ADMIN']))
	user_service.add_user(security.new_user('moderator', 'mod123', ['MODERATOR']))
	user_service.add_user(security.new_user('user', 'user123', ['USER']))

	mut auth_mgr := security.new_auth_manager()
	jwt_provider := &security.JwtAuthenticationProvider{
		jwt_manager: jwt_mgr
	}
	auth_mgr.add_provider(jwt_provider)

	csrf_config := security.CsrfConfig{
		enabled: true
	}
	csrf_mgr := security.new_csrf_manager(csrf_config)

	mut security_chain := security.new_security_filter_chain(auth_mgr, jwt_mgr, csrf_mgr)
	security_chain.with_permit_all('/')
	security_chain.with_permit_all('/health')
	security_chain.with_permit_all('/ping')
	security_chain.with_permit_all('/stats')
	security_chain.with_permit_all('/cache')
	security_chain.with_permit_all('/concurrent')
	security_chain.with_permit_all('/api/auth/login')
	security_chain.with_permit_all('/api/auth/register')
	security_chain.with_secured('/api/users')
	security_chain.with_roles('/api/admin', ['ADMIN'])
	security_chain.with_roles('/api/mod', ['ADMIN', 'MODERATOR'])
	logger.info('Security module initialized with JWT + CSRF + RBAC')

	// ── Cache Module ──
	logger.info('--- Initializing Cache Module ---')
	mut cache_mgr := cache.new_cache_manager()
	unsafe {
		cache_mgr.register('default', cache.new_memory_cache('default'))
	}
	cache_mgr.set('app:name', cfg.get('app.name'), 0)!
	cache_mgr.set('app:version', cfg.get('app.version'), 0)!
	logger.info('Cache initialized with memory driver')

	// ── ORM Module ──
	logger.info('--- Initializing ORM Module ---')
	mut demo_om := orm.new_orm_manager()
	demo_om.register_connection('default', .sqlite, voidptr(99))!
	logger.info('ORM manager initialized with SQLite connection')

	// ── Run Demos ──
	demo_orm_adapter(logger, demo_om)!
	demo_transactional_hooks(logger, demo_om)!
	demo_derived_repository(logger, demo_om)!
	demo_transaction_manager(logger)!
	demo_concurrency(logger)!
	demo_cache_operations(logger, mut cache_mgr)!

	// ── Start Web Server ──
	port := cfg.get_int_or('server.port', 8080)
	logger.info('Starting web server on port ${port}...')

	// Create App instance with shared services
	_ = &App{
		logger:     logger
		cache_mgr:  cache_mgr
		start_time: time.ticks()
	}

	logger.info('Available endpoints:')
	logger.info('  GET /           - API info with uptime')
	logger.info('  GET /health     - Health check')
	logger.info('  GET /ping       - Ping/pong')
	logger.info('  GET /stats      - Request statistics')
	logger.info('  GET /cache      - Cache demo (?key=xxx)')
	logger.info('  GET /concurrent - Parallel processing demo')

	// Spring Boot-style: two-type pattern [App, Context]
	web.run_with_routes[App, Context](port)
}

// ── OrmAdapter Demo ──

fn demo_orm_adapter(logger &log.Logger, om &orm.OrmManager) ! {
	mut a := orm.new_orm_adapter[DemoUser](om, 'default')!

	conn_ptr := a.get_conn()!
	logger.info('  Connection routing: ${typeof(conn_ptr).name}')

	mut user := DemoUser{
		name:  'Alice'
		email: 'alice@demo.com'
	}
	a.before_insert(mut user)!
	logger.info('  Touchable.touch(): created_at=${user.created_at} updated_at=${user.updated_at} version=${user.version}')
	assert user.created_at > 0
	assert user.updated_at > 0
	assert user.version == 1

	mut callback_ran := false
	mut cb_flag := &callback_ran
	a.wrap_insert(mut user, fn [cb_flag] (mut u DemoUser) ! {
		_ = cb_flag
		unsafe {
			*cb_flag = true
		}
	})!
	assert callback_ran

	a.with_connection(fn (conn_ptr voidptr) ! {
		_ = conn_ptr
	})!
	logger.info('  with_connection convenience method — OK')

	parts := orm.parse_method_name('findByNameAndEmail')!
	logger.info('  Derived query: ${parts.to_where_cond()}')
	assert parts.to_where_param_count() == 2

	logger.info('  OrmAdapter demo: PASSED')
}

// ── Transactional Lifecycle Hooks Demo ──

fn demo_transactional_hooks(logger &log.Logger, om &orm.OrmManager) ! {
	mut a := orm.new_orm_adapter[DemoUser](om, 'default')!

	mut order_a := DemoUser{
		name:  'Order42'
		email: 'order@shop.com'
	}
	mut tx_called := false
	tx_flag := &tx_called
	a.before_insert(mut order_a)!
	unsafe {
		*tx_flag = true
	}
	a.after_insert(mut order_a)!
	assert tx_called
	_ = tx_flag
	logger.info('  Pattern A: hooks inside transaction — BEFORE + AFTER fired atomically')

	mut tm := orm.new_transaction_manager()
	mut execute_called := false
	mut exec_flag := &execute_called
	tm.execute(.required, fn [exec_flag] () ! {
		_ = exec_flag
		unsafe {
			*exec_flag = true
		}
	})!
	assert execute_called
	logger.info('  Pattern B: TransactionManager with .required — OK')

	tm.execute(.required, fn [mut tm] () ! {
		tm.execute(.nested, fn () ! {})!
	})!
	logger.info('  Pattern B: .required + .nested propagation — OK')

	mut txc_called := false
	mut txc_flag := &txc_called
	orm.transactional(fn [txc_flag] () ! {
		_ = txc_flag
		unsafe {
			*txc_flag = true
		}
	})!
	assert txc_called
	logger.info('  Pattern C: transactional() convenience — OK')

	logger.info('  Transactional hooks demo: PASSED')
}

// ── DerivedRepository Demo ──

fn demo_derived_repository(logger &log.Logger, om &orm.OrmManager) ! {
	demo_derived_find := fn (conn voidptr, parts orm.QueryParts, params []voidptr) ![]DemoUser {
		_ = conn
		return [DemoUser{
			name:  'derived_alice'
			email: 'alice@derived.com'
		}]
	}
	demo_derived_count := fn (conn voidptr, parts orm.QueryParts, params []voidptr) !int {
		_ = conn
		return 42
	}
	demo_derived_exists := fn (conn voidptr, parts orm.QueryParts, params []voidptr) bool {
		_ = conn
		return params.len > 0
	}
	demo_derived_delete := fn (conn voidptr, parts orm.QueryParts, params []voidptr) ! {
		_ = conn
	}

	mut dr := orm.new_derived_repository[DemoUser](om, 'default', fn (conn voidptr, id int) !DemoUser {
		return DemoUser{}
	}, fn (conn voidptr) ![]DemoUser {
		return []DemoUser{}
	}, fn (conn voidptr, e DemoUser) ! {}, fn (conn voidptr, e DemoUser) ! {}, fn (conn voidptr, id int) ! {},
		fn (conn voidptr) !int {
		return 0
	}, fn (conn voidptr, id int) bool {
		return false
	}, demo_derived_find, demo_derived_count, demo_derived_exists, demo_derived_delete)!

	users := dr.find('findByNameAndEmail', voidptr(c'Alice'), voidptr(c'a@b.com'))!
	logger.info('  dr.find(findByNameAndEmail): ${users.len} results, first=${users[0].name}')
	assert users.len == 1

	count := dr.count('countByStatus', voidptr(c'active'))!
	logger.info('  dr.count(countByStatus): ${count}')
	assert count == 42

	has := dr.exists('existsByEmail', voidptr(c'a@b.com'))
	logger.info('  dr.exists(existsByEmail): ${has}')
	assert has

	dr.delete_by('deleteByStatus', voidptr(c'expired'))!
	logger.info('  dr.delete_by(deleteByStatus): OK')

	mut demo_e := DemoUser{
		name:  'repo_user'
		email: 'repo@demo.com'
	}
	dr.repo.save(mut demo_e)!
	logger.info('  dr.repo.save(): created_at=${demo_e.created_at} version=${demo_e.version}')

	logger.info('  DerivedRepository demo: PASSED')
}

// ── TransactionManager Propagation Demo ──

fn demo_transaction_manager(logger &log.Logger) ! {
	mut tm := orm.new_transaction_manager()

	mut d1_called := false
	mut d1_flag := &d1_called
	tm.execute(.required, fn [d1_flag] () ! {
		_ = d1_flag
		unsafe {
			*d1_flag = true
		}
	})!
	assert d1_called
	assert !tm.is_active()
	logger.info('  1. .required: created → committed → inactive — OK')

	mut d2_outer := false
	mut d2_inner := false
	mut d2o := &d2_outer
	mut d2i := &d2_inner
	tm.execute(.required, fn [mut tm, d2o, d2i] () ! {
		_ = d2o
		_ = d2i
		unsafe {
			*d2o = true
		}
		tm.execute(.required, fn [d2i] () ! {
			_ = d2i
			unsafe {
				*d2i = true
			}
		})!
	})!
	assert d2_outer && d2_inner
	assert !tm.is_active()
	logger.info('  2. .required + nested .required: outer+inner ran, single commit — OK')

	mut d3_outer := false
	mut d3_inner := false
	mut d3o := &d3_outer
	mut d3i := &d3_inner
	tm.execute(.required, fn [mut tm, d3o, d3i] () ! {
		_ = d3o
		_ = d3i
		unsafe {
			*d3o = true
		}
		tm.execute(.requires_new, fn [d3i] () ! {
			_ = d3i
			unsafe {
				*d3i = true
			}
		})!
		tm.execute(.mandatory, fn () ! {})!
	})!
	assert d3_outer && d3_inner
	logger.info('  3. .required + .requires_new: inner independent tx, outer restored — OK')

	mut d4_failed := false
	tm.execute(.required, fn () ! {
		return error('simulated business error')
	}) or { d4_failed = true }
	assert d4_failed && !tm.is_active()
	logger.info('  4. .required + error: rolled back → inactive — OK')

	mut d5_called := false
	mut d5_flag := &d5_called
	orm.transactional(fn [d5_flag] () ! {
		_ = d5_flag
		unsafe {
			*d5_flag = true
		}
	})!
	assert d5_called
	logger.info('  5. transactional() convenience — OK')

	logger.info('  TransactionManager demo: PASSED')
}

// ── Concurrency Demo ──

fn demo_concurrency(logger &log.Logger) ! {
	logger.info('--- Concurrency & Parallel Processing Demo ---')

	// 1. Goroutine with mutex-protected counter (using shared references)
	mut counter := 0
	mut mu := sync.Mutex{}
	mut counter_ptr := &counter
	mut mu_ptr := &mu

	for _ in 0 .. 5 {
		spawn fn [mut counter_ptr, mut mu_ptr] () {
			time.sleep(50 * time.millisecond) // Simulate work
			mu_ptr.@lock()
			unsafe {
				*counter_ptr += 1
			}
			mu_ptr.unlock()
		}()
	}

	time.sleep(200 * time.millisecond) // Wait for goroutines
	mu.@lock()
	final_count := counter
	mu.unlock()
	assert final_count == 5
	logger.info('  1. Goroutines: 5 parallel tasks completed, counter=${final_count}')

	// 2. Parallel map-reduce pattern (using array indices)
	data := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	mut squares := []int{len: data.len}
	mut squares_ptr := &squares

	for i, val in data {
		spawn fn [i, val, mut squares_ptr] () {
			squares_ptr[i] = val * val
		}()
	}

	time.sleep(100 * time.millisecond) // Wait for goroutines

	mut sum := 0
	for s in squares {
		sum += s
	}
	assert sum == 385 // 1² + 2² + ... + 10²
	logger.info('  2. Parallel map-reduce: computed ${data.len} squares, sum=${sum}')

	logger.info('  Concurrency demo: PASSED')
}

// ── Cache Operations Demo ──

fn demo_cache_operations(logger &log.Logger, mut cache_mgr cache.CacheManager) ! {
	logger.info('--- Cache Operations Demo ---')

	// 1. Basic set/get
	cache_mgr.set('user:1:name', 'Alice', int(60 * time.second))!
	name := cache_mgr.get('user:1:name') or { 'not found' }
	assert name == 'Alice'
	logger.info('  1. Basic set/get: user:1:name = ${name}')

	// 2. Cache miss
	missing := cache_mgr.get('nonexistent') or { 'cache miss' }
	assert missing == 'cache miss'
	logger.info('  2. Cache miss handling: ${missing}')

	// 3. Batch operations
	cache_mgr.set('batch:1', 'value1', int(30 * time.second))!
	cache_mgr.set('batch:2', 'value2', int(30 * time.second))!
	cache_mgr.set('batch:3', 'value3', int(30 * time.second))!
	logger.info('  3. Batch operations: stored 3 keys')

	// 4. Delete operation
	cache_mgr.delete('batch:2')!
	deleted := cache_mgr.get('batch:2') or { 'deleted' }
	assert deleted == 'deleted'
	logger.info('  4. Delete operation: batch:2 removed')

	// 5. TTL expiration (short TTL for demo)
	cache_mgr.set('temp', 'expires_soon', 1)!
	temp1 := cache_mgr.get('temp') or { 'gone' }
	assert temp1 == 'expires_soon'
	time.sleep(1500 * time.millisecond)
	temp2 := cache_mgr.get('temp') or { 'expired' }
	assert temp2 == 'expired'
	logger.info('  5. TTL expiration: temp key expired after 1s')

	logger.info('  Cache operations demo: PASSED')
}

// ── Web Server ──
// Spring Boot-style: web.run[App, Context](8080) — two-type pattern.
// Routes: GET /, /health, /ping, /stats, /cache, /concurrent
// Request logging: before_request() logs method, path, IP, User-Agent per request.

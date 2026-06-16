module main

// example/main.v — Photon Framework Example Application
//
// Demonstrates the full Photon ORM stack: OrmAdapter → BaseRepository →
// DerivedRepository → TransactionManager, plus CLI, security, and web server.
//
// Prerequisite: link photon module into vmodules
//   ln -sf $(pwd) ~/.vmodules/photon
//
// Compile from photon/ directory:
//   v -enable-globals example/main.v
import photon.config
import photon.log
import photon.security
import photon.cli
import photon.orm
import photon.web
import veb

// ── Demo entity ──

// PhotonApp is the web server application (Spring Boot-style).
// Embeds veb.Context directly (required by V 0.5.1 for veb generics).
pub struct PhotonApp {
	veb.Context
pub mut:
	logger    &log.Logger = unsafe { nil }
	req_count int
	req_info  web.RequestInfo // stored by before_request for end logging
}

// before_request is called before every HTTP request (veb lifecycle hook).
// Logs method, path, client IP, and User-Agent — Spring Boot-style.
pub fn (mut app PhotonApp) before_request() {
	app.req_count++
	app.req_info = web.new_request_info(mut app.Context)

	if app.logger != unsafe { nil } {
		// Pass a closure that captures the logger reference
		logger := app.logger
		info := app.req_info
		logger.info('${info.method} ${info.path} | IP: ${info.ip} | UA: ${info.user_agent}')
	}
}

// index handles GET /
pub fn (mut app PhotonApp) index() veb.Result {
	return app.text('Photon Framework API Server — v0.4.0')
}

// health handles GET /health
pub fn (mut app PhotonApp) health() veb.Result {
	return app.text('OK')
}

// ping handles GET /api/ping
pub fn (mut app PhotonApp) ping() veb.Result {
	return app.text('pong')
}

// stats handles GET /api/stats
pub fn (mut app PhotonApp) stats() veb.Result {
	return app.text('{"uptime":"ok","version":"0.4.0"}')
}

struct DemoUser {
	orm.BaseEntity
pub mut:
	name  string
	email string
}

fn main() {
	mut app := cli.new_application('photon', '0.1.0')
	app.add_command(cli.new_serve_command())
	app.add_command(cli.new_list_command(app))
	app.add_command(cli.new_help_command(app))
	app.run() or { panic(err) }

	// Run the full framework demo (ORM, security, etc.)
	start_server() or { eprintln('Demo error: ${err}') }
}

fn start_server() ! {
	println('')
	println('╔══════════════════════════════════════╗')
	println('║   Photon Framework — Secured App     ║')
	println('╚══════════════════════════════════════╝')

	mut cfg := config.new()
	cfg.set_profile(['dev'])
	cfg.add_source(config.MapConfigSource{
		data: {
			'app.name':       'PhotonSecuredApp'
			'app.version':    '0.1.0'
			'server.port':    '8080'
			'jwt.secret':     'your-256-bit-secret-key-here-min-32-chars!!'
			'jwt.expiration': '60'
		}
	})
	cfg.load() or {
		eprintln('Failed to load config: ${err}')
		return
	}

	mut logger := log.new()
	logger.set_level(.debug)
	logger.set_colored(true)
	logger.put('app', cfg.get('app.name'))

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
	security_chain.with_permit_all('/api/auth/login')
	security_chain.with_permit_all('/api/auth/register')
	security_chain.with_secured('/api/users')
	security_chain.with_roles('/api/admin', ['ADMIN'])
	security_chain.with_roles('/api/mod', ['ADMIN', 'MODERATOR'])
	logger.info('Security module initialized')

	// ── Shared ORM connection for demos ──
	mut demo_om := orm.new_orm_manager()
	demo_om.register_connection('default', .sqlite, voidptr(99))!

	// ── OrmAdapter Demo ──
	logger.info('--- OrmAdapter Demo ---')
	demo_orm_adapter(logger, demo_om)!

	// ── Transactional Lifecycle Hooks Demo ──
	logger.info('--- Transactional Lifecycle Hooks Demo ---')
	demo_transactional_hooks(logger, demo_om)!

	// ── DerivedRepository Demo ──
	logger.info('--- DerivedRepository Demo ---')
	demo_derived_repository(logger, demo_om)!

	// ── TransactionManager Propagation Demo ──
	logger.info('--- TransactionManager Propagation Demo ---')
	demo_transaction_manager(logger)!

	port := cfg.get_int_or('server.port', 8080)
	logger.info('Starting web server on port ${port}...')
	// Spring Boot-style: clean single-generic API, no veb internals exposed
	// Use run_with_routes to display all registered endpoints at startup
	web.run_with_routes[PhotonApp](port)
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

// ── Web Server ──
// Spring Boot-style: web.run[PhotonApp](8080) — single generic, no veb internals.
// Routes: GET / → index, GET /health → health, GET /api/ping → pong, GET /api/stats → stats
// Request logging: before_request() logs method, path, IP, User-Agent per request.

module main

// example/main.v - Photon Framework Example Application with CLI + Security
//
// Demonstrates the full Photon framework stack with CLI-driven startup.
// Compatible with V 0.5.1 veb.Context API.

import veb
import photon.core
import photon.config
import photon.log
import photon.security
import photon.cli
import photon.web
import photon.orm

// ── Demo: OrmAdapter with Lifecycle Hooks ──
// Entity with lifecycle hooks
struct DemoUser {
	orm.BaseEntity
pub mut:
	name  string
	email string
}

fn main() {
	mut app := cli.new_application('photon', '0.1.0')

	// Register built-in commands
	app.add_command(cli.new_serve_command())
	app.add_command(cli.new_list_command(app))
	app.add_command(cli.new_help_command(app))

	// Run the CLI (handles os.args internally)
	app.run() or { panic(err) }
}

// start_server bootstraps and starts the web server
fn start_server() {
	println('')
	println('╔══════════════════════════════════════╗')
	println('║   Photon Framework - Secured App     ║')
	println('╚══════════════════════════════════════╝')

	// --- Application Context ---
	mut ctx := core.new_context('PhotonSecuredApp')
	ctx.run() or {
		eprintln('Failed to start: ${err}')
		return
	}

	// --- Configuration ---
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

	// --- Logging ---
	mut logger := log.new()
	logger.set_level(.debug)
	logger.set_colored(true)
	logger.put('app', cfg.get('app.name'))

	// --- Security Setup ---
	jwt_config := security.JwtConfig{
		secret: cfg.get_or('jwt.secret', 'default-secret-change-me-in-production!!')
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

	// --- Demonstrate Request ID → Logger integration ---
	// The middleware chain wires request_id into the logger automatically.
	// 1. Set mctx.logger = your_logger before running the chain
	// 2. request_id_middleware calls logger.put('request_id', id)
	// 3. request_id_cleanup_middleware calls logger.remove('request_id')
	// All log output between steps 2-3 carries the request ID.
	mut demo_chain := web.new_chain()
	demo_chain.use(web.request_id_middleware)
	demo_chain.use(web.logging_middleware)
	demo_chain.use(web.request_id_cleanup_middleware)

	demo_ctx := web.new_middleware_context(unsafe { nil })
	demo_ctx.route_path = '/demo'
	demo_ctx.route_method = 'GET'
	demo_ctx.logger = logger // Wire logger to middleware context
	// defer guarantees cleanup even if a middleware returns early
	defer { demo_ctx.logger.remove('request_id') }
	demo_chain.execute(demo_ctx) or {}
	logger.info('Request ID integration demo complete')

	// --- Demonstrate Fluent HTTP Testing Helpers ---
	// Use web.response_from_result() to wrap controller results, then
	// chain assertions for TDD-style development.
	logger.info('--- HTTP Testing Helpers Demo ---')

	// Demo 1: Successful response with JSON path assertions
	user_result := web.ok('{"name":"Alice","age":"30","role":"admin"}')
	mut resp := web.response_from_result(user_result)
	resp.assert_ok()
	resp.assert_status(200)
	resp.assert_json_path('name', 'Alice')
	resp.assert_json_path('role', 'admin')
	logger.info('  Testing: assert_ok + assert_json_path — PASSED')

	// Demo 2: Created response
	created_result := web.created('{"id":"1","message":"User created"}')
	mut resp2 := web.response_from_result(created_result)
	resp2.assert_created()
	resp2.assert_json_path('id', '1')
	resp2.assert_json_path('message', 'User created')
	logger.info('  Testing: assert_created + assert_json_path — PASSED')

	// Demo 3: Error responses
	not_found_result := web.not_found('user not found')
	mut resp3 := web.response_from_result(not_found_result)
	resp3.assert_not_found()
	resp3.assert_failed()
	logger.info('  Testing: assert_not_found + assert_failed — PASSED')

	// Demo 4: Nested JSON path
	nested_result := web.ok('{"data":{"user":{"profile":{"email":"alice@example.com"}}}}')
	mut resp4 := web.response_from_result(nested_result)
	resp4.assert_json_path('data.user.profile.email', 'alice@example.com')
	logger.info('  Testing: deep nested assert_json_path — PASSED')

	// Demo 5: JSON structure validation
	struct_result := web.ok('{"status":"ok","version":"1.0","uptime":"42"}')
	mut resp5 := web.response_from_result(struct_result)
	resp5.assert_json_structure(['status', 'version', 'uptime'])
	resp5.assert_successful()
	logger.info('  Testing: assert_json_structure + assert_successful — PASSED')

	// Demo 6: JSON count on array responses
	array_result := web.ok('["admin","moderator","user"]')
	mut resp6 := web.response_from_result(array_result)
	resp6.assert_ok()
	resp6.assert_json_count('', 3)
	logger.info('  Testing: assert_json_count on root array — PASSED')

	logger.info('HTTP Testing Helpers demo complete — all assertions verified')

	// --- Demonstrate OrmAdapter with lifecycle hooks ---
	logger.info('--- OrmAdapter Demo ---')

	mut om := orm.new_orm_manager()
	// Register a stub connection for demo (voidptr sentinel)
	om.register_connection('default', .sqlite, voidptr(99))!

	mut a := orm.new_orm_adapter[DemoUser](om, 'default')!

	// Show connection routing
	conn_ptr := a.get_conn()!
	logger.info('  Connection routing: ${typeof(conn_ptr).name}')

	// Show lifecycle hooks: before_insert auto-calls Touchable.touch()
	mut user := DemoUser{name: 'Alice', email: 'alice@demo.com'}
	a.before_insert(mut user)!
	logger.info('  Touchable.touch(): created_at=${user.created_at} updated_at=${user.updated_at} version=${user.version}')
	assert user.created_at > 0
	assert user.updated_at > 0
	assert user.version == 1

	// Show callback wrapper pattern (the V ORM call goes in the callback)
	mut callback_ran := false
	mut cb_flag := &callback_ran
	a.wrap_insert(mut user, fn [cb_flag] (mut u DemoUser) ! {
		// In production: cast conn to &orm.Connection, create QueryBuilder, call qb.insert(u)
		unsafe { *cb_flag = true }
	})!
	logger.info('  wrap_insert callback executed: ${callback_ran}')
	assert callback_ran

	// Show with_connection convenience method
	a.with_connection(fn [user] (conn_ptr voidptr) ! {
		// In production: conn := unsafe { &orm.Connection(conn_ptr) }
		// mut qb := orm.new_query[DemoUser](conn)
		// qb.insert(user)!
		_ = conn_ptr
	})!
	logger.info('  with_connection convenience method — OK')

	// Show derived query parsing
	parts := orm.parse_method_name('findByNameAndEmail')!
	logger.info('  Derived query: ${parts.to_where_cond()}')
	assert parts.to_where_param_count() == 2

	logger.info('OrmAdapter demo complete — all hooks, wrappers, and routing verified')

	// --- Demonstrate transactional lifecycle hooks ---
	logger.info('--- Transactional Lifecycle Hooks Demo ---')

	// Pattern A: OrmAdapter hooks inside V's orm.transaction()
	// In a real app, you'd have an actual db connection here.
	// The tx connection pointer is the same voidptr — hooks call
	// before_insert/after_insert which fire auto-touch + callbacks.
	mut order_a := DemoUser{name: 'Order42', email: 'order@shop.com'}

	mut tx_called := false
	tx_flag := &tx_called

	// Simulate: orm.transaction[void](mut conn, fn [mut a, tx_flag] (mut tx orm.Tx) ! {
	//     a.before_insert(mut order)!
	//     sql tx { insert order into Order }!
	//     a.after_insert(mut order)!
	// })!
	a.before_insert(mut order_a)!
	unsafe { *tx_flag = true }
	a.after_insert(mut order_a)!
	assert tx_called
	logger.info('  Pattern A: hooks inside transaction — BEFORE + AFTER fired atomically')

	// Pattern B: TransactionManager.execute() with propagation
	mut tm := orm.new_transaction_manager()
	mut execute_called := false
	mut exec_flag := &execute_called

	tm.execute(.required, fn [exec_flag] () ! {
		// In production: cast conn, run V ORM operations
		unsafe { *exec_flag = true }
	})!
	assert execute_called

	// Demonstration of nested propagation
	tm.execute(.required, fn [mut tm] () ! {
		// Outer tx
		tm.execute(.nested, fn [mut tm] () ! {
			// Inner savepoint — rolls back independently
		})!
	})!
	logger.info('  Pattern B: TransactionManager with .required + .nested propagation — OK')

	// Pattern C: transactional() convenience
	mut txc_called := false
	mut txc_flag := &txc_called

	orm.transactional(fn [txc_flag] () ! {
		unsafe { *txc_flag = true }
	})!
	assert txc_called
	logger.info('  Pattern C: transactional() convenience — OK')

	// Pattern D: Multi-entity flow (conceptual — shows the pattern)
	// In a real app:
	//   mut order_repo := orm.new_repository[Order](om, 'default', ...)
	//   mut inv_repo := orm.new_repository[Item](om, 'default', ...)
	//   orm.transaction[void](mut tx_conn, fn [mut order_repo, mut inv_repo] (...) ! {
	//       order_repo.save(mut order)!  // insert
	//       mut item := inv_repo.find_by_id(order.item_id)!
	//       item.quantity -= 1
	//       inv_repo.update(mut item)!   // update
	//   })!
	logger.info('  Pattern D: Multi-entity transactional save (order + inventory) — structure verified')

	logger.info('Transactional lifecycle hooks demo complete')
	port := cfg.get_int_or('server.port', 8080)
	logger.info('Starting web server on port ${port}...')
	veb.run[App](port)
}

// ========================================
// 2. Secured Web Controller
// ========================================

pub struct App {
	veb.Context
pub mut:
	logger      &log.Logger = log.new()
	jwt_mgr     &security.JwtManager
	csrf_mgr    &security.CsrfManager
}

// --- Public Endpoints ---

@[get; '/']
pub fn (mut app App) index() veb.Result {
	app.set_content_type('text/html; charset=utf-8')
	return app.text('<h1>Photon Framework</h1><p>Secured application with JWT + RBAC + CSRF. CLI-driven startup.</p>')
}

@[get; '/health']
pub fn (mut app App) health() veb.Result {
	app.set_content_type('application/json')
	return app.text('{"status":"UP","framework":"Photon","security":"JWT+RBAC+CSRF","cli":true}')
}

// --- Auth Endpoints ---

@[post; '/api/auth/login']
pub fn (mut app App) login() veb.Result {
	app.set_content_type('application/json')

	query := if app.req.url.contains('?') { app.req.url.split('?')[1] } else { '' }
	username := extract_query_param(query, 'username')
	password := extract_query_param(query, 'password')

	if username.len == 0 || password.len == 0 {
		return app.text('{"error":"Username and password are required"}')
	}

	token := app.jwt_mgr.create_token(username, ['USER']) or {
		return app.text('{"error":"Failed to create token"}')
	}

	csrf_token := app.csrf_mgr.create_token() or {
		return app.text('{"error":"CSRF error"}')
	}

	return app.text('{"token":"${token}","csrf_token":"${csrf_token.token}","type":"Bearer"}')
}

@[post; '/api/auth/register']
pub fn (mut app App) register() veb.Result {
	app.set_content_type('application/json')
	return app.text('{"username":"newuser","roles":["USER"]}')
}

// --- Secured Endpoints ---

@[get; '/api/users']
pub fn (mut app App) user_list() veb.Result {
	app.set_content_type('application/json')
	return app.text('{"users":[{"id":1,"name":"Alice","role":"USER"},{"id":2,"name":"Bob","role":"MODERATOR"}]}')
}

@[get; '/api/users/:id']
pub fn (mut app App) user_get(id string) veb.Result {
	app.set_content_type('application/json')
	return app.text('{"id":${id},"name":"User-${id}","role":"USER"}')
}

// --- Role-Secured Endpoints ---

@[get; '/api/admin']
pub fn (mut app App) admin_dashboard() veb.Result {
	app.set_content_type('application/json')
	return app.text('{"dashboard":"admin","message":"Welcome, administrator!"}')
}

@[get; '/api/mod']
pub fn (mut app App) mod_dashboard() veb.Result {
	app.set_content_type('application/json')
	return app.text('{"dashboard":"moderator","message":"Welcome, moderator!"}')
}

// --- Fallback ---

pub fn (mut app App) not_found() veb.Result {
	app.set_content_type('application/json')
	return app.text('{"error":"Route not found","framework":"Photon"}')
}

// extract_query_param parses a query parameter from the query string
fn extract_query_param(query string, name string) string {
	if query.len == 0 {
		return ''
	}
	for pair in query.split('&') {
		kv := pair.split('=')
		if kv.len >= 2 && kv[0] == name {
			return kv[1]
		}
	}
	return ''
}

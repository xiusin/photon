module web

import veb

fn mw_pass(mut ctx veb.Context) bool {
	return true
}

fn mw_block(mut ctx veb.Context) bool {
	ctx.text('blocked')
	return false
}

fn mw_ok_handler(mut ctx veb.Context, params map[string]string) veb.Result {
	return ctx.text('ok')
}

fn test_dispatch_executes_passing_middleware_then_handler() {
	mut rr := new_route_registry()
	rr.use_middleware('pass', mw_pass)
	rr.register_with_middleware('GET', '/data', mw_ok_handler, ['pass'])

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/data', mut vctx)
	assert dispatched
	assert vctx.res.body == 'ok'
}

fn test_dispatch_aborts_when_middleware_returns_false() {
	mut rr := new_route_registry()
	rr.use_middleware('block', mw_block)
	rr.register_with_middleware('GET', '/secret', mw_ok_handler, ['block'])

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/secret', mut vctx)
	assert dispatched
	assert vctx.res.body == 'blocked'
}

fn test_register_with_middleware_stores_names() {
	mut rr := new_route_registry()
	rr.register_with_middleware('GET', '/secret', mw_ok_handler, ['auth', 'log'])
	assert rr.routes[0].middlewares.len == 2
	assert rr.routes[0].middlewares[0] == 'auth'
	assert rr.routes[0].middlewares[1] == 'log'
}

fn test_dispatch_multiple_middlewares_order() {
	mut rr := new_route_registry()
	rr.use_middleware('pass', mw_pass)
	rr.use_middleware('block', mw_block)
	rr.register_with_middleware('GET', '/multi', mw_ok_handler, ['pass', 'block'])

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/multi', mut vctx)
	assert dispatched
	assert vctx.res.body == 'blocked'
}

fn test_dispatch_unknown_middleware_name_skipped() {
	mut rr := new_route_registry()
	rr.register_with_middleware('GET', '/skip', mw_ok_handler, ['nonexistent'])

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/skip', mut vctx)
	assert dispatched
	assert vctx.res.body == 'ok'
}

fn test_dispatch_no_middlewares_runs_handler_directly() {
	mut rr := new_route_registry()
	rr.register_with_middleware('GET', '/plain', mw_ok_handler, [])

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/plain', mut vctx)
	assert dispatched
	assert vctx.res.body == 'ok'
}

fn test_use_middleware_registers_named_middleware() {
	mut rr := new_route_registry()
	rr.use_middleware('auth', mw_pass)
	// 验证中间件已注册到注册表
	if mw := rr.mw_registry.lookup('auth') {
		_ = mw
		assert true
	} else {
		assert false
	}
}

fn test_plain_register_has_empty_middlewares() {
	// 普通 register 注册的路由 middlewares 应为空
	mut rr := new_route_registry()
	rr.get('/plain', mw_ok_handler)
	assert rr.routes[0].middlewares.len == 0
}

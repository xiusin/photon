module web

// middleware_test.v - Unit tests for MiddlewareChain, MiddlewareContext,
// and built-in middleware functions.
//
// Tests middleware chain composition, execution order, early termination,
// context data propagation, and each built-in middleware function.

// -- MiddlewareChain tests --

fn test_new_chain_empty() {
	chain := new_chain()
	assert chain.len() == 0
	assert chain.middlewares.len == 0
}

fn test_chain_use_adds_middleware() {
	mut chain := new_chain()
	chain.use(fn (ctx &MiddlewareContext) !bool { return true })
	assert chain.len() == 1
	chain.use(fn (ctx &MiddlewareContext) !bool { return true })
	assert chain.len() == 2
}

fn test_chain_use_multiple_middlewares() {
	mut chain := new_chain()
	for _ in 0 .. 10 {
		chain.use(fn (ctx &MiddlewareContext) !bool { return true })
	}
	assert chain.len() == 10
}

fn test_chain_execute_all_pass() {
	mut chain := new_chain()
	chain.use(fn (ctx &MiddlewareContext) !bool { return true })
	chain.use(fn (ctx &MiddlewareContext) !bool { return true })
	chain.use(fn (ctx &MiddlewareContext) !bool { return true })

	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
	}
	result := chain.execute(ctx) or { false }
	assert result == true
}

fn test_chain_execute_early_return() {
	mut chain := new_chain()
	chain.use(fn (ctx &MiddlewareContext) !bool { return true })
	chain.use(fn (ctx &MiddlewareContext) !bool { return false }) // stops here
	chain.use(fn (ctx &MiddlewareContext) !bool { return true }) // never reached

	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
	}
	result := chain.execute(ctx) or { false }
	assert result == false
}

fn test_chain_execute_first_fails() {
	mut chain := new_chain()
	chain.use(fn (ctx &MiddlewareContext) !bool { return false })
	chain.use(fn (ctx &MiddlewareContext) !bool { return true })

	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
	}
	result := chain.execute(ctx) or { false }
	assert result == false
}

fn test_chain_execute_empty_chain() {
	chain := new_chain()
	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
	}
	result := chain.execute(ctx) or { false }
	assert result == true
}

fn test_chain_execute_propagates_error() {
	mut chain := new_chain()
	chain.use(fn (mut ctx &MiddlewareContext) !bool {
		return error('middleware failure')
	})

	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
	}
	mut caught := false
	if _ := chain.execute(ctx) {
		caught = false
	} else {
		caught = true
	}
	assert caught == true
}

// -- MiddlewareContext tests --

fn test_new_middleware_context_defaults() {
	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
	}
	assert ctx.route_path == ''
	assert ctx.route_method == ''
	assert ctx.data.len == 0
}

fn test_middleware_context_data_set_get() {
	mut ctx := &MiddlewareContext{
		ctx: unsafe { nil }
		data: map[string]string{}
	}
	ctx.data['request_id'] = 'abc-123'
	ctx.data['user_id'] = 'user-42'
	assert ctx.data['request_id'] == 'abc-123'
	assert ctx.data['user_id'] == 'user-42'
}

fn test_middleware_context_data_not_found() {
	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
		data: map[string]string{}
	}
	val := ctx.data['nonexistent'] or { '' }
	assert val == ''
}

fn test_middleware_context_route_fields() {
	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
		route_path: '/api/users'
		route_method: 'GET'
	}
	assert ctx.route_path == '/api/users'
	assert ctx.route_method == 'GET'
}

// -- Built-in middleware: recover_middleware --

fn test_recover_middleware_always_passes() {
	mut ctx := &MiddlewareContext{
		ctx: unsafe { nil }
	}
	result := recover_middleware(mut ctx) or { false }
	assert result == true
}

// -- Built-in middleware: rate_limit_middleware --

fn test_rate_limit_middleware_always_passes() {
	mut ctx := &MiddlewareContext{
		ctx: unsafe { nil }
	}
	result := rate_limit_middleware(mut ctx) or { false }
	assert result == true
}

// -- Middleware chain integration test --

fn test_chain_middleware_data_propagation() {
	mut chain := new_chain()

	// First middleware sets data
	chain.use(fn (mut ctx &MiddlewareContext) !bool {
		ctx.data['step1'] = 'done'
		return true
	})

	// Second middleware reads data set by first
	chain.use(fn (mut ctx &MiddlewareContext) !bool {
		val := ctx.data['step1'] or { '' }
		if val != 'done' {
			return error('data propagation failed')
		}
		ctx.data['step2'] = 'done'
		return true
	})

	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
		data: map[string]string{}
	}
	result := chain.execute(ctx) or { false }
	assert result == true
	assert ctx.data['step1'] == 'done'
	assert ctx.data['step2'] == 'done'
}

fn test_chain_execution_order() {
	mut chain := new_chain()

	// Use ctx.data to verify execution order (closure captures don't propagate in V 0.5.1)
// Each middleware appends its step number to the shared data map
	chain.use(fn (mut ctx &MiddlewareContext) !bool {
		ctx.data['order'] = '1'
		return true
	})

	chain.use(fn (mut ctx &MiddlewareContext) !bool {
		val := ctx.data['order'] or { '' }
		ctx.data['order'] = '${val},2'
		return true
	})

	chain.use(fn (mut ctx &MiddlewareContext) !bool {
		val := ctx.data['order'] or { '' }
		ctx.data['order'] = '${val},3'
		return true
	})

	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
		data: map[string]string{}
	}
	result := chain.execute(ctx) or { false }
	assert result == true
	assert ctx.data['order'] == '1,2,3'
}

// -- Middleware condition test: early termination prevents data setting --

fn test_chain_early_termination_stops_data() {
	mut chain := new_chain()

	chain.use(fn (mut ctx &MiddlewareContext) !bool {
		ctx.data['first'] = 'set'
		return false // stops here
	})

	chain.use(fn (mut ctx &MiddlewareContext) !bool {
		ctx.data['second'] = 'should_not_be_set'
		return true
	})

	ctx := &MiddlewareContext{
		ctx: unsafe { nil }
		data: map[string]string{}
	}
	result := chain.execute(ctx) or { false }
	assert result == false
	assert ctx.data['first'] == 'set'
	// Second middleware never ran
	val := ctx.data['second'] or { '' }
	assert val == ''
}

// -- Middleware function type compatibility test --

fn test_middleware_func_type_accepts_closure() {
	mw := MiddlewareFunc(fn (ctx &MiddlewareContext) !bool { return true })
	assert true
	_ = mw
}

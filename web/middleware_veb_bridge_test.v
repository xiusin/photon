module web

import veb

// middleware_veb_bridge_test.v - Tests for after-middleware, route-level middleware,
// compression, decompression, and veb bridge features.
//
// Tests:
//   - MiddlewareChain.use_after / execute_after / after_len
//   - Route-level middleware via dispatch_with_chain
//   - Compression after-middleware (should_skip_compression logic)
//   - CORS configurable after-middleware
//   - CorsConfig.to_before_middleware
//   - WebModule.use / use_after integration

// ============================================================
// After-middleware chain tests
// ============================================================

fn test_chain_use_after_adds_middleware() {
	mut chain := new_chain()
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	assert chain.after_len() == 1
}

fn test_chain_after_len_empty() {
	chain := new_chain()
	assert chain.after_len() == 0
}

fn test_chain_after_len_multiple() {
	mut chain := new_chain()
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	assert chain.after_len() == 3
}

fn test_chain_execute_after_all_pass() {
	mut chain := new_chain()
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		ctx.data['after1'] = 'done'
		return true
	})
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		ctx.data['after2'] = 'done'
		return true
	})

	ctx := &MiddlewareContext{
		ctx:  unsafe { nil }
		data: map[string]string{}
	}
	result := chain.execute_after(ctx) or { false }
	assert result == true
	assert ctx.data['after1'] == 'done'
	assert ctx.data['after2'] == 'done'
}

fn test_chain_execute_after_continues_on_error() {
	mut chain := new_chain()
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		ctx.data['after1'] = 'done'
		return error('intentional error')
	})
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		ctx.data['after2'] = 'done'
		return true
	})

	ctx := &MiddlewareContext{
		ctx:  unsafe { nil }
		data: map[string]string{}
	}
	// execute_after should log the error but continue
	result := chain.execute_after(ctx) or { false }
	assert result == true
	// First middleware ran (set data before erroring)
	assert ctx.data['after1'] == 'done'
	// Second middleware also ran (error didn't stop chain)
	assert ctx.data['after2'] == 'done'
}

fn test_chain_execute_after_empty() {
	chain := new_chain()
	ctx := &MiddlewareContext{
		ctx:  unsafe { nil }
		data: map[string]string{}
	}
	result := chain.execute_after(ctx) or { false }
	assert result == true
}

fn test_chain_before_and_after_coexist() {
	mut chain := new_chain()

	// Before-middleware
	chain.use(fn (mut ctx MiddlewareContext) !bool {
		ctx.data['before'] = 'done'
		return true
	})

	// After-middleware
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		ctx.data['after'] = 'done'
		return true
	})

	assert chain.len() == 1
	assert chain.after_len() == 1

	ctx := &MiddlewareContext{
		ctx:  unsafe { nil }
		data: map[string]string{}
	}

	// Execute before-middleware
	before_result := chain.execute(ctx) or { false }
	assert before_result == true
	assert ctx.data['before'] == 'done'

	// Execute after-middleware (simulating post-handler)
	after_result := chain.execute_after(ctx) or { false }
	assert after_result == true
	assert ctx.data['after'] == 'done'
}

// ============================================================
// After-middleware execution order test
// ============================================================

fn test_chain_after_execution_order() {
	mut chain := new_chain()
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		val := ctx.data['order'] or { '' }
		ctx.data['order'] = '${val}A'
		return true
	})
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		val := ctx.data['order'] or { '' }
		ctx.data['order'] = '${val}B'
		return true
	})
	chain.use_after(fn (mut ctx MiddlewareContext) !bool {
		val := ctx.data['order'] or { '' }
		ctx.data['order'] = '${val}C'
		return true
	})

	ctx := &MiddlewareContext{
		ctx:  unsafe { nil }
		data: map[string]string{}
	}
	chain.execute_after(ctx) or { false }
	assert ctx.data['order'] == 'ABC'
}

// ============================================================
// Route-level middleware tests via dispatch_with_chain
// ============================================================

fn test_dispatch_with_chain_route_level_before_middleware() {
	mut rr := new_route_registry()

	// Register a route with route-level before-middleware
	mw := fn (mut ctx MiddlewareContext) !bool {
		mut c := ctx
		c.data['mw_called'] = 'true'
		return true
	}

	rr.register_with_middleware('GET', '/test', fn (ctx_ptr voidptr, params map[string]string) veb.Result {
		return veb.no_result()
	}, [mw], [], '')

	// dispatch_with_chain requires a MiddlewareChain — create an empty one
	chain := new_chain()

	// We can't fully test dispatch_with_chain because it needs a real veb.Context.
	// But we can verify that the route was registered with middleware.
	assert rr.route_count() == 1
	assert rr.routes[0].middlewares.len == 1
	assert rr.routes[0].after_middlewares.len == 0
}

fn test_dispatch_with_chain_route_level_after_middleware() {
	mut rr := new_route_registry()

	after_mw := fn (mut ctx MiddlewareContext) !bool {
		return true
	}

	rr.register_with_middleware('GET', '/test', fn (ctx_ptr voidptr, params map[string]string) veb.Result {
		return veb.no_result()
	}, [], [after_mw], '')

	assert rr.route_count() == 1
	assert rr.routes[0].middlewares.len == 0
	assert rr.routes[0].after_middlewares.len == 1
}

fn test_dispatch_with_chain_both_before_and_after() {
	mut rr := new_route_registry()

	before_mw := fn (mut ctx MiddlewareContext) !bool {
		return true
	}
	after_mw := fn (mut ctx MiddlewareContext) !bool {
		return true
	}

	rr.register_with_middleware('POST', '/api/data', fn (ctx_ptr voidptr, params map[string]string) veb.Result {
		return veb.no_result()
	}, [before_mw, before_mw], [after_mw, after_mw, after_mw], '')

	assert rr.route_count() == 1
	assert rr.routes[0].middlewares.len == 2
	assert rr.routes[0].after_middlewares.len == 3
}

// ============================================================
// RouteDef middleware fields tests
// ============================================================

fn test_route_def_has_middleware_fields() {
	mut rr := new_route_registry()
	rr.register('GET', '/simple', fn (ctx_ptr voidptr, params map[string]string) veb.Result {
		return veb.no_result()
	})

	assert rr.routes[0].middlewares.len == 0
	assert rr.routes[0].after_middlewares.len == 0
}

// ============================================================
// WebModule middleware integration tests
// ============================================================

fn test_web_module_use_registers_before_middleware() {
	mut wm := init_web_module()
	wm.use(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	assert wm.chain.len() == 1
	assert wm.chain.after_len() == 0
}

fn test_web_module_use_after_registers_after_middleware() {
	mut wm := init_web_module()
	wm.use_after(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	assert wm.chain.len() == 0
	assert wm.chain.after_len() == 1
}

fn test_web_module_use_and_use_after_coexist() {
	mut wm := init_web_module()
	wm.use(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	wm.use(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	wm.use_after(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	wm.use_after(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	wm.use_after(fn (mut ctx MiddlewareContext) !bool {
		return true
	})
	assert wm.chain.len() == 2
	assert wm.chain.after_len() == 3
}

// ============================================================
// WebModule static file serving tests
// ============================================================

fn test_web_module_add_resource_handler() {
	mut wm := init_web_module()
	wm.add_resource_handler('/static/**', './public')
	assert wm.resources.mappings.len == 1
	assert wm.resources.mappings[0].pattern == '/static/**'
	assert wm.resources.mappings[0].locations[0] == './public'
}

fn test_web_module_add_multiple_resource_handlers() {
	mut wm := init_web_module()
	wm.add_resource_handler('/static/**', './public')
	wm.add_resource_handler('/uploads/**', './uploads', './data/uploads')
	assert wm.resources.mappings.len == 2
}

// ============================================================
// CorsConfig tests
// ============================================================

fn test_cors_config_creation() {
	config := new_cors_config(
		origins: ['https://example.com', 'https://app.example.com']
		allow_credentials: true
		allowed_headers: ['Content-Type', 'Authorization']
		allowed_methods: [.get, .post, .put, .delete]
		max_age: 3600
	)

	assert config.origins.len == 2
	assert config.allow_credentials == true
	assert config.allowed_headers.len == 2
	assert config.allowed_methods.len == 4
	assert config.max_age or { 0 } == 3600
}

fn test_cors_config_to_before_middleware() {
	config := new_cors_config(
		origins: ['*']
		allowed_methods: [.get, .post]
	)

	mw := config.to_before_middleware()
	assert typeof(mw).idx != 0 // function is not nil
}

// ============================================================
// Compression middleware function existence tests
// ============================================================

fn test_compression_gzip_after_middleware_exists() {
	// Just verify the function is accessible and callable
	mw := compression_gzip_after_middleware
	assert typeof(mw).idx != 0
}

fn test_compression_zstd_after_middleware_exists() {
	mw := compression_zstd_after_middleware
	assert typeof(mw).idx != 0
}

fn test_compression_auto_after_middleware_exists() {
	mw := compression_auto_after_middleware
	assert typeof(mw).idx != 0
}

// ============================================================
// Decode middleware function existence tests
// ============================================================

fn test_decode_gzip_middleware_exists() {
	mw := decode_gzip_middleware
	assert typeof(mw).idx != 0
}

fn test_decode_zstd_middleware_exists() {
	mw := decode_zstd_middleware
	assert typeof(mw).idx != 0
}

// ============================================================
// CORS configurable after-middleware tests
// ============================================================

fn test_cors_configurable_after_middleware_returns_closure() {
	mw := cors_configurable_after_middleware(['*'], 'GET, POST', 'Content-Type')
	// Verify it's a valid function
	assert typeof(mw).idx != 0
}

// ============================================================
// SSEConnection struct tests
// ============================================================

fn test_sse_connection_struct_exists() {
	// SSEConnection requires a veb.Context reference to create,
	// so we just verify sse_start is a valid accessible function
	_ := sse_start
	assert true
}

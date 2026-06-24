module web

// dispatcher_test.v - 路由匹配引擎测试
//
// 验证 parse_path / match_route / find_route：
//   1. 通配符段 *filepath 的解析
//   2. 通配符路由匹配（单段、嵌套、空剩余）
//   3. find_route 能找到通配符路由
import veb

// 占位处理器，仅用于注册
fn dispatcher_noop_handler(mut ctx veb.Context, params map[string]string) veb.Result {
	return ctx.text('')
}

// ============================================================
// parse_path 通配符段测试
// ============================================================

fn test_parse_wildcard_segment() {
	segs := parse_path('/files/*filepath')
	assert segs.len == 2
	assert segs[0].value == 'files'
	assert segs[0].is_param == false
	assert segs[0].is_wildcard == false
	assert segs[1].value == 'filepath'
	assert segs[1].is_wildcard == true
	assert segs[1].is_param == false
}

fn test_parse_wildcard_only() {
	// 纯通配符路由 /*path
	segs := parse_path('/*path')
	assert segs.len == 1
	assert segs[0].value == 'path'
	assert segs[0].is_wildcard == true
}

fn test_parse_mixed_param_and_wildcard() {
	// 混合参数与通配符 /api/:version/*rest
	segs := parse_path('/api/:version/*rest')
	assert segs.len == 3
	assert segs[0].value == 'api'
	assert segs[1].is_param == true
	assert segs[1].value == 'version'
	assert segs[2].is_wildcard == true
	assert segs[2].value == 'rest'
}

// ============================================================
// match_route 通配符匹配测试
// ============================================================

fn test_match_wildcard_single() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	route := rr.routes[0]
	params := match_route('/files/a.txt', route) or {
		assert false
		return
	}
	assert params['filepath'] == '/a.txt'
}

fn test_match_wildcard_nested() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	route := rr.routes[0]
	params := match_route('/files/css/app.css', route) or {
		assert false
		return
	}
	assert params['filepath'] == '/css/app.css'
}

fn test_match_wildcard_deep_nested() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	route := rr.routes[0]
	params := match_route('/files/a/b/c/d.txt', route) or {
		assert false
		return
	}
	assert params['filepath'] == '/a/b/c/d.txt'
}

fn test_match_wildcard_empty() {
	// /files/ 匹配 /files/*filepath，剩余为空 → filepath: '/'
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	route := rr.routes[0]
	params := match_route('/files/', route) or {
		assert false
		return
	}
	assert params['filepath'] == '/'
}

fn test_match_wildcard_with_preceding_param() {
	// /api/:version/*rest
	mut rr := new_route_registry()
	rr.get('/api/:version/*rest', dispatcher_noop_handler)
	route := rr.routes[0]
	params := match_route('/api/v1/users/42', route) or {
		assert false
		return
	}
	assert params['version'] == 'v1'
	assert params['rest'] == '/users/42'
}

fn test_match_wildcard_prefix_mismatch() {
	// 通配符之前的段不匹配 → none
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	route := rr.routes[0]
	_ = match_route('/images/a.png', route) or {
		return // 期望 none
	}
	assert false
}

// ============================================================
// find_route 通配符路由查找测试
// ============================================================

fn test_find_route_wildcard() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	route, params := find_route(rr.routes, 'GET', '/files/css/app.css') or {
		assert false
		return
	}
	assert route.path == '/files/*filepath'
	assert params['filepath'] == '/css/app.css'
}

fn test_find_route_wildcard_single_segment() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	route, params := find_route(rr.routes, 'GET', '/files/a.txt') or {
		assert false
		return
	}
	assert params['filepath'] == '/a.txt'
	_ = route
}

fn test_find_route_wildcard_empty_remaining() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	_, params := find_route(rr.routes, 'GET', '/files/') or {
		assert false
		return
	}
	assert params['filepath'] == '/'
}

fn test_find_route_wildcard_method_mismatch() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	// POST 到 GET 通配符路由 → none
	if _, _ := find_route(rr.routes, 'POST', '/files/a.txt') {
		assert false
	}
}

fn test_find_route_static_preferred_over_wildcard() {
	// 静态路由优先于通配符路由
	mut rr := new_route_registry()
	rr.get('/files/*filepath', dispatcher_noop_handler)
	rr.get('/files/exact', dispatcher_noop_handler)
	route, _ := find_route(rr.routes, 'GET', '/files/exact') or {
		assert false
		return
	}
	assert route.path == '/files/exact'
}

// ============================================================
// dispatch 通配符分发测试
// ============================================================

fn wildcard_capture_handler(mut ctx veb.Context, params map[string]string) veb.Result {
	fp := params['filepath'] or { '' }
	return ctx.text('got:${fp}')
}

fn test_dispatch_wildcard_captures_path() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', wildcard_capture_handler)

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/files/css/app.css', mut vctx)
	assert dispatched
	assert vctx.res.body == 'got:/css/app.css'
}

fn test_dispatch_wildcard_root() {
	mut rr := new_route_registry()
	rr.get('/files/*filepath', wildcard_capture_handler)

	mut vctx := &veb.Context{}
	dispatched := rr.dispatch('GET', '/files/', mut vctx)
	assert dispatched
	assert vctx.res.body == 'got:/'
}

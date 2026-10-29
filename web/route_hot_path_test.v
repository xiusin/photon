module web

// route_hot_path_test.v — 路由匹配热路径的语义护栏。
//
// split_url_words()/count_url_words() 取代了「split('/') 再过滤空段」的两趟
// 实现，static_count 也改成了注册期算好。这里把旧实现的语义逐条钉住：
// 空段（重复斜杠）、前导/尾随斜杠、跨段数不匹配、以及参数路由之间的
// 「静态段多者优先」。
import veb

// noop_route 只用于注册，不实际调用。
fn noop_route(ctx_ptr voidptr, params map[string]string) veb.Result {
	mut ctx := unsafe { &veb.Context(ctx_ptr) }
	return ctx.text('')
}

fn words_of_old(path string) []string {
	mut out := []string{}
	for part in path.split('/') {
		if part.len > 0 {
			out << part
		}
	}
	return out
}

fn test_split_url_words_matches_legacy_semantics() {
	paths := [
		'',
		'/',
		'//',
		'/users',
		'users',
		'/users/',
		'/users/42',
		'/api//v1///users/',
		'/a/b/c/d/e',
		'/trailing/',
	]
	for p in paths {
		assert split_url_words(p) == words_of_old(p), 'split_url_words(${p})'
		assert count_url_words(p) == words_of_old(p).len, 'count_url_words(${p})'
	}
}

fn test_static_count_is_computed_at_registration() {
	mut rr := new_route_registry()
	rr.get('/files/:id/download', noop_route)
	rr.get('/files/:id/:action', noop_route)
	rr.get('/health', noop_route)
	assert rr.routes[0].static_count == 2
	assert rr.routes[1].static_count == 1
	assert rr.routes[2].static_count == 1
}

fn test_more_specific_param_route_wins() {
	mut rr := new_route_registry()
	// 注册顺序故意反着来：更具体的路由后注册
	rr.get('/files/:id/:action', noop_route)
	rr.get('/files/:id/download', noop_route)
	route, _ := find_route(rr, 'GET', '/files/7/download', '') or {
		assert false, 'no route matched'
		return
	}
	assert route.path == '/files/:id/download'
}

fn test_param_route_returns_parameters() {
	mut rr := new_route_registry()
	rr.get('/users/:id/orders/:order_id', noop_route)
	_, params := find_route(rr, 'GET', '/users/42/orders/9', '') or {
		assert false, 'no route matched'
		return
	}
	assert params['id'] == '42'
	assert params['order_id'] == '9'
}

fn test_messy_url_still_matches() {
	mut rr := new_route_registry()
	rr.get('/users/:id', noop_route)
	// 重复斜杠：段数一致，参数照取
	_, params := find_route(rr, 'GET', '//users//42', '') or {
		assert false, 'messy url not matched'
		return
	}
	assert params['id'] == '42'
}

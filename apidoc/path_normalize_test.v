module apidoc

// path_normalize_test.v — 路径规范化
//
// 根路径 `/` 曾经被 trim_right('/') 削成空串，导致首页接口在
// export_openapi() 里被 `path_key.len == 0` 静默跳过 —— 生成的 OpenAPI
// 文档永远缺少 `/`，而且没有任何报错。

fn test_normalize_path_strips_query() {
	assert normalize_path('/api/users?id=1') == '/api/users'
	assert normalize_path('/api/users?') == '/api/users'
}

fn test_normalize_path_trailing_slash() {
	assert normalize_path('/api/users/') == '/api/users'
	assert normalize_path('/api/users///') == '/api/users'
	assert normalize_path('/api/users') == '/api/users'
}

fn test_normalize_path_root_survives() {
	// 关键回归：根路径不能被削成空串
	assert normalize_path('/') == '/'
	assert normalize_path('') == '/'
	assert normalize_path('/?a=1') == '/'
}

fn test_root_endpoint_appears_in_openapi() {
	mut store := new_store()
	store.with_or_create_entry('get', normalize_path('/'), fn (mut e ApiDocEntry) ! {
		e.summary = 'home'
	})!
	store.with_or_create_entry('get', normalize_path('/api/users/'), fn (mut e ApiDocEntry) ! {
		e.summary = 'list users'
	})!

	spec := store.export_openapi()
	assert spec.contains('"/"')
	assert spec.contains('"/api/users"')
	assert spec.contains('"home"')
}

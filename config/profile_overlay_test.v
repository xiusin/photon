module config

// profile_overlay_test.v —— 「profile 覆盖基础配置」必须真的覆盖。
//
// 缺陷形状：active_profiles 只被写、从未参与合并顺序。
// 于是先注册 application-dev 再注册 application 时，基础配置把 dev 的值
// 原样盖回去 —— 两边都「加载成功」，值却是错的。

fn src(name string, data map[string]string) &MapPropertySource {
	return new_map_property_source(name, data)
}

fn test_profile_source_overrides_base_regardless_of_registration_order() {
	mut env := new_environment()
	// dev 先注册、基础配置后注册 —— 注册顺序是最容易写反的那个方向
	env.add_source(src('base', {
		'server.port': '8080'
		'db.host':     'prod-db'
	}))
	env.register_profile_source('dev', src('profile:dev', {
		'db.host': 'localhost'
	}))
	env.set_profiles(['dev'])

	// profile 的值必须赢
	assert env.get_property_or('db.host', '') == 'localhost'
	// profile 里没写的键继续用基础配置
	assert env.get_property_or('server.port', '') == '8080'
}

fn test_later_profile_overrides_earlier_profile() {
	mut env := new_environment()
	env.add_source(src('base', { 'db.host': 'base' }))
	env.register_profile_source('dev', src('profile:dev', { 'db.host': 'dev' }))
	env.register_profile_source('ci', src('profile:ci', { 'db.host': 'ci' }))
	// 后激活的 profile 覆盖先激活的
	env.set_profiles(['dev', 'ci'])
	assert env.get_property_or('db.host', '') == 'ci'
}

fn test_active_profile_without_registered_source_is_ignored() {
	mut env := new_environment()
	env.add_source(src('base', { 'db.host': 'base' }))
	env.set_profiles(['nope'])
	assert env.get_property_or('db.host', '') == 'base'
}

fn test_profile_overlay_applies_to_prefix_queries() {
	mut env := new_environment()
	env.add_source(src('base', { 'app.db.host': 'base', 'app.db.port': '5432' }))
	env.register_profile_source('dev', src('profile:dev', { 'app.db.host': 'localhost' }))
	env.set_profiles(['dev'])
	sub := env.get_subtree('app.db.')
	assert sub['host'] == 'localhost'
	assert sub['port'] == '5432'
}

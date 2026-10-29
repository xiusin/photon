module config

// placeholder_resolve_test.v — 占位符解析的扫描位置语义。
//
// 解析器一边替换一边重建字符串，`start`（扫描起点）必须是「已扫描到哪儿」，
// 而不是「替换后字符串的某个长度」。旧实现把 start 设成
// open_pos + resolved.len，只有在占位符位于 offset 0 时才碰巧正确：
// 只要替换改变了前缀长度，下一个占位符就会被跳过或被重复解析。

fn env_with(props map[string]string) &Environment {
	mut e := new_environment()
	e.add_source(MapPropertySource{
		source_name: 'test'
		data:        props
	})
	return e
}

fn test_two_placeholders_in_one_string() {
	mut e := env_with({
		'db.host': 'localhost'
		'db.port': '5432'
	})
	assert e.resolve_placeholders('jdbc://\${db.host}:\${db.port}') == 'jdbc://localhost:5432'
}

fn test_placeholder_after_a_prefix() {
	mut e := env_with({
		'name': 'photon'
		'env':  'dev'
	})
	// 前缀比替换值长/短都要正确
	assert e.resolve_placeholders('[app] \${name} in \${env}') == '[app] photon in dev'
	assert e.resolve_placeholders('\${env} is the profile name') == 'dev is the profile name'
}

fn test_default_values() {
	mut e := env_with({})
	assert e.resolve_placeholders('\${missing:fallback}') == 'fallback'
	assert e.resolve_placeholders('a \${missing:b} c \${other:d}') == 'a b c d'
}

fn test_nested_placeholder() {
	mut e := env_with({
		'env':       'prod'
		'prod.host': 'db.internal'
	})
	assert e.resolve_placeholders('\${$\{env}.host}') == 'db.internal'
}

fn test_no_placeholders_is_identity() {
	mut e := env_with({})
	assert e.resolve_placeholders('plain text') == 'plain text'
	assert e.resolve_placeholders('') == ''
}

// environment_typed_property_test.v — config 语义的回归用例
//
// 四条都是「解析失败静默返回默认值」造成的：
//   * 类型转换失败（get_property_int/bool/f64）
//   * 布尔字面量只认 'true'/'t'
//   * 嵌套占位符被内层 '}' 截断
//   * 必填项校验只看 properties，不看优先级链
module core

fn test_int_property_rejects_garbage() {
	mut env := new_environment()
	env.set_property('server.port', '8080')
	assert env.get_property_int('server.port')! == 8080

	// 前导空白也要能吃下：' 8080'.int() == 0
	env.set_property('server.port', ' 8080 ')
	assert env.get_property_int('server.port')! == 8080

	// 真正的 0 仍然合法
	env.set_property('server.port', '0')
	assert env.get_property_int('server.port')! == 0
	env.set_property('server.port', '-3')
	assert env.get_property_int('server.port')! == -3

	// 写错的值必须是错误，不是 0
	env.set_property('server.port', '八十')
	if _ := env.get_property_int('server.port') {
		assert false, 'non-numeric value must not parse as 0'
	} else {
		assert err.msg().contains('server.port')
	}
	env.set_property('server.port', '')
	if _ := env.get_property_int('server.port') {
		assert false, 'empty value must not parse as 0'
	} else {
		assert err.msg().contains('empty')
	}

	// _or 版退回默认值，而不是静默 0
	assert env.get_property_int_or('server.port', 3000) == 3000
}

fn test_f64_property_rejects_garbage() {
	mut env := new_environment()
	env.set_property('app.rate', '2.71')
	assert env.get_property_f64('app.rate')! == 2.71
	env.set_property('app.rate', '0.0')
	assert env.get_property_f64('app.rate')! == 0.0
	env.set_property('app.rate', '0')
	assert env.get_property_f64('app.rate')! == 0.0

	env.set_property('app.rate', 'fast')
	if _ := env.get_property_f64('app.rate') {
		assert false, 'non-numeric value must not parse as 0.0'
	} else {
		assert err.msg().contains('app.rate')
	}
	assert env.get_property_f64_or('app.rate', 1.5) == 1.5
}

fn test_bool_property_accepts_common_literals() {
	mut env := new_environment()
	// V 的 'true'/'t' 之外的字面量以前全部读成 false
	for truthy in ['true', 'TRUE', 'True', 't', '1', 'yes', 'on'] {
		env.set_property('app.debug', truthy)
		assert env.get_property_bool('app.debug')!, 'failed for "${truthy}"'
	}
	for falsy in ['false', 'FALSE', 'f', '0', 'no', 'off'] {
		env.set_property('app.debug', falsy)
		assert !env.get_property_bool('app.debug')!, 'failed for "${falsy}"'
	}

	env.set_property('app.debug', 'maybe')
	if _ := env.get_property_bool('app.debug') {
		assert false, '"maybe" must not be silently false'
	} else {
		assert err.msg().contains('app.debug')
	}
	assert env.get_property_bool_or('app.debug', true)
}

fn test_bind_to_struct_parses_values() {
	mut env := new_environment()
	env.set_property('app.port', '8080')
	env.set_property('app.debug', 'yes') // 以前读成 false
	env.set_property('app.rate', '2.5')
	env.set_property('app.replicas', 'r1, r2')

	cfg := bind_to_struct[BindingSample](env, 'app')!
	assert cfg.port == 8080
	assert cfg.debug
	assert cfg.rate == 2.5
	assert cfg.replicas == ['r1', 'r2']
}

struct BindingSample {
	port     int
	debug    bool
	rate     f64
	replicas []string
}

fn test_nested_placeholder_resolution() {
	mut env := new_environment()
	env.set_property('env', 'dev')
	env.set_property('app.dev.host', 'dev.local')
	env.set_property('app.prod.host', 'prod.local')

	// 以前 index_after('}') 命中的是内层的 '}'，key 被截成 'app.${env'
	// 用 raw string 避免 V 把 ${...} 当插值
	assert env.resolve_placeholders(r'${app.${env}.host}') == 'dev.local'
	env.set_property('env', 'prod')
	assert env.resolve_placeholders(r'${app.${env}.host}') == 'prod.local'
}

fn test_placeholder_replacement_is_not_rescanned() {
	mut env := new_environment()
	env.set_property('a', r'${b}')
	env.set_property('b', 'X')
	env.set_property('prompt', 'ask')
	// 替换进去的值不参与后续匹配：${prompt} -> '{"a":"1"}'，其中的 {a} 不该被再解析
	env.set_property('json', '{"a":"1"}')
	assert env.resolve_placeholders(r'${json}') == '{"a":"1"}'
	assert env.resolve_placeholders(r'${a}') == 'X'
}

fn test_required_properties_use_priority_chain() {
	mut env := new_environment()
	env.set_property('app.name', 'Photon')
	// 来自 CLI 覆盖的必填项以前一律被报成缺失
	env.set_cli_arg('app.port', '9090')
	env.validate_required_properties(['app.name', 'app.port'])!

	if _ := env.validate_required_properties(['app.name', 'app.missing']) {
		assert false, 'missing key must fail'
	} else {
		assert err.msg().contains('app.missing')
	}
}

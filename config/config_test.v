module config

// config_test.v - Unit tests for Photon Config Module
// Tests: Config get/set, MapConfigSource, typed accessors, profiles, load

// ============================================================
// Config Basic Tests
// ============================================================

fn test_new_config() {
	mut cfg := new()
	assert cfg.loaded == false
	assert cfg.keys().len == 0
	assert cfg.profiles.len == 0
}

fn test_config_set_and_get() {
	mut cfg := new()
	cfg.set('app.name', 'PhotonTest')
	assert cfg.get('app.name') == 'PhotonTest'
}

fn test_config_get_missing() {
	mut cfg := new()
	assert cfg.get('missing.key') == ''
}

fn test_config_get_or() {
	mut cfg := new()
	assert cfg.get_or('missing.key', 'default') == 'default'
	cfg.set('existing.key', 'real')
	assert cfg.get_or('existing.key', 'default') == 'real'
}

fn test_config_has() {
	mut cfg := new()
	assert cfg.has('any.key') == false
	cfg.set('app.name', 'Test')
	assert cfg.has('app.name') == true
}

fn test_config_keys() {
	mut cfg := new()
	cfg.set('k1', 'v1')
	cfg.set('k2', 'v2')
	cfg.set('k3', 'v3')
	keys := cfg.keys()
	assert keys.len == 3
}

// ============================================================
// Config Typed Accessors
// ============================================================

fn test_config_get_int() {
	mut cfg := new()
	cfg.set('port', '8080')
	val := cfg.get_int('port')!
	assert val == 8080
}

fn test_config_get_int_missing() {
	mut cfg := new()
	if _ := cfg.get_int('missing') {
		assert false, 'expected error for missing key'
	} else {
		assert true
	}
}

fn test_config_get_int_or() {
	mut cfg := new()
	assert cfg.get_int_or('missing', 3000) == 3000
	cfg.set('port', '8080')
	assert cfg.get_int_or('port', 3000) == 8080
}

fn test_config_get_bool() {
	mut cfg := new()
	cfg.set('enabled', 'true')
	cfg.set('disabled', 'false')
	assert cfg.get_bool('enabled')! == true
	assert cfg.get_bool('disabled')! == false
}

fn test_config_get_bool_or() {
	mut cfg := new()
	assert cfg.get_bool_or('missing', true) == true
	cfg.set('flag', 'true')
	assert cfg.get_bool_or('flag', false) == true
}

fn test_config_get_f64() {
	mut cfg := new()
	cfg.set('ratio', '3.14')
	val := cfg.get_f64('ratio')!
	assert val > 3.13 && val < 3.15
}

// ============================================================
// Config Profiles
// ============================================================

fn test_config_profiles() {
	mut cfg := new()
	cfg.set_profile(['dev', 'test'])
	assert cfg.profiles.len == 2
	assert 'dev' in cfg.profiles
	assert 'test' in cfg.profiles
}

fn test_config_add_profile() {
	mut cfg := new()
	cfg.add_profile('dev')
	cfg.add_profile('cloud')
	assert cfg.profiles.len == 2
}

// ============================================================
// MapConfigSource Tests
// ============================================================

fn test_map_config_source_name() {
	source := MapConfigSource{
		data: {
			'key': 'value'
		}
	}
	assert source.name() == 'map'
}

fn test_map_config_source_load() {
	mut source := MapConfigSource{
		data: {
			'app.name':    'TestApp'
			'server.port': '8080'
			'db.host':     'localhost'
		}
	}
	props := source.load()!
	assert props['app.name'] == 'TestApp'
	assert props['server.port'] == '8080'
	assert props['db.host'] == 'localhost'
	assert props.len == 3
}

fn test_map_config_source_load_empty() {
	mut source := MapConfigSource{
		data: map[string]string{}
	}
	props := source.load()!
	assert props.len == 0
}

// ============================================================
// Config Load from Sources
// ============================================================

fn test_config_load_from_map_source() {
	mut cfg := new()
	source := MapConfigSource{
		data: {
			'app.name': 'LoadedApp'
			'debug':    'true'
		}
	}
	cfg.add_source(source)
	cfg.load()!
	assert cfg.loaded == true
	assert cfg.get('app.name') == 'LoadedApp'
	assert cfg.get('debug') == 'true'
}

fn test_config_load_multiple_sources() {
	mut cfg := new()
	source1 := MapConfigSource{
		data: {
			'app.name': 'App1'
			'common':   'from1'
		}
	}
	source2 := MapConfigSource{
		data: {
			'server.port': '9090'
			'common':      'from2' // Overrides source1
		}
	}
	cfg.add_source(source1)
	cfg.add_source(source2)
	cfg.load()!
	assert cfg.get('app.name') == 'App1'
	assert cfg.get('server.port') == '9090'
	assert cfg.get('common') == 'from2' // Last source wins
}

// ============================================================
// Config to_json
// ============================================================

fn test_config_to_json() {
	mut cfg := new()
	cfg.set('key1', 'val1')
	cfg.set('key2', 'val2')
	json_str := cfg.to_json()
	assert json_str.len > 0
	assert json_str.contains('key1')
	assert json_str.contains('val1')
}

// ============================================================
// Property Binder Tests
// ============================================================

fn test_property_binder_resolve_value() {
	mut cfg := new()
	cfg.set('db.host', 'localhost')
	binder := new_property_binder(cfg)
	assert binder.resolve_value('db.host') == 'localhost'
}

fn test_property_binder_resolve_with_default() {
	mut cfg := new()
	binder := new_property_binder(cfg)
	// key:default format
	assert binder.resolve_value('missing.key:fallback') == 'fallback'
}

fn test_find_value_attr() {
	attrs := ['value:server.port', 'component']
	result := find_value_attr(attrs)
	assert result == 'server.port'
}

fn test_find_value_attr_none() {
	attrs := ['component', 'service']
	result := find_value_attr(attrs)
	assert result == ''
}

fn test_bind_field_value() {
	attrs := ['value:db.host']
	result := bind_field_value(attrs, '')
	// bind_field_value expects key:default format; 'db.host' has no :default
	assert result == ''
}

fn test_bind_field_value_with_default() {
	attrs := ['value:missing.key:localhost']
	result := bind_field_value(attrs, '')
	// bind_field_value splits by ':' and returns parts[1] as default
	assert result == 'localhost'
}

// ============================================================
// Environment & Placeholder Resolution Tests
// ============================================================

fn test_environment_new() {
	mut env := new_environment()
	assert env.active_profiles.len == 0
	assert env.property_sources.len == 0
}

fn test_environment_add_source_and_get_property() {
	mut env := new_environment()
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'app.name':    'PhotonApp'
			'server.port': '8080'
		}
	}
	env.add_source(source)
	assert env.get_property('app.name')? == 'PhotonApp'
	assert env.get_property('server.port')? == '8080'
}

fn test_environment_get_property_or() {
	mut env := new_environment()
	assert env.get_property_or('missing.key', 'default') == 'default'
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'key': 'value'
		}
	}
	env.add_source(source)
	assert env.get_property_or('key', 'default') == 'value'
}

fn test_environment_contains_property() {
	mut env := new_environment()
	assert env.contains_property('any.key') == false
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'key': 'value'
		}
	}
	env.add_source(source)
	assert env.contains_property('key') == true
	assert env.contains_property('missing') == false
}

fn test_environment_has_property() {
	mut env := new_environment()
	assert env.has_property('any.key') == false
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'key': 'value'
		}
	}
	env.add_source(source)
	assert env.has_property('key') == true
}

fn test_resolve_placeholders_simple() {
	mut env := new_environment()
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'app.name': 'Photon'
		}
	}
	env.add_source(source)
	result := env.resolve_placeholders('Hello \${app.name}')
	assert result == 'Hello Photon'
}

fn test_resolve_placeholders_with_default() {
	mut env := new_environment()
	// ${key:default} — key not found, use default
	result := env.resolve_placeholders('jdbc://\${db.host:localhost}:\${db.port:5432}/mydb')
	assert result == 'jdbc://localhost:5432/mydb'
}

fn test_resolve_placeholders_with_default_override() {
	mut env := new_environment()
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'db.host': 'prod-db.example.com'
			'db.port': '3306'
		}
	}
	env.add_source(source)
	// ${key:default} — key found, use actual value (ignore default)
	result := env.resolve_placeholders('jdbc://\${db.host:localhost}:\${db.port:5432}/mydb')
	assert result == 'jdbc://prod-db.example.com:3306/mydb'
}

fn test_resolve_placeholders_no_placeholders() {
	mut env := new_environment()
	result := env.resolve_placeholders('plain text without placeholders')
	assert result == 'plain text without placeholders'
}

fn test_resolve_placeholders_missing_key_no_default() {
	mut env := new_environment()
	// ${key} — key not found, no default → empty string
	result := env.resolve_placeholders('Hello \${missing.key}')
	assert result == 'Hello '
}

fn test_resolve_placeholders_multiple() {
	mut env := new_environment()
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'first':  'John'
			'last':   'Doe'
		}
	}
	env.add_source(source)
	result := env.resolve_placeholders('\${first} \${last}')
	assert result == 'John Doe'
}

fn test_resolve_placeholders_nested() {
	mut env := new_environment()
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'env':        'dev'
			'app.dev.host': 'dev.example.com'
		}
	}
	env.add_source(source)
	// ${app.${env}.host} — inner ${env} resolved first → ${app.dev.host}
	result := env.resolve_placeholders('\${app.\${env}.host}')
	assert result == 'dev.example.com'
}

fn test_resolve_placeholders_nested_with_default() {
	mut env := new_environment()
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'env': 'prod'
		}
	}
	env.add_source(source)
	// ${app.${env}.host:fallback.example.com} — inner resolved, outer uses default
	result := env.resolve_placeholders('\${app.\${env}.host:fallback.example.com}')
	assert result == 'fallback.example.com'
}

fn test_environment_profiles() {
	mut env := new_environment()
	env.add_profile('dev')
	assert env.accepts_profile('dev') == true
	assert env.accepts_profile('prod') == false
	env.set_profiles(['prod', 'cloud'])
	assert env.accepts_profile('prod') == true
	assert env.accepts_profile('cloud') == true
	assert env.accepts_profile('dev') == false
}

fn test_environment_get_by_prefix() {
	mut env := new_environment()
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'app.db.host': 'localhost'
			'app.db.port': '5432'
			'app.name':    'TestApp'
		}
	}
	env.add_source(source)
	result := env.get_by_prefix('app.db.')
	assert result['app.db.host'] == 'localhost'
	assert result['app.db.port'] == '5432'
	assert 'app.name' !in result
}

fn test_environment_get_subtree() {
	mut env := new_environment()
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'app.db.host': 'localhost'
			'app.db.port': '5432'
		}
	}
	env.add_source(source)
	result := env.get_subtree('app.db.')
	assert result['host'] == 'localhost'
	assert result['port'] == '5432'
}

// ============================================================
// MapPropertySource Tests
// ============================================================

fn test_map_property_source() {
	source := new_map_property_source('test', {
		'key1': 'value1'
		'key2': 'value2'
	})
	assert source.name() == 'test'
	assert source.get_property('key1')? == 'value1'
	assert source.get_property('key2')? == 'value2'
	assert source.contains_property('key1') == true
	assert source.contains_property('missing') == false
}

fn test_map_property_source_get_all_with_prefix() {
	source := MapPropertySource{
		source_name: 'test'
		data: {
			'app.db.host': 'localhost'
			'app.db.port': '5432'
			'app.name':    'TestApp'
		}
	}
	result := source.get_all_with_prefix('app.db.')
	assert result['app.db.host'] == 'localhost'
	assert result['app.db.port'] == '5432'
	assert result.len == 2
}

// ============================================================
// ConfigPropertySourceAdapter Tests
// ============================================================

fn test_config_property_source_adapter() {
	mut cfg := new()
	cfg.set('key1', 'value1')
	cfg.set('key2', 'value2')
	adapter := new_config_property_source(cfg)
	assert adapter.name() == 'config_adapter'
	assert adapter.get_property('key1')? == 'value1'
	assert adapter.contains_property('key1') == true
	assert adapter.contains_property('missing') == false
}

// ============================================================
// PropertyBinder resolve_value_with_placeholders Tests
// ============================================================

fn test_property_binder_resolve_value_with_placeholders() {
	mut cfg := new()
	cfg.set('db.host', 'localhost')
	cfg.set('db.port', '5432')
	mut env := new_environment()
	source := new_map_property_source('test', {
		'db.host': 'localhost'
		'db.port': '5432'
	})
	env.add_source(source)
	mut binder := new_property_binder_with_env(cfg, env)
	result := binder.resolve_value_with_placeholders('jdbc://\${db.host:localhost}:\${db.port:5432}/mydb')
	assert result == 'jdbc://localhost:5432/mydb'
}

// ============================================================
// extract_value_expr_full Tests
// ============================================================

fn test_extract_value_expr_full() {
	// @[value: 'app.name'] → attr = "value: 'app.name'"
	attrs := ["value: 'app.name'"]
	result := extract_value_expr_full(attrs)
	assert result == 'app.name'
}

fn test_extract_value_expr_full_with_default() {
	attrs := ["value: 'db.host:localhost'"]
	result := extract_value_expr_full(attrs)
	assert result == 'db.host:localhost'
}

fn test_extract_value_key() {
	attrs := ["value: 'db.host:localhost'"]
	key := extract_value_key(attrs)
	assert key == 'db.host'
}

fn test_extract_value_default() {
	attrs := ["value: 'db.host:localhost'"]
	default_val := extract_value_default(attrs)
	assert default_val == 'localhost'
}

fn test_extract_value_no_default() {
	attrs := ["value: 'app.name'"]
	default_val := extract_value_default(attrs)
	assert default_val == ''
}

fn test_extract_value_expr_full_none() {
	attrs := ['component', 'service']
	result := extract_value_expr_full(attrs)
	assert result == ''
}

// ============================================================
// extract_config_field_key Tests
// ============================================================

fn test_extract_config_field_key() {
	attrs := ["config_field: 'hostname'"]
	result := extract_config_field_key(attrs)
	assert result == 'hostname'
}

fn test_extract_config_field_key_none() {
	attrs := ['component', 'service']
	result := extract_config_field_key(attrs)
	assert result == ''
}

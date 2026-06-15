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
	source := MapConfigSource{
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
	source := MapConfigSource{
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

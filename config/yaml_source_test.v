module config

import os

// ── YAML Parser Tests ──

fn test_parse_yaml_simple_key_value() ! {
	content := 'name: Photon\nversion: 0.1.0'
	result := parse_yaml(content)!
	assert result['name'] == 'Photon'
	assert result['version'] == '0.1.0'
}

fn test_parse_yaml_nested_keys() ! {
	content := 'database:\n  host: localhost\n  port: 5432'
	result := parse_yaml(content)!
	assert result['database.host'] == 'localhost'
	assert result['database.port'] == '5432'
}

fn test_parse_yaml_comments() ! {
	content := '# This is a comment\nkey: value  # inline comment\n# another comment'
	result := parse_yaml(content)!
	assert result['key'] == 'value'
}

fn test_parse_yaml_boolean_values() ! {
	content := 'debug: true\nverbose: false'
	result := parse_yaml(content)!
	assert result['debug'] == 'true'
	assert result['verbose'] == 'false'
}

fn test_parse_yaml_null_values() ! {
	content := 'empty: null\nalso_empty: ~'
	result := parse_yaml(content)!
	assert result['empty'] == ''
	assert result['also_empty'] == ''
}

fn test_parse_yaml_quoted_strings() ! {
	content := 'name: "John Doe"\ncity: \'New York\''
	result := parse_yaml(content)!
	assert result['name'] == 'John Doe'
	assert result['city'] == 'New York'
}

fn test_parse_yaml_list_items() ! {
	content := 'servers:\n  - web1\n  - web2\n  - web3'
	result := parse_yaml(content)!
	assert result['servers[0]'] == 'web1'
	assert result['servers[1]'] == 'web2'
	assert result['servers[2]'] == 'web3'
}

fn test_parse_yaml_list_with_dict() ! {
	content := 'users:\n  - name: Alice\n  - name: Bob'
	result := parse_yaml(content)!
	assert result['users[0].name'] == 'Alice'
	assert result['users[1].name'] == 'Bob'
}

fn test_parse_yaml_document_markers() ! {
	content := '---\nkey: value\n...'
	result := parse_yaml(content)!
	assert result['key'] == 'value'
}

fn test_parse_yaml_empty_string() ! {
	result := parse_yaml('')!
	assert result.len == 0
}

fn test_parse_yaml_deep_nesting() ! {
	content := 'level1:\n  level2:\n    level3:\n      key: deep_value'
	result := parse_yaml(content)!
	assert result['level1.level2.level3.key'] == 'deep_value'
}

// ── TOML Parser Tests ──

fn test_parse_toml_simple_key_value() ! {
	content := 'name = "Photon"\nversion = "0.1.0"'
	result := parse_toml(content)!
	assert result['name'] == 'Photon'
	assert result['version'] == '0.1.0'
}

fn test_parse_toml_sections() ! {
	content := '[database]\nhost = "localhost"\nport = 5432\n[server]\nport = 8080'
	result := parse_toml(content)!
	assert result['database.host'] == 'localhost'
	assert result['database.port'] == '5432'
	assert result['server.port'] == '8080'
}

fn test_parse_toml_comments() ! {
	content := '# Config file\nkey = "value"  # inline comment'
	result := parse_toml(content)!
	assert result['key'] == 'value'
}

fn test_parse_toml_booleans() ! {
	content := 'debug = true\nverbose = false'
	result := parse_toml(content)!
	assert result['debug'] == 'true'
	assert result['verbose'] == 'false'
}

fn test_parse_toml_numbers() ! {
	content := 'port = 8080\nratio = 3.14'
	result := parse_toml(content)!
	assert result['port'] == '8080'
	assert result['ratio'] == '3.14'
}

fn test_parse_toml_empty_string() ! {
	result := parse_toml('')!
	assert result.len == 0
}

fn test_parse_toml_array_of_tables() ! {
	content := '[[servers]]\nname = "web1"\n[[servers]]\nname = "web2"'
	result := parse_toml(content)!
	// Array of tables: servers[0].name, servers[1].name
	assert result['servers[0].name'] == 'web1'
	assert result['servers[1].name'] == 'web2'
}

fn test_parse_toml_quoted_strings() ! {
	content := 'name = "John Doe"'
	result := parse_toml(content)!
	assert result['name'] == 'John Doe'
}

fn test_parse_toml_dotted_section() ! {
	content := '[database.connection]\nhost = "localhost"'
	result := parse_toml(content)!
	assert result['database.connection.host'] == 'localhost'
}

// ── YamlConfigSource Tests ──

fn test_yaml_source_name() {
	source := new_yaml_source('/config/app.yaml')
	assert source.name() == 'yaml:/config/app.yaml'
}

fn test_toml_source_name() {
	source := new_toml_source('/config/app.toml')
	assert source.name() == 'toml:/config/app.toml'
}

// ── YamlConfigSource File Load Test ──

fn test_yaml_source_load_from_file() ! {
	// Create a temporary YAML file
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_${os.getpid()}.yaml')
	os.write_file(tmp_file,
		'app:\n  name: TestApp\n  debug: true\ndatabase:\n  host: localhost\n  port: 5432')!
	defer {
		os.rm(tmp_file) or {}
	}

	mut source := new_yaml_source(tmp_file)
	result := source.load()!
	assert result['app.name'] == 'TestApp'
	assert result['app.debug'] == 'true'
	assert result['database.host'] == 'localhost'
	assert result['database.port'] == '5432'
}

fn test_toml_source_load_from_file() ! {
	// Create a temporary TOML file
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_${os.getpid()}.toml')
	os.write_file(tmp_file,
		'[app]\nname = "TestApp"\ndebug = true\n\n[database]\nhost = "localhost"\nport = 5432')!
	defer {
		os.rm(tmp_file) or {}
	}

	mut source := new_toml_source(tmp_file)
	result := source.load()!
	assert result['app.name'] == 'TestApp'
	assert result['app.debug'] == 'true'
	assert result['database.host'] == 'localhost'
	assert result['database.port'] == '5432'
}

// ── Profile-Specific Config Tests ──

fn test_new_profile_yaml_source() {
	source := new_profile_yaml_source('config/application.yml', 'dev')
	assert source.filepath == 'config/application-dev.yml'
	assert source.profile == 'dev'
}

fn test_new_profile_yaml_source_yaml_ext() {
	source := new_profile_yaml_source('config/application.yaml', 'prod')
	assert source.filepath == 'config/application-prod.yaml'
	assert source.profile == 'prod'
}

fn test_new_profile_toml_source() {
	source := new_profile_toml_source('config/application.toml', 'dev')
	assert source.filepath == 'config/application-dev.toml'
	assert source.profile == 'dev'
}

fn test_yaml_source_with_profile_name() {
	source := new_yaml_source_with_profile('/config/application-dev.yml', 'dev')
	assert source.name() == 'yaml:/config/application-dev.yml (profile:dev)'
}

fn test_toml_source_with_profile_name() {
	source := new_toml_source_with_profile('/config/application-prod.toml', 'prod')
	assert source.name() == 'toml:/config/application-prod.toml (profile:prod)'
}

fn test_load_yaml_with_profiles() ! {
	tmp_dir := os.temp_dir()
	base_file := os.join_path(tmp_dir, 'photon_test_base_${os.getpid()}.yml')
	dev_file := os.join_path(tmp_dir, 'photon_test_base_${os.getpid()}-dev.yml')

	os.write_file(base_file, 'app:\n  name: MyApp\n  env: default')!
	os.write_file(dev_file, 'app:\n  env: development\n  debug: true')!
	defer {
		os.rm(base_file) or {}
		os.rm(dev_file) or {}
	}

	result := load_yaml_with_profiles(base_file, ['dev'])!
	assert result['app.name'] == 'MyApp'
	assert result['app.env'] == 'development' // overridden by dev profile
	assert result['app.debug'] == 'true' // added by dev profile
}

fn test_load_toml_with_profiles() ! {
	tmp_dir := os.temp_dir()
	base_file := os.join_path(tmp_dir, 'photon_test_base_${os.getpid()}.toml')
	prod_file := os.join_path(tmp_dir, 'photon_test_base_${os.getpid()}-prod.toml')

	os.write_file(base_file, '[app]\nname = "MyApp"\nenv = "default"')!
	os.write_file(prod_file, '[app]\nenv = "production"\ndebug = false')!
	defer {
		os.rm(base_file) or {}
		os.rm(prod_file) or {}
	}

	result := load_toml_with_profiles(base_file, ['prod'])!
	assert result['app.name'] == 'MyApp'
	assert result['app.env'] == 'production' // overridden by prod profile
	assert result['app.debug'] == 'false' // added by prod profile
}

// ── YamlConfigSource PropertySource Interface Tests ──

fn test_yaml_source_get_property() ! {
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_prop_${os.getpid()}.yaml')
	os.write_file(tmp_file, 'database:\n  host: localhost\n  port: 5432')!
	defer {
		os.rm(tmp_file) or {}
	}

	mut source := new_yaml_source(tmp_file)
	assert source.get_property('database.host')? == 'localhost'
	assert source.get_property('database.port')? == '5432'
}

fn test_yaml_source_contains_property() ! {
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_contains_${os.getpid()}.yaml')
	os.write_file(tmp_file, 'database:\n  host: localhost')!
	defer {
		os.rm(tmp_file) or {}
	}

	mut source := new_yaml_source(tmp_file)
	assert source.contains_property('database.host') == true
	assert source.contains_property('database.missing') == false
}

fn test_yaml_source_get_all_with_prefix() ! {
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_prefix_${os.getpid()}.yaml')
	os.write_file(tmp_file, 'database:\n  host: localhost\n  port: 5432\napp:\n  name: MyApp')!
	defer {
		os.rm(tmp_file) or {}
	}

	mut source := new_yaml_source(tmp_file)
	result := source.get_all_with_prefix('database.')
	assert result['database.host'] == 'localhost'
	assert result['database.port'] == '5432'
	assert result.len == 2
}

// ── TomlConfigSource PropertySource Interface Tests ──

fn test_toml_source_get_property() ! {
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_prop_${os.getpid()}.toml')
	os.write_file(tmp_file, '[database]\nhost = "localhost"\nport = 5432')!
	defer {
		os.rm(tmp_file) or {}
	}

	mut source := new_toml_source(tmp_file)
	assert source.get_property('database.host')? == 'localhost'
	assert source.get_property('database.port')? == '5432'
}

fn test_toml_source_contains_property() ! {
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_contains_${os.getpid()}.toml')
	os.write_file(tmp_file, '[database]\nhost = "localhost"')!
	defer {
		os.rm(tmp_file) or {}
	}

	mut source := new_toml_source(tmp_file)
	assert source.contains_property('database.host') == true
	assert source.contains_property('database.missing') == false
}

fn test_toml_source_get_all_with_prefix() ! {
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_prefix_${os.getpid()}.toml')
	os.write_file(tmp_file, '[database]\nhost = "localhost"\nport = 5432\n[app]\nname = "MyApp"')!
	defer {
		os.rm(tmp_file) or {}
	}

	mut source := new_toml_source(tmp_file)
	result := source.get_all_with_prefix('database.')
	assert result['database.host'] == 'localhost'
	assert result['database.port'] == '5432'
	assert result.len == 2
}

// ── YAML Nested Key Flattening Tests ──

fn test_parse_yaml_colon_notation() ! {
	content := 'app:\n  database:\n    host: localhost\n    port: 5432'
	result := parse_yaml(content)!
	// Should have both dot-notation and colon-notation keys
	assert result['app.database.host'] == 'localhost'
	assert result['app.database.port'] == '5432'
	// Colon-notation keys should also be present
	assert result['app:database:host'] == 'localhost'
	assert result['app:database:port'] == '5432'
}

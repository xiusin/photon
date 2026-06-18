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
	os.write_file(tmp_file, 'app:\n  name: TestApp\n  debug: true\ndatabase:\n  host: localhost\n  port: 5432')!
	defer {
		os.rm(tmp_file) or {}
	}

	source := new_yaml_source(tmp_file)
	result := source.load()!
	assert result['app.name'] == 'TestApp'
	assert result['app.debug'] == 'true'
	assert result['database.host'] == 'localhost'
	assert result['database.port'] == '5432'
}

fn test_toml_source_load_from_file() ! {
	// Create a temporary TOML file
	tmp_file := os.join_path(os.temp_dir(), 'photon_test_${os.getpid()}.toml')
	os.write_file(tmp_file, '[app]\nname = "TestApp"\ndebug = true\n\n[database]\nhost = "localhost"\nport = 5432')!
	defer {
		os.rm(tmp_file) or {}
	}

	source := new_toml_source(tmp_file)
	result := source.load()!
	assert result['app.name'] == 'TestApp'
	assert result['app.debug'] == 'true'
	assert result['database.host'] == 'localhost'
	assert result['database.port'] == '5432'
}

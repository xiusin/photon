module web

// resource_handler_test.v - Tests for ResourceHandlerRegistry
import os

// setup_tmp_dir creates a clean temp directory for a test and returns its path.
fn setup_tmp_dir(name string) string {
	dir := os.join_path('/tmp', 'photon_web_test_' + name)
	os.rmdir_all(dir) or {}
	os.mkdir(dir) or {}
	return dir
}

fn test_resource_handler_registry_new() {
	r := new_resource_handler_registry()
	assert r.mappings.len == 0
}

fn test_resource_handler_add_mapping() {
	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', './static/')
	assert r.mappings.len == 1
	assert r.mappings[0].pattern == '/static/**'
	assert r.mappings[0].locations[0] == './static/'
}

fn test_resource_handler_add_multiple_locations() {
	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', './static/', './public/')
	assert r.mappings[0].locations.len == 2
}

fn test_pattern_matches_exact() {
	assert pattern_matches('/favicon.ico', '/favicon.ico') == true
	assert pattern_matches('/favicon.ico', '/other.ico') == false
}

fn test_pattern_matches_wildcard() {
	assert pattern_matches('/static/**', '/static/app.css') == true
	assert pattern_matches('/static/**', '/static/sub/app.css') == true
	assert pattern_matches('/static/**', '/other/app.css') == false
}

fn test_extract_relative_path() {
	assert extract_relative_path('/static/**', '/static/app.css') == 'app.css'
	assert extract_relative_path('/static/**', '/static/sub/app.css') == 'sub/app.css'
}

fn test_resource_handler_resolve_existing_file() {
	tmp_dir := setup_tmp_dir('resolve_existing')
	defer {
		os.rmdir_all(tmp_dir) or {}
	}

	test_file := os.join_path(tmp_dir, 'app.css')
	os.write_file(test_file, 'body { color: red; }') or {}

	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', tmp_dir)

	mut found := false
	if _ := r.resolve('/static/app.css') {
		found = true
	}
	assert found
}

fn test_resource_handler_resolve_nonexistent() {
	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', '/nonexistent/dir/')

	mut found := false
	if _ := r.resolve('/static/app.css') {
		found = true
	}
	assert found == false
}

fn test_resource_handler_serve_content() {
	tmp_dir := setup_tmp_dir('serve_content')
	defer {
		os.rmdir_all(tmp_dir) or {}
	}

	test_file := os.join_path(tmp_dir, 'app.css')
	expected_content := 'body { color: red; }'
	os.write_file(test_file, expected_content) or {}

	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', tmp_dir)

	content := r.serve('/static/app.css')!
	assert content == expected_content
}

fn test_resource_handler_serve_not_found() {
	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', '/nonexistent/dir/')

	mut failed := false
	r.serve('/static/app.css') or { failed = true }
	assert failed
}

fn test_resource_handler_multiple_mappings() {
	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', './static/')
	r.add_mapping('/assets/**', './assets/')
	assert r.mappings.len == 2
}

fn test_resource_handler_fallback_locations() {
	// First location doesn't have file, second does
	tmp_dir1 := setup_tmp_dir('fallback1')
	tmp_dir2 := setup_tmp_dir('fallback2')
	defer {
		os.rmdir_all(tmp_dir1) or {}
		os.rmdir_all(tmp_dir2) or {}
	}

	test_file := os.join_path(tmp_dir2, 'app.css')
	os.write_file(test_file, 'content') or {}

	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', tmp_dir1, tmp_dir2)

	mut found := false
	if _ := r.resolve('/static/app.css') {
		found = true
	}
	assert found
}

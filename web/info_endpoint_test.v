module web

// info_endpoint_test.v - Tests for the /info actuator endpoint (SubTask D7.3)
//
// Verifies that the /info endpoint:
//   - Returns 200 OK with JSON body containing build metadata
//   - Sets Content-Type: application/json
//   - Includes a "build" object with version, commit, build_time, v_version
//   - Reflects the BuildInfo values passed to serve_info()
//   - Returns defaults when BuildInfo is zero-valued
//   - load_build_info() reads key=value files correctly
//   - load_build_info() returns defaults for missing files
//   - The mock handler dispatches /info correctly
import core
import os

// ── serve_info unit tests ──

fn test_serve_info_default_returns_200() {
	info := core.default_build_info()
	body, ct, code := serve_info(info)
	assert code == 200
	assert ct == info_content_type
	assert body.len > 0
}

fn test_serve_info_default_body_contains_version() {
	info := core.default_build_info()
	body, _, _ := serve_info(info)
	assert body.contains('"version"')
}

fn test_serve_info_default_body_contains_commit() {
	info := core.default_build_info()
	body, _, _ := serve_info(info)
	assert body.contains('"commit"')
}

fn test_serve_info_default_body_contains_build_time() {
	info := core.default_build_info()
	body, _, _ := serve_info(info)
	assert body.contains('"build_time"')
}

fn test_serve_info_default_body_contains_v_version() {
	info := core.default_build_info()
	body, _, _ := serve_info(info)
	assert body.contains('"v_version"')
}

fn test_serve_info_default_body_contains_commit_time() {
	info := core.default_build_info()
	body, _, _ := serve_info(info)
	assert body.contains('"commit_time"')
}

fn test_serve_info_custom_values_reflected_in_body() {
	info := core.BuildInfo{
		version:    '1.2.3'
		commit:     'deadbeef'
		commit_time: '2026-06-20T10:00:00Z'
		build_time: '2026-06-20T10:30:00Z'
		v_version:  '0.5.1'
	}
	body, _, _ := serve_info(info)
	assert body.contains('"version":"1.2.3"')
	assert body.contains('"commit":"deadbeef"')
	assert body.contains('"commit_time":"2026-06-20T10:00:00Z"')
	assert body.contains('"build_time":"2026-06-20T10:30:00Z"')
	assert body.contains('"v_version":"0.5.1"')
}

fn test_serve_info_content_type_is_json() {
	info := core.default_build_info()
	_, ct, _ := serve_info(info)
	assert ct == info_content_type
}

fn test_serve_info_json_structure_has_build_object() {
	info := core.default_build_info()
	body, _, _ := serve_info(info)
	// Body must start with {"build":{
	assert body.starts_with('{"build":{')
	assert body.ends_with('}}')
}

fn test_serve_info_default_version_value() {
	info := core.default_build_info()
	body, _, _ := serve_info(info)
	assert body.contains('"version":"0.0.0"')
}

fn test_serve_info_default_commit_value() {
	info := core.default_build_info()
	body, _, _ := serve_info(info)
	assert body.contains('"commit":"unknown"')
}

// ── MockMvc endpoint tests ──

fn test_info_endpoint_returns_200() {
	info := core.BuildInfo{version: '0.1.0'}

	mut mvc := new_mockmvc()
	mvc.get('/info', info_mock_handler(info))

	result := mvc.perform(mock_request('GET', '/info'))!
	result.assert_status(200)!
}

fn test_info_endpoint_content_type_is_json() {
	info := core.default_build_info()

	mut mvc := new_mockmvc()
	mvc.get('/info', info_mock_handler(info))

	result := mvc.perform(mock_request('GET', '/info'))!
	result.assert_header('Content-Type', info_content_type)!
}

fn test_info_endpoint_body_contains_version() {
	info := core.BuildInfo{version: '0.4.0'}

	mut mvc := new_mockmvc()
	mvc.get('/info', info_mock_handler(info))

	result := mvc.perform(mock_request('GET', '/info'))!
	result.assert_body_contains('"version":"0.4.0"')!
}

fn test_info_endpoint_body_contains_commit() {
	info := core.BuildInfo{commit: 'abc123def'}

	mut mvc := new_mockmvc()
	mvc.get('/info', info_mock_handler(info))

	result := mvc.perform(mock_request('GET', '/info'))!
	result.assert_body_contains('"commit":"abc123def"')!
}

fn test_info_endpoint_body_contains_build_time() {
	info := core.BuildInfo{build_time: '2026-06-20T10:30:00Z'}

	mut mvc := new_mockmvc()
	mvc.get('/info', info_mock_handler(info))

	result := mvc.perform(mock_request('GET', '/info'))!
	result.assert_body_contains('"build_time":"2026-06-20T10:30:00Z"')!
}

fn test_info_endpoint_body_contains_build_object() {
	info := core.default_build_info()

	mut mvc := new_mockmvc()
	mvc.get('/info', info_mock_handler(info))

	result := mvc.perform(mock_request('GET', '/info'))!
	result.assert_body_contains('"build":{')!
}

fn test_info_endpoint_full_body_structure() {
	info := core.BuildInfo{
		version:    '0.1.0'
		commit:     'abc123'
		commit_time: '2026-06-20T10:00:00Z'
		build_time: '2026-06-20T10:30:00Z'
		v_version:  '0.5.1'
	}

	mut mvc := new_mockmvc()
	mvc.get('/info', info_mock_handler(info))

	result := mvc.perform(mock_request('GET', '/info'))!
	expected := '{"build":{"version":"0.1.0","commit":"abc123","commit_time":"2026-06-20T10:00:00Z","build_time":"2026-06-20T10:30:00Z","v_version":"0.5.1"}}'
	result.assert_body(expected)!
}

fn test_info_endpoint_unknown_path_returns_404() {
	info := core.default_build_info()

	mut mvc := new_mockmvc()
	mvc.get('/info', info_mock_handler(info))

	// /info is registered, but /unknown is not.
	result := mvc.perform(mock_request('GET', '/unknown'))!
	result.assert_not_found()!
}

// ── load_build_info / parse_build_info tests ──

fn test_load_build_info_reads_version_from_file() {
	dir := setup_info_test_dir('test1')!
	defer {
		cleanup_info_test_dir(dir)
	}
	path := write_info_file(dir, 'build.info', [
		'version=0.4.0',
		'commit=abc123',
		'build_time=2026-06-20T10:30:00Z',
	])!

	info := core.load_build_info(path)
	assert info.version == '0.4.0'
	assert info.commit == 'abc123'
	assert info.build_time == '2026-06-20T10:30:00Z'
}

fn test_load_build_info_reads_all_fields() {
	dir := setup_info_test_dir('test2')!
	defer {
		cleanup_info_test_dir(dir)
	}
	path := write_info_file(dir, 'build.info', [
		'version=1.2.3',
		'commit=deadbeef',
		'commit_time=2026-06-20T10:00:00Z',
		'build_time=2026-06-20T10:30:00Z',
		'v_version=0.5.1',
	])!

	info := core.load_build_info(path)
	assert info.version == '1.2.3'
	assert info.commit == 'deadbeef'
	assert info.commit_time == '2026-06-20T10:00:00Z'
	assert info.build_time == '2026-06-20T10:30:00Z'
	assert info.v_version == '0.5.1'
}

fn test_load_build_info_missing_file_returns_defaults() {
	info := core.load_build_info('/nonexistent/path/to/build.info')
	def := core.default_build_info()
	assert info.version == def.version
	assert info.commit == def.commit
	assert info.commit_time == def.commit_time
	assert info.build_time == def.build_time
	assert info.v_version == def.v_version
}

fn test_load_build_info_ignores_comments_and_blank_lines() {
	dir := setup_info_test_dir('test3')!
	defer {
		cleanup_info_test_dir(dir)
	}
	path := write_info_file(dir, 'build.info', [
		'# This is a comment',
		'',
		'   # indented comment',
		'version=0.4.0',
		'',
		'commit=abc123',
	])!

	info := core.load_build_info(path)
	assert info.version == '0.4.0'
	assert info.commit == 'abc123'
}

fn test_load_build_info_ignores_unknown_keys() {
	dir := setup_info_test_dir('test4')!
	defer {
		cleanup_info_test_dir(dir)
	}
	path := write_info_file(dir, 'build.info', [
		'version=0.4.0',
		'unknown_key=should_be_ignored',
		'another_unknown=value',
	])!

	info := core.load_build_info(path)
	assert info.version == '0.4.0'
}

fn test_load_build_info_trims_whitespace() {
	dir := setup_info_test_dir('test5')!
	defer {
		cleanup_info_test_dir(dir)
	}
	path := write_info_file(dir, 'build.info', [
		'  version  =  0.4.0  ',
		'  commit=abc123  ',
	])!

	info := core.load_build_info(path)
	assert info.version == '0.4.0'
	assert info.commit == 'abc123'
}

fn test_parse_build_info_empty_content() {
	info := core.parse_build_info('')
	def := core.default_build_info()
	assert info.version == def.version
	assert info.commit == def.commit
}

fn test_parse_build_info_only_comments() {
	info := core.parse_build_info('# comment 1\n# comment 2\n')
	def := core.default_build_info()
	assert info.version == def.version
}

fn test_default_build_info_returns_zero_version() {
	info := core.default_build_info()
	assert info.version == '0.0.0'
	assert info.commit == 'unknown'
	assert info.commit_time == 'unknown'
	assert info.build_time == 'unknown'
	assert info.v_version == 'unknown'
}

// ── Integration: load_build_info → serve_info ──

fn test_load_build_info_then_serve_info() {
	dir := setup_info_test_dir('test6')!
	defer {
		cleanup_info_test_dir(dir)
	}
	path := write_info_file(dir, 'build.info', [
		'version=2.0.0',
		'commit=feedface',
		'build_time=2026-06-21T08:00:00Z',
		'v_version=0.5.1',
	])!

	info := core.load_build_info(path)
	body, _, code := serve_info(info)

	assert code == 200
	assert body.contains('"version":"2.0.0"')
	assert body.contains('"commit":"feedface"')
	assert body.contains('"build_time":"2026-06-21T08:00:00Z"')
	assert body.contains('"v_version":"0.5.1"')
}

// ── Test helpers ──

fn setup_info_test_dir(prefix string) !string {
	dir := os.join_path(os.vtmp_dir(), 'photon_info_${prefix}_${os.getpid().str()}')
	os.mkdir_all(dir)!
	return dir
}

fn write_info_file(dir string, filename string, lines []string) !string {
	path := os.join_path(dir, filename)
	content := lines.join('\n') + '\n'
	os.write_file(path, content)!
	return path
}

fn cleanup_info_test_dir(dir string) {
	os.rmdir_all(dir) or {}
}

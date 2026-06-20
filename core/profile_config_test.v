module core

// profile_config_test.v - Tests for Task A4: Profile-specific config and
// property source priority chain.
//
// Verifies:
//   - application-{profile}.toml loading
//   - Property source priority: CLI > env vars > profile config > default config
//   - Profile detection from PHOTON_PROFILE env var and --profile CLI arg
//   - get_property() priority chain lookup
//   - Missing key handling
//
// Uses temp directories for config files to avoid filesystem assumptions.
import os

// ── Test Helpers ──

// write_test_toml writes a TOML file with the given content to a temp dir.
// Returns the full path to the written file.
fn write_test_toml(dir string, filename string, content string) !string {
	path := os.join_path(dir, filename)
	os.write_file(path, content)!
	return path
}

// make_test_dir creates a unique temp directory for test config files.
fn make_test_dir(prefix string) !string {
	dir := os.join_path(os.temp_dir(), 'photon_test_${prefix}_${os.getpid()}')
	os.mkdir_all(dir)!
	return dir
}

// cleanup_test_dir removes a test directory and all its contents.
fn cleanup_test_dir(dir string) {
	os.rmdir_all(dir) or {}
}

// ── Test 1: Default config only ──

fn test_default_config_only() {
	dir := make_test_dir('default_only')!
	defer { cleanup_test_dir(dir) }

	// Write application.toml
	write_test_toml(dir, 'application.toml', '
[app]
name = "DefaultApp"
port = 8080
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!

	// Properties should come from default config
	assert env.get_property('app.name') == 'DefaultApp'
	assert env.get_property('app.port') == '8080'

	// Property source should be 'default'
	assert env.property_source('app.name') == 'default'
}

// ── Test 2: Profile config overrides default ──

fn test_profile_overrides_default() {
	dir := make_test_dir('profile_override')!
	defer { cleanup_test_dir(dir) }

	// Write application.toml (default)
	write_test_toml(dir, 'application.toml', '
[app]
name = "DefaultApp"
port = "8080"
debug = "false"
')!

	// Write application-dev.toml (profile override)
	write_test_toml(dir, 'application-dev.toml', '
[app]
name = "DevApp"
debug = "true"
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!
	env.load_profile('dev')!

	// app.name should be overridden by profile config
	assert env.get_property('app.name') == 'DevApp'
	// app.port should come from default config (not in profile)
	assert env.get_property('app.port') == '8080'
	// app.debug should come from profile config
	assert env.get_property('app.debug') == 'true'

	// Property source checks
	assert env.property_source('app.name') == 'profile'
	assert env.property_source('app.port') == 'default'
	assert env.property_source('app.debug') == 'profile'
}

// ── Test 3: Env var overrides profile config ──

fn test_env_var_overrides_profile() {
	dir := make_test_dir('env_override')!
	defer { cleanup_test_dir(dir) }

	// Write application.toml
	write_test_toml(dir, 'application.toml', '
[app]
name = "DefaultApp"
')!

	// Write application-dev.toml
	write_test_toml(dir, 'application-dev.toml', '
[app]
name = "DevApp"
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!
	env.load_profile('dev')!

	// Before env var: should come from profile
	assert env.get_property('app.name') == 'DevApp'

	// Set PHOTON_APP_NAME env var
	os.setenv('PHOTON_APP_NAME', 'EnvApp', true)
	defer {
		os.unsetenv('PHOTON_APP_NAME')
	}

	// After env var: should come from env var (overrides profile)
	assert env.get_property('app.name') == 'EnvApp'
	assert env.property_source('app.name') == 'env_var'
}

// ── Test 4: CLI arg overrides env var ──

fn test_cli_arg_overrides_env_var() {
	dir := make_test_dir('cli_override')!
	defer { cleanup_test_dir(dir) }

	// Write application.toml
	write_test_toml(dir, 'application.toml', '
[app]
name = "DefaultApp"
')!

	// Set env var
	os.setenv('PHOTON_APP_NAME', 'EnvApp', true)
	defer {
		os.unsetenv('PHOTON_APP_NAME')
	}

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!

	// Parse CLI args with --app.name=CliApp
	env.parse_cli_args(['testprog', '--app.name=CliApp'])

	// CLI arg should override env var
	assert env.get_property('app.name') == 'CliApp'
	assert env.property_source('app.name') == 'cli'
}

// ── Test 5: Missing key returns empty / error ──

fn test_missing_key_returns_empty() {
	mut env := new_environment()

	// get_property returns empty string for missing key
	assert env.get_property('nonexistent.key') == ''

	// get_property_or returns default for missing key
	assert env.get_property_or('nonexistent.key', 'fallback') == 'fallback'

	// has_property returns false for missing key
	assert env.has_property('nonexistent.key') == false

	// get_property_strict returns error for missing key
	val := env.get_property_strict('nonexistent.key') or {
		assert err.msg().contains('not found')
		return
	}
	// Should not reach here
	assert false
}

// ── Test 6: Profile detection from env var ──

fn test_profile_detection_from_env_var() {
	// Set PHOTON_PROFILE env var
	os.setenv('PHOTON_PROFILE', 'staging', true)
	defer {
		os.unsetenv('PHOTON_PROFILE')
	}

	mut env := new_environment()

	// detect_profile should return 'staging' from env var
	profile := env.detect_profile()
	assert profile == 'staging'

	// apply_detected_profile should set it as active
	applied := env.apply_detected_profile()
	assert applied == 'staging'
	assert env.get_active_profile() == 'staging'
	assert env.accepts_profile('staging') == true
}

// ── Test 7: Profile detection from CLI arg ──

fn test_profile_detection_from_cli_arg() {
	mut env := new_environment()

	// Parse CLI args with --profile=prod
	env.parse_cli_args(['testprog', '--profile=prod'])

	// detect_profile should return 'prod' from CLI arg
	profile := env.detect_profile()
	assert profile == 'prod'

	// apply_detected_profile should set it as active
	applied := env.apply_detected_profile()
	assert applied == 'prod'
	assert env.get_active_profile() == 'prod'
}

// ── Test 7b: Profile detection from CLI arg (space-separated form) ──

fn test_profile_detection_from_cli_arg_space_form() {
	mut env := new_environment()

	// Parse CLI args with --profile prod (space-separated)
	env.parse_cli_args(['testprog', '--profile', 'prod'])

	// detect_profile should return 'prod' from CLI arg
	profile := env.detect_profile()
	assert profile == 'prod'
}

// ── Test 8: Full priority chain correctness ──

fn test_priority_chain_correctness() {
	dir := make_test_dir('priority_chain')!
	defer { cleanup_test_dir(dir) }

	// Write application.toml (default - lowest priority)
	write_test_toml(dir, 'application.toml', '
[app]
name = "DefaultApp"
level = "default"
')!

	// Write application-test.toml (profile config)
	write_test_toml(dir, 'application-test.toml', '
[app]
name = "ProfileApp"
level = "profile"
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!
	env.load_profile('test')!

	// Set env var (overrides profile)
	os.setenv('PHOTON_APP_NAME', 'EnvApp', true)
	defer {
		os.unsetenv('PHOTON_APP_NAME')
	}

	// Set CLI arg (overrides env var - highest priority)
	env.set_cli_arg('app.name', 'CliApp')

	// app.name: CLI > env > profile > default → 'CliApp'
	assert env.get_property('app.name') == 'CliApp'
	assert env.property_source('app.name') == 'cli'

	// app.level: only in profile and default → 'profile' (profile overrides default)
	assert env.get_property('app.level') == 'profile'
	assert env.property_source('app.level') == 'profile'

	// Remove CLI arg → env var should take over
	env.clear_cli_args()
	assert env.get_property('app.name') == 'EnvApp'
	assert env.property_source('app.name') == 'env_var'

	// Remove env var → profile should take over
	os.unsetenv('PHOTON_APP_NAME')
	assert env.get_property('app.name') == 'ProfileApp'
	assert env.property_source('app.name') == 'profile'
}

// ── Test 9: CLI arg space-separated form ──

fn test_cli_arg_space_separated_form() {
	mut env := new_environment()

	// --key value form
	env.parse_cli_args(['testprog', '--server.port', '9090'])
	assert env.get_property('server.port') == '9090'
	assert env.property_source('server.port') == 'cli'

	// --key=value form
	env.parse_cli_args(['testprog', '--server.host=localhost'])
	assert env.get_property('server.host') == 'localhost'
}

// ── Test 10: CLI arg boolean flag ──

fn test_cli_arg_boolean_flag() {
	mut env := new_environment()

	// --flag form (no value → 'true')
	env.parse_cli_args(['testprog', '--app.enabled'])
	assert env.get_property('app.enabled') == 'true'
}

// ── Test 11: Non-config args returned ──

fn test_non_config_args_returned() {
	mut env := new_environment()

	remaining := env.parse_cli_args(['testprog', 'command', '--key=value', 'subcommand', '--flag'])

	// Non-config args should be returned
	assert remaining.len == 2
	assert remaining[0] == 'command'
	assert remaining[1] == 'subcommand'

	// Config args should be parsed
	assert env.get_property('key') == 'value'
	assert env.get_property('flag') == 'true'
}

// ── Test 12: Env var name conversion ──

fn test_env_var_name_conversion() {
	assert env_var_name_for_key('app.name') == 'PHOTON_APP_NAME'
	assert env_var_name_for_key('server.port') == 'PHOTON_SERVER_PORT'
	assert env_var_name_for_key('db.host') == 'PHOTON_DB_HOST'
	assert env_var_name_for_key('cache-ttl') == 'PHOTON_CACHE_TTL'
	assert env_var_name_for_key('simple') == 'PHOTON_SIMPLE'
}

// ── Test 13: TOML parsing to flat map ──

fn test_toml_parsing_to_flat_map() {
	toml_content := '
[app]
name = "MyApp"
port = 8080
debug = true

[server]
host = "localhost"
'

	props := parse_toml_to_flat_map(toml_content)!
	assert props['app.name'] == 'MyApp'
	assert props['app.port'] == '8080'
	assert props['app.debug'] == 'true'
	assert props['server.host'] == 'localhost'
}

// ── Test 14: Missing config files are optional ──

fn test_missing_config_files_optional() {
	dir := make_test_dir('missing_config')!
	defer { cleanup_test_dir(dir) }

	mut env := new_environment()
	env.set_config_dir(dir)

	// Loading non-existent default config should be a no-op (no error)
	env.load_default_config('')!

	// Loading non-existent profile config should be a no-op (no error)
	env.load_profile('nonexistent')!

	// No properties should be loaded
	assert env.get_property('any.key') == ''
}

// ── Test 15: Programmatic properties as fallback ──

fn test_programmatic_properties_fallback() {
	dir := make_test_dir('prog_fallback')!
	defer { cleanup_test_dir(dir) }

	write_test_toml(dir, 'application.toml', '
[app]
name = "ConfigApp"
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!

	// Set programmatic property (fallback - lowest priority)
	env.set_property('app.name', 'ProgrammaticApp')
	env.set_property('custom.key', 'custom_value')

	// app.name: default config overrides programmatic
	assert env.get_property('app.name') == 'ConfigApp'
	assert env.property_source('app.name') == 'default'

	// custom.key: only in programmatic → fallback
	assert env.get_property('custom.key') == 'custom_value'
}

// ── Test 16: Merged properties ──

fn test_merged_properties() {
	dir := make_test_dir('merged')!
	defer { cleanup_test_dir(dir) }

	write_test_toml(dir, 'application.toml', '
[app]
name = "DefaultApp"
port = "8080"
')!

	write_test_toml(dir, 'application-dev.toml', '
[app]
name = "DevApp"
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!
	env.load_profile('dev')!

	// Set programmatic property
	env.set_property('app.name', 'ProgrammaticApp')
	env.set_property('custom.key', 'custom')

	// Set CLI arg
	env.set_cli_arg('app.name', 'CliApp')

	merged := env.merged_properties()

	// CLI arg should win for app.name
	assert merged['app.name'] == 'CliApp'
	// Default config for app.port
	assert merged['app.port'] == '8080'
	// Programmatic for custom.key
	assert merged['custom.key'] == 'custom'
}

// ── Test 17: Property source priority enum ──

fn test_property_source_priority_enum() {
	// Verify enum values (higher = higher priority)
	assert int(PropertySourcePriority.default) == 0
	assert int(PropertySourcePriority.profile) == 1
	assert int(PropertySourcePriority.env_var) == 2
	assert int(PropertySourcePriority.cli) == 3

	// Verify str()
	assert PropertySourcePriority.default.str() == 'default'
	assert PropertySourcePriority.profile.str() == 'profile'
	assert PropertySourcePriority.env_var.str() == 'env_var'
	assert PropertySourcePriority.cli.str() == 'cli'
}

// ── Test 18: get_property_int with priority chain ──

fn test_get_property_int_with_priority_chain() {
	dir := make_test_dir('int_chain')!
	defer { cleanup_test_dir(dir) }

	write_test_toml(dir, 'application.toml', '
[server]
port = 8080
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!

	// From default config
	mut port := env.get_property_int('server.port')!
	assert port == 8080

	// Override with CLI arg
	env.set_cli_arg('server.port', '9090')
	port = env.get_property_int('server.port')!
	assert port == 9090

	// get_property_int_or with default
	env.clear_cli_args()
	assert env.get_property_int_or('server.port', 3000) == 8080
	assert env.get_property_int_or('missing.port', 3000) == 3000
}

// ── Test 19: get_property_bool with priority chain ──

fn test_get_property_bool_with_priority_chain() {
	dir := make_test_dir('bool_chain')!
	defer { cleanup_test_dir(dir) }

	write_test_toml(dir, 'application.toml', '
[app]
debug = true
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!

	// From default config
	mut debug := env.get_property_bool('app.debug')!
	assert debug == true

	// Override with CLI arg
	env.set_cli_arg('app.debug', 'false')
	debug = env.get_property_bool('app.debug')!
	assert debug == false

	// get_property_bool_or with default
	env.clear_cli_args()
	assert env.get_property_bool_or('app.debug', false) == true
	assert env.get_property_bool_or('missing.flag', true) == true
}

// ── Test 20: Backward compatibility - set_property + get_property ──

fn test_backward_compatibility_set_get_property() {
	mut env := new_environment()

	// Existing set_property / get_property behavior must still work
	env.set_property('app.name', 'PhotonAPI')
	assert env.get_property('app.name') == 'PhotonAPI'
	assert env.get_property('nonexistent') == ''
	assert env.has_property('app.name') == true
	assert env.has_property('nonexistent') == false

	// get_property_or
	assert env.get_property_or('app.name', 'default') == 'PhotonAPI'
	assert env.get_property_or('missing', 'default') == 'default'

	// set_properties
	env.set_properties({
		'app.version': '1.0.0'
		'app.author':  'Photon'
	})
	assert env.get_property('app.version') == '1.0.0'
	assert env.get_property('app.author') == 'Photon'
}

// ── Test 21: load_profile_config with explicit path ──

fn test_load_profile_config_explicit_path() {
	dir := make_test_dir('explicit_path')!
	defer { cleanup_test_dir(dir) }

	// Write a custom profile config
	custom_path := write_test_toml(dir, 'custom-profile.toml', '
[app]
name = "CustomProfileApp"
')!

	mut env := new_environment()
	env.load_profile_config(custom_path)!

	assert env.get_property('app.name') == 'CustomProfileApp'
	assert env.property_source('app.name') == 'profile'
}

// ── Test 22: Multiple profile loads accumulate ──

fn test_multiple_profile_loads_accumulate() {
	dir := make_test_dir('multi_profile')!
	defer { cleanup_test_dir(dir) }

	write_test_toml(dir, 'application.toml', '
[app]
name = "DefaultApp"
')!

	write_test_toml(dir, 'application-dev.toml', '
[app]
name = "DevApp"
[dev]
feature = "enabled"
')!

	write_test_toml(dir, 'application-local.toml', '
[local]
override = "yes"
')!

	mut env := new_environment()
	env.set_config_dir(dir)
	env.load_default_config('')!
	env.load_profile('dev')!
	env.load_profile_config('${dir}/application-local.toml')!

	// dev.feature should be present
	assert env.get_property('dev.feature') == 'enabled'
	// local.override should be present
	assert env.get_property('local.override') == 'yes'
	// app.name should be from dev (loaded after default)
	assert env.get_property('app.name') == 'DevApp'
}

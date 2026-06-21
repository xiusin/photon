module core

// starter_pattern_test.v - Tests for Task A5: Starter pattern with
// auto_configuration_imports.v manifest.
//
// Verifies:
//   - Manifest imports registration (register_imports / register_imported)
//   - list_imports() returns snapshot copy
//   - Duplicate import behavior (append-only, no deduplication)
//   - Imports do not activate without comptime registration
//   - Full starter flow: imports + register_auto_configuration[T]()
//   - Manifest file format parsing (parse_manifest_content)
//   - Manifest with comments (# lines ignored)
//   - Manifest with empty lines (ignored)
//   - Multiple modules: scan_manifests() aggregates across module dirs
//   - Conditional starter: import with @[conditional_on_profile]
//   - Thread-safety of concurrent register_imported() calls
//   - V const array approach (programmatic module declaration)
//
// Uses temp directories for manifest files to avoid filesystem assumptions.
import os

// ═══════════════════════════════════════════════════════════
// Test Fixtures — auto-configuration candidate structs
// (unique names to avoid collision with auto_configuration_scan_test.v)
// ═══════════════════════════════════════════════════════════

// StarterDbAutoConfig is a plain auto-configuration — no conditions.
@[auto_configuration]
struct StarterDbAutoConfig {
	host string
	port int
}

// StarterRedisAutoConfig is a plain auto-configuration — no conditions.
@[auto_configuration]
struct StarterRedisAutoConfig {
	host string
}

// StarterProdAutoConfig carries a profile condition — only active under 'prod'.
@[conditional_on_profile: 'prod']
@[auto_configuration]
struct StarterProdAutoConfig {
	port int
}

// StarterDevAutoConfig carries a profile condition for 'dev'.
@[conditional_on_profile: 'dev']
@[auto_configuration]
struct StarterDevAutoConfig {
	debug bool
}

// StarterWebAutoConfig is a plain auto-configuration — no conditions.
@[auto_configuration]
struct StarterWebAutoConfig {
	port int
}

// StarterCacheAutoConfig carries a property condition — active only if
// cache.enabled == true.
@[conditional_on_property: 'cache.enabled,true']
@[auto_configuration]
struct StarterCacheAutoConfig {
	driver string
}

// ═══════════════════════════════════════════════════════════
// Test Helpers — temp directory and manifest file management
// ═══════════════════════════════════════════════════════════

// make_starter_test_dir creates a unique temp directory for test manifest files.
fn make_starter_test_dir(prefix string) !string {
	dir := os.join_path(os.temp_dir(), 'photon_starter_test_${prefix}_${os.getpid()}')
	os.mkdir_all(dir)!
	return dir
}

// cleanup_starter_test_dir removes a test directory and all its contents.
fn cleanup_starter_test_dir(dir string) {
	os.rmdir_all(dir) or {}
}

// write_starter_manifest writes a manifest file with the given content to a dir.
// Returns the full path to the written file.
fn write_starter_manifest(dir string, filename string, content string) !string {
	path := os.join_path(dir, filename)
	os.write_file(path, content)!
	return path
}

// starter_db_module_imports simulates a third-party module's
// `pub const auto_configuration_imports` array. In a real module this would be:
//   module db
//   pub const auto_configuration_imports = ['DbAutoConfig', 'RedisAutoConfig']
fn starter_db_module_imports() []string {
	return ['StarterDbAutoConfig', 'StarterRedisAutoConfig']
}

// starter_web_module_imports simulates a second module's const array.
fn starter_web_module_imports() []string {
	return ['StarterWebAutoConfig']
}

// ═══════════════════════════════════════════════════════════
// SubTask A5.1 — Manifest import registration API
// ═══════════════════════════════════════════════════════════

// ── Test 1: Register imports ──

fn test_register_imports() {
	mut mgr := new_auto_configuration_manager()
	assert mgr.import_count() == 0

	mgr.register_imports(['DbAutoConfig', 'RedisAutoConfig'])

	assert mgr.import_count() == 2
	imports := mgr.list_imports()
	assert imports.len == 2
	assert 'DbAutoConfig' in imports
	assert 'RedisAutoConfig' in imports
}

// ── Test 2: List imports empty by default ──

fn test_list_imports_empty_by_default() {
	mut mgr := new_auto_configuration_manager()

	assert mgr.import_count() == 0
	assert mgr.list_imports().len == 0
}

// ── Test 3: Duplicate imports are listed (append-only, no deduplication) ──

fn test_duplicate_imports_listed_twice() {
	mut mgr := new_auto_configuration_manager()

	mgr.register_imports(['DbAutoConfig', 'DbAutoConfig'])

	// No deduplication — both entries are kept (append-only behavior).
	assert mgr.import_count() == 2
}

// ── Test 3b: register_imported adds a single import ──

fn test_register_imported_single() {
	mut mgr := new_auto_configuration_manager()

	mgr.register_imported('DbAutoConfig')
	assert mgr.import_count() == 1
	assert mgr.has_import('DbAutoConfig') == true
	assert mgr.has_import('RedisAutoConfig') == false
}

// ── Test 3c: list_imports returns a snapshot copy ──

fn test_list_imports_returns_snapshot_copy() {
	mut mgr := new_auto_configuration_manager()
	mgr.register_imported('DbAutoConfig')

	mut snapshot := mgr.list_imports()
	assert snapshot.len == 1

	// Mutating the snapshot must NOT affect the manager's internal state.
	snapshot.clear()
	assert mgr.import_count() == 1
}

// ── Test 3d: clear_imports removes all imports but not candidates ──

fn test_clear_imports() {
	mut mgr := new_auto_configuration_manager()
	mgr.register_imports(['DbAutoConfig', 'RedisAutoConfig'])
	mgr.register_from_comptime[StarterDbAutoConfig]()!

	assert mgr.import_count() == 2
	assert mgr.candidate_count() == 1

	mgr.clear_imports()

	assert mgr.import_count() == 0
	// Candidates are NOT affected by clear_imports.
	assert mgr.candidate_count() == 1
}

// ═══════════════════════════════════════════════════════════
// SubTask A5.1 — Manifest file format (parse_manifest_content)
// ═══════════════════════════════════════════════════════════

// ── Test 4: Manifest file format — basic parsing ──

fn test_parse_manifest_content_basic() {
	content := 'photon.db.DbAutoConfig\nphoton.db.RedisAutoConfig\n'
	class_names := parse_manifest_content(content)

	assert class_names.len == 2
	assert class_names[0] == 'photon.db.DbAutoConfig'
	assert class_names[1] == 'photon.db.RedisAutoConfig'
}

// ── Test 5: Manifest with comments (# lines ignored) ──

fn test_parse_manifest_content_with_comments() {
	content := '# This is a comment\nphoton.db.DbAutoConfig\n# Another comment\nphoton.db.RedisAutoConfig\n# trailing comment'
	class_names := parse_manifest_content(content)

	assert class_names.len == 2
	assert 'photon.db.DbAutoConfig' in class_names
	assert 'photon.db.RedisAutoConfig' in class_names
}

// ── Test 6: Manifest with empty lines (ignored) ──

fn test_parse_manifest_content_with_empty_lines() {
	content := '\nphoton.db.DbAutoConfig\n\n\nphoton.db.RedisAutoConfig\n\n'
	class_names := parse_manifest_content(content)

	assert class_names.len == 2
	assert class_names[0] == 'photon.db.DbAutoConfig'
	assert class_names[1] == 'photon.db.RedisAutoConfig'
}

// ── Test 6b: Manifest with whitespace-only lines (ignored) ──

fn test_parse_manifest_content_with_whitespace_lines() {
	content := '   \nphoton.db.DbAutoConfig\n\t\n   \t  \nphoton.db.RedisAutoConfig\n'
	class_names := parse_manifest_content(content)

	assert class_names.len == 2
}

// ── Test 6c: Manifest trims whitespace around class names ──

fn test_parse_manifest_content_trims_whitespace() {
	content := '  photon.db.DbAutoConfig  \n\tphoton.db.RedisAutoConfig\t\n'
	class_names := parse_manifest_content(content)

	assert class_names.len == 2
	assert class_names[0] == 'photon.db.DbAutoConfig'
	assert class_names[1] == 'photon.db.RedisAutoConfig'
}

// ── Test 6d: Empty manifest returns empty list ──

fn test_parse_manifest_content_empty() {
	assert parse_manifest_content('').len == 0
	assert parse_manifest_content('# only comments\n# no class names').len == 0
	assert parse_manifest_content('\n\n\n').len == 0
}

// ── Test 6e: Manifest with mixed comments, empty lines, and class names ──

fn test_parse_manifest_content_mixed() {
	content := '# Photon Framework auto-configuration imports
# Database module
photon.db.DbAutoConfig
photon.db.RedisAutoConfig

# Web module
photon.web.WebMvcAutoConfig

# End of file
'
	class_names := parse_manifest_content(content)

	assert class_names.len == 3
	assert class_names[0] == 'photon.db.DbAutoConfig'
	assert class_names[1] == 'photon.db.RedisAutoConfig'
	assert class_names[2] == 'photon.web.WebMvcAutoConfig'
}

// ═══════════════════════════════════════════════════════════
// SubTask A5.2 — load_imports_from_manifest (file-based loading)
// ═══════════════════════════════════════════════════════════

// ── Test 7: load_imports_from_manifest reads and registers from file ──

fn test_load_imports_from_manifest() {
	dir := make_starter_test_dir('load_manifest')!
	defer { cleanup_starter_test_dir(dir) }

	path := write_starter_manifest(dir, auto_configuration_imports_filename, '# DB configs
photon.db.DbAutoConfig
photon.db.RedisAutoConfig
')!

	mut mgr := new_auto_configuration_manager()
	count := mgr.load_imports_from_manifest(path)!

	assert count == 2
	assert mgr.import_count() == 2
	imports := mgr.list_imports()
	assert 'photon.db.DbAutoConfig' in imports
	assert 'photon.db.RedisAutoConfig' in imports
}

// ── Test 7b: load_imports_from_manifest returns error for missing file ──

fn test_load_imports_from_manifest_missing_file() {
	mut mgr := new_auto_configuration_manager()

	mgr.load_imports_from_manifest('/nonexistent/path/to/manifest.v') or {
		assert err.msg().contains('not found') || err.msg().contains('不存在')
		return
	}
	assert false
}

// ── Test 7c: load_imports_from_manifest with empty manifest ──

fn test_load_imports_from_manifest_empty() {
	dir := make_starter_test_dir('empty_manifest')!
	defer { cleanup_starter_test_dir(dir) }

	path := write_starter_manifest(dir, auto_configuration_imports_filename, '# only comments\n')!

	mut mgr := new_auto_configuration_manager()
	count := mgr.load_imports_from_manifest(path)!

	assert count == 0
	assert mgr.import_count() == 0
}

// ═══════════════════════════════════════════════════════════
// SubTask A5.2 — scan_manifests (directory scanning)
// ═══════════════════════════════════════════════════════════

// ── Test 8: scan_manifests aggregates across multiple module dirs ──

fn test_scan_manifests_multiple_modules() {
	dir := make_starter_test_dir('multi_module')!
	defer { cleanup_starter_test_dir(dir) }

	// Simulate two module directories, each with its own manifest.
	db_dir := os.join_path(dir, 'db')
	os.mkdir_all(db_dir)!
	write_starter_manifest(db_dir, auto_configuration_imports_filename, 'photon.db.DbAutoConfig
photon.db.RedisAutoConfig
')!

	web_dir := os.join_path(dir, 'web')
	os.mkdir_all(web_dir)!
	write_starter_manifest(web_dir, auto_configuration_imports_filename, 'photon.web.WebMvcAutoConfig
photon.web.DispatcherAutoConfig
')!

	mut mgr := new_auto_configuration_manager()
	count := mgr.scan_manifests(dir)!

	assert count == 4
	assert mgr.import_count() == 4
	imports := mgr.list_imports()
	assert 'photon.db.DbAutoConfig' in imports
	assert 'photon.db.RedisAutoConfig' in imports
	assert 'photon.web.WebMvcAutoConfig' in imports
	assert 'photon.web.DispatcherAutoConfig' in imports
}

// ── Test 8b: scan_manifests with nested module directories ──

fn test_scan_manifests_nested_directories() {
	dir := make_starter_test_dir('nested')!
	defer { cleanup_starter_test_dir(dir) }

	// Simulate a vendor/photon/db/ structure with nested dirs.
	vendor_dir := os.join_path(dir, 'vendor')
	photon_dir := os.join_path(vendor_dir, 'photon')
	db_dir := os.join_path(photon_dir, 'db')
	os.mkdir_all(db_dir)!
	write_starter_manifest(db_dir, auto_configuration_imports_filename, 'photon.db.DbAutoConfig\n')!

	mut mgr := new_auto_configuration_manager()
	count := mgr.scan_manifests(dir)!

	assert count == 1
	assert mgr.has_import('photon.db.DbAutoConfig') == true
}

// ── Test 8c: scan_manifests skips hidden directories ──

fn test_scan_manifests_skips_hidden_dirs() {
	dir := make_starter_test_dir('hidden_dirs')!
	defer { cleanup_starter_test_dir(dir) }

	// A manifest in a hidden directory should be skipped.
	hidden_dir := os.join_path(dir, '.hidden')
	os.mkdir_all(hidden_dir)!
	write_starter_manifest(hidden_dir, auto_configuration_imports_filename, 'photon.hidden.ShouldNotLoad\n')!

	// A manifest in a normal directory should be loaded.
	normal_dir := os.join_path(dir, 'db')
	os.mkdir_all(normal_dir)!
	write_starter_manifest(normal_dir, auto_configuration_imports_filename, 'photon.db.DbAutoConfig\n')!

	mut mgr := new_auto_configuration_manager()
	count := mgr.scan_manifests(dir)!

	assert count == 1
	assert mgr.has_import('photon.db.DbAutoConfig') == true
	assert mgr.has_import('photon.hidden.ShouldNotLoad') == false
}

// ── Test 8d: scan_manifests on non-existent directory returns 0 ──

fn test_scan_manifests_nonexistent_directory() {
	mut mgr := new_auto_configuration_manager()
	count := mgr.scan_manifests('/nonexistent/path/that/does/not/exist')!

	assert count == 0
	assert mgr.import_count() == 0
}

// ── Test 8e: scan_manifests on empty directory returns 0 ──

fn test_scan_manifests_empty_directory() {
	dir := make_starter_test_dir('empty_dir')!
	defer { cleanup_starter_test_dir(dir) }

	mut mgr := new_auto_configuration_manager()
	count := mgr.scan_manifests(dir)!

	assert count == 0
}

// ── Test 8f: scan_manifests on a file (not a directory) returns error ──

fn test_scan_manifests_file_not_directory() {
	dir := make_starter_test_dir('file_not_dir')!
	defer { cleanup_starter_test_dir(dir) }

	path := write_starter_manifest(dir, 'somefile.txt', 'content')!

	mut mgr := new_auto_configuration_manager()
	mgr.scan_manifests(path) or {
		assert err.msg().contains('not a directory') || err.msg().contains('不是目录')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// SubTask A5.3 — Starter flow integration tests
// ═══════════════════════════════════════════════════════════

// ── Test 9: Imports do not activate without comptime registration ──

fn test_imports_do_not_activate_without_comptime_registration() {
	mut ctx := new_application_context()

	// Register imports (manifest declaration) — this does NOT create candidates.
	ctx.register_imports(['StarterDbAutoConfig'])

	assert ctx.auto_config_manager.import_count() == 1
	// No candidates yet — imports are declarations only.
	assert ctx.auto_config_manager.candidate_count() == 0
}

// ── Test 10: Full starter flow — imports + comptime registration ──

fn test_full_starter_flow() {
	mut ctx := new_application_context()

	// Step 1: Register imports (simulating manifest loading).
	ctx.register_imports(['StarterDbAutoConfig', 'StarterRedisAutoConfig'])
	assert ctx.auto_config_manager.import_count() == 2

	// Step 2: Register each via comptime (actual registration).
	ctx.register_auto_configuration[StarterDbAutoConfig]()!
	ctx.register_auto_configuration[StarterRedisAutoConfig]()!

	// Step 3: Verify candidates created.
	assert ctx.auto_config_manager.candidate_count() == 2
	assert ctx.auto_config_manager.has_candidate('core.StarterDbAutoConfig') == true
	assert ctx.auto_config_manager.has_candidate('core.StarterRedisAutoConfig') == true

	// Step 4: apply_all evaluates conditions (none here → all match).
	ctx.auto_config_manager.apply_all(mut ctx) or { assert false }
}

// ── Test 10b: Full starter flow with manifest file loading ──

fn test_full_starter_flow_with_manifest_file() {
	dir := make_starter_test_dir('full_flow_manifest')!
	defer { cleanup_starter_test_dir(dir) }

	// Write a manifest file declaring the auto-configuration classes.
	write_starter_manifest(dir, auto_configuration_imports_filename, 'core.StarterDbAutoConfig
core.StarterRedisAutoConfig
')!

	mut ctx := new_application_context()

	// Load imports from the manifest file.
	count := ctx.load_imports_from_manifest(os.join_path(dir, auto_configuration_imports_filename))!
	assert count == 2
	assert ctx.auto_config_manager.import_count() == 2

	// Register each via comptime (actual registration).
	ctx.register_auto_configuration[StarterDbAutoConfig]()!
	ctx.register_auto_configuration[StarterRedisAutoConfig]()!

	assert ctx.auto_config_manager.candidate_count() == 2
}

// ── Test 10c: Full starter flow with scan_manifests ──

fn test_full_starter_flow_with_scan_manifests() {
	dir := make_starter_test_dir('full_flow_scan')!
	defer { cleanup_starter_test_dir(dir) }

	// Simulate a module directory with a manifest.
	db_dir := os.join_path(dir, 'db')
	os.mkdir_all(db_dir)!
	write_starter_manifest(db_dir, auto_configuration_imports_filename, 'core.StarterDbAutoConfig\ncore.StarterRedisAutoConfig\n')!

	mut ctx := new_application_context()

	// Scan the directory tree for manifest files.
	count := ctx.scan_manifests(dir)!
	assert count == 2
	assert ctx.auto_config_manager.import_count() == 2

	// Register each via comptime.
	ctx.register_auto_configuration[StarterDbAutoConfig]()!
	ctx.register_auto_configuration[StarterRedisAutoConfig]()!

	assert ctx.auto_config_manager.candidate_count() == 2
}

// ── Test 11: V const array approach (programmatic module declaration) ──

fn test_const_array_approach() {
	mut ctx := new_application_context()

	// Simulate: ctx.register_imports(db.auto_configuration_imports)
	ctx.register_imports(starter_db_module_imports())

	assert ctx.auto_config_manager.import_count() == 2
	imports := ctx.auto_config_manager.list_imports()
	assert 'StarterDbAutoConfig' in imports
	assert 'StarterRedisAutoConfig' in imports

	// Register via comptime.
	ctx.register_auto_configuration[StarterDbAutoConfig]()!
	ctx.register_auto_configuration[StarterRedisAutoConfig]()!
	assert ctx.auto_config_manager.candidate_count() == 2
}

// ── Test 11b: Multiple modules via const arrays ──

fn test_multiple_modules_via_const_arrays() {
	mut ctx := new_application_context()

	// Simulate two modules each declaring their imports via const arrays.
	ctx.register_imports(starter_db_module_imports())
	ctx.register_imports(starter_web_module_imports())

	assert ctx.auto_config_manager.import_count() == 3
	imports := ctx.auto_config_manager.list_imports()
	assert 'StarterDbAutoConfig' in imports
	assert 'StarterRedisAutoConfig' in imports
	assert 'StarterWebAutoConfig' in imports
}

// ═══════════════════════════════════════════════════════════
// Conditional Starter — @[conditional_on_*] with manifest imports
// ═══════════════════════════════════════════════════════════

// ── Test 12: Conditional starter — profile condition not met ──

fn test_conditional_starter_profile_not_met() {
	mut ctx := new_application_context()

	// StarterProdAutoConfig requires profile 'prod'. Activate 'dev' instead.
	ctx.register_imports(['StarterProdAutoConfig'])
	ctx.register_auto_configuration[StarterProdAutoConfig]()!

	assert ctx.auto_config_manager.candidate_count() == 1

	// The candidate should have a profile condition.
	candidates := ctx.auto_config_manager.list()
	assert candidates.len == 1
	assert candidates[0].conditions.len == 1

	// Activate 'dev' profile — condition should NOT match.
	ctx.set_profiles(['dev'])

	// apply_all should run cleanly (silently skips non-matching candidates).
	ctx.auto_config_manager.apply_all(mut ctx) or { assert false }
}

// ── Test 12b: Conditional starter — profile condition met ──

fn test_conditional_starter_profile_met() {
	mut ctx := new_application_context()

	ctx.register_imports(['StarterProdAutoConfig'])
	ctx.register_auto_configuration[StarterProdAutoConfig]()!

	// Activate 'prod' profile — condition should match.
	ctx.set_profiles(['prod'])

	// apply_all should run cleanly (condition matches; config is nil for A1).
	ctx.auto_config_manager.apply_all(mut ctx) or { assert false }
}

// ── Test 12c: Conditional starter — property condition ──

fn test_conditional_starter_property_condition() {
	mut ctx := new_application_context()

	ctx.register_imports(['StarterCacheAutoConfig'])
	ctx.register_auto_configuration[StarterCacheAutoConfig]()!

	assert ctx.auto_config_manager.candidate_count() == 1

	// Without cache.enabled=true, condition does NOT match.
	ctx.auto_config_manager.apply_all(mut ctx) or { assert false }

	// With cache.enabled=true, condition matches.
	ctx.set_property('cache.enabled', 'true')
	ctx.auto_config_manager.apply_all(mut ctx) or { assert false }
}

// ── Test 12d: Mixed conditional and unconditional starters ──

fn test_mixed_conditional_and_unconditional_starters() {
	mut ctx := new_application_context()
	ctx.set_profiles(['prod'])

	// Register imports for mixed starters.
	ctx.register_imports(['StarterDbAutoConfig', 'StarterProdAutoConfig', 'StarterDevAutoConfig'])

	// Register each via comptime.
	ctx.register_auto_configuration[StarterDbAutoConfig]()! // no conditions
	ctx.register_auto_configuration[StarterProdAutoConfig]()! // requires 'prod' → matches
	ctx.register_auto_configuration[StarterDevAutoConfig]()! // requires 'dev' → does NOT match

	assert ctx.auto_config_manager.candidate_count() == 3
	assert ctx.auto_config_manager.import_count() == 3

	// apply_all evaluates all conditions; non-matching candidates are skipped.
	ctx.auto_config_manager.apply_all(mut ctx) or { assert false }
}

// ═══════════════════════════════════════════════════════════
// Thread-Safety — concurrent register_imported() calls
// ═══════════════════════════════════════════════════════════

// ── Test 13: Concurrent register_imported is thread-safe ──

fn test_imports_thread_safety() {
	mut mgr := new_auto_configuration_manager()

	// Spawn goroutines that concurrently register different imports.
	// The manager's RwMutex must keep the imports slice consistent.
	done := chan bool{cap: 30}

	for i in 0 .. 30 {
		spawn fn (m &AutoConfigurationManager, idx int, d chan bool) {
			unsafe {
				m.register_imported('Import${idx}')
			}
			d <- true
		}(unsafe { mgr }, i, done)
	}

	mut completed := 0
	for _ in 0 .. 30 {
		_ = <-done
		completed++
	}
	assert completed == 30

	// All 30 imports must be present (no lost updates).
	assert mgr.import_count() == 30
}

// ── Test 13b: Concurrent load_imports_from_manifest is thread-safe ──

fn test_concurrent_manifest_loading_thread_safety() {
	dir := make_starter_test_dir('concurrent_load')!
	defer { cleanup_starter_test_dir(dir) }

	// Create multiple manifest files.
	mut paths := []string{}
	for i in 0 .. 5 {
		p := write_starter_manifest(dir, 'manifest_${i}.v', 'photon.mod.Config${i}\nphoton.mod.Config${i}b\n')!
		paths << p
	}

	mut mgr := new_auto_configuration_manager()
	done := chan bool{cap: paths.len}

	for p in paths {
		spawn fn (m &AutoConfigurationManager, path string, d chan bool) {
			unsafe {
				m.load_imports_from_manifest(path) or { assert false }
			}
			d <- true
		}(unsafe { mgr }, p, done)
	}

	mut completed := 0
	for _ in 0 .. paths.len {
		_ = <-done
		completed++
	}
	assert completed == paths.len

	// 5 files × 2 class names each = 10 imports.
	assert mgr.import_count() == 10
}

// ═══════════════════════════════════════════════════════════
// Diagnostics — declared vs. registered detection
// ═══════════════════════════════════════════════════════════

// ── Test 14: Declared imports vs. registered candidates (diagnostics) ──

fn test_declared_vs_registered_diagnostics() {
	mut ctx := new_application_context()

	// Declare 3 imports via manifest.
	ctx.register_imports(['StarterDbAutoConfig', 'StarterRedisAutoConfig', 'StarterWebAutoConfig'])
	assert ctx.auto_config_manager.import_count() == 3

	// Only register 2 via comptime (StarterWebAutoConfig is "missing").
	ctx.register_auto_configuration[StarterDbAutoConfig]()!
	ctx.register_auto_configuration[StarterRedisAutoConfig]()!

	assert ctx.auto_config_manager.candidate_count() == 2

	// Diagnostic: detect declared-but-unregistered configurations.
	imports := ctx.auto_config_manager.list_imports()
	mut unregistered := []string{}
	for import_name in imports {
		// The import name is the struct name; the candidate type_name is
		// module-qualified (e.g., 'core.StarterDbAutoConfig').
		fq_name := 'core.${import_name}'
		if !ctx.auto_config_manager.has_candidate(fq_name) {
			unregistered << import_name
		}
	}

	// StarterWebAutoConfig was declared but not registered.
	assert unregistered.len == 1
	assert 'StarterWebAutoConfig' in unregistered
}

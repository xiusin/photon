module core

// environment.v - Environment Abstraction (Spring Environment inspired)
//
// Provides a unified abstraction over profiles and properties.
// This is the Photon equivalent of Spring's Environment interface:
//   - Profile management (active profiles, default profiles)
//   - Property resolution (with hierarchical sources)
//   - Type-safe property access (string, int, bool, f64)
//   - Property source integration (Spring PropertySource)
//   - Nested property prefix queries
//
// Spring equivalent: org.springframework.core.env.Environment
// Laravel equivalent: Illuminate\Foundation\EnvironmentDetector + config()
//
// Usage:
//   env := core.new_environment()
//   env.set_active_profiles(['dev', 'local'])
//   env.set_property('app.name', 'PhotonAPI')
//   env.get_or('app.name', 'MyApp')  // → 'PhotonAPI'
//   env.accepts_profile('dev')        // → true
//
// Profile-specific config (Task A4):
//   env.load_default_config('config/application.toml')!  // default config
//   env.load_profile('dev')!                              // application-dev.toml
//   env.parse_cli_args(os.args)                           // --key=value overrides
//   // Priority chain: CLI > env vars > profile config > default config > properties
import sync
import os
import toml

// ── Property Source Priority (Task A4) ──

// PropertySourcePriority defines the priority order of property sources.
// Higher values indicate higher priority (override lower-priority sources).
//
// Priority chain (highest → lowest):
//   1. cli          — --key=value command-line arguments
//   2. env_var      — PHOTON_* environment variables
//   3. profile      — application-{profile}.toml
//   4. default      — application.toml
//
// Spring equivalent: MutablePropertySources with ordered PropertySource list
pub enum PropertySourcePriority {
	default = 0 // application.toml (lowest)
	profile = 1 // application-{profile}.toml
	env_var = 2 // PHOTON_* environment variables
	cli     = 3 // --key=value command-line arguments (highest)
}

// str returns a human-readable source name.
pub fn (p PropertySourcePriority) str() string {
	return match p {
		.default { 'default' }
		.profile { 'profile' }
		.env_var { 'env_var' }
		.cli { 'cli' }
	}
}

// ── Environment ──

// PropertySource is the interface for property sources that can be
// loaded into the Environment. Inspired by Spring's PropertySource<T>.
//
// Spring equivalent: org.springframework.core.env.PropertySource
pub interface PropertySource {
	name() string
	load() !map[string]string
}

// Environment provides a unified abstraction for profiles and properties.
// It serves as the single source of truth for configuration in the application.
//
// Features:
//   - Type-safe access (string, int, bool, f64)
//   - Property source integration (Spring PropertySource)
//   - Nested property prefix queries (get_by_prefix)
//   - Placeholder resolution (${key} and ${key:default})
//   - Profile-specific config loading (Task A4)
//   - Property source priority chain (Task A4):
//       CLI > env vars > profile config > default config > properties
//
// Property source maps (Task A4):
//   - properties:                programmatic properties (set_property) — lowest priority fallback
//   - default_config_properties: application.toml loaded properties
//   - profile_config_properties: application-{profile}.toml loaded properties
//   - cli_args:                  parsed --key=value command-line arguments
//   - env vars:                  looked up dynamically via os.getenv('PHOTON_*')
@[heap]
pub struct Environment {
pub mut:
	active_profiles  []string
	default_profiles []string
	properties       map[string]string
	sources          []&PropertySource
	// ── Task A4: Profile-specific config & priority chain ──
	active_profile string // the single active profile for config loading (e.g. 'dev')
	config_dir     string // directory to search for application*.toml files
mut:
	mu                        sync.RwMutex
	default_config_properties map[string]string // application.toml
	profile_config_properties map[string]string // application-{profile}.toml
	cli_args                  map[string]string // --key=value parsed args
}

// new_environment creates an empty Environment with sensible defaults.
pub fn new_environment() &Environment {
	return &Environment{
		active_profiles:           ['default']
		default_profiles:          ['default']
		properties:                map[string]string{}
		default_config_properties: map[string]string{}
		profile_config_properties: map[string]string{}
		cli_args:                  map[string]string{}
	}
}

// ── Profile Management ──

// set_active_profiles replaces all active profiles.
pub fn (mut env Environment) set_active_profiles(profiles []string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.active_profiles = profiles.clone()
}

// add_active_profile adds a profile.
pub fn (mut env Environment) add_active_profile(profile string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	if profile !in env.active_profiles {
		env.active_profiles << profile
	}
}

// remove_active_profile removes a profile.
pub fn (mut env Environment) remove_active_profile(profile string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	for i, p in env.active_profiles {
		if p == profile {
			env.active_profiles.delete(i)
			break
		}
	}
}

// get_active_profiles returns the active profiles.
pub fn (mut env Environment) get_active_profiles() []string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.active_profiles.clone()
}

// accepts_profile checks if a profile is active.
// This is the Spring equivalent of Environment.acceptsProfiles().
pub fn (mut env Environment) accepts_profile(profile string) bool {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return profile in env.active_profiles || profile in env.default_profiles
}

// is_profile_active checks if a specific profile is active (alias for accepts_profile).
pub fn (mut env Environment) is_profile_active(profile string) bool {
	return env.accepts_profile(profile)
}

// set_default_profiles sets the default profiles (active when no explicit profiles set).
pub fn (mut env Environment) set_default_profiles(profiles []string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.default_profiles = profiles.clone()
}

// ── Profile-Specific Config (Task A4) ──

// set_active_profile sets a single active profile for config loading.
// This is used by load_profile() to determine which application-{profile}.toml
// to load. It also adds the profile to active_profiles for accepts_profile().
//
// Unlike set_active_profiles() which replaces the entire profile list,
// this sets the `active_profile` field used for config file resolution.
//
// Spring equivalent: spring.profiles.active
pub fn (mut env Environment) set_active_profile(profile string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.active_profile = profile
	if profile.len > 0 && profile !in env.active_profiles {
		env.active_profiles << profile
	}
}

// get_active_profile returns the single active profile used for config loading.
// Returns empty string if no profile is set.
pub fn (mut env Environment) get_active_profile() string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.active_profile
}

// set_config_dir sets the directory where application*.toml files are searched.
// Used by load_profile() and load_default_config() when no explicit path is given.
// Defaults to the current working directory if not set.
pub fn (mut env Environment) set_config_dir(dir string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.config_dir = dir
}

// get_config_dir returns the config directory, defaulting to '.' if not set.
pub fn (mut env Environment) get_config_dir() string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	if env.config_dir.len > 0 {
		return env.config_dir
	}
	return '.'
}

// detect_profile detects the active profile from (in priority order):
//   1. --profile=xxx or --profile xxx CLI argument
//   2. PHOTON_PROFILE environment variable
//   3. Empty string (no profile) if neither is set
//
// This does NOT mutate the environment — it only returns the detected profile.
// Call set_active_profile() to apply it, or use apply_detected_profile() which
// combines detection + application.
//
// Spring equivalent: spring.profiles.active from --spring.profiles.active
pub fn (mut env Environment) detect_profile() string {
	// 1. Check CLI args (--profile=xxx or --profile xxx)
	env.mu.rlock()
	args_snapshot := env.cli_args.clone()
	env.mu.runlock()
	// cli_args already has --profile parsed into 'profile' key
	if profile := args_snapshot['profile'] {
		return profile
	}

	// Also scan os.args directly for --profile (in case parse_cli_args wasn't called)
	if os.args.len > 1 {
		for i := 1; i < os.args.len; i++ {
			arg := os.args[i]
			if arg == '--profile' && i + 1 < os.args.len {
				return os.args[i + 1]
			}
			if arg.starts_with('--profile=') {
				return arg['--profile='.len..]
			}
		}
	}

	// 2. Check PHOTON_PROFILE environment variable
	env_var := os.getenv('PHOTON_PROFILE')
	if env_var.len > 0 {
		return env_var
	}

	// 3. No profile detected
	return ''
}

// apply_detected_profile detects the profile (from CLI/env) and applies it
// to the environment via set_active_profile(). Returns the detected profile.
//
// Usage:
//   env.parse_cli_args(os.args)
//   profile := env.apply_detected_profile()  // → 'dev' (if --profile=dev)
//   env.load_profile(profile)!
pub fn (mut env Environment) apply_detected_profile() string {
	profile := env.detect_profile()
	if profile.len > 0 {
		env.set_active_profile(profile)
	}
	return profile
}

// load_default_config loads application.toml from the given path (or from
// config_dir if path is empty). The loaded properties are stored in
// default_config_properties (priority: default, the lowest config source).
//
// If the file does not exist, this is a no-op (returns ok) — default config
// is optional. Other read/parse errors are propagated.
//
// Spring equivalent: application.properties / application.toml
pub fn (mut env Environment) load_default_config(path string) ! {
	file_path := if path.len > 0 { path } else { '${env.get_config_dir()}/application.toml' }

	// Default config is optional — silently skip if file doesn't exist
	if !os.exists(file_path) {
		return
	}

	content := os.read_file(file_path) or {
		return error('failed to read default config "${file_path}": ${err}')
	}

	props := parse_toml_to_flat_map(content) or {
		return error('failed to parse default config "${file_path}": ${err}')
	}

	env.mu.@lock()
	defer { env.mu.unlock() }
	for key, value in props {
		env.default_config_properties[key] = value
	}
}

// load_profile_config loads a specific profile config file (e.g.
// application-dev.toml) from the given path. The loaded properties are stored
// in profile_config_properties (priority: profile, overrides default config).
//
// If the file does not exist, this is a no-op (returns ok) — profile config
// is optional. Other read/parse errors are propagated.
pub fn (mut env Environment) load_profile_config(path string) ! {
	// Profile config is optional — silently skip if file doesn't exist
	if !os.exists(path) {
		return
	}

	content := os.read_file(path) or {
		return error('failed to read profile config "${path}": ${err}')
	}

	props := parse_toml_to_flat_map(content) or {
		return error('failed to parse profile config "${path}": ${err}')
	}

	env.mu.@lock()
	defer { env.mu.unlock() }
	for key, value in props {
		env.profile_config_properties[key] = value
	}
}

// load_profile loads application-{profile}.toml for the given profile (or the
// currently active profile if profile is empty). The file is searched in
// config_dir. Loaded properties override default_config_properties.
//
// If the file does not exist, this is a no-op (returns ok) — profile config
// is optional.
//
// Usage:
//   env.set_config_dir('config')
//   env.load_profile('dev')!  // loads config/application-dev.toml
//   // or:
//   env.set_active_profile('prod')
//   env.load_profile('')!     // loads config/application-prod.toml
pub fn (mut env Environment) load_profile(profile string) ! {
	target_profile := if profile.len > 0 { profile } else { env.get_active_profile() }
	if target_profile.len == 0 {
		return
	}

	// Ensure the profile is tracked as active
	if profile.len > 0 {
		env.set_active_profile(profile)
	}

	file_path := '${env.get_config_dir()}/application-${target_profile}.toml'
	env.load_profile_config(file_path)!
}

// ── CLI Argument Parsing (Task A4) ──

// parse_cli_args parses command-line arguments for property overrides.
// Recognized forms:
//   --profile=xxx        sets the active profile
//   --profile xxx        sets the active profile (space-separated)
//   --key=value          sets property 'key' to 'value'
//   --key value          sets property 'key' to 'value' (space-separated)
//   --flag               sets property 'flag' to 'true'
//
// The 'profile' key is extracted and stored separately for detect_profile().
// All other --key=value pairs are stored in cli_args (highest priority source).
//
// Returns the list of non-config arguments (args that don't start with --).
// This allows callers to pass remaining args to their own CLI parser.
//
// Spring equivalent: --spring.profiles.active=xxx, --my.property=value
//
// Usage:
//   remaining := env.parse_cli_args(os.args)
pub fn (mut env Environment) parse_cli_args(args []string) []string {
	mut remaining := []string{}
	mut parsed := map[string]string{}

	mut i := 1 // skip args[0] (program name)
	for i < args.len {
		arg := args[i]

		if !arg.starts_with('--') {
			remaining << arg
			i++
			continue
		}

		// Strip leading --
		key_part := arg[2..]

		// --key=value form
		if eq_idx := key_part.index('=') {
			key := key_part[..eq_idx]
			value := key_part[eq_idx + 1..]
			parsed[key] = value
			i++
			continue
		}

		// --key value form (peek at next arg)
		// Only consume next arg if it doesn't start with -- (otherwise treat as flag)
		if i + 1 < args.len && !args[i + 1].starts_with('--') {
			parsed[key_part] = args[i + 1]
			i += 2
			continue
		}

		// --flag form (boolean flag → 'true')
		parsed[key_part] = 'true'
		i++
	}

	env.mu.@lock()
	defer { env.mu.unlock() }
	for key, value in parsed {
		env.cli_args[key] = value
	}

	return remaining
}

// set_cli_arg programmatically sets a CLI arg override.
// This is primarily useful for testing. In production, use parse_cli_args().
pub fn (mut env Environment) set_cli_arg(key string, value string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.cli_args[key] = value
}

// clear_cli_args removes all parsed CLI arg overrides.
pub fn (mut env Environment) clear_cli_args() {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.cli_args = map[string]string{}
}

// get_cli_args returns a snapshot of all parsed CLI arg overrides.
pub fn (mut env Environment) get_cli_args() map[string]string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.cli_args.clone()
}

// ── Environment Variable Lookup (Task A4) ──

// env_var_name_for_key converts a property key to its PHOTON_ env var name.
// Conversion: uppercase, replace '.' with '_', prefix with 'PHOTON_'.
//
// Examples:
//   'app.name'       → 'PHOTON_APP_NAME'
//   'server.port'    → 'PHOTON_SERVER_PORT'
//   'db.host'        → 'PHOTON_DB_HOST'
pub fn env_var_name_for_key(key string) string {
	return 'PHOTON_' + key.to_upper().replace('.', '_').replace('-', '_')
}

// lookup_env_var checks if a PHOTON_* environment variable exists for the
// given property key. Returns the value if set (non-empty), or none if unset.
fn (mut env Environment) lookup_env_var(key string) ?string {
	env_var := env_var_name_for_key(key)
	val := os.getenv(env_var)
	if val.len > 0 {
		return val
	}
	return none
}

// ── Property Management ──

// set_property sets a configuration property.
pub fn (mut env Environment) set_property(key string, value string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.properties[key] = value
}

// set_properties sets multiple properties at once.
pub fn (mut env Environment) set_properties(props map[string]string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	for key, value in props {
		env.properties[key] = value
	}
}

// get_property retrieves a property by key, checking the priority chain:
//   1. CLI args (--key=value)                    [highest]
//   2. Environment variables (PHOTON_*)
//   3. Profile config (application-{profile}.toml)
//   4. Default config (application.toml)
//   5. Programmatic properties (set_property)   [lowest, fallback]
//
// Returns empty string if the key is not found in any source.
//
// Task A4: priority chain lookup
pub fn (mut env Environment) get_property(key string) string {
	return env.lookup_property(key) or { '' }
}

// get_property_or retrieves a property by key with a default value.
// Checks the full priority chain (see get_property).
// This is the Spring equivalent of Environment.getProperty(key, defaultValue).
pub fn (mut env Environment) get_property_or(key string, default_val string) string {
	return env.lookup_property(key) or { default_val }
}

// get_property_strict retrieves a property by key, returning an error if not
// found in any source. Checks the full priority chain (see get_property).
//
// This is the explicit-error variant of get_property for callers that need
// to distinguish "missing" from "empty string".
pub fn (mut env Environment) get_property_strict(key string) !string {
	return env.lookup_property(key) or { return error('property "${key}" not found in any source') }
}

// lookup_property is the internal priority-chain lookup.
// Returns the value and its source, or none if not found.
//
// Priority (highest → lowest):
//   1. cli_args                  — --key=value CLI overrides
//   2. env_var                   — PHOTON_* environment variables
//   3. profile_config_properties — application-{profile}.toml
//   4. default_config_properties — application.toml
//   5. properties                — programmatic (set_property) fallback
fn (mut env Environment) lookup_property(key string) ?string {
	// Step 1: Check CLI args (highest priority) under read lock
	env.mu.rlock()
	if val := env.cli_args[key] {
		env.mu.runlock()
		return val
	}
	env.mu.runlock()

	// Step 2: Check env vars (outside lock — os.getenv is a syscall)
	// Env vars have HIGHER priority than profile/default config.
	if val := env.lookup_env_var(key) {
		return val
	}

	// Steps 3-5: Check in-memory config sources under read lock
	env.mu.rlock()
	// 3. Profile config
	if val := env.profile_config_properties[key] {
		env.mu.runlock()
		return val
	}
	// 4. Default config
	if val := env.default_config_properties[key] {
		env.mu.runlock()
		return val
	}
	// 5. Programmatic properties (fallback)
	if val := env.properties[key] {
		env.mu.runlock()
		return val
	}
	env.mu.runlock()

	return none
}

// PropertyLookupResult holds the result of a priority-chain lookup,
// including the value and the source it came from.
pub struct PropertyLookupResult {
pub:
	value  string
	source PropertySourcePriority
}

// lookup_property_with_source returns both the value and the source priority
// of a property. Useful for diagnostics. Returns none if not found.
pub fn (mut env Environment) lookup_property_with_source(key string) ?PropertyLookupResult {
	// Step 1: Check CLI args (highest priority) under read lock
	env.mu.rlock()
	if val := env.cli_args[key] {
		env.mu.runlock()
		return PropertyLookupResult{
			value:  val
			source: .cli
		}
	}
	env.mu.runlock()

	// Step 2: Check env vars (outside lock — os.getenv is a syscall)
	if val := env.lookup_env_var(key) {
		return PropertyLookupResult{
			value:  val
			source: .env_var
		}
	}

	// Steps 3-5: Check in-memory config sources under read lock
	env.mu.rlock()
	// 3. Profile config
	if val := env.profile_config_properties[key] {
		env.mu.runlock()
		return PropertyLookupResult{
			value:  val
			source: .profile
		}
	}
	// 4. Default config
	if val := env.default_config_properties[key] {
		env.mu.runlock()
		return PropertyLookupResult{
			value:  val
			source: .default
		}
	}
	// 5. Programmatic properties (fallback)
	if val := env.properties[key] {
		env.mu.runlock()
		return PropertyLookupResult{
			value:  val
			source: .default
		}
	}
	env.mu.runlock()

	return none
}

// property_source returns the name of the source that provides the given key,
// or empty string if the key is not found in any source.
// Useful for debugging which source a property value came from.
pub fn (mut env Environment) property_source(key string) string {
	res := env.lookup_property_with_source(key) or { return '' }
	return res.source.str()
}

// get_property_int retrieves a property as an integer.
// Checks the full priority chain (see get_property).
pub fn (mut env Environment) get_property_int(key string) !int {
	val := env.lookup_property(key) or { return error('property "${key}" not found') }
	return val.int()
}

// get_property_int_or retrieves a property as an integer with a default.
// Checks the full priority chain (see get_property).
pub fn (mut env Environment) get_property_int_or(key string, default_val int) int {
	val := env.lookup_property(key) or { return default_val }
	return val.int()
}

// get_property_bool retrieves a property as a boolean.
// Checks the full priority chain (see get_property).
pub fn (mut env Environment) get_property_bool(key string) !bool {
	val := env.lookup_property(key) or { return error('property "${key}" not found') }
	return val.bool()
}

// get_property_bool_or retrieves a property as a boolean with a default.
// Checks the full priority chain (see get_property).
pub fn (mut env Environment) get_property_bool_or(key string, default_val bool) bool {
	val := env.lookup_property(key) or { return default_val }
	return val.bool()
}

// has_property checks if a property exists in any source (priority chain).
// Returns true if the key is found in CLI args, env vars, profile config,
// default config, or programmatic properties.
pub fn (mut env Environment) has_property(key string) bool {
	_ := env.lookup_property(key) or { return false }
	return true
}

// remove_property removes a property.
pub fn (mut env Environment) remove_property(key string) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.properties.delete(key)
}

// property_keys returns all property keys.
pub fn (mut env Environment) property_keys() []string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.properties.keys()
}

// property_count returns the number of properties.
pub fn (mut env Environment) property_count() int {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.properties.len
}

// properties_snapshot returns a thread-safe clone of all properties.
// Used by the container when building a ConditionContext during register()
// so that condition evaluators (e.g. OnPropertyCondition) can read property
// values without racing with concurrent writers.
pub fn (mut env Environment) properties_snapshot() map[string]string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.properties.clone()
}

// ── Property Placeholder Resolution ──

// resolve_placeholders resolves ${...} placeholders in a string.
// For example: "Hello ${app.name}" → "Hello PhotonAPI"
//
// Spring equivalent: PropertyPlaceholderConfigurer / PropertySourcesPlaceholderConfigurer
// Laravel equivalent: Config replacements
//
// Circular references are detected and produce an error in the resolved output
// (e.g., "${a→b→a}" when a references b which references a).
pub fn (mut env Environment) resolve_placeholders(text string) string {
	return env.resolve_placeholders_with_visited(text, []string{})
}

// resolve_placeholders_with_visited carries a visited set to detect
// circular placeholder references (e.g., ${a} → ${b} → ${a}).
fn (mut env Environment) resolve_placeholders_with_visited(text string, visited []string) string {
	mut result := text
	mut start := 0
	dollar := '$'
	open_pattern := dollar + '{'
	for {
		open_pos := result.index_after(open_pattern, start) or { break }
		close_pos := result.index_after('}', open_pos) or { break }

		placeholder := result[open_pos + 2..close_pos]
		// Support default values: ${key:default}
		parts := placeholder.split_nth(':', 2)
		key := parts[0]
		default_val := if parts.len > 1 { parts[1] } else { '' }

		// Check for circular reference
		if key in visited {
			cycle_path := visited.join('→') + '→' + key
			result = result[..open_pos] + '${cycle_path}' + result[close_pos + 1..]
			break
		}

		resolved_raw := env.get_property_or(key, default_val)
		// Recursively resolve if the value itself contains placeholders
		mut resolved := resolved_raw
		if resolved_raw.contains(open_pattern) {
			mut new_visited := visited.clone()
			new_visited << key
			resolved = env.resolve_placeholders_with_visited(resolved_raw, new_visited)
		}

		result = result[..open_pos] + resolved + result[close_pos + 1..]
		start = open_pos + resolved.len
		if start >= result.len {
			break
		}
	}
	return result
}

// ── Required Properties ──

// validate_required_properties checks that all required properties are present.
// Returns an error listing any missing keys.
//
// Spring equivalent: ConfigurablePropertyResolver.validateRequiredProperties()
pub fn (mut env Environment) validate_required_properties(keys []string) ! {
	env.mu.rlock()
	defer { env.mu.runlock() }

	mut missing := []string{}
	for key in keys {
		if key !in env.properties {
			missing << key
		}
	}
	if missing.len > 0 {
		return error('missing required properties: ${missing.join(', ')}')
	}
}

// ── Diagnostic ──

// print_environment prints the current environment state.
pub fn (mut env Environment) print_environment() {
	env.mu.rlock()
	defer { env.mu.runlock() }

	println('═══ Environment ═══')
	println('Active Profiles:  ${env.active_profiles.join(', ')}')
	println('Default Profiles:  ${env.default_profiles.join(', ')}')
	println('Properties:        ${env.properties.len}')
	for key, val in env.properties {
		println('  ${key} = ${val}')
	}
	println('═══════════════════')
}

// ── Property Source Integration ──

// add_source adds a PropertySource to the environment.
// Sources are added in order; earlier sources have lower priority.
// Use add_source_first() for higher priority sources.
//
// Spring equivalent: MutablePropertySources.addLast()
pub fn (mut env Environment) add_source(source &PropertySource) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	env.sources << unsafe { source }
}

// add_source_first adds a PropertySource at the beginning of the source list,
// giving it the highest priority (its values will be loaded last, overriding others).
//
// Spring equivalent: MutablePropertySources.addFirst()
pub fn (mut env Environment) add_source_first(source &PropertySource) {
	env.mu.@lock()
	defer { env.mu.unlock() }
	mut new_sources := []&PropertySource{}
	new_sources << unsafe { source }
	for existing in env.sources {
		new_sources << existing
	}
	env.sources = new_sources
}

// remove_source removes a PropertySource by name.
// Returns true if a source was removed.
//
// Spring equivalent: MutablePropertySources.remove()
pub fn (mut env Environment) remove_source(source_name string) bool {
	env.mu.@lock()
	defer { env.mu.unlock() }
	mut new_sources := []&PropertySource{}
	mut removed := false
	for source in env.sources {
		if !isnil(source) && source.name() == source_name {
			removed = true
			continue
		}
		new_sources << source
	}
	if removed {
		env.sources = new_sources
	}
	return removed
}

// has_source checks if a PropertySource with the given name exists.
pub fn (mut env Environment) has_source(source_name string) bool {
	env.mu.rlock()
	defer { env.mu.runlock() }
	for source in env.sources {
		if !isnil(source) && source.name() == source_name {
			return true
		}
	}
	return false
}

// source_names returns the names of all registered property sources in priority order.
pub fn (mut env Environment) source_names() []string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	mut names := []string{}
	for source in env.sources {
		if !isnil(source) {
			names << source.name()
		}
	}
	return names
}

// load_sources loads all registered property sources into the environment.
// Sources are loaded in order; later sources override earlier ones.
// Spring equivalent: PropertySourcesPlaceholderConfigurer
pub fn (mut env Environment) load_sources() ! {
	mut loaded_props := map[string]string{}
	for source in env.sources {
		if isnil(source) {
			continue
		}
		props := source.load() or {
			eprintln('[Environment] failed to load source: ${err}')
			continue
		}
		for key, value in props {
			loaded_props[key] = value
		}
	}
	// Merge into existing properties (loaded sources override existing)
	env.mu.@lock()
	for key, value in loaded_props {
		env.properties[key] = value
	}
	env.mu.unlock()
}

// source_count returns the number of registered property sources.
pub fn (mut env Environment) source_count() int {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.sources.len
}

// ── f64 Type Access ──

// get_property_f64 retrieves a property as a float64.
// Checks the full priority chain (see get_property).
pub fn (mut env Environment) get_property_f64(key string) !f64 {
	val := env.lookup_property(key) or { return error('property "${key}" not found') }
	return val.f64()
}

// get_property_f64_or retrieves a property as a float64 with a default.
// Checks the full priority chain (see get_property).
pub fn (mut env Environment) get_property_f64_or(key string, default_val f64) f64 {
	val := env.lookup_property(key) or { return default_val }
	return val.f64()
}

// ── Merged Properties (Task A4) ──

// merged_properties returns a merged view of all property sources, with
// higher-priority sources overriding lower-priority ones.
//
// Merge order (applied low → high, so high priority wins):
//   1. properties (programmatic)         — base
//   2. default_config_properties         — overrides base
//   3. profile_config_properties         — overrides default
//   4. env vars (PHOTON_*)               — overrides profile
//   5. cli_args                          — overrides all
//
// Note: env vars are NOT included in the merged map because they require
// scanning the entire process environment, which is expensive and may
// expose unrelated variables. Only explicitly-set sources are merged.
// Use get_property(key) for env var lookup.
//
// This is useful for diagnostics, exporting config, or binding to structs
// when you want a single consolidated view.
pub fn (mut env Environment) merged_properties() map[string]string {
	env.mu.rlock()
	defer { env.mu.runlock() }

	mut result := map[string]string{}

	// 5. Programmatic properties (base)
	for key, value in env.properties {
		result[key] = value
	}
	// 4. Default config (overrides base)
	for key, value in env.default_config_properties {
		result[key] = value
	}
	// 3. Profile config (overrides default)
	for key, value in env.profile_config_properties {
		result[key] = value
	}
	// 1. CLI args (highest priority, overrides all in-memory sources)
	for key, value in env.cli_args {
		result[key] = value
	}

	return result
}

// all_property_keys returns all unique property keys from all in-memory
// sources (properties, default_config, profile_config, cli_args).
// Does NOT include env var keys (which would require scanning the environment).
pub fn (mut env Environment) all_property_keys() []string {
	env.mu.rlock()
	defer { env.mu.runlock() }

	mut seen := map[string]bool{}
	mut keys := []string{}

	for key in env.properties.keys() {
		if key !in seen {
			seen[key] = true
			keys << key
		}
	}
	for key in env.default_config_properties.keys() {
		if key !in seen {
			seen[key] = true
			keys << key
		}
	}
	for key in env.profile_config_properties.keys() {
		if key !in seen {
			seen[key] = true
			keys << key
		}
	}
	for key in env.cli_args.keys() {
		if key !in seen {
			seen[key] = true
			keys << key
		}
	}

	return keys
}

// ── Nested Property Prefix Query ──

// get_by_prefix returns all properties that start with the given prefix.
// The returned map uses the full key (including prefix).
//
// Spring equivalent: Environment.getProperty("prefix.*")
// Useful for binding all "app.database.*" properties into a config struct.
//
// Example:
//   env.get_by_prefix('app.database.')
//   // Returns: { 'app.database.host': 'localhost', 'app.database.port': '5432' }
pub fn (mut env Environment) get_by_prefix(prefix string) map[string]string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	mut result := map[string]string{}
	for key, value in env.properties {
		if key.starts_with(prefix) {
			result[key] = value
		}
	}
	return result
}

// get_subtree returns all properties under a prefix, with the prefix stripped.
// This is useful for binding nested configuration into structs.
//
// Example:
//   // Properties: { 'app.db.host': 'localhost', 'app.db.port': '5432' }
//   env.get_subtree('app.db.')
//   // Returns: { 'host': 'localhost', 'port': '5432' }
pub fn (mut env Environment) get_subtree(prefix string) map[string]string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	mut result := map[string]string{}
	for key, value in env.properties {
		if key.starts_with(prefix) {
			stripped := key[prefix.len..]
			result[stripped] = value
		}
	}
	return result
}

// ── @ConfigurationProperties Support (Spring Boot inspired) ──

// contains_prefix checks if any property starts with the given prefix.
// This is useful for conditional logic that depends on the existence
// of a group of properties.
//
// Spring equivalent: @ConfigurationProperties prefix existence check
// Spring Boot equivalent: @ConditionalOnProperty(prefix = "app.database")
//
// Example:
//   // Properties: { 'app.db.host': 'localhost', 'app.db.port': '5432' }
//   env.contains_prefix('app.db.')  // → true
//   env.contains_prefix('app.cache.')  // → false
pub fn (mut env Environment) contains_prefix(prefix string) bool {
	env.mu.rlock()
	defer { env.mu.runlock() }
	for key, _ in env.properties {
		if key.starts_with(prefix) {
			return true
		}
	}
	return false
}

// prefix_count returns the number of properties that start with the given prefix.
//
// Spring equivalent: ConfigurationProperties property count
//
// Example:
//   // Properties: { 'app.db.host': 'localhost', 'app.db.port': '5432', 'app.name': 'MyApp' }
//   env.prefix_count('app.db.')  // → 2
pub fn (mut env Environment) prefix_count(prefix string) int {
	env.mu.rlock()
	defer { env.mu.runlock() }
	mut count := 0
	for key, _ in env.properties {
		if key.starts_with(prefix) {
			count++
		}
	}
	return count
}

// bind_to binds all properties with a given prefix into a target map.
// The prefix is stripped from the keys in the resulting map.
//
// Deprecated: use bind_to_struct[T] for type-safe binding to structs.
@[deprecated('use bind_to_struct[T] for type-safe binding to structs')]
@[deprecated_after: '2026-06-01']
pub fn (mut env Environment) bind_to(prefix string) !map[string]string {
	env.mu.rlock()
	defer { env.mu.runlock() }

	mut result := map[string]string{}
	mut found_any := false

	// Determine the effective prefix:
	// If prefix doesn't end with '.', and there are keys that start with prefix + '.',
	// use prefix + '.' as the effective prefix. Otherwise, use prefix as-is.
	// This ensures 'app.db' matches 'app.db.host' and strips to 'host' (not '.host').
	mut effective_prefix := prefix
	if !prefix.ends_with('.') {
		// Check if there are keys with the dotted version
		dotted_prefix := prefix + '.'
		mut has_dotted := false
		for key, _ in env.properties {
			if key.starts_with(dotted_prefix) {
				has_dotted = true
				break
			}
		}
		if has_dotted {
			effective_prefix = dotted_prefix
		}
	}

	for key, value in env.properties {
		if key.starts_with(effective_prefix) {
			stripped := key[effective_prefix.len..]
			if stripped.len > 0 {
				result[stripped] = value
				found_any = true
			}
		}
	}

	if !found_any {
		return error('no properties found with prefix "${prefix}"')
	}

	return result
}

// bind_to_with_defaults binds properties with a prefix, merging with default values.
// Properties from the environment override defaults.
//
// Spring equivalent: @ConfigurationProperties with @DefaultValue
// Laravel equivalent: config('database', $defaults)
//
// Example:
//   defaults := { 'host': 'localhost', 'port': '5432', 'timeout': '30' }
//   config := env.bind_to_with_defaults('app.db', defaults)!
//   // Environment values override defaults
pub fn (mut env Environment) bind_to_with_defaults(prefix string, defaults map[string]string) !map[string]string {
	mut result := defaults.clone()

	bound := env.bind_to(prefix) or {
		// If no properties found, just return defaults
		return result
	}

	// Override defaults with environment values
	for key, value in bound {
		result[key] = value
	}

	return result
}

// validate_prefix validates that all required sub-keys exist under a prefix.
// Returns an error listing any missing keys.
//
// Spring equivalent: @ConfigurationProperties with JSR-303 @Valid + @NotNull
// Laravel equivalent: Config::requiredKeys()
//
// Example:
//   env.validate_prefix('app.db', ['host', 'port'])!
//   // Error: "missing required properties under 'app.db': port"
pub fn (mut env Environment) validate_prefix(prefix string, required_keys []string) ! {
	env.mu.rlock()
	defer { env.mu.runlock() }

	// Determine the actual prefix (with or without trailing dot)
	actual_prefix := if prefix.ends_with('.') { prefix } else { prefix + '.' }

	mut missing := []string{}
	for key in required_keys {
		full_key := actual_prefix + key
		if full_key !in env.properties {
			missing << key
		}
	}

	if missing.len > 0 {
		return error('missing required properties under \'${prefix}\': ${missing.join(', ')}')
	}
}

// ── Type-Safe @ConfigurationProperties Binding (Spring Boot inspired) ──

// extract_config_field_key extracts the custom key from a @[config_field: 'key']
// or @[config_field('key')] attribute. Returns empty string if not present.
//
// Both attribute forms normalize to the string `config_field: 'value'` in V's
// comptime `field.attrs` list.
//
// Example:
//   struct C { host string @[config_field: 'hostname'] }
//   // extract_config_field_key(field.attrs) -> 'hostname'
pub fn extract_config_field_key(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('config_field:') {
			rest := attr['config_field:'.len..].trim_space()
			// Strip surrounding single quotes
			if rest.len >= 2 && rest[0] == `'` && rest[rest.len - 1] == `'` {
				return rest[1..rest.len - 1]
			}
			// Strip surrounding double quotes
			if rest.len >= 2 && rest[0] == `"` && rest[rest.len - 1] == `"` {
				return rest[1..rest.len - 1]
			}
			return rest
		}
	}
	return ''
}

// bind_to_struct binds all properties with a given prefix into a typed struct T.
// This is the Photon equivalent of Spring Boot's @ConfigurationProperties annotation,
// providing compile-time type-safe binding via V's comptime facilities.
//
// Supported field types:
//   - Primitive: string, int, i64, f32, f64, bool
//   - Arrays: []string, []int, []f64, []bool (comma-separated values)
//   - Nested structs: recursively bound with prefix.field_name
//
// Field attributes:
//   @[config_field: 'custom_key']  — use 'custom_key' instead of field name for lookup
//   @[config_field('custom_key')]  — alternative syntax (same effect)
//
// Fields not present in the environment remain at their zero/default values.
//
// Spring Boot equivalent: @ConfigurationProperties(prefix = "app.database")
//
// Example:
//   struct DatabaseConfig {
//       host     string
//       port     int
//       timeout  f64
//       ssl      bool
//       replicas []string
//   }
//   env.set_property('app.db.host', 'localhost')
//   env.set_property('app.db.port', '5432')
//   env.set_property('app.db.replicas', 'r1,r2,r3')
//   config := core.bind_to_struct[DatabaseConfig](env, 'app.db')!
//   // config.host == 'localhost', config.port == 5432, config.replicas == ['r1','r2','r3']
pub fn bind_to_struct[T](mut env &Environment, prefix string) !T {
	// The `&T{}` dummy instance is used for type inference of nested struct fields.
	return bind_to_struct_impl[T](mut env, prefix, &T{})
}

// bind_to_struct_impl is the internal helper that carries a `&T` dummy instance
// for recursive type inference. The `typ` parameter is only used to help V infer
// the generic type of nested struct fields via `typ.$(field.name)` — it is never
// read for its values.
//
// This pattern is inspired by V's toml/json decoder implementations.
fn bind_to_struct_impl[T](mut env &Environment, prefix string, typ &T) !T {
	mut config := T{}

	$for field in T.fields {
		// Determine the lookup key: use @[config_field] custom key if present,
		// otherwise use the field name.
		field_key := extract_config_field_key(field.attrs)
		effective_key := if field_key.len > 0 { field_key } else { field.name }

		// Build the full property key: prefix.effective_key (or just effective_key if no prefix)
		full_key := if prefix.len > 0 { '${prefix}.${effective_key}' } else { effective_key }

		// Bind based on field type — primitive types first, then arrays, then nested structs
		$if field.typ is string {
			if env.has_property(full_key) {
				config.$(field.name) = env.get_property(full_key)
			}
		} $else $if field.typ is int {
			if env.has_property(full_key) {
				config.$(field.name) = env.get_property(full_key).int()
			}
		} $else $if field.typ is i64 {
			if env.has_property(full_key) {
				config.$(field.name) = env.get_property(full_key).i64()
			}
		} $else $if field.typ is f32 {
			if env.has_property(full_key) {
				config.$(field.name) = f32(env.get_property(full_key).f64())
			}
		} $else $if field.typ is f64 {
			if env.has_property(full_key) {
				config.$(field.name) = env.get_property(full_key).f64()
			}
		} $else $if field.typ is bool {
			if env.has_property(full_key) {
				val := env.get_property(full_key)
				config.$(field.name) = val == 'true' || val == '1' || val == 'yes' || val == 'on'
			}
		} $else $if field.typ is []string {
			if env.has_property(full_key) {
				raw := env.get_property(full_key)
				if raw.len > 0 {
					mut arr := []string{}
					for part in raw.split(',') {
						arr << part.trim_space()
					}
					config.$(field.name) = arr
				}
			}
		} $else $if field.typ is []int {
			if env.has_property(full_key) {
				raw := env.get_property(full_key)
				if raw.len > 0 {
					mut arr := []int{}
					for part in raw.split(',') {
						arr << part.trim_space().int()
					}
					config.$(field.name) = arr
				}
			}
		} $else $if field.typ is []f64 {
			if env.has_property(full_key) {
				raw := env.get_property(full_key)
				if raw.len > 0 {
					mut arr := []f64{}
					for part in raw.split(',') {
						arr << part.trim_space().f64()
					}
					config.$(field.name) = arr
				}
			}
		} $else $if field.typ is []bool {
			if env.has_property(full_key) {
				raw := env.get_property(full_key)
				if raw.len > 0 {
					mut arr := []bool{}
					for part in raw.split(',') {
						p := part.trim_space()
						arr << p == 'true' || p == '1' || p == 'yes' || p == 'on'
					}
					config.$(field.name) = arr
				}
			}
		} $else $if field.is_struct {
			// Recursively bind nested struct fields.
			// The `typ.$(field.name)` trick provides V with the field's type
			// for generic type inference of the recursive call.
			// Note: `continue` is not allowed in comptime $for loops, so we use
			// `or { typ_ }` to fall back to the zero-value instance on error.
			typ_ := typ.$(field.name)
			nested := bind_to_struct_impl(mut env, full_key, &typ_) or { typ_ }
			config.$(field.name) = nested
		}
	}
	return config
}

// ── TOML Parsing Helper (Task A4) ──

// parse_toml_to_flat_map parses a TOML document string into a flat
// dot-notation key-value map. Uses V's official `toml` module.
//
// Example:
//   Input TOML:
//     [app]
//     name = "MyApp"
//     [server]
//     port = 8080
//
//   Output map:
//     { 'app.name': 'MyApp', 'server.port': '8080' }
//
// This is a self-contained implementation in `core` to avoid a dependency
// on the `config` module. The `config` module has a similar function
// (toml_doc_to_flat_map) for its own use cases.
pub fn parse_toml_to_flat_map(content string) !map[string]string {
	doc := toml.parse_text(content)!
	mut result := map[string]string{}
	any := doc.to_any()
	flatten_toml_value(any, '', mut result)
	return result
}

// flatten_toml_value recursively flattens a toml.Any value into dot-notation keys.
fn flatten_toml_value(val toml.Any, prefix string, mut result map[string]string) {
	match val {
		map[string]toml.Any {
			for key, any_val in val {
				new_key := if prefix.len > 0 { '${prefix}.${key}' } else { key }
				flatten_toml_value(any_val, new_key, mut result)
			}
		}
		[]toml.Any {
			for i, any_val in val {
				new_key := '${prefix}[${i}]'
				flatten_toml_value(any_val, new_key, mut result)
			}
		}
		string {
			if prefix.len > 0 {
				result[prefix] = val
			}
		}
		bool {
			if prefix.len > 0 {
				result[prefix] = if val { 'true' } else { 'false' }
			}
		}
		int, i64, u64, f32, f64 {
			if prefix.len > 0 {
				result[prefix] = val.str()
			}
		}
		else {
			// DateTime, Date, Time, Null — use str()
			if prefix.len > 0 {
				result[prefix] = val.str()
			}
		}
	}
}

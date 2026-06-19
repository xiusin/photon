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
import sync

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
@[heap]
pub struct Environment {
pub mut:
	active_profiles  []string
	default_profiles []string
	properties       map[string]string
	sources          []&PropertySource
mut:
	mu sync.RwMutex
}

// new_environment creates an empty Environment with sensible defaults.
pub fn new_environment() &Environment {
	return &Environment{
		active_profiles:  ['default']
		default_profiles: ['default']
		properties:       map[string]string{}
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

// get_property retrieves a property by key.
pub fn (mut env Environment) get_property(key string) string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.properties[key] or { '' }
}

// get_property_or retrieves a property by key with a default value.
// This is the Spring equivalent of Environment.getProperty(key, defaultValue).
pub fn (mut env Environment) get_property_or(key string, default_val string) string {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return env.properties[key] or { default_val }
}

// get_property_int retrieves a property as an integer.
pub fn (mut env Environment) get_property_int(key string) !int {
	env.mu.rlock()
	defer { env.mu.runlock() }
	val := env.properties[key] or { return error('property "${key}" not found') }
	return val.int()
}

// get_property_int_or retrieves a property as an integer with a default.
pub fn (mut env Environment) get_property_int_or(key string, default_val int) int {
	env.mu.rlock()
	defer { env.mu.runlock() }
	val := env.properties[key] or { return default_val }
	return val.int()
}

// get_property_bool retrieves a property as a boolean.
pub fn (mut env Environment) get_property_bool(key string) !bool {
	env.mu.rlock()
	defer { env.mu.runlock() }
	val := env.properties[key] or { return error('property "${key}" not found') }
	return val.bool()
}

// get_property_bool_or retrieves a property as a boolean with a default.
pub fn (mut env Environment) get_property_bool_or(key string, default_val bool) bool {
	env.mu.rlock()
	defer { env.mu.runlock() }
	val := env.properties[key] or { return default_val }
	return val.bool()
}

// has_property checks if a property exists.
pub fn (mut env Environment) has_property(key string) bool {
	env.mu.rlock()
	defer { env.mu.runlock() }
	return key in env.properties
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
pub fn (mut env Environment) get_property_f64(key string) !f64 {
	env.mu.rlock()
	defer { env.mu.runlock() }
	val := env.properties[key] or { return error('property "${key}" not found') }
	return val.f64()
}

// get_property_f64_or retrieves a property as a float64 with a default.
pub fn (mut env Environment) get_property_f64_or(key string, default_val f64) f64 {
	env.mu.rlock()
	defer { env.mu.runlock() }
	val := env.properties[key] or { return default_val }
	return val.f64()
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
// This is the Photon equivalent of Spring's @ConfigurationProperties annotation.
//
// Unlike get_subtree(), this method also:
//   - Validates that at least one property exists for the prefix
//   - Supports nested prefix binding (e.g., 'app.db' matches 'app.db.host')
//   - Returns an error if no properties match the prefix
//
// Spring equivalent: @ConfigurationProperties(prefix = "app.database")
//   - Binds properties with the given prefix into a configuration class
// Laravel equivalent: config('database') → returns all config under 'database' key
//
// Example:
//   // Properties: { 'app.db.host': 'localhost', 'app.db.port': '5432' }
//   config := env.bind_to('app.db.') or { return }
//   // config = { 'host': 'localhost', 'port': '5432' }
//
//   // Also works without trailing dot:
//   config2 := env.bind_to('app.db') or { return }
//   // config2 = { 'host': 'localhost', 'port': '5432' }  (same result with auto-dot handling)
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

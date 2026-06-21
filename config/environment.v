module config

// environment.v - Environment Abstraction (Spring Environment inspired)
//
// Provides unified property access across multiple property sources,
// active profile management, and placeholder resolution.

// PropertySource is a source of configuration properties
pub interface PropertySource {
	name() string
	get_property(key string) ?string
	contains_property(key string) bool
}

// Environment provides unified property access
pub struct Environment {
pub mut:
	property_sources []&PropertySource
	active_profiles  []string
}

// new_environment creates an Environment
pub fn new_environment() &Environment {
	return &Environment{}
}

// add_source registers a property source
pub fn (mut e Environment) add_source(source &PropertySource) {
	e.property_sources << source
}

// add_profile activates a profile
pub fn (mut e Environment) add_profile(profile string) {
	e.active_profiles << profile
}

// set_profiles replaces all active profiles
pub fn (mut e Environment) set_profiles(profiles []string) {
	e.active_profiles = profiles.clone()
}

// get_active_profiles returns active profiles
pub fn (e &Environment) get_active_profiles() []string {
	return e.active_profiles.clone()
}

// accepts_profile checks if a profile is active
pub fn (e &Environment) accepts_profile(profile string) bool {
	return profile in e.active_profiles
}

// get_property retrieves a property from any source
pub fn (e &Environment) get_property(key string) ?string {
	// Check sources in reverse order (last added = highest priority)
	mut i := e.property_sources.len
	for i > 0 {
		i--
		source := e.property_sources[i]
		if val := source.get_property(key) {
			return val
		}
	}
	return none
}

// get_property_or retrieves a property with default
pub fn (e &Environment) get_property_or(key string, default_val string) string {
	val := e.get_property(key) or { return default_val }
	return val
}

// contains_property checks if any source has the property
pub fn (e &Environment) contains_property(key string) bool {
	for source in e.property_sources {
		if source.contains_property(key) {
			return true
		}
	}
	return false
}

// resolve_placeholders replaces ${key} with property values
pub fn (e &Environment) resolve_placeholders(value string) string {
	placeholder := '\${'
	if !value.contains(placeholder) {
		return value
	}
	pos := value.index(placeholder) or { return value }
	after := value[pos + 2..]
	end := after.index('}') or { return value[..pos] + after }
	key := after[..end]
	replacement := e.get_property(key) or { return value[..pos] + after[end + 1..] }
	return value[..pos] + replacement + after[end + 1..]
}

// has_any_profile checks if any profile is active
pub fn (e &Environment) has_any_profile() bool {
	return e.active_profiles.len > 0
}

// is_production checks if 'prod' or 'production' profile is active
pub fn (e &Environment) is_production() bool {
	return e.accepts_profile('prod') || e.accepts_profile('production')
}

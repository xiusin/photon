module config

// source.v - Configuration Source Implementations
//
// Provides various config sources: file-based, environment variables,
// and programmatic defaults.
//
// Each source implements both ConfigSource (for Config.load()) and
// PropertySource (for Environment's property resolution).
// Both interfaces use mut receivers for their methods to support
// lazy loading of property data from external sources.
import os
import json

// FileConfigSource loads configuration from a file (JSON or properties format)
pub struct FileConfigSource {
	filepath string
mut:
	cached map[string]string
	loaded bool
}

// new_file_config_source creates a FileConfigSource.
pub fn new_file_config_source(filepath string) &FileConfigSource {
	return &FileConfigSource{
		filepath: filepath
	}
}

pub fn (s FileConfigSource) name() string {
	return 'file:${s.filepath}'
}

pub fn (mut s FileConfigSource) load() !map[string]string {
	content := os.read_file(s.filepath)!
	mut result := map[string]string{}

	if s.filepath.ends_with('.json') {
		// Parse JSON config
		parsed := json.decode(map[string]string, content) or {
			return error('failed to parse JSON config: ${err}')
		}
		for key, val in parsed {
			result[key] = val
		}
	} else {
		// Parse key=value properties format
		lines := content.split_into_lines()
		for line in lines {
			trimmed := line.trim_space()
			if trimmed.len == 0 || trimmed.starts_with('#') || trimmed.starts_with('//') {
				continue
			}
			parts := trimmed.split_nth('=', 1)
			if parts.len == 2 {
				key := parts[0].trim_space()
				value := parts[1].trim_space()
				result[key] = value
			}
		}
	}

	return result
}

// ensure_loaded lazily loads the config data if not already loaded.
fn (mut s FileConfigSource) ensure_loaded() {
	if !s.loaded {
		s.cached = s.load() or { map[string]string{} }
		s.loaded = true
	}
}

// get_property retrieves a property by key from the loaded config.
// Note: This method uses a mut receiver internally for lazy loading,
// but is not part of the PropertySource interface.
pub fn (mut s FileConfigSource) get_property(key string) ?string {
	s.ensure_loaded()
	if key in s.cached {
		return s.cached[key]
	}
	return none
}

// contains_property checks if a key exists in the loaded config.
pub fn (mut s FileConfigSource) contains_property(key string) bool {
	s.ensure_loaded()
	return key in s.cached
}

// get_all_with_prefix returns all properties with the given prefix.
pub fn (mut s FileConfigSource) get_all_with_prefix(prefix string) map[string]string {
	s.ensure_loaded()
	mut result := map[string]string{}
	for key, value in s.cached {
		if key.starts_with(prefix) {
			result[key] = value
		}
	}
	return result
}

// EnvConfigSource loads configuration from environment variables
pub struct EnvConfigSource {
pub:
	prefix string // e.g., "APP_" to filter environment variables
mut:
	cached map[string]string
	loaded bool
}

// new_env_config_source creates an EnvConfigSource.
pub fn new_env_config_source(prefix string) &EnvConfigSource {
	return &EnvConfigSource{
		prefix: prefix
	}
}

pub fn (s EnvConfigSource) name() string {
	return 'env'
}

pub fn (mut s EnvConfigSource) load() !map[string]string {
	if s.loaded {
		return s.cached.clone()
	}
	mut result := map[string]string{}
	env_vars := os.environ()

	for _, env_var in env_vars {
		if s.prefix.len > 0 && !env_var.starts_with(s.prefix) {
			continue
		}
		parts := env_var.split_nth('=', 1)
		if parts.len == 2 {
			mut key := parts[0]
			if s.prefix.len > 0 {
				key = key[s.prefix.len..]
			}
			result[key.to_lower()] = parts[1]
		}
	}

	s.cached = result.clone()
	s.loaded = true
	return s.cached.clone()
}

// ensure_loaded lazily loads the env data if not already loaded.
fn (mut s EnvConfigSource) ensure_loaded() {
	if !s.loaded {
		s.load() or {}
	}
}

// get_property retrieves an environment variable as a property.
pub fn (mut s EnvConfigSource) get_property(key string) ?string {
	s.ensure_loaded()
	if key in s.cached {
		return s.cached[key]
	}
	return none
}

// contains_property checks if an environment variable key exists.
pub fn (mut s EnvConfigSource) contains_property(key string) bool {
	s.ensure_loaded()
	return key in s.cached
}

// get_all_with_prefix returns all env properties with the given prefix.
pub fn (mut s EnvConfigSource) get_all_with_prefix(prefix string) map[string]string {
	s.ensure_loaded()
	mut result := map[string]string{}
	for key, value in s.cached {
		if key.starts_with(prefix) {
			result[key] = value
		}
	}
	return result
}

// MapConfigSource loads configuration from an in-memory map (useful for defaults)
pub struct MapConfigSource {
pub mut:
	data map[string]string
}

pub fn (s MapConfigSource) name() string {
	return 'map'
}

pub fn (mut s MapConfigSource) load() !map[string]string {
	return s.data.clone()
}

// get_property retrieves a property from the in-memory map.
pub fn (s MapConfigSource) get_property(key string) ?string {
	if key in s.data {
		return s.data[key]
	}
	return none
}

// contains_property checks if a key exists in the map.
pub fn (s MapConfigSource) contains_property(key string) bool {
	return key in s.data
}

// get_all_with_prefix returns all map properties with the given prefix.
pub fn (s MapConfigSource) get_all_with_prefix(prefix string) map[string]string {
	mut result := map[string]string{}
	for key, value in s.data {
		if key.starts_with(prefix) {
			result[key] = value
		}
	}
	return result
}

// MapPropertySource wraps a map[string]string as a PropertySource.
// This is useful for creating property sources from programmatic data
// that can be used with the Environment's property resolution.
pub struct MapPropertySource {
pub:
	source_name string
	data        map[string]string
}

// new_map_property_source creates a MapPropertySource with the given name and data.
pub fn new_map_property_source(name string, data map[string]string) &MapPropertySource {
	return &MapPropertySource{
		source_name: name
		data:        data
	}
}

pub fn (s MapPropertySource) name() string {
	return s.source_name
}

pub fn (s MapPropertySource) get_property(key string) ?string {
	if key in s.data {
		return s.data[key]
	}
	return none
}

pub fn (s MapPropertySource) contains_property(key string) bool {
	return key in s.data
}

pub fn (s MapPropertySource) get_all_with_prefix(prefix string) map[string]string {
	mut result := map[string]string{}
	for key, value in s.data {
		if key.starts_with(prefix) {
			result[key] = value
		}
	}
	return result
}

// ConfigPropertySourceAdapter adapts a Config instance to implement PropertySource.
// This allows a Config to be used as a property source in the Environment.
pub struct ConfigPropertySourceAdapter {
pub:
	config &Config
}

// new_config_property_source creates a PropertySource adapter for a Config.
pub fn new_config_property_source(cfg &Config) &ConfigPropertySourceAdapter {
	return &ConfigPropertySourceAdapter{
		config: unsafe { cfg }
	}
}

pub fn (s ConfigPropertySourceAdapter) name() string {
	return 'config_adapter'
}

pub fn (s ConfigPropertySourceAdapter) get_property(key string) ?string {
	val := s.config.get(key)
	if val.len == 0 && !s.config.has(key) {
		return none
	}
	return val
}

pub fn (s ConfigPropertySourceAdapter) contains_property(key string) bool {
	return s.config.has(key)
}

pub fn (s ConfigPropertySourceAdapter) get_all_with_prefix(prefix string) map[string]string {
	mut result := map[string]string{}
	for key in s.config.keys() {
		if key.starts_with(prefix) {
			result[key] = s.config.get(key)
		}
	}
	return result
}

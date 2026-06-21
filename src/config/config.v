module config

// config.v - Photon Config Module
//
// Provides a unified configuration system supporting multiple sources
// (files, environment variables, command-line flags) with property binding
// and profile-based configuration.
import json

// Config manages application configuration from multiple sources
pub struct Config {
pub mut:
	sources    []ConfigSource
	properties map[string]string
	profiles   []string
	loaded     bool
}

// ConfigSource is a trait for configuration sources
pub interface ConfigSource {
	load() !map[string]string
	name() string
}

// new creates a new Config instance
pub fn new() &Config {
	return &Config{
		properties: map[string]string{}
	}
}

// add_source adds a configuration source
pub fn (mut c Config) add_source(source ConfigSource) {
	c.sources << source
}

// set_profile sets active profile(s)
pub fn (mut c Config) set_profile(profiles []string) {
	c.profiles = profiles
}

// add_profile adds a profile
pub fn (mut c Config) add_profile(profile string) {
	c.profiles << profile
}

// load loads all configuration sources and merges properties
pub fn (mut c Config) load() ! {
	for source in c.sources {
		props := source.load()!
		for key, value in props {
			c.properties[key] = value
		}
	}
	c.loaded = true
}

// get returns a configuration value by key
pub fn (c &Config) get(key string) string {
	return c.properties[key] or { '' }
}

// get_or returns a configuration value or default
pub fn (c &Config) get_or(key string, default_val string) string {
	return c.properties[key] or { default_val }
}

// get_int returns a configuration value as int
pub fn (c &Config) get_int(key string) !int {
	val := c.properties[key] or { return error('config key "${key}" not found') }
	return val.int()
}

// get_int_or returns a configuration value as int or default
pub fn (c &Config) get_int_or(key string, default_val int) int {
	val := c.properties[key] or { return default_val }
	return val.int()
}

// get_bool returns a configuration value as bool
pub fn (c &Config) get_bool(key string) !bool {
	val := c.properties[key] or { return error('config key "${key}" not found') }
	return val.bool()
}

// get_bool_or returns a configuration value as bool or default
pub fn (c &Config) get_bool_or(key string, default_val bool) bool {
	val := c.properties[key] or { return default_val }
	return val.bool()
}

// get_f64 returns a configuration value as f64
pub fn (c &Config) get_f64(key string) !f64 {
	val := c.properties[key] or { return error('config key "${key}" not found') }
	return val.f64()
}

// set sets a configuration value
pub fn (mut c Config) set(key string, value string) {
	c.properties[key] = value
}

// keys returns all configuration keys
pub fn (c &Config) keys() []string {
	return c.properties.keys()
}

// has checks if a key exists
pub fn (c &Config) has(key string) bool {
	return key in c.properties
}

// to_json returns all properties as JSON string
pub fn (c &Config) to_json() string {
	return json.encode(c.properties)
}

module config

// config.v - Photon Config Module
//
// Provides a unified configuration system supporting multiple sources
// (files, environment variables, command-line flags) with property binding
// and profile-based configuration.
import x.json2
import sync

// Config manages application configuration from multiple sources
// @[heap]: the fluent setters return &Config for chaining, and V 0.5.2
// refuses to hand out a pointer to a stack object.
@[heap]
pub struct Config {
pub mut:
	sources    []ConfigSource
	properties map[string]string
	profiles   []string
	loaded     bool
mut:
	mu sync.RwMutex
}

// ConfigSource is a trait for configuration sources
pub interface ConfigSource {
	name() string
mut:
	load() !map[string]string
}

// new creates a new Config instance
pub fn new() &Config {
	return &Config{
		properties: map[string]string{}
	}
}

// add_source adds a configuration source. Returns &Config for chaining.
pub fn (mut c Config) add_source(source ConfigSource) &Config {
	c.mu.@lock()
	defer { c.mu.unlock() }
	c.sources << source
	return c
}

// set_profile sets active profile(s). Returns &Config for chaining.
pub fn (mut c Config) set_profile(profiles []string) &Config {
	c.mu.@lock()
	defer { c.mu.unlock() }
	c.profiles = profiles
	return c
}

// add_profile adds a profile. Returns &Config for chaining.
pub fn (mut c Config) add_profile(profile string) &Config {
	c.mu.@lock()
	defer { c.mu.unlock() }
	c.profiles << profile
	return c
}

// load loads all configuration sources and merges properties. Returns &Config for chaining.
pub fn (mut c Config) load() !&Config {
	c.mu.@lock()
	defer { c.mu.unlock() }
	for mut source in c.sources {
		props := source.load()!
		for key, value in props {
			c.properties[key] = value
		}
	}
	c.loaded = true
	return c
}

// get returns a configuration value by key
pub fn (c &Config) get(key string) string {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	return c.properties[key] or { '' }
}

// get_or returns a configuration value or default
pub fn (c &Config) get_or(key string, default_val string) string {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	return c.properties[key] or { default_val }
}

// get_int returns a configuration value as int
pub fn (c &Config) get_int(key string) !int {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	val := c.properties[key] or { return error('config key "${key}" not found') }
	return val.int()
}

// get_int_or returns a configuration value as int or default
pub fn (c &Config) get_int_or(key string, default_val int) int {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	val := c.properties[key] or { return default_val }
	return val.int()
}

// get_bool returns a configuration value as bool
pub fn (c &Config) get_bool(key string) !bool {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	val := c.properties[key] or { return error('config key "${key}" not found') }
	return parse_config_bool(val)
}

// get_bool_or returns a configuration value as bool or default
pub fn (c &Config) get_bool_or(key string, default_val bool) bool {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	val := c.properties[key] or { return default_val }
	return parse_config_bool(val)
}

// get_f64 returns a configuration value as f64
pub fn (c &Config) get_f64(key string) !f64 {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	val := c.properties[key] or { return error('config key "${key}" not found') }
	return val.f64()
}

// parse_config_bool 把配置里的布尔字面量解析成 bool。
//
// 不能用 `val.bool()`：V 的实现只认 `'true'` 和 `'t'`，于是
// `debug = false` / `debug = 0` / `debug = off` / `debug = no` 全部被读成
// **true** —— 生产配置里把开关关掉，程序反而打开了它，而且不报任何错。
// 空值按「未设置」处理，沿用 V 的默认 false；无法识别的字面量同样为 false
// （与 Spring 的 Boolean.parseBoolean 对齐）。
pub fn parse_config_bool(val string) bool {
	v := val.trim_space().to_lower()
	return match v {
		'true', 't', '1', 'yes', 'y', 'on' { true }
		else { false }
	}
}

// set sets a configuration value
pub fn (mut c Config) set(key string, value string) {
	c.mu.@lock()
	defer { c.mu.unlock() }
	c.properties[key] = value
}

// keys returns all configuration keys
pub fn (c &Config) keys() []string {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	return c.properties.keys()
}

// has checks if a key exists
pub fn (c &Config) has(key string) bool {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	return key in c.properties
}

// to_json returns all properties as JSON string
pub fn (c &Config) to_json() string {
	mut cm := unsafe { &Config(c) }
	cm.mu.@rlock()
	defer { cm.mu.runlock() }
	return json2.encode(c.properties)
}

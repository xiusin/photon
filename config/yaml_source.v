module config

// yaml_source.v - YAML/TOML Configuration Source
//
// Provides configuration loading from YAML and TOML files.
// YAML is the most popular config format (Spring Boot, Laravel).
// TOML is the standard for V/Go projects.
//
// NOTE: TOML parsing uses a lightweight string-based parser instead of V's
// official `toml` module. This is because V 0.5.1's C backend generates invalid
// C function names for `toml.Any` sum type (which contains `map[string]toml.Any`
// and `[]toml.Any`), causing C compilation errors.
//
// YAML parsing uses a built-in lightweight parser that supports
// the most common YAML patterns (no V official YAML module exists).
//
// Profile-specific config:
//   application.yml          — default config
//   application-dev.yml      — dev profile overrides
//   application-prod.yml     — prod profile overrides
//   application-{profile}.yml — any profile
//
// Usage:
//   env := config.new_environment()
//   env.add_source(config.new_yaml_source('config/app.yaml'))!
//   env.add_source(config.new_toml_source('config/app.toml'))!
//   env.add_source(config.new_env_source('APP_'))
//
//   db_host := mgr.get('database.host') or { 'localhost' }
import os
import strconv

// ascii_str converts a byte to a string (helper for TOML parsing)
fn ascii_str(ch u8) string {
	return unsafe { strconv.v_sprintf('%c', ch) }
}

// ── YamlConfigSource ──

// YamlConfigSource loads configuration from a YAML file.
// Implements both ConfigSource and PropertySource interfaces.
pub struct YamlConfigSource {
pub:
	filepath string
	profile  string // optional profile suffix (e.g., 'dev', 'prod')
mut:
	cached map[string]string
	loaded bool
}

// new_yaml_source creates a YamlConfigSource.
pub fn new_yaml_source(filepath string) &YamlConfigSource {
	return &YamlConfigSource{
		filepath: filepath
	}
}

// new_yaml_source_with_profile creates a YamlConfigSource for a specific profile.
// The profile is used for identification purposes; the filepath should already
// include the profile suffix (e.g., 'config/application-dev.yml').
pub fn new_yaml_source_with_profile(filepath string, profile string) &YamlConfigSource {
	return &YamlConfigSource{
		filepath: filepath
		profile:  profile
	}
}

// new_profile_yaml_source creates a YamlConfigSource for a profile-specific file.
// Given a base path like 'config/application.yml' and a profile like 'dev',
// it constructs the path 'config/application-dev.yml'.
//
// Spring Boot equivalent: application-{profile}.yml
pub fn new_profile_yaml_source(base_path string, profile string) &YamlConfigSource {
	// Replace .yml/.yaml extension with -{profile}.yml/.yaml
	mut filepath := base_path
	if base_path.ends_with('.yml') {
		filepath = base_path[..base_path.len - 4] + '-${profile}.yml'
	} else if base_path.ends_with('.yaml') {
		filepath = base_path[..base_path.len - 5] + '-${profile}.yaml'
	} else {
		filepath = base_path + '-${profile}'
	}
	return &YamlConfigSource{
		filepath: filepath
		profile:  profile
	}
}

// name returns the source name.
pub fn (s YamlConfigSource) name() string {
	if s.profile.len > 0 {
		return 'yaml:${s.filepath} (profile:${s.profile})'
	}
	return 'yaml:${s.filepath}'
}

// load reads and parses a YAML file into a flat key-value map.
pub fn (mut s YamlConfigSource) load() !map[string]string {
	if s.loaded {
		return s.cached.clone()
	}
	if !os.exists(s.filepath) {
		return map[string]string{}
	}
	content := os.read_file(s.filepath)!
	result := parse_yaml(content)!
	s.cached = result.clone()
	s.loaded = true
	return result
}

// get_property retrieves a property by key from the loaded YAML config.
// Implements PropertySource interface.
pub fn (mut s YamlConfigSource) get_property(key string) ?string {
	if !s.loaded {
		s.cached = s.load() or { map[string]string{} }
		s.loaded = true
	}
	// Try exact key first
	if key in s.cached {
		return s.cached[key]
	}
	// Try with dot notation (app.database.host → app.database.host)
	// Also try colon notation (app.database.host → app:database:host)
	colon_key := key.replace('.', ':')
	if colon_key in s.cached {
		return s.cached[colon_key]
	}
	return none
}

// contains_property checks if a key exists in the loaded YAML config.
// Implements PropertySource interface.
pub fn (mut s YamlConfigSource) contains_property(key string) bool {
	if !s.loaded {
		s.cached = s.load() or { map[string]string{} }
		s.loaded = true
	}
	if key in s.cached {
		return true
	}
	colon_key := key.replace('.', ':')
	return colon_key in s.cached
}

// get_all_with_prefix returns all properties with the given prefix.
// Implements PropertySource interface.
pub fn (mut s YamlConfigSource) get_all_with_prefix(prefix string) map[string]string {
	if !s.loaded {
		s.cached = s.load() or { map[string]string{} }
		s.loaded = true
	}
	mut result := map[string]string{}
	// Try with dot-notation prefix
	for key, value in s.cached {
		if key.starts_with(prefix) {
			result[key] = value
		}
	}
	// Also try with colon-notation prefix
	colon_prefix := prefix.replace('.', ':')
	if colon_prefix != prefix {
		for key, value in s.cached {
			if key.starts_with(colon_prefix) {
				// Convert colon key back to dot notation for consistency
				dot_key := key.replace(':', '.')
				result[dot_key] = value
			}
		}
	}
	return result
}

// ── TomlConfigSource ──

// TomlConfigSource loads configuration from a TOML file.
// Uses V's official `toml` standard library for full TOML 1.0 support.
// Implements both ConfigSource and PropertySource interfaces.
pub struct TomlConfigSource {
pub:
	filepath string
	profile  string // optional profile suffix
mut:
	cached map[string]string
	loaded bool
}

// new_toml_source creates a TomlConfigSource.
pub fn new_toml_source(filepath string) &TomlConfigSource {
	return &TomlConfigSource{
		filepath: filepath
	}
}

// new_toml_source_with_profile creates a TomlConfigSource for a specific profile.
pub fn new_toml_source_with_profile(filepath string, profile string) &TomlConfigSource {
	return &TomlConfigSource{
		filepath: filepath
		profile:  profile
	}
}

// new_profile_toml_source creates a TomlConfigSource for a profile-specific file.
// Given a base path like 'config/application.toml' and a profile like 'dev',
// it constructs the path 'config/application-dev.toml'.
//
// Spring Boot equivalent: application-{profile}.toml
pub fn new_profile_toml_source(base_path string, profile string) &TomlConfigSource {
	mut filepath := base_path
	if base_path.ends_with('.toml') {
		filepath = base_path[..base_path.len - 5] + '-${profile}.toml'
	} else {
		filepath = base_path + '-${profile}'
	}
	return &TomlConfigSource{
		filepath: filepath
		profile:  profile
	}
}

// name returns the source name.
pub fn (s TomlConfigSource) name() string {
	if s.profile.len > 0 {
		return 'toml:${s.filepath} (profile:${s.profile})'
	}
	return 'toml:${s.filepath}'
}

// load reads and parses a TOML file into a flat key-value map.
// Uses lightweight string-based parser to avoid V 0.5.1 C backend issues.
pub fn (mut s TomlConfigSource) load() !map[string]string {
	if s.loaded {
		return s.cached.clone()
	}
	if !os.exists(s.filepath) {
		return map[string]string{}
	}
	content := os.read_file(s.filepath)!
	result := parse_toml_lightweight(content)
	s.cached = result.clone()
	s.loaded = true
	return result
}

// get_property retrieves a property by key from the loaded TOML config.
// Implements PropertySource interface.
pub fn (mut s TomlConfigSource) get_property(key string) ?string {
	if !s.loaded {
		s.cached = s.load() or { map[string]string{} }
		s.loaded = true
	}
	if key in s.cached {
		return s.cached[key]
	}
	return none
}

// contains_property checks if a key exists in the loaded TOML config.
// Implements PropertySource interface.
pub fn (mut s TomlConfigSource) contains_property(key string) bool {
	if !s.loaded {
		s.cached = s.load() or { map[string]string{} }
		s.loaded = true
	}
	return key in s.cached
}

// get_all_with_prefix returns all properties with the given prefix.
// Implements PropertySource interface.
pub fn (mut s TomlConfigSource) get_all_with_prefix(prefix string) map[string]string {
	if !s.loaded {
		s.cached = s.load() or { map[string]string{} }
		s.loaded = true
	}
	mut result := map[string]string{}
	for key, value in s.cached {
		if key.starts_with(prefix) {
			result[key] = value
		}
	}
	return result
}

// ── Profile-Aware Config Loading ──

// load_yaml_with_profiles loads a base YAML config and then overlays
// profile-specific configs on top. Properties from profile configs
// override the base config.
//
// The base file is loaded first, then each profile file is loaded in order.
// Later profiles override earlier ones.
//
// Spring Boot equivalent: application.yml + application-dev.yml
//
// Example:
//   props := config.load_yaml_with_profiles('config/application.yml', ['dev'])!
pub fn load_yaml_with_profiles(base_path string, profiles []string) !map[string]string {
	mut result := map[string]string{}

	// Load base config
	if os.exists(base_path) {
		base := parse_yaml(os.read_file(base_path)!)!
		for key, value in base {
			result[key] = value
		}
	}

	// Load profile configs (later profiles override earlier ones)
	for profile in profiles {
		profile_path := build_profile_path(base_path, profile, 'yml')
		if os.exists(profile_path) {
			profile_props := parse_yaml(os.read_file(profile_path)!)!
			for key, value in profile_props {
				result[key] = value
			}
		}
	}

	return result
}

// load_toml_with_profiles loads a base TOML config and then overlays
// profile-specific configs on top. Properties from profile configs
// override the base config.
//
// Spring Boot equivalent: application.toml + application-dev.toml
//
// Example:
//   props := config.load_toml_with_profiles('config/application.toml', ['dev'])!
pub fn load_toml_with_profiles(base_path string, profiles []string) !map[string]string {
	mut result := map[string]string{}

	// Load base config
	if os.exists(base_path) {
		content := os.read_file(base_path)!
		base := parse_toml_lightweight(content)
		for key, value in base {
			result[key] = value
		}
	}

	// Load profile configs (later profiles override earlier ones)
	for profile in profiles {
		profile_path := build_profile_path(base_path, profile, 'toml')
		if os.exists(profile_path) {
			profile_content := os.read_file(profile_path)!
			profile_props := parse_toml_lightweight(profile_content)
			for key, value in profile_props {
				result[key] = value
			}
		}
	}

	return result
}

// build_profile_path constructs a profile-specific config file path.
// Given 'config/application.yml' and profile 'dev', returns 'config/application-dev.yml'.
fn build_profile_path(base_path string, profile string, ext string) string {
	mut path := base_path
	ext_dot := '.${ext}'
	if path.ends_with(ext_dot) {
		path = path[..path.len - ext_dot.len] + '-${profile}${ext_dot}'
	} else {
		path = path + '-${profile}'
	}
	return path
}

// ── YAML Parser (lightweight, built-in) ──

// parse_yaml parses a simplified YAML document into a flat map.
// This is a lightweight parser that supports the most common YAML patterns:
//   - key: value
//   - nested.key: value (via indentation)
//   - list items (- value)
//   - Comments (#)
//   - Quoted strings
//
// The resulting map uses dot-notation keys (e.g., 'app.database.host').
// Both dot-notation and colon-notation keys are stored for compatibility:
//   'app.database.host' AND 'app:database:host'
pub fn parse_yaml(content string) !map[string]string {
	mut result := map[string]string{}
	mut key_stack := []string{}
	mut list_indices := map[string]int{}
	mut prev_indent := 0

	lines := content.split_into_lines()
	for line in lines {
		trimmed := line.trim_space()

		// Skip empty lines and comments
		if trimmed.len == 0 || trimmed.starts_with('#') || trimmed == '---' || trimmed == '...' {
			continue
		}

		// Calculate indentation
		mut indent := 0
		for ch in line {
			if ch == ` ` {
				indent++
			} else if ch == `\t` {
				indent += 2
			} else {
				break
			}
		}

		// Adjust key stack based on indentation
		indent_level := indent / 2
		if indent_level < prev_indent {
			// Pop keys from stack
			for key_stack.len > indent_level {
				key_stack.delete(key_stack.len - 1)
			}
		}
		prev_indent = indent_level

		// Check for list item
		if trimmed.starts_with('- ') {
			list_value := trimmed[2..].trim_space()

			// Determine the list key
			list_key := key_stack.join('.')
			idx := list_indices[list_key] or { 0 }
			list_indices[list_key] = idx + 1

			// Handle inline dict in list: - key: value
			if list_value.contains(': ') {
				parts := list_value.split_nth(': ', 2)
				sub_key := parts[0].trim_space()
				sub_val := parts[1].trim_space()
				full_key := '${list_key}[${idx}].${sub_key}'
				result[full_key] = clean_yaml_value(sub_val)
			} else {
				full_key := '${list_key}[${idx}]'
				result[full_key] = clean_yaml_value(list_value)
			}
			continue
		}

		// Parse key: value
		if trimmed.contains(': ') {
			parts := trimmed.split_nth(': ', 2)
			key := parts[0].trim_space()
			value := parts[1].trim_space()

			// Push key onto stack
			key_stack << key

			if value.len > 0 && value != '|' && value != '>' {
				// Leaf value — store with dot-notation key
				full_key := key_stack.join('.')
				result[full_key] = clean_yaml_value(value)
				// Also store with colon-notation key for compatibility
				// (some systems use 'app:database:host' instead of 'app.database.host')
				colon_key := key_stack.join(':')
				if colon_key != full_key {
					result[colon_key] = clean_yaml_value(value)
				}
				// Pop immediately since this is a leaf
				key_stack.delete(key_stack.len - 1)
			}
			// If value is empty or a block indicator, key stays on stack for nesting
		} else if trimmed.ends_with(':') && !trimmed.contains(': ') {
			// Key with no value (parent key for nesting)
			key := trimmed[..trimmed.len - 1].trim_space()
			key_stack << key
		}
	}

	return result
}

// clean_yaml_value cleans a YAML value string.
fn clean_yaml_value(value string) string {
	mut v := value.trim_space()

	// Remove inline comments (but not inside quoted strings)
	if !v.starts_with('"') && !v.starts_with("'") {
		if comment_idx := v.index('#') {
			v = v[..comment_idx].trim_space()
		}
	}

	// Remove quotes
	if (v.starts_with('"') && v.ends_with('"')) || (v.starts_with("'") && v.ends_with("'")) {
		v = v[1..v.len - 1]
	}

	// Convert YAML booleans and null
	return match v.to_lower() {
		'true' { 'true' }
		'false' { 'false' }
		'null', '~', '' { '' }
		else { v }
	}
}

// ── TOML Helpers (lightweight string-based parser) ──
//
// NOTE: V 0.5.1 的 C 后端在为 `map[string]toml.Any` 和 `[]toml.Any` 等复杂嵌套泛型类型
// 生成 `_v_type_idx_` 函数时会产生无效的 C 函数名（含 `[string]`），导致 C 编译失败。
// 因此不能使用 V 标准库的 `toml` 模块（它使用了 `toml.Any` sum type）。
// 改用轻量级的字符串解析方案，支持常见的 TOML 配置模式。

// parse_toml parses a TOML document string into a flat key-value map.
// Uses a lightweight string-based parser that supports the most common TOML patterns:
//   - key = value (string, number, bool, datetime)
//   - [section] headers for nesting
//   - inline tables { key = value }
//   - arrays [value1, value2]
pub fn parse_toml(content string) !map[string]string {
	return parse_toml_lightweight(content)
}

// parse_toml_lightweight parses TOML using string processing.
// Supports: sections [section], array of tables [[section]], key=value pairs, inline tables, arrays.
fn parse_toml_lightweight(content string) map[string]string {
	mut result := map[string]string{}
	mut current_section := ''
	mut array_table_indices := map[string]int{} // Track indices for array of tables

	lines := content.split_into_lines()
	for line in lines {
		trimmed := line.trim_space()

		// Skip empty lines and comments
		if trimmed.len == 0 || trimmed.starts_with('#') {
			continue
		}

		// Section header [section] or [[array_of_tables]]
		if trimmed.starts_with('[') && trimmed.ends_with(']') {
			section := trimmed[1..trimmed.len - 1].trim_space()
			// Handle array of tables [[section]]
			if section.starts_with('[') && section.ends_with(']') {
				array_name := section[1..section.len - 1].trim_space()
				// Get current index for this array table
				idx := array_table_indices[array_name] or { 0 }
				array_table_indices[array_name] = idx + 1
				current_section = '${array_name}[${idx}]'
			} else {
				current_section = section
			}
			continue
		}

		// Parse key = value
		if trimmed.contains('=') {
			parts := trimmed.split_nth('=', 2)
			if parts.len == 2 {
				mut key := parts[0].trim_space()
				mut value := parts[1].trim_space()

				// Skip inline comments (but not inside quoted strings)
				value = strip_toml_comment(value)

				// Build full key with section prefix
				full_key := if current_section.len > 0 { '${current_section}.${key}' } else { key }

				// Parse the value
				parsed_value := parse_toml_value(value)
				result[full_key] = parsed_value

				// Handle inline tables recursively
				if value.starts_with('{') && value.ends_with('}') {
					inline_table := value[1..value.len - 1]
					parse_inline_table(inline_table, full_key, mut result)
				}
			}
		}
	}

	return result
}

// strip_toml_comment removes inline comments from a TOML value.
// Handles quoted strings properly.
fn strip_toml_comment(value string) string {
	mut in_single_quote := false
	mut in_double_quote := false
	mut escaped := false

	for i, ch in value {
		if escaped {
			escaped = false
			continue
		}
		if ch == `\\` {
			escaped = true
			continue
		}
		if ch == `"` && !in_single_quote {
			in_double_quote = !in_double_quote
			continue
		}
		if ch == `'` && !in_double_quote {
			in_single_quote = !in_single_quote
			continue
		}
		if ch == `#` && !in_single_quote && !in_double_quote {
			return value[..i].trim_space()
		}
	}
	return value
}

// parse_toml_value parses a TOML value string, handling quotes and arrays.
fn parse_toml_value(value string) string {
	mut v := value.trim_space()

	// Handle quoted strings
	if (v.starts_with('"') && v.ends_with('"')) || (v.starts_with("'") && v.ends_with("'")) {
		return v[1..v.len - 1]
	}

	// Handle arrays - return as-is for now (flattened separately if needed)
	if v.starts_with('[') && v.ends_with(']') {
		return v // Keep array syntax for potential further processing
	}

	// Return other values as-is (numbers, booleans, dates)
	return v
}

// parse_inline_table parses an inline table { key = value, ... } recursively.
fn parse_inline_table(table_content string, prefix string, mut result map[string]string) {
	// Split by comma, but handle nested braces
	mut items := []string{}
	mut depth := 0
	mut current := ''

	for ch in table_content {
		if ch == `{` {
			depth++
			current += ch.ascii_str()
		} else if ch == `}` {
			depth--
			current += ch.ascii_str()
		} else if ch == `,` && depth == 0 {
			items << current.trim_space()
			current = ''
		} else {
			current += ch.ascii_str()
		}
	}
	if current.len > 0 {
		items << current.trim_space()
	}

	// Parse each key=value pair
	for item in items {
		if item.contains('=') {
			parts := item.split_nth('=', 2)
			if parts.len == 2 {
				key := parts[0].trim_space()
				value := parts[1].trim_space()
				full_key := '${prefix}.${key}'
				result[full_key] = parse_toml_value(value)

				// Handle nested inline tables
				if value.starts_with('{') && value.ends_with('}') {
					nested_table := value[1..value.len - 1]
					parse_inline_table(nested_table, full_key, mut result)
				}
			}
		}
	}
}

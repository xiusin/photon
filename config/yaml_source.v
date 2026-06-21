module config

// yaml_source.v - YAML/TOML Configuration Source
//
// Provides configuration loading from YAML and TOML files.
// YAML is the most popular config format (Spring Boot, Laravel).
// TOML is the standard for V/Go projects.
//
// TOML parsing uses V's official `toml` standard library module,
// which supports the full TOML 1.0 specification including
// arrays of tables, inline tables, datetime values, etc.
//
// YAML parsing uses a built-in lightweight parser that supports
// the most common YAML patterns (no V official YAML module exists).
//
// Usage:
//   mgr := config.new_config_manager()
//   mgr.add_source(config.new_yaml_source('config/app.yaml'))!
//   mgr.add_source(config.new_toml_source('config/app.toml'))!
//   mgr.add_source(config.new_env_source('APP_'))
//
//   db_host := mgr.get('database.host') or { 'localhost' }
import os
import toml

// ── YamlConfigSource ──

// YamlConfigSource loads configuration from a YAML file.
pub struct YamlConfigSource {
pub:
	filepath string
}

// new_yaml_source creates a YamlConfigSource.
pub fn new_yaml_source(filepath string) &YamlConfigSource {
	return &YamlConfigSource{
		filepath: filepath
	}
}

// name returns the source name.
pub fn (s YamlConfigSource) name() string {
	return 'yaml:${s.filepath}'
}

// load reads and parses a YAML file into a flat key-value map.
pub fn (s YamlConfigSource) load() !map[string]string {
	content := os.read_file(s.filepath)!
	return parse_yaml(content)
}

// ── TomlConfigSource ──

// TomlConfigSource loads configuration from a TOML file.
// Uses V's official `toml` standard library for full TOML 1.0 support.
pub struct TomlConfigSource {
pub:
	filepath string
}

// new_toml_source creates a TomlConfigSource.
pub fn new_toml_source(filepath string) &TomlConfigSource {
	return &TomlConfigSource{
		filepath: filepath
	}
}

// name returns the source name.
pub fn (s TomlConfigSource) name() string {
	return 'toml:${s.filepath}'
}

// load reads and parses a TOML file into a flat key-value map.
// Delegates to V's official `toml` module for spec-compliant parsing.
pub fn (s TomlConfigSource) load() !map[string]string {
	doc := toml.parse_file(s.filepath)!
	return toml_doc_to_flat_map(doc)
}

// ── YAML Parser (lightweight, built-in) ──

// parse_yaml parses a simplified YAML document into a flat map.
// This is a lightweight parser that supports the most common YAML patterns:
//   - key: value
//   - nested.key: value (via indentation)
//   - list items (- value)
//   - Comments (#)
//   - Quoted strings
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
				// Leaf value
				full_key := key_stack.join('.')
				result[full_key] = clean_yaml_value(value)
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

// ── TOML Helpers (using V official toml module) ──

// parse_toml parses a TOML document string into a flat key-value map.
// Delegates to V's official `toml` module for spec-compliant parsing.
pub fn parse_toml(content string) !map[string]string {
	doc := toml.parse_text(content)!
	return toml_doc_to_flat_map(doc)
}

// toml_doc_to_flat_map converts a toml.Doc into a flat dot-notation map.
fn toml_doc_to_flat_map(doc toml.Doc) map[string]string {
	mut result := map[string]string{}
	any := doc.to_any()
	flatten_toml_any(any, '', mut result)
	return result
}

// flatten_toml_any recursively flattens a toml.Any value into dot-notation keys.
fn flatten_toml_any(val toml.Any, prefix string, mut result map[string]string) {
	match val {
		map[string]toml.Any {
			for key, any_val in val {
				new_key := if prefix.len > 0 { '${prefix}.${key}' } else { key }
				flatten_toml_any(any_val, new_key, mut result)
			}
		}
		[]toml.Any {
			for i, any_val in val {
				new_key := '${prefix}[${i}]'
				flatten_toml_any(any_val, new_key, mut result)
			}
		}
		string {
			result[prefix] = val
		}
		bool {
			result[prefix] = if val { 'true' } else { 'false' }
		}
		int, i64, u64, f32, f64 {
			result[prefix] = val.str()
		}
		else {
			// DateTime, Date, Time, Null — use str()
			result[prefix] = val.str()
		}
	}
}

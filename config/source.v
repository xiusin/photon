module config

// source.v - Configuration Source Implementations
//
// Provides various config sources: file-based, environment variables,
// and programmatic defaults.
import os
import json

// FileConfigSource loads configuration from a file (JSON or properties format)
pub struct FileConfigSource {
	filepath string
}

pub fn (s FileConfigSource) name() string {
	return 'file:${s.filepath}'
}

pub fn (s FileConfigSource) load() !map[string]string {
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

// EnvConfigSource loads configuration from environment variables
pub struct EnvConfigSource {
pub:
	prefix string // e.g., "APP_" to filter environment variables
}

pub fn (s EnvConfigSource) name() string {
	return 'env'
}

pub fn (s EnvConfigSource) load() !map[string]string {
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

pub fn (s MapConfigSource) load() !map[string]string {
	return s.data.clone()
}

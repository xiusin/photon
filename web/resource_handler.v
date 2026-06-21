module web

// resource_handler.v - Spring ResourceHandlerRegistry equivalent
//
// Registers URL pattern → filesystem location mappings for serving static resources.
// Spring equivalent: org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry
import os

// ResourceHandlerMapping maps a URL pattern to one or more filesystem locations.
pub struct ResourceHandlerMapping {
pub:
	pattern   string
	locations []string
}

// ResourceHandlerRegistry holds all static resource mappings.
pub struct ResourceHandlerRegistry {
pub mut:
	mappings []ResourceHandlerMapping
}

pub fn new_resource_handler_registry() ResourceHandlerRegistry {
	return ResourceHandlerRegistry{
		mappings: []ResourceHandlerMapping{}
	}
}

// add_mapping registers a URL pattern → locations mapping.
pub fn (mut r ResourceHandlerRegistry) add_mapping(pattern string, locations ...string) {
	r.mappings << ResourceHandlerMapping{
		pattern:   pattern
		locations: locations
	}
}

// resolve matches a request path against registered patterns and returns
// the first existing file path, or none.
pub fn (r &ResourceHandlerRegistry) resolve(path string) ?string {
	for mapping in r.mappings {
		if pattern_matches(mapping.pattern, path) {
			// Extract the part of path after the pattern prefix
			relative := extract_relative_path(mapping.pattern, path)
			for location in mapping.locations {
				file_path := os.join_path(location, relative)
				if os.exists(file_path) && os.is_file(file_path) {
					return file_path
				}
			}
		}
	}
	return none
}

// serve reads and returns the file content for a resolved path.
pub fn (r &ResourceHandlerRegistry) serve(path string) !string {
	file_path := r.resolve(path) or { return error('resource not found: ${path}') }
	return os.read_file(file_path)!
}

// pattern_matches checks if a path matches a URL pattern.
// Supports /static/** style patterns.
fn pattern_matches(pattern string, path string) bool {
	if pattern.ends_with('/**') {
		prefix := pattern[..pattern.len - 3]
		return path.starts_with(prefix)
	}
	return pattern == path
}

// extract_relative_path extracts the path after the pattern prefix.
fn extract_relative_path(pattern string, path string) string {
	if pattern.ends_with('/**') {
		prefix := pattern[..pattern.len - 2] // keep the trailing '/'
		if path.starts_with(prefix) {
			return path[prefix.len..]
		}
	}
	return path
}

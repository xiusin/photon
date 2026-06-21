module config

// property.v - Property Value Binding
//
// Provides helper functions for binding configuration values to struct fields.
// Supports the @[value('key')] pattern for field-level injection.

// ValuePrefix is the prefix for @[value] attribute values
const value_prefix = 'value:'

// PropertyBinder binds configuration values to struct fields
pub struct PropertyBinder {
pub mut:
	config &Config
}

// new_property_binder creates a new PropertyBinder
pub fn new_property_binder(cfg &Config) &PropertyBinder {
	return &PropertyBinder{
		config: unsafe { cfg }
	}
}

// resolve_value resolves a configuration value expression
// Supports: 'key' (simple), 'key:default' (with default)
pub fn (b &PropertyBinder) resolve_value(expr string) string {
	parts := expr.split(':')
	key := parts[0]
	default_val := if parts.len > 1 { parts[1] } else { '' }

	val := b.config.get(key)
	if val.len > 0 {
		return val
	}
	return default_val
}

// find_value_attr extracts value from attributes
pub fn find_value_attr(attrs []string) string {
	for a in attrs {
		if a.starts_with(value_prefix) {
			return a[value_prefix.len..]
		}
	}
	return ''
}

// bind_str_fields binds @[value] attributes for string fields at comptime
// Usage: $for field in T.fields { ... } inside a comptime block
pub fn bind_field_value(attrs []string, config_val string) string {
	expr := find_value_attr(attrs)
	if expr.len == 0 {
		return config_val
	}
	parts := expr.split(':')
	_ = parts[0] // key (used for property lookup)
	return if config_val.len > 0 {
		config_val
	} else {
		if parts.len > 1 {
			parts[1]
		} else {
			''
		}
	}
}

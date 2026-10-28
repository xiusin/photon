module config

// property.v - Property Value Binding
//
// Provides helper functions for binding configuration values to struct fields.
// Supports the @[value('key')] pattern for field-level injection and
// @ConfigurationProperties-style prefix-based struct binding.
//
// Spring equivalent: PropertyBinder + @ConfigurationProperties
// Laravel equivalent: Config::get() + config binding

// ValuePrefix is the prefix for @[value] attribute values
const value_prefix = 'value:'

// PropertyBinder binds configuration values to struct fields
pub struct PropertyBinder {
pub mut:
	config &Config
	env    &Environment
}

// new_property_binder creates a new PropertyBinder
pub fn new_property_binder(cfg &Config) &PropertyBinder {
	return &PropertyBinder{
		config: unsafe { cfg }
		env:    unsafe { nil }
	}
}

// new_property_binder_with_env creates a PropertyBinder with both Config and Environment.
// When an Environment is set, placeholder resolution is available.
pub fn new_property_binder_with_env(cfg &Config, env &Environment) &PropertyBinder {
	return &PropertyBinder{
		config: unsafe { cfg }
		env:    unsafe { env }
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

// resolve_value_with_placeholders resolves a configuration value expression with
// placeholder support. Uses the Environment's resolve_placeholders method
// if an Environment is set, otherwise falls back to simple resolution.
//
// Example:
//   binder.resolve_value_with_placeholders('jdbc://${db.host:localhost}:${db.port:5432}/${db.name}')
//   // → 'jdbc://localhost:5432/mydb'
pub fn (mut b PropertyBinder) resolve_value_with_placeholders(expr string) string {
	if !isnil(b.env) {
		mut env_ref := b.env
		return env_ref.resolve_placeholders(expr)
	}
	return b.resolve_value(expr)
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

// extract_value_key extracts the property key from a @[value('key')] or @[value('key:default')]
// attribute. Returns the key part (before the colon).
//
// Both V-normalized attribute forms are supported:
//   @[value: 'app.name']       → attr = "value: 'app.name'"  → key = "app.name"
//   @[value('app.name')]       → attr = "value('app.name')"  → key = "app.name"
//   @[value: 'app.name:def']   → key = "app.name"
//   @[value('app.name:def')]   → key = "app.name"
pub fn extract_value_key(attrs []string) string {
	expr := extract_value_expr_full(attrs)
	if expr.len == 0 {
		return ''
	}
	// Split on first ':' to separate key from default
	parts := expr.split_nth(':', 2)
	return parts[0]
}

// extract_value_default extracts the default value from a @[value('key:default')] attribute.
// Returns empty string if no default is specified.
pub fn extract_value_default(attrs []string) string {
	expr := extract_value_expr_full(attrs)
	if expr.len == 0 {
		return ''
	}
	parts := expr.split_nth(':', 2)
	if parts.len > 1 {
		return parts[1]
	}
	return ''
}

// extract_value_expr_full extracts the full expression from @[value('...')] attributes.
// Handles both V-normalized forms:
//   @[value: 'app.name']  → attr = "value: 'app.name'"  → returns "app.name"
//   @[value('app.name')]  → attr = "value('app.name')"  → returns "app.name"
//   @[value: 'app.name:def']  → returns "app.name:def"
pub fn extract_value_expr_full(attrs []string) string {
	for attr in attrs {
		trimmed := attr.trim_space()
		if trimmed.starts_with('value:') || trimmed.starts_with('value(') {
			mut val := trimmed
			if val.starts_with('value:') {
				val = val['value:'.len..]
			} else {
				val = val['value('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			// Trim space first so surrounding quotes are at the edges,
			// then strip matching quotes, then trim any inner space.
			return val.trim_space().trim("'").trim('"').trim_space()
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

// ── Type-Safe Struct Binding ──

// bind_to_struct binds configuration values to a struct T using comptime.
// Uses V's $for field in T.fields to iterate struct fields and bind
// values from the Config or Environment.
//
// Supported field types: string, int, i64, f32, f64, bool
//
// Field attributes:
//   @[value('key')]        — bind from the specified property key
//   @[value('key:default')]— bind from key, use default if not found
//
// If no @[value] attribute is present, the field name is used as the key.
// Fields not present in the config remain at their zero values.
//
// Example:
//   struct DbConfig {
//       host string @[value('db.host:localhost')]
//       port int    @[value('db.port:5432')]
//   }
//   config := config.bind_to_struct[DbConfig](binder)!
pub fn (b &PropertyBinder) bind_to_struct[T]() !T {
	mut result := T{}

	$for field in T.fields {
		// V hands comptime attribute text through `field.attrs` as raw
		// source fragments (e.g. "value: 'db.host:5432'"), so normalise
		// each entry before pattern matching.
		attrs := normalize_attrs(field.attrs)

		mut key := ''
		mut default_val := ''
		expr := extract_value_expr_full(attrs)
		if expr.len > 0 {
			// Parse key:default from the expression
			parts := expr.split_nth(':', 2)
			key = parts[0]
			if parts.len > 1 {
				default_val = parts[1]
			}
		}
		if key.len == 0 {
			// No @[value] attribute — fall back to @[config_field: 'key'],
			// then to the field name as the key.
			key = extract_config_field_key(attrs)
		}
		if key.len == 0 {
			key = field.name
		}

		// Look up the property value. Both sources participate: an explicit
		// Config entry wins, otherwise the Environment is consulted — passing
		// an Environment used to shadow every Config value entirely.
		mut found := b.config.has(key)
		mut raw_value := b.config.get(key)
		if !isnil(b.env) {
			mut env_ref := b.env
			if !found && env_ref.has_property(key) {
				raw_value = env_ref.get_property_or(key, '')
				found = true
			}
			// Resolve placeholders in the value before defaulting.
			if found && raw_value.contains('\${') {
				raw_value = env_ref.resolve_placeholders(raw_value)
			}
		}
		// An explicitly configured empty value must win over the default —
		// `has()` decides, not `len`.
		if !found && default_val.len > 0 {
			raw_value = default_val
		}

		// Only assign if we found a value (skip if key not found and no default)
		if !found && default_val.len == 0 {
			// continue is not allowed in comptime $for loops
			// so we just skip the assignment
		} else {
			// Convert and assign by field type (comptime — zero runtime reflection)
			$if field.typ is string {
				result.$(field.name) = raw_value
			} $else $if field.typ is int {
				if raw_value.len > 0 {
					result.$(field.name) = raw_value.int()
				}
			} $else $if field.typ is i64 {
				if raw_value.len > 0 {
					result.$(field.name) = raw_value.i64()
				}
			} $else $if field.typ is f32 {
				if raw_value.len > 0 {
					result.$(field.name) = raw_value.f32()
				}
			} $else $if field.typ is f64 {
				if raw_value.len > 0 {
					result.$(field.name) = raw_value.f64()
				}
			} $else $if field.typ is bool {
				if raw_value.len > 0 {
					result.$(field.name) = raw_value.to_lower() == 'true' || raw_value == '1'
				}
			}
		}
	}
	return result
}

// ── @ConfigurationProperties Binding ──

// normalize_attrs converts V's raw comptime attribute fragments into the
// normalised "name: 'arg'" form the extract_* helpers expect.
//
// V exposes `field.attrs` / `method.attrs` as raw source slices, so a field
// declared `@[value: 'db.host']` yields the literal string `value: 'db.host'`.
// A plain `@[component]` yields `component`. Both are already in the expected
// shape; this helper additionally accepts the call form `value('db.host')`
// and rewritten spellings such as `value:db.host` so hand-built attribute
// lists (tests, code generators) keep working.
pub fn normalize_attrs(attrs []string) []string {
	mut out := []string{cap: attrs.len}
	for raw in attrs {
		attr := raw.trim_space()
		if attr.len == 0 {
			continue
		}
		idx := attr.index(':') or { -1 }
		paren := attr.index('(') or { -1 }
		if idx > 0 && (paren < 0 || idx < paren) {
			name := attr[..idx].trim_space()
			arg := attr[idx + 1..].trim_space()
			out << '${name}: ${arg}'
			continue
		}
		if paren > 0 {
			name := attr[..paren].trim_space()
			mut rest := attr[paren + 1..].trim_space()
			if rest.ends_with(')') {
				rest = rest[..rest.len - 1].trim_space()
			}
			out << '${name}: ${rest}'
			continue
		}
		out << attr
	}
	return out
}

// extract_config_field_key extracts the custom key from a @[config_field: 'key']
// or @[config_field('key')] attribute. Returns empty string if not present.
//
// Both attribute forms normalize to the string `config_field: 'value'` in V's
// comptime `field.attrs` list.
//
// Example:
//   struct C { host string @[config_field: 'hostname'] }
//   // extract_config_field_key(field.attrs) -> 'hostname'
pub fn extract_config_field_key(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('config_field:') {
			rest := attr['config_field:'.len..].trim_space()
			// Strip surrounding single quotes
			if rest.len >= 2 && rest[0] == `'` && rest[rest.len - 1] == `'` {
				return rest[1..rest.len - 1]
			}
			// Strip surrounding double quotes
			if rest.len >= 2 && rest[0] == `"` && rest[rest.len - 1] == `"` {
				return rest[1..rest.len - 1]
			}
			return rest
		}
	}
	return ''
}

// bind_configuration_properties binds all properties with a given prefix into
// a typed struct T. This is the Photon equivalent of Spring Boot's
// @ConfigurationProperties annotation.
//
// Supported field types:
//   - Primitive: string, int, i64, f32, f64, bool
//   - Arrays: []string, []int, []f64, []bool (comma-separated values)
//   - Nested structs: recursively bound with prefix.field_name
//
// Field attributes:
//   @[value('custom_key')]       — use 'custom_key' instead of field name for lookup
//   @[config_field: 'custom_key'] — alternative syntax (same effect)
//
// Fields not present in the environment remain at their zero/default values.
//
// Spring Boot equivalent: @ConfigurationProperties(prefix = "app.database")
//
// Example:
//   struct DatabaseConfig {
//       host     string
//       port     int
//       timeout  f64
//       ssl      bool
//       replicas []string
//   }
//   env.set_property('app.db.host', 'localhost')
//   env.set_property('app.db.port', '5432')
//   env.set_property('app.db.replicas', 'r1,r2,r3')
//   config := config.bind_configuration_properties[DatabaseConfig](env, 'app.db')!
//   // config.host == 'localhost', config.port == 5432, config.replicas == ['r1','r2','r3']
pub fn bind_configuration_properties[T](mut env Environment, prefix string) !T {
	return bind_configuration_properties_impl[T](mut env, prefix, &T{})
}

// bind_configuration_properties_impl is the internal helper that carries a `&T` dummy
// instance for recursive type inference of nested struct fields.
fn bind_configuration_properties_impl[T](mut env Environment, prefix string, typ &T) !T {
	mut bound := T{}

	$for field in T.fields {
		// V hands comptime attribute text through `field.attrs` as raw
		// source fragments (e.g. "value: 'db.host:5432'"), so normalise
		// each entry before pattern matching.
		attrs := normalize_attrs(field.attrs)

		// Determine the lookup key: use @[config_field] or @[value] custom key
		// if present, otherwise use the field name.
		mut explicit_key := extract_config_field_key(attrs)
		// Both attribute forms accept a `key:default` payload; only the part
		// before the first ':' is the property key.
		if explicit_key.contains(':') {
			explicit_key = explicit_key.split_nth(':', 2)[0]
		}
		mut value_key := ''
		if explicit_key.len == 0 {
			value_key = extract_value_expr_full(attrs)
			// For @[value('key:default')], extract just the key part
			if value_key.contains(':') {
				value_key = value_key.split_nth(':', 2)[0]
			}
		}
		effective_key := if explicit_key.len > 0 {
			explicit_key
		} else if value_key.len > 0 {
			value_key
		} else {
			field.name
		}

		// Build the full property key: prefix.effective_key (or just effective_key if no prefix)
		full_key := if prefix.len > 0 { '${prefix}.${effective_key}' } else { effective_key }
		// An @[value] key is an absolute property address, so it is also tried
		// verbatim — bind_configuration_properties[Outer](env, 'app') with
		// `@[value('app.db.host')]` must find app.db.host, not app.app.db.host.
		alt_key := if value_key.len > 0 && full_key != value_key { value_key } else { '' }
		found := env.has_property(full_key) || (alt_key.len > 0 && env.has_property(alt_key))
		lookup_key := if env.has_property(full_key) { full_key } else { alt_key }

		// Bind based on field type — primitive types first, then arrays, then nested structs
		$if field.typ is string {
			if found {
				bound.$(field.name) = env.get_property_or(lookup_key, '')
			}
		} $else $if field.typ is int {
			if found {
				bound.$(field.name) = env.get_property_or(lookup_key, '0').int()
			}
		} $else $if field.typ is i64 {
			if found {
				bound.$(field.name) = env.get_property_or(lookup_key, '0').i64()
			}
		} $else $if field.typ is f32 {
			if found {
				bound.$(field.name) = f32(env.get_property_or(lookup_key, '0').f64())
			}
		} $else $if field.typ is f64 {
			if found {
				bound.$(field.name) = env.get_property_or(lookup_key, '0').f64()
			}
		} $else $if field.typ is bool {
			if found {
				val := env.get_property_or(lookup_key, 'false')
				bound.$(field.name) = val == 'true' || val == '1' || val == 'yes' || val == 'on'
			}
		} $else $if field.typ is []string {
			raw := env.get_property_or(lookup_key, '')
			if raw.len > 0 {
				mut arr := []string{}
				for part in raw.split(',') {
					arr << part.trim_space()
				}
				bound.$(field.name) = arr
			}
		} $else $if field.typ is []int {
			raw := env.get_property_or(lookup_key, '')
			if raw.len > 0 {
				mut arr := []int{}
				for part in raw.split(',') {
					arr << part.trim_space().int()
				}
				bound.$(field.name) = arr
			}
		} $else $if field.typ is []f64 {
			raw := env.get_property_or(lookup_key, '')
			if raw.len > 0 {
				mut arr := []f64{}
				for part in raw.split(',') {
					arr << part.trim_space().f64()
				}
				bound.$(field.name) = arr
			}
		} $else $if field.typ is []bool {
			raw := env.get_property_or(lookup_key, '')
			if raw.len > 0 {
				mut arr := []bool{}
				for part in raw.split(',') {
					p := part.trim_space()
					arr << p == 'true' || p == '1' || p == 'yes' || p == 'on'
				}
				bound.$(field.name) = arr
			}
		} $else $if field.is_struct {
			// Recursively bind nested struct fields.
			// The `typ.$(field.name)` trick provides V with the field's type
			// for generic type inference of the recursive call.
			//
			// A nested struct is a namespace, not a value: its children live
			// under the field address (prefix.inner.host), never under the
			// @[value] key used for scalar overrides. Passing `full_key` here
			// produced keys like "app.db.host.host".
			typ_ := typ.$(field.name)
			child_prefix := if prefix.len > 0 { '${prefix}.${field.name}' } else { field.name }
			nested := bind_configuration_properties_impl(mut env, child_prefix, &typ_) or { typ_ }
			bound.$(field.name) = nested
		}
	}
	return bound
}

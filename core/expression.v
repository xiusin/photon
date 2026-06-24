module core

// expression.v - Photon Expression Language (Photon EL)
//
// A lightweight expression engine for resolving placeholders and evaluating
// simple condition expressions at runtime. Inspired by Spring's
// PropertySourcesPlaceholderConfigurer and SpEL (Spring Expression Language),
// but drastically simplified for V's no-reflection philosophy.
//
// ── Features ──
//
// 1. Placeholder Resolution: ${key} or ${key:default}
//    Resolves property keys from an Environment or map[string]string.
//    Supports nested placeholders: ${${prefix}.suffix}
//
//    Usage:
//      resolved := core.resolve_placeholders('${app.name:MyApp} v${app.version:1.0}', env)
//      // → "MyApp v1.0" (if app.name and app.version are not set)
//
// 2. Condition Expression Evaluation:
//    Supports ==, !=, and simple boolean checks for @[conditional_on_expression].
//
//    Supported syntax:
//      key==value          → true if property 'key' equals 'value'
//      key!=value          → true if property 'key' does not equal 'value'
//      key                 → true if property 'key' exists and is non-empty
//      !key                → true if property 'key' does not exist or is empty
//      expr1 && expr2      → logical AND
//      expr1 || expr2      → logical OR
//
//    Usage:
//      ok := core.eval_condition('app.env==prod && feature.x', env)
//
// Spring equivalent:
//   - Placeholder resolution: ${...} in @Value annotations
//   - Condition evaluation: @ConditionalOnExpression("#{...}")

// ── Placeholder Resolution ──

// resolve_placeholders replaces all ${key} and ${key:default} placeholders
// in the given string using properties from the provided map.
//
// Nested placeholders are supported: ${${prefix}.suffix}
//
// If a key has no value and no default is provided, the placeholder is
// left as-is (not replaced).
//
// Spring equivalent: PropertySourcesPlaceholderConfigurer.processPlaceholders()
pub fn resolve_placeholders(expr string, properties map[string]string) string {
	return resolve_placeholders_internal(expr, properties, 0)
}

// resolve_placeholders_env resolves placeholders using an Environment's
// properties. This is the preferred function for use within the framework
// since Environment supports multi-source property lookup with priority.
pub fn resolve_placeholders_env(expr string, mut env Environment) string {
	props := env.to_map()
	return resolve_placeholders(expr, props)
}

// resolve_placeholders_internal is the recursive implementation.
// `depth` prevents infinite recursion on circular placeholders.
fn resolve_placeholders_internal(expr string, properties map[string]string, depth int) string {
	if depth > 10 {
		return expr // safety: prevent infinite recursion
	}

	mut result := ''
	bytes_ := expr.bytes()
	mut i := 0

	for i < bytes_.len {
		if i + 1 < bytes_.len && bytes_[i] == `$` && bytes_[i + 1] == `{` {
			// Find the matching closing }
			mut brace_depth := 1
			mut j := i + 2
			for j < bytes_.len && brace_depth > 0 {
				if bytes_[j] == `{` {
					brace_depth++
				} else if bytes_[j] == `}` {
					brace_depth--
				}
				if brace_depth > 0 {
					j++
				}
			}

			if brace_depth == 0 {
				// Extract the placeholder content
				inner := expr[i + 2..j]
				// Recursively resolve nested placeholders inside the key
				resolved_key := resolve_placeholders_internal(inner, properties, depth + 1)

				// Split on first ':' to get key:default
				key_parts := split_default(resolved_key)
				key := key_parts[0].trim_space()

				if val := properties[key] {
					result += val
				} else if key_parts.len > 1 {
					// Use default value
					default_val := key_parts[1].trim_space()
					result += default_val
				} else {
					// No value and no default — leave placeholder as-is
					result += '\${' + inner + '}'
				}

				i = j + 1
			} else {
				// No matching } — treat as literal
				result += bytes_[i].ascii_str()
				i++
			}
		} else {
			result += bytes_[i].ascii_str()
			i++
		}
	}

	return result
}

// split_default splits a placeholder content on the first ':' to separate
// the key from the default value. Handles colons inside the value correctly
// by only splitting on the first occurrence.
//
// Uses byte-level index() for correct behavior with both ASCII and UTF-8
// strings (runes() index would not match byte-based string slicing).
fn split_default(s string) []string {
	if idx := s.index(':') {
		return [s[..idx], s[idx + 1..]]
	}
	return [s]
}

// ── Condition Expression Evaluation ──

// eval_condition evaluates a condition expression against the given properties.
//
// Supported operators (in order of precedence):
//   1. || (logical OR, lowest precedence)
//   2. && (logical AND)
//   3. == != (equality / inequality)
//   4. ! (negation)
//   5. key (existence check, highest precedence)
//
// Examples:
//   'app.env==prod'                     → true if app.env equals 'prod'
//   'app.env!=dev'                      → true if app.env does not equal 'dev'
//   'feature.x'                         → true if feature.x exists and is non-empty
//   '!feature.disabled'                 → true if feature.disabled is absent or empty
//   'app.env==prod && feature.x'        → both conditions must be true
//   'app.env==prod || app.env==staging' → either condition must be true
//
// Spring equivalent: @ConditionalOnExpression("#{...}")
pub fn eval_condition(expr string, properties map[string]string) bool {
	trimmed := expr.trim_space()
	if trimmed.len == 0 {
		return true
	}
	return eval_or(trimmed, properties)
}

// eval_condition_env evaluates a condition expression using an Environment.
pub fn eval_condition_env(expr string, mut env Environment) bool {
	props := env.to_map()
	return eval_condition(expr, props)
}

// eval_or handles the || operator (lowest precedence).
fn eval_or(expr string, properties map[string]string) bool {
	parts := split_top_level(expr, '||')
	for part in parts {
		if eval_and(part.trim_space(), properties) {
			return true
		}
	}
	return false
}

// eval_and handles the && operator.
fn eval_and(expr string, properties map[string]string) bool {
	parts := split_top_level(expr, '&&')
	for part in parts {
		if !eval_comparison(part.trim_space(), properties) {
			return false
		}
	}
	return true
}

// eval_comparison handles ==, !=, and existence checks.
fn eval_comparison(expr string, properties map[string]string) bool {
	trimmed := expr.trim_space()

	// Check for == operator
	if idx := index_of_str(trimmed, '==') {
		left := trimmed[..idx].trim_space()
		right := trimmed[idx + 2..].trim_space()
		val := properties[left] or { '' }
		return val == right
	}

	// Check for != operator
	if idx := index_of_str(trimmed, '!=') {
		left := trimmed[..idx].trim_space()
		right := trimmed[idx + 2..].trim_space()
		val := properties[left] or { '' }
		return val != right
	}

	// Check for ! (negation of existence)
	if trimmed.len > 1 && trimmed[0] == `!` {
		key := trimmed[1..].trim_space()
		val := properties[key] or { '' }
		return val.len == 0
	}

	// Plain key existence check
	val := properties[trimmed] or { '' }
	return val.len > 0
}

// split_top_level splits a string on the given separator, but only at
// the top level (not inside ${...} placeholders or quotes).
fn split_top_level(s string, sep string) []string {
	mut parts := []string{}
	mut current := ''
	bytes_ := s.bytes()
	sep_bytes := sep.bytes()

	for i := 0; i < bytes_.len; {
		// Check if we're at the separator
		if i + sep_bytes.len <= bytes_.len {
			mut matches := true
			for k in 0..sep_bytes.len {
				if bytes_[i + k] != sep_bytes[k] {
					matches = false
					break
				}
			}
			if matches {
				parts << current
				current = ''
				i += sep_bytes.len
				continue
			}
		}

		// Skip ${...} blocks
		if i + 1 < bytes_.len && bytes_[i] == `$` && bytes_[i + 1] == `{` {
			mut brace_depth := 1
			current += '\$'
			current += '{'
			i += 2
			for i < bytes_.len && brace_depth > 0 {
				if bytes_[i] == `{` {
					brace_depth++
				} else if bytes_[i] == `}` {
					brace_depth--
				}
				current += bytes_[i].ascii_str()
				i++
			}
			continue
		}

		current += bytes_[i].ascii_str()
		i++
	}

	parts << current
	return parts
}

// index_of_str finds the index of a substring, returning an optional.
fn index_of_str(s string, needle string) ?int {
	idx := s.index(needle) or { return none }
	return idx
}

// ── Environment Helper ──

// env_to_map is a helper that converts an Environment's properties to a flat map.
pub fn env_to_map(mut env Environment) map[string]string {
	return env.to_map()
}

module web

// bind.v — Spring-style DTO Binding
//
// Binds HTTP request data (query params, form body, JSON body) to typed structs.
// Spring equivalents: @RequestBody, @ModelAttribute, @RequestParam, @PathVariable.
//
// Field attributes:
//   @[required]            — field must be present and non-empty
//   @[form: 'field_name']  — map to a different form field name
//
// Usage:
//   struct LoginDto {
//       username string @[required]
//       password string @[required]
//       remember bool
//   }
//   dto := web.bind[LoginDto](ctx) or { return app.text('invalid') }
//   dto_json := web.bind_json[CreateUserDto](ctx) or { ... }

import veb
import json

// ============================================================
// Query/Form Binding (like Spring @ModelAttribute)
// ============================================================

// bind binds query-string and form-body data to a struct T.
// Supports `@[required]` validation on struct fields.
//
// Field mapping:
//   - Uses field name by default
//   - Uses @[form: 'alt_name'] attribute for custom mapping
pub fn bind[T](ctx &veb.Context) !T {
	mut result := T{}
	mut params := extract_params(ctx)

	$for field in T.fields {
		// Determine the input key name
		mut key := field.name
		for attr in field.attrs {
			if attr.starts_with('form:') {
				key = extract_attr_arg(attr)
			}
		}

		val := params[key] or { '' }

		// Check required
		mut is_required := false
		for attr in field.attrs {
			if attr == 'required' {
				is_required = true
				break
			}
		}
		if is_required && val == '' {
			return error('${field.name} is required')
		}

		// Assign value based on type
		$if field.typ is string {
			result.$(field.name) = val
		} $else $if field.typ is int {
			if is_required && val == '' {
				return error('${field.name} is required but empty — cannot convert to int')
			}
			if val != '' {
				if !is_numeric(val) {
					return error('${field.name}: invalid integer value "${val}"')
			}
				result.$(field.name) = val.int()
			}
		} $else $if field.typ is i64 {
			if is_required && val == '' {
				return error('${field.name} is required but empty — cannot convert to i64')
			}
			if val != '' {
				if !is_numeric(val) {
					return error('${field.name}: invalid i64 value "${val}"')
			}
				result.$(field.name) = val.i64()
			}
		} $else $if field.typ is f64 {
			if is_required && val == '' {
				return error('${field.name} is required but empty — cannot convert to f64')
			}
			if val != '' {
				if !is_numeric(val) {
					return error('${field.name}: invalid f64 value "${val}"')
			}
				result.$(field.name) = val.f64()
			}
		} $else $if field.typ is bool {
			result.$(field.name) = val == '1' || val == 'true' || val == 'on' || val == 'yes'
		}
	}

	return result
}

// ============================================================
// JSON Body Binding (like Spring @RequestBody)
// ============================================================

// bind_json binds a JSON request body to a struct T.
// Uses the `ctx.req.data` field which contains the raw request body.
pub fn bind_json[T](ctx &veb.Context) !T {
	body := ctx.req.data
	if body == '' {
		return error('empty request body')
	}
	return json.decode(T, body) or { error('invalid JSON: ${err}') }
}

// ============================================================
// Path Variable Binding (like Spring @PathVariable)
// ============================================================

// bind_path extracts path variables from the route pattern.
// veb provides these via ctx.query map when using :param routes.
//
// Usage:
//   pub fn (mut app MyApp) get_user(id string) veb.Result {
//       // id is automatically populated by veb from /users/:id
//   }
pub fn bind_path[T](ctx &veb.Context) !T {
	// Path variables in veb are available via the query map
	return bind[T](ctx)!
}

// ============================================================
// Internal helpers
// ============================================================

// extract_params collects all input parameters from context
fn extract_params(ctx &veb.Context) map[string]string {
	mut params := map[string]string{}

	// Query parameters
	for k, v in ctx.query {
		params[k] = v
	}

	// Form parameters
	for k, v in ctx.form {
		params[k] = v
	}

	// Parse URL query string as fallback
	url := ctx.req.url
	pos := url.index('?') or { return params }
	query := url[pos + 1..]
	for kv in query.split('&') {
		pair := kv.split('=')
		if pair.len >= 1 {
			key := url_decode(pair[0])
			val := if pair.len >= 2 { url_decode(pair[1]) } else { '' }
			// Don't overwrite existing keys (form params take precedence)
			if params[key] == '' {
				params[key] = val
			}
		}
	}

	return params
}

// extract_attr_arg extracts the argument string from an attribute like "form: 'username'"
fn extract_attr_arg(attr string) string {
	pos := attr.index(':') or { return attr }
	rest := attr[pos + 1..].trim_space()
	if rest.len > 2 && rest[0] == `'` && rest[rest.len - 1] == `'` {
		return rest[1..rest.len - 1]
	}
	return rest
}

// is_numeric checks if a string represents a valid number (integer or float).
fn is_numeric(s string) bool {
	if s.len == 0 {
		return false
	}
	mut has_digit := false
	mut has_dot := false
	for i, ch in s {
		if ch == `-` && i == 0 {
			continue
		}
		if ch == `.` {
			if has_dot {
				return false
			}
			has_dot = true
			continue
		}
		if ch < `0` || ch > `9` {
			return false
		}
		has_digit = true
	}
	return has_digit
}

// url_decode performs simple percent-decoding for URL-encoded values.
// Converts %XX sequences back to their character equivalents.
fn url_decode(s string) string {
	mut result := []u8{}
	mut i := 0
	for i < s.len {
		if s[i] == `%` && i + 2 < s.len {
			hex_str := s[i + 1..i + 3]
			code := int_from_hex(hex_str)
			if code >= 0 {
				result << u8(code)
				i += 3
				continue
			}
		} else if s[i] == `+` {
			result << u8(` `)
			i++
			continue
		}
		result << s[i]
		i++
	}
	return result.bytestr()
}

// int_from_hex converts a 2-char hex string to an integer.
fn int_from_hex(s string) int {
	if s.len < 2 {
		return -1
	}
	mut result := 0
	for i in 0 .. 2 {
		ch := s[i]
		if ch >= `0` && ch <= `9` {
			result = result * 16 + int(ch - `0`)
		} else if ch >= `a` && ch <= `f` {
			result = result * 16 + int(ch - `a`) + 10
		} else if ch >= `A` && ch <= `F` {
			result = result * 16 + int(ch - `A`) + 10
		} else {
			return -1
		}
	}
	return result
}

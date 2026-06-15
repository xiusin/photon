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
			result.$(field.name) = val.int()
		} $else $if field.typ is i64 {
			result.$(field.name) = val.i64()
		} $else $if field.typ is f64 {
			result.$(field.name) = val.f64()
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
		if pair.len == 2 {
			// Don't overwrite existing keys
			if params[pair[0]] == '' {
				params[pair[0]] = pair[1]
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

module web

// input.v — Laravel-style Request Input Service
//
// Provides a fluent API for accessing HTTP request data:
//   - Query parameters (`?name=alice`)
//   - Form body data (POST form data)
//   - JSON request body (`{"key":"value"}`)
//   - Route parameters (`/users/:id`)
//   - Headers, cookies, files
//
// Usage in a controller:
//   pub fn (mut app MyApp) create() veb.Result {
//       name := web.input(app.Context).get('name', 'guest')
//       all  := web.input(app.Context).all()
//       ...
//   }

import veb
import json

// Input wraps veb.Context with Laravel-style access methods.
// Create with: web.input(ctx)
pub struct Input {
	ctx &veb.Context
}

// input creates an Input wrapper for a veb.Context
pub fn input(ctx &veb.Context) Input {
	return Input{ctx: ctx}
}

// all returns all input data (query + form merged)
pub fn (i Input) all() map[string]string {
	mut result := map[string]string{}
	// Merge query params
	for k, v in i.ctx.query {
		result[k] = v
	}
	// Form params override query
	for k, v in i.ctx.form {
		result[k] = v
	}
	// Parse URL query string if ctx.query is empty
	if result.len == 0 {
		url := i.ctx.req.url
		pos := url.index('?') or { return result }
		query := url[pos + 1..]
		for kv in query.split('&') {
			pair := kv.split('=')
			if pair.len == 2 {
				result[pair[0]] = pair[1]
			}
		}
	}
	return result
}

// get returns a single input value with an optional default
pub fn (i Input) get(key string, default string) string {
	val := i.ctx.query[key] or {
		val2 := i.ctx.form[key] or {
			// Parse from URL query string
			url := i.ctx.req.url
			pos := url.index('?') or { return default }
			query := url[pos + 1..]
			for kv in query.split('&') {
				pair := kv.split('=')
				if pair.len == 2 && pair[0] == key {
					return pair[1]
				}
			}
			return default
		}
		return val2
	}
	return val
}

// only returns a subset of input data for the given keys
pub fn (i Input) only(keys []string) map[string]string {
	mut result := map[string]string{}
	all := i.all()
	for key in keys {
		if val := all[key] {
			result[key] = val
		}
	}
	return result
}

// except returns all input data except the given keys
pub fn (i Input) except(keys []string) map[string]string {
	mut result := i.all()
	for key in keys {
		result.delete(key)
	}
	return result
}

// has checks if a key exists in the input (non-empty)
pub fn (i Input) has(key string) bool {
	val := i.get(key, '__NONEXISTENT__')
	return val != '__NONEXISTENT__'
}

// filled checks if a key exists and is non-empty
pub fn (i Input) filled(key string) bool {
	val := i.get(key, '')
	return val.len > 0
}

// missing checks if a key is missing or empty
pub fn (i Input) missing(key string) bool {
	return !i.filled(key)
}

// header returns a request header value
pub fn (i Input) header(key string) string {
	val := i.ctx.get_custom_header(key) or { return '' }
	return val
}

// cookie returns a cookie value
pub fn (i Input) cookie(key string) string {
	val := i.ctx.get_cookie(key) or { return '' }
	return val
}

// method returns the HTTP method
pub fn (i Input) method() string {
	return i.ctx.req.method.str()
}

// path returns the request path (without query string)
pub fn (i Input) path() string {
	url := i.ctx.req.url
	pos := url.index('?') or { return url }
	return url[..pos]
}

// url returns the full request URL
pub fn (i Input) url() string {
	return i.ctx.req.url
}

// is_method checks if the request method matches
pub fn (i Input) is_method(method string) bool {
	return i.method() == method
}

// is_json checks if the request expects JSON
pub fn (i Input) is_json() bool {
	ct := i.header('Content-Type')
	return ct.contains('json')
}

// json_body returns the raw JSON request body
pub fn (i Input) json_body() string {
	return i.ctx.req.data
}

// query_all returns only query string parameters
pub fn (i Input) query_all() map[string]string {
	return i.ctx.query.clone()
}

// query returns a single query parameter
pub fn (i Input) query(key string, default string) string {
	val := i.ctx.query[key] or { return default }
	return val
}

// form_all returns only form body parameters
pub fn (i Input) form_all() map[string]string {
	return i.ctx.form.clone()
}

// form_key returns a single form parameter
pub fn (i Input) form_key(key string, default string) string {
	val := i.ctx.form[key] or { return default }
	return val
}

// file returns an uploaded file's data by key
pub fn (i Input) file(key string) ?string {
	files := i.ctx.files[key] or { return none }
	if files.len == 0 {
		return none
	}
	return files[0].data
}

// has_file checks if a file was uploaded
pub fn (i Input) has_file(key string) bool {
	files := i.ctx.files[key] or { return false }
	return files.len > 0
}

// to_json returns all input data as a JSON string
pub fn (i Input) to_json() string {
	all := i.all()
	return json.encode(all)
}

// integer returns an input value as int, with default
pub fn (i Input) integer(key string, default int) int {
	val := i.get(key, '')
	if val == '' {
		return default
	}
	return val.int()
}

// boolean returns an input value as bool
pub fn (i Input) boolean(key string, default bool) bool {
	val := i.get(key, '')
	if val == '' {
		return default
	}
	return val == '1' || val == 'true' || val == 'on' || val == 'yes'
}

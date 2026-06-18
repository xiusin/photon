module apidoc

// collector.v — Request/Response Collector for API Docs

import veb
import x.json2

@[heap]
pub struct Collector {
pub mut:
	store &ApiDocStore
mut:
	pending map[string]string // path → entry_id for response matching
}

const resource_exts = ['.css', '.js', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico',
	'.woff', '.woff2', '.ttf', '.eot', '.map']

fn is_resource(path string) bool {
	for ext in resource_exts {
		if path.to_lower().ends_with(ext) {
			return true
		}
	}
	return path.starts_with('/__apidoc') || path.starts_with('/__docs')
}

pub fn new_collector(store &ApiDocStore) &Collector {
	return &Collector{
		store: store
		pending: map[string]string{}
	}
}

// collect captures request metadata (called from before_middleware)
pub fn (mut c Collector) collect(mut ctx veb.Context) {
	path := ctx.req.url
	if is_resource(path) {
		return
	}

	method := ctx.req.method.str()
	id := method.to_upper() + '::' + normalize_path(path)

	mut entry := c.store.get_or_create_entry(method, normalize_path(path)) or {
		eprintln('[apidoc] collect — get_or_create_entry failed: ${err}')
		return
	}

	// Update method/path
	unsafe {
		entry.method = method.to_upper()
		entry.path = normalize_path(path)
		entry.hit_count++
	}

	// Capture query params
	parse_and_merge_params(mut entry, ctx.req.url)

	// Capture form params for POST/PUT/PATCH
	if ctx.req.method == .post || ctx.req.method == .put || ctx.req.method == .patch {
		parse_and_merge_form_params(mut entry, ctx)
	}

	// Capture headers
	parse_and_merge_headers(mut entry, ctx)

	// Save
	c.store.update_entry(id, entry) or {}

	eprintln('[apidoc] collect — ${id} hits=${entry.hit_count} params=${entry.parameters.len}')
}

// collect_response captures response metadata (called from after_middleware)
pub fn (mut c Collector) collect_response(mut ctx veb.Context) {
	path := ctx.req.url
	if is_resource(path) {
		return
	}

	method := ctx.req.method.str()
	id := method.to_upper() + '::' + normalize_path(path)

	mut entry := c.store.get_entry(id) or { return }

	body := ctx.res.body
	ct := ctx.res.header.get(.content_type) or { 'application/json' }
	status := ctx.res.status_code

	unsafe {
		entry.response.content_type = ct
		entry.response.status_code = status
		// Store a sample of the response body (truncated)
		if body.len > 0 {
			if body.len > 2048 {
				entry.response.body_sample = body[..2048] + '...'
			} else {
				entry.response.body_sample = body
			}
		}
	}

	// Parse JSON response body to extract property schema
	if ct.contains('json') && body.len > 0 {
		parse_json_response(mut entry, body)
	}

	c.store.update_entry(id, entry) or {}
}

fn normalize_path(path string) string {
	mut p := path
	if idx := p.index('?') {
		p = p[..idx]
	}
	return p.trim_right('/')
}

fn parse_and_merge_params(mut entry &ApiDocEntry, url string) {
	idx := url.index('?') or { return }
	query := url[idx + 1..]
	if query.len == 0 { return }

	for kv in query.split('&') {
		pair := kv.split('=')
		if pair.len < 1 || pair[0].len == 0 { continue }
		mut val := ''
		if pair.len >= 2 { val = pair[1] }

		// Check if parameter already exists
		mut found := false
		for i in 0 .. entry.parameters.len {
			if entry.parameters[i].name == pair[0] && entry.parameters[i].location == 'query' {
				if !entry.parameters[i].locked {
					// Add example value
					if val.len > 0 && entry.parameters[i].examples.len < 5 {
						mut exists := false
						for ex in entry.parameters[i].examples {
							if ex == val { exists = true; break }
						}
						if !exists {
							entry.parameters[i].examples << val
						}
					}
				}
				found = true
				break
			}
		}
		if !found {
			mut param := ApiDocParam{
				name:     pair[0]
				location: 'query'
				required: false
				type_:    infer_type(val)
			}
			if val.len > 0 {
				param.examples = [val]
			}
			entry.parameters << param
		}
	}
}

fn parse_and_merge_headers(mut entry &ApiDocEntry, ctx &veb.Context) {
	// Authorization
	auth := ctx.get_custom_header('Authorization') or { '' }
	if auth.len > 0 {
		mut sample := auth
		if sample.starts_with('Bearer ') { sample = 'Bearer ***' }
		else if sample.starts_with('Basic ') { sample = 'Basic ***' }

		mut found := false
		for i in 0 .. entry.headers.len {
			if entry.headers[i].name == 'Authorization' {
				if !entry.headers[i].locked {
					entry.headers[i].value_sample = sample
				}
				found = true
				break
			}
		}
		if !found {
			entry.headers << ApiDocHeader{
				name: 'Authorization'
				description: 'Authentication token'
				value_sample: sample
			}
		}
	}

	// Content-Type
	ct := ctx.get_custom_header('Content-Type') or { '' }
	if ct.len > 0 {
		mut found := false
		for i in 0 .. entry.headers.len {
			if entry.headers[i].name == 'Content-Type' {
				if !entry.headers[i].locked {
					entry.headers[i].value_sample = ct
				}
				found = true
				break
			}
		}
		if !found {
			entry.headers << ApiDocHeader{
				name: 'Content-Type'
				description: 'Request body content type'
				value_sample: ct
			}
		}
	}

	// Accept
	accept := ctx.get_custom_header('Accept') or { '' }
	if accept.len > 0 {
		mut found := false
		for i in 0 .. entry.headers.len {
			if entry.headers[i].name == 'Accept' {
				if !entry.headers[i].locked {
					entry.headers[i].value_sample = accept
				}
				found = true
				break
			}
		}
		if !found {
			entry.headers << ApiDocHeader{
				name: 'Accept'
				description: 'Expected response content type'
				value_sample: accept
			}
		}
	}
}

fn parse_and_merge_form_params(mut entry &ApiDocEntry, ctx &veb.Context) {
	for key, val in ctx.form {
		if key.len == 0 { continue }

		// Check if parameter already exists
		mut found := false
		for i in 0 .. entry.parameters.len {
			if entry.parameters[i].name == key && entry.parameters[i].location == 'body' {
				if !entry.parameters[i].locked {
					// Add example value
					if val.len > 0 && entry.parameters[i].examples.len < 5 {
						mut exists := false
						for ex in entry.parameters[i].examples {
							if ex == val { exists = true; break }
						}
						if !exists {
							entry.parameters[i].examples << val
						}
					}
				}
				found = true
				break
			}
		}
		if !found {
			mut param := ApiDocParam{
				name:     key
				location: 'body'
				required: false
				type_:    infer_type(val)
			}
			if val.len > 0 {
				param.examples = [val]
			}
			entry.parameters << param
		}
	}
}

fn infer_type(val string) string {
	if val.len == 0 { return 'string' }
	if val == 'true' || val == 'false' { return 'bool' }
	mut is_int := true
	for ch in val {
		if ch < `0` || ch > `9` { is_int = false; break }
	}
	if is_int { return 'int' }
	if val.count('.') == 1 {
		mut is_float := true
		for ch in val {
			if (ch < `0` || ch > `9`) && ch != `.` { is_float = false; break }
		}
		if is_float { return 'float' }
	}
	return 'string'
}

// parse_json_response extracts property schema from a JSON response body
// Clears existing properties first to avoid duplication across multiple requests.
fn parse_json_response(mut entry &ApiDocEntry, body string) {
	root := json2.decode[json2.Any](body, json2.DecoderOptions{}) or { return }
	// Clear existing properties to prevent duplication on subsequent requests
	entry.response.properties.clear()
	extract_json2_props(mut entry.response, '', root, 0)
}

// extract_json2_props recursively extracts properties from json2.Any
// Only adds leaf nodes (primitives) to properties — objects/arrays are recursed into without adding the container path.
fn extract_json2_props(mut resp ApiDocResponse, prefix string, node json2.Any, depth int) {
	if depth > 3 { return }
	if node is map[string]json2.Any {
		obj := node as map[string]json2.Any
		for key, val in obj {
			path := if prefix.len > 0 { '${prefix}.${key}' } else { key }

			if val is json2.Null {
				resp.properties << ApiDocResponseProp{ path: path, type_: 'null' }
			} else if val is bool {
				resp.properties << ApiDocResponseProp{ path: path, type_: 'bool' }
			} else if val is int || val is i64 {
				resp.properties << ApiDocResponseProp{ path: path, type_: 'int' }
			} else if val is f64 {
				resp.properties << ApiDocResponseProp{ path: path, type_: 'float' }
			} else if val is string {
				resp.properties << ApiDocResponseProp{ path: path, type_: 'string' }
			} else if val is []json2.Any {
				arr := val as []json2.Any
				if arr.len > 0 && arr[0] is map[string]json2.Any {
					sub := arr[0] as map[string]json2.Any
					extract_json2_props(mut resp, '${path}[]', sub, depth + 1)
				} else {
					resp.properties << ApiDocResponseProp{ path: path, type_: 'array' }
				}
			} else if val is map[string]json2.Any {
				sub := val as map[string]json2.Any
				extract_json2_props(mut resp, path, sub, depth + 1)
			}
		}
	}
}
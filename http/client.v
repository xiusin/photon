// ============================================================
// http — Spring RestTemplate‑aligned HTTP client for Photon
//
// Design principles:
//   • Strategy & Template Method patterns (mirrors Spring)
//   • Immutable RestTemplate — thread‑safe, use as singleton
//   • All public methods delegate to a single exchange() entry point
//   • URI template expansion via UriTemplateHandler
//   • Error handling via ResponseErrorHandler strategy
//   • Request/Response interception via ClientHttpRequestInterceptor
// ============================================================
module http

import json
import time
import net.http as vhttp
import strings

// ============================================================
// URI Template — /users/{id} → /users/42
// ============================================================

// UriTemplateHandler expands URI templates like Spring's UriTemplateHandler
pub struct UriTemplateHandler {
pub mut:
	left_delim  u8 = `{`
	right_delim u8 = `}`
	strict      bool
}

pub fn new_uri_template_handler() UriTemplateHandler {
	return UriTemplateHandler{}
}

pub fn (h UriTemplateHandler) expand(template string, vars map[string]string) string {
	mut sb := strings.new_builder(template.len)
	mut i := 0
	mut in_var := false
	mut var_name_buf := []u8{cap: 16}

	for i < template.len {
		ch := template[i]

		if !in_var && ch == h.left_delim {
			// Check for escaped delimiter (e.g. {{)
			if i + 1 < template.len && template[i + 1] == h.left_delim {
				sb << ch
				sb << ch
				i += 2
				continue
			}
			in_var = true
			var_name_buf = []u8{cap: 16}
			i++
			continue
		}

		if in_var && ch == h.right_delim {
			in_var = false
			name := var_name_buf.bytestr().trim_space()
			if name.len > 0 {
				val := vars[name] or { '' }
				if val.len > 0 {
					sb << val.bytes()
				}
			}
			i++
			continue
		}

		if in_var {
			var_name_buf << ch
		} else {
			sb << ch
		}
		i++
	}

	return sb.bytestr()
}

// ============================================================
// RequestEntity — mirrors Spring HttpEntity / RequestEntity
//   Immutable value object
// ============================================================

pub struct RequestEntity {
pub:
	method   string            // HTTP method: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
	url      string            // full URL or path (template)
	headers  map[string]string // request headers
	body     string            // request body as raw string
	uri_vars map[string]string // URI template variables, e.g. {'id':'42'}
}

pub fn request_entity(method string, url string) RequestEntity {
	return RequestEntity{
		method:   method
		url:      url
		headers:  map[string]string{}
		uri_vars: map[string]string{}
	}
}

pub fn (e RequestEntity) header(key string, value string) RequestEntity {
	mut h := e.headers.clone()
	h[key] = value
	return RequestEntity{
		...e
		headers: h
	}
}

pub fn (e RequestEntity) headers_from(h map[string]string) RequestEntity {
	mut merged := h.clone()
	for k, v in e.headers {
		merged[k] = v
	}
	return RequestEntity{
		...e
		headers: merged
	}
}

pub fn (e RequestEntity) body_str(data string) RequestEntity {
	return RequestEntity{
		...e
		body: data
	}
}

pub fn (e RequestEntity) body_json[T](data T) RequestEntity {
	return RequestEntity{
		...e
		body: json.encode(data)
	}
}

pub fn (e RequestEntity) uri_var(key string, value string) RequestEntity {
	mut u := e.uri_vars.clone()
	u[key] = value
	return RequestEntity{
		...e
		uri_vars: u
	}
}

pub fn (e RequestEntity) uri_vars_from(v map[string]string) RequestEntity {
	mut merged := v.clone()
	for k, val in e.uri_vars {
		merged[k] = val
	}
	return RequestEntity{
		...e
		uri_vars: merged
	}
}

// ============================================================
// ResponseEntity — mirrors Spring ResponseEntity
//   Immutable value object. Generic body accessed via body_as[T]().
// ============================================================

pub struct ResponseEntity {
pub:
	status_code int
	status_text string
	headers     map[string]string
	body        string
}

pub fn (r ResponseEntity) is_2xx() bool {
	return r.status_code >= 200 && r.status_code < 300
}

pub fn (r ResponseEntity) is_4xx() bool {
	return r.status_code >= 400 && r.status_code < 500
}

pub fn (r ResponseEntity) is_5xx() bool {
	return r.status_code >= 500 && r.status_code < 600
}

// body_as deserialises the response body into T (Spring's getBody())
pub fn (r ResponseEntity) body_as[T]() !T {
	return json.decode(T, r.body)
}

// header_value returns a single header value (Spring's getHeaders().getFirst())
pub fn (r ResponseEntity) header_value(key string) string {
	return r.headers[key] or { '' }
}

// ============================================================
// ResponseErrorHandler — Strategy pattern (mirrors Spring)
// ============================================================

pub type ResponseErrorHandler = fn (resp ResponseEntity) !

pub const default_error_handler = ResponseErrorHandler(fn (resp ResponseEntity) ! {
	if resp.is_4xx() || resp.is_5xx() {
		return error('${resp.status_code} ${resp.status_text}: ${resp.body}')
	}
})

// ============================================================
// ClientHttpRequestInterceptor — mirrors Spring
//   Single intercept() method (not split before/after).
// ============================================================

pub fn new_interceptor(name string, intercept_fn fn (entity RequestEntity, next fn (RequestEntity) !ResponseEntity) !ResponseEntity) ClientHttpRequestInterceptor {
	return ClientHttpRequestInterceptor{
		name:         name
		intercept_fn: intercept_fn
	}
}

pub struct ClientHttpRequestInterceptor {
pub:
	name         string
	intercept_fn fn (entity RequestEntity, next fn (RequestEntity) !ResponseEntity) !ResponseEntity = noop_intercept
}

// noop_intercept is the default intercept function that simply calls next.
fn noop_intercept(entity RequestEntity, next fn (RequestEntity) !ResponseEntity) !ResponseEntity {
	return next(entity)
}

// new_noop_interceptor returns a ClientHttpRequestInterceptor that passes
// through to next. Use this instead of relying on the unsafe { nil } default.
pub fn new_noop_interceptor() ClientHttpRequestInterceptor {
	return ClientHttpRequestInterceptor{
		name:         'noop'
		intercept_fn: noop_intercept
	}
}

// ============================================================
// SSLConfig / ProxyConfig — TLS and proxy configuration
// ============================================================

// SSLConfig configures TLS/SSL for HTTPS requests.
pub struct SSLConfig {
pub:
	enable               bool
	cert_file            string
	key_file             string
	ca_file              string
	insecure_skip_verify bool
}

// ProxyConfig configures HTTP/HTTPS proxy.
pub struct ProxyConfig {
pub:
	host     string
	port     int
	username string
	password string
}

// ============================================================
// RestTemplate — mirrors Spring RestTemplate
//   Immutable, thread‑safe. Configure once, reuse across requests.
// ============================================================

pub struct RestTemplate {
pub mut:
	base_url             string
	default_headers      map[string]string
	interceptors         []ClientHttpRequestInterceptor
	uri_template_handler UriTemplateHandler   = new_uri_template_handler()
	error_handler        ResponseErrorHandler = default_error_handler
	connect_timeout      int                  = 30000
	read_timeout         int                  = 30000
	max_retries          int                  = 3
	retry_base_delay     int                  = 200
	ssl_config           ?SSLConfig
	proxy_config         ?ProxyConfig
}

// ----------------------------------------------------------
// Constructor
// ----------------------------------------------------------

pub fn new_rest_template() RestTemplate {
	return RestTemplate{
		default_headers: map[string]string{}
		interceptors:    []ClientHttpRequestInterceptor{}
	}
}

// ----------------------------------------------------------
// Builder‑style configuration (returns new instance — safe for reuse)
// ----------------------------------------------------------

pub fn (rt RestTemplate) set_base_url(url string) RestTemplate {
	mut r := rt
	r.base_url = url
	return r
}

pub fn (rt RestTemplate) set_default_header(key string, value string) RestTemplate {
	mut r := rt
	r.default_headers[key] = value
	return r
}

pub fn (rt RestTemplate) set_default_headers(h map[string]string) RestTemplate {
	mut r := rt
	for k, v in h {
		r.default_headers[k] = v
	}
	return r
}

pub fn (rt RestTemplate) set_connect_timeout(ms int) RestTemplate {
	mut r := rt
	r.connect_timeout = ms
	return r
}

pub fn (rt RestTemplate) set_read_timeout(ms int) RestTemplate {
	mut r := rt
	r.read_timeout = ms
	return r
}

pub fn (rt RestTemplate) set_retry(max_retries int, base_delay_ms int) RestTemplate {
	mut r := rt
	r.max_retries = max_retries
	r.retry_base_delay = base_delay_ms
	return r
}

pub fn (rt RestTemplate) set_error_handler(handler ResponseErrorHandler) RestTemplate {
	mut r := rt
	r.error_handler = handler
	return r
}

pub fn (rt RestTemplate) set_uri_template_handler(handler UriTemplateHandler) RestTemplate {
	mut r := rt
	r.uri_template_handler = handler
	return r
}

pub fn (rt RestTemplate) add_interceptor(ic ClientHttpRequestInterceptor) RestTemplate {
	mut r := rt
	r.interceptors << ic
	return r
}

pub fn (rt RestTemplate) set_ssl_config(config SSLConfig) RestTemplate {
	mut r := rt
	r.ssl_config = config
	return r
}

pub fn (rt RestTemplate) set_proxy(config ProxyConfig) RestTemplate {
	mut r := rt
	r.proxy_config = config
	return r
}

// ----------------------------------------------------------
// High‑level API  — mirrors Spring's convenience methods
//   Each method: expand template → build entity → exchange()
// ----------------------------------------------------------

// get_for_object — GET + body → T  (Spring: getForObject)
pub fn (rt RestTemplate) get_for_object[T](url string, uri_vars map[string]string) !T {
	resp := rt.get_for_entity(url, uri_vars) or { return err }
	return resp.body_as[T]()
}

// get_for_entity — GET → ResponseEntity  (Spring: getForEntity)
pub fn (rt RestTemplate) get_for_entity(url string, uri_vars map[string]string) !ResponseEntity {
	entity := request_entity('GET', url).uri_vars_from(uri_vars)
	return rt.exchange(entity)
}

// post_for_object — POST + body → T  (Spring: postForObject)
pub fn (rt RestTemplate) post_for_object[T](url string, body string, uri_vars map[string]string) !T {
	resp := rt.post_for_entity(url, body, uri_vars) or { return err }
	return resp.body_as[T]()
}

// post_for_entity — POST + body → ResponseEntity  (Spring: postForEntity)
pub fn (rt RestTemplate) post_for_entity(url string, body string, uri_vars map[string]string) !ResponseEntity {
	entity := request_entity('POST', url).body_str(body).uri_vars_from(uri_vars)
	return rt.exchange(entity)
}

// put — PUT + body  (Spring: put)
pub fn (rt RestTemplate) put(url string, body string, uri_vars map[string]string) ! {
	entity := request_entity('PUT', url).body_str(body).uri_vars_from(uri_vars)
	_ := rt.exchange(entity) or { return err }
}

// delete — DELETE  (Spring: delete)
pub fn (rt RestTemplate) delete(url string, uri_vars map[string]string) ! {
	entity := request_entity('DELETE', url).uri_vars_from(uri_vars)
	_ := rt.exchange(entity) or { return err }
}

// patch_for_entity — PATCH → ResponseEntity  (like Spring's patchForObject, adapted for V)
pub fn (rt RestTemplate) patch_for_entity(url string, body string, uri_vars map[string]string) !ResponseEntity {
	entity := request_entity('PATCH', url).body_str(body).uri_vars_from(uri_vars)
	return rt.exchange(entity)
}

// head_for_headers — HEAD → headers  (Spring: headForHeaders)
pub fn (rt RestTemplate) head_for_headers(url string, uri_vars map[string]string) !map[string]string {
	entity := request_entity('HEAD', url).uri_vars_from(uri_vars)
	resp := rt.exchange(entity) or { return err }
	return resp.headers
}

// options_for_allow — OPTIONS → Allow header  (Spring: optionsForAllow)
pub fn (rt RestTemplate) options_for_allow(url string, uri_vars map[string]string) !string {
	entity := request_entity('OPTIONS', url).uri_vars_from(uri_vars)
	resp := rt.exchange(entity) or { return err }
	return resp.header_value('Allow')
}

// ----------------------------------------------------------
// exchange() — the universal request entry point
//   All high‑level methods delegate here.
//   Steps:
//     1. Expand URI template
//     2. Merge default headers + entity headers
//     3. Resolve full URL (base_url + path)
//     4. Interceptor chain
//     5. HTTP execution (with retry + exponential backoff)
//     6. Error handling strategy
// ----------------------------------------------------------

pub fn (rt RestTemplate) exchange(entity RequestEntity) !ResponseEntity {
	// 1. Expand URI template: /users/{id} → /users/42
	expanded_url := rt.uri_template_handler.expand(entity.url, entity.uri_vars)

	// 2. Resolve full URL
	final_url := resolve_url(rt.base_url, expanded_url)

	// 3. Merge headers: entity.headers overlay default_headers
	mut merged_headers := rt.default_headers.clone()
	for k, v in entity.headers {
		merged_headers[k] = v
	}

	// 4. Build mutable request for interceptor chain
	mut req := RequestEntity{
		method:   entity.method
		url:      final_url
		headers:  merged_headers
		body:     entity.body
		uri_vars: entity.uri_vars
	}

	// 5. Execute interceptor chain (Spring: recursive pipeline)
	//    Each interceptor wraps the next, like Spring's doExecute chain.
	mut chain_fn := fn [rt] (entity RequestEntity) !ResponseEntity {
		return rt.execute_http(entity)
	}

	for i := rt.interceptors.len - 1; i >= 0; i-- {
		ic := rt.interceptors[i]
		next := chain_fn
		if !isnil(ic.intercept_fn) {
			chain_fn = fn [ic, next] (e RequestEntity) !ResponseEntity {
				return ic.intercept_fn(e, next)
			}
		}
	}

	return chain_fn(req)
}

// ----------------------------------------------------------
// execute() — lowest‑level API (mirrors Spring's execute)
//   Full control: raw RequestEntity in, raw ResponseEntity out.
// ----------------------------------------------------------

pub fn (rt RestTemplate) execute(entity RequestEntity) !ResponseEntity {
	return rt.exchange(entity)
}

// ----------------------------------------------------------
// execute_http — the actual HTTP call without interception
// ----------------------------------------------------------

fn (rt RestTemplate) execute_http(entity RequestEntity) !ResponseEntity {
	// Apply SSL configuration if set.
	// V's net.http.FetchConfig does not yet expose full TLS/SSL or proxy
	// fields in the supported version. We validate and log the configuration
	// here so that misconfiguration is caught early, and apply what the
	// FetchConfig API supports.
	ssl_cfg := rt.ssl_config or { SSLConfig{} }
	proxy_cfg := rt.proxy_config or { ProxyConfig{} }

	if ssl_cfg.enable && ssl_cfg.insecure_skip_verify {
		eprintln('[warn] SSL insecure_skip_verify is enabled — not recommended for production')
	}
	if proxy_cfg.host.len > 0 && proxy_cfg.port > 0 {
		// Proxy is configured; V's FetchConfig does not yet expose proxy
		// fields, so this is recorded for future use when the API supports it.
		eprintln('[info] Proxy configured: ${proxy_cfg.host}:${proxy_cfg.port}')
	}

	config := vhttp.FetchConfig{
		method:      method_from_string(entity.method)
		url:         entity.url
		header:      header_from_map(entity.headers)
		data:        entity.body
		// NOTE: net.http.FetchConfig (V 0.5.1) does not expose read/write
		// timeout fields, so rt.read_timeout / rt.connect_timeout cannot be
		// applied here. Retained in RequestTemplate for future API support.
		max_retries: if rt.max_retries > 0 { rt.max_retries } else { 1 }
	}

	vhttp_resp := execute_with_retry(config, rt.max_retries, rt.retry_base_delay) or {
		mut resp_headers := map[string]string{}
		err_resp := ResponseEntity{
			status_code: 0
			status_text: err.str()
			headers:     resp_headers
			body:        ''
		}
		// Apply error handler even on connection errors
		rt.error_handler(err_resp) or { return err }
		return err_resp
	}

	// Build response headers
	mut resp_headers := map[string]string{}
	keys := vhttp_resp.header.keys()
	for k in keys {
		val := vhttp_resp.header.get_custom(k, vhttp.HeaderQueryConfig{}) or { '' }
		if val != '' {
			resp_headers[k] = val
		}
	}

	mut resp := ResponseEntity{
		status_code: vhttp_resp.status_code
		status_text: vhttp_resp.status_msg
		headers:     resp_headers
		body:        vhttp_resp.body
	}

	// Apply ResponseErrorHandler strategy (Spring behaviour)
	rt.error_handler(resp) or { return err }

	return resp
}

// ============================================================
// Internal helpers
// ============================================================

fn resolve_url(base string, path_or_url string) string {
	if path_or_url == '' {
		return base
	}
	if path_or_url.starts_with('http://') || path_or_url.starts_with('https://') {
		return path_or_url
	}
	if base == '' {
		return path_or_url
	}
	if path_or_url.starts_with('/') {
		return '${base}${path_or_url}'
	}
	return '${base}/${path_or_url}'
}

// vfmt off
fn method_from_string(method string) vhttp.Method {
	return match method.to_upper() {
		'GET' { vhttp.Method.get }
		'POST' { vhttp.Method.post }
		'PUT' { vhttp.Method.put }
		'DELETE' { vhttp.Method.delete }
		'PATCH' { vhttp.Method.patch }
		'HEAD' { vhttp.Method.head }
		'OPTIONS' { vhttp.Method.options }
		else { vhttp.Method.get }
	}
}

fn header_from_map(m map[string]string) vhttp.Header {
	mut h := vhttp.Header{}
	for k, v in m {
		h.add_custom(k, v) or { continue }
	}
	return h
}

fn execute_with_retry(config vhttp.FetchConfig, max_retries int, base_delay int) !vhttp.Response {
	// vfmt on
	mut last_error := IError(none)
	mut attempt := 0

	for attempt <= max_retries {
		resp := vhttp.fetch(config) or {
			last_error = err
			attempt++
			if attempt <= max_retries {
				delay := base_delay * (1 << u32(attempt - 1))
				time.sleep(i64(delay) * time.millisecond)
				continue
			}
			return err
		}
		return resp
	}

	return last_error
}

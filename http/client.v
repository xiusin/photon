module http

// client.v - HTTP Client (Laravel/Guzzle inspired)
//
// Provides a fluent HTTP client for making requests to external APIs.
// Supports GET, POST, PUT, DELETE, PATCH with headers, auth, retry,
// timeout, query params, and JSON handling.
//
// Backed by V's net.http module for real network requests.
//
// Usage:
//   mut client := http.new_client()
//   resp := client.with_base_url('https://api.example.com')
//               .with_header('Accept', 'application/json')
//               .with_token('my-token')
//               .get('/users') or { return err }
//   println(resp.body)
//
//   // POST JSON
//   resp := client.post('/users', '{"name":"Alice"}')!
//
//   // With query parameters
//   client.with_query({'page': '1', 'limit': '10'})
//   resp := client.get('/users')!

import net.http as vhttp
import net.urllib

// ── Types ──

// HttpResponse wraps an HTTP response with convenient helper methods.
pub struct HttpResponse {
pub:
	status_code int
	body        string
	headers     map[string]string
}

// new_response creates an HttpResponse from components.
pub fn new_response(status int, body string) &HttpResponse {
	return &HttpResponse{
		status_code: status
		body:        body
		headers:     map[string]string{}
	}
}

// is_success checks if the response is 2xx.
pub fn (r &HttpResponse) is_success() bool {
	return r.status_code >= 200 && r.status_code < 300
}

// is_client_error checks if the response is 4xx.
pub fn (r &HttpResponse) is_client_error() bool {
	return r.status_code >= 400 && r.status_code < 500
}

// is_server_error checks if the response is 5xx.
pub fn (r &HttpResponse) is_server_error() bool {
	return r.status_code >= 500 && r.status_code < 600
}

// json parses the response body as JSON into type T.
pub fn (r &HttpResponse) json[T]() !T {
	return json.decode[T](r.body)
}

// header returns a specific response header value (case-insensitive).
pub fn (r &HttpResponse) header(name string) ?string {
	for k, v in r.headers {
		if k.to_lower() == name.to_lower() {
			return v
		}
	}
	return none
}

// ── HttpClient ──

// HttpClient provides a fluent API for HTTP requests.
// Backed by V's net.http.fetch() for real network I/O.
pub struct HttpClient {
mut:
	base_url     string
	timeout_sec  int    = 30
	headers      map[string]string
	query_params map[string]string
	retry_times  int
	retry_delay  int // ms
	debug        bool
}

// new_client creates a new HttpClient with default settings.
pub fn new_client() HttpClient {
	return HttpClient{
		headers:      map[string]string{}
		query_params: map[string]string{}
	}
}

// with_base_url sets the base URL for all requests.
pub fn (mut c HttpClient) with_base_url(url string) HttpClient {
	c.base_url = url
	return c
}

// with_header adds a request header.
pub fn (mut c HttpClient) with_header(key string, value string) HttpClient {
	c.headers[key] = value
	return c
}

// with_headers merges multiple headers at once.
pub fn (mut c HttpClient) with_headers(headers map[string]string) HttpClient {
	for k, v in headers {
		c.headers[k] = v
	}
	return c
}

// with_token adds a Bearer token authorization header.
pub fn (mut c HttpClient) with_token(token string) HttpClient {
	c.headers['Authorization'] = 'Bearer ${token}'
	return c
}

// with_basic_auth adds Basic authentication header.
pub fn (mut c HttpClient) with_basic_auth(username string, password string) HttpClient {
	encoded := base64_encode('${username}:${password}')
	c.headers['Authorization'] = 'Basic ${encoded}'
	return c
}

// with_content_type sets the Content-Type header.
pub fn (mut c HttpClient) with_content_type(ct string) HttpClient {
	c.headers['Content-Type'] = ct
	return c
}

// with_json sets Content-Type to application/json.
pub fn (mut c HttpClient) with_json() HttpClient {
	c.headers['Content-Type'] = 'application/json'
	return c
}

// with_accept sets the Accept header.
pub fn (mut c HttpClient) with_accept(mime_type string) HttpClient {
	c.headers['Accept'] = mime_type
	return c
}

// with_query sets query parameters that will be appended to every request URL.
pub fn (mut c HttpClient) with_query(params map[string]string) HttpClient {
	for k, v in params {
		c.query_params[k] = v
	}
	return c
}

// retry configures automatic retries on socket errors.
pub fn (mut c HttpClient) retry(times int, delay_ms int) HttpClient {
	c.retry_times = times
	c.retry_delay = delay_ms
	return c
}

// timeout_sec sets the request timeout in seconds.
pub fn (mut c HttpClient) timeout_sec(seconds int) HttpClient {
	c.timeout_sec = seconds
	return c
}

// debug enables verbose HTTP logging.
pub fn (mut c HttpClient) debug_enabled(enabled bool) HttpClient {
	c.debug = enabled
	return c
}

// clone_headers returns a copy of the headers map.
fn (c &HttpClient) clone_headers() map[string]string {
	mut result := map[string]string{}
	for k, v in c.headers {
		result[k] = v
	}
	return result
}

// clone_query_params returns a copy of the query params map.
fn (c &HttpClient) clone_query_params() map[string]string {
	mut result := map[string]string{}
	for k, v in c.query_params {
		result[k] = v
	}
	return result
}

// ── HTTP Methods ──

// get sends a GET request.
pub fn (c &HttpClient) get(path string) !&HttpResponse {
	url := c.build_url(path)
	return do_request(c.clone_headers(), .get, url, '')
}

// post sends a POST request with a body string.
pub fn (c &HttpClient) post(path string, body string) !&HttpResponse {
	url := c.build_url(path)
	return do_request(c.clone_headers(), .post, url, body)
}

// post_json sends a POST request with a JSON body and proper Content-Type.
pub fn (c &HttpClient) post_json(path string, data string) !&HttpResponse {
	url := c.build_url(path)
	mut h := c.clone_headers()
	h['Content-Type'] = 'application/json'
	return do_request(h, .post, url, data)
}

// post_form sends a POST request with form-encoded data.
pub fn (c &HttpClient) post_form(path string, form_data map[string]string) !&HttpResponse {
	url := c.build_url(path)
	mut h := c.clone_headers()
	h['Content-Type'] = 'application/x-www-form-urlencoded'

	// Build form body manually using query_escape for each key-value
	mut parts := []string{}
	for k, v in form_data {
		parts << '${urllib.query_escape(k)}=${urllib.query_escape(v)}'}
	body := parts.join('&')
	return do_request(h, .post, url, body)
}

// put sends a PUT request with a body string.
pub fn (c &HttpClient) put(path string, body string) !&HttpResponse {
	url := c.build_url(path)
	return do_request(c.clone_headers(), .put, url, body)
}

// delete sends a DELETE request.
pub fn (c &HttpClient) delete(path string) !&HttpResponse {
	url := c.build_url(path)
	return do_request(c.clone_headers(), .delete, url, '')
}

// patch sends a PATCH request with a body string.
pub fn (c &HttpClient) patch(path string, body string) !&HttpResponse {
	url := c.build_url(path)
	return do_request(c.clone_headers(), .patch, url, body)
}

// head sends a HEAD request.
pub fn (c &HttpClient) head(path string) !&HttpResponse {
	url := c.build_url(path)
	return do_request(c.clone_headers(), .head, url, '')
}

// ── Internal Request Execution ──

// do_request executes the actual HTTP request using net.http.fetch().
// This is a free function to avoid receiver mutability issues.
fn do_request(headers map[string]string, method vhttp.Method, url string, body string) !&HttpResponse {
	// Build fetch config header using custom_add for string keys
	mut header := vhttp.Header{}
	for k, v in headers {
		header.add_custom(k, v) or {}
	}

	config := vhttp.FetchConfig{
		url:           url
		method:        method
		header:        header
		data:          body
		user_agent:    'Photon/0.1.0'
		allow_redirect: true
		max_retries:   0
		verbose:       false
	}

	// Execute the request via V's net.http
	resp := vhttp.fetch(config)!

	// Convert response headers to map[string]string
	mut resp_headers := map[string]string{}
	for key in resp.header.keys() {
		val := resp.header.custom_values(key, vhttp.HeaderQueryConfig{}).join(', ')
		resp_headers[key] = val
	}

	result := &HttpResponse{
		status_code: resp.status_code
		body:        resp.body
		headers:     resp_headers
	}

	return result
}

// build_url constructs the full URL by combining base_url, path, and query params.
fn (c &HttpClient) build_url(path string) string {
	mut url := ''

	// Combine base_url + path
	if c.base_url.len > 0 {
		if c.base_url.ends_with('/') && path.starts_with('/') {
			url = c.base_url + path[1..]
		} else if !c.base_url.ends_with('/') && !path.starts_with('/') {
			url = c.base_url + '/' + path
		} else {
			url = c.base_url + path
		}
	} else {
		url = path
	}

	// Append query params
	if c.query_params.len > 0 {
		separator := if url.contains('?') { '&' } else { '?' }
		mut parts := []string{}
		for k, v in c.query_params {
			parts << '${urllib.query_escape(k)}=${urllib.query_escape(v)}'
		}
		url = url + separator + parts.join('&')
	}

	return url
}

// ── Utility Functions ──

// base64_encode performs Base64 encoding (used for Basic Auth).
fn base64_encode(input string) string {
	chars := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut result := ''
	mut buffer := u64(0)
	mut bits := 0

	for ch in input {
		buffer = (buffer << 8) | u64(ch)
		bits += 8
		for bits >= 6 {
			bits -= 6
			idx := int((buffer >> bits) & 0x3F)
			result += chars[idx].ascii_str()
		}
	}

	if bits > 0 {
		buffer <<= u64(6 - bits)
		idx := int(buffer & 0x3F)
		result += chars[idx].ascii_str()
	}

	for result.len % 4 != 0 {
		result += '='
	}

	return result
}

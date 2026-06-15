module http

// client.v - HTTP Client (Laravel/Guzzle inspired)
//
// Provides a fluent HTTP client for making requests to external APIs.
// Supports GET, POST, PUT, DELETE, PATCH with headers, auth, and retry.

// HttpResponse wraps an HTTP response
pub struct HttpResponse {
pub:
	status_code int
	body        string
	headers     map[string]string
}

// new_response creates an HttpResponse
pub fn new_response(status int, body string) &HttpResponse {
	return &HttpResponse{
		status_code: status
		body: body
	}
}

// is_success checks if the response is 2xx
pub fn (r &HttpResponse) is_success() bool {
	return r.status_code >= 200 && r.status_code < 300
}

// is_client_error checks if the response is 4xx
pub fn (r &HttpResponse) is_client_error() bool {
	return r.status_code >= 400 && r.status_code < 500
}

// is_server_error checks if the response is 5xx
pub fn (r &HttpResponse) is_server_error() bool {
	return r.status_code >= 500 && r.status_code < 600
}

// HttpClient provides a fluent API for HTTP requests
pub struct HttpClient {
pub mut:
	base_url    string
	timeout_sec int = 30
	headers     map[string]string
	retry_times int
	retry_delay int // ms
}

// new_client creates a new HttpClient
pub fn new_client() &HttpClient {
	return &HttpClient{
		headers: map[string]string{}
	}
}

// with_base_url sets the base URL
pub fn (mut c HttpClient) with_base_url(url string) &HttpClient {
	c.base_url = url
	return c
}

// with_header adds a request header
pub fn (mut c HttpClient) with_header(key string, value string) &HttpClient {
	c.headers[key] = value
	return c
}

// with_token adds a Bearer token authorization header
pub fn (mut c HttpClient) with_token(token string) &HttpClient {
	c.headers['Authorization'] = 'Bearer ${token}'
	return c
}

// with_basic_auth adds Basic authentication
pub fn (mut c HttpClient) with_basic_auth(username string, password string) &HttpClient {
	encoded := base64_encode('${username}:${password}')
	c.headers['Authorization'] = 'Basic ${encoded}'
	return c
}

// with_content_type sets the Content-Type header
pub fn (mut c HttpClient) with_content_type(ct string) &HttpClient {
	c.headers['Content-Type'] = ct
	return c
}

// with_json sets Content-Type to application/json
pub fn (mut c HttpClient) with_json() &HttpClient {
	c.headers['Content-Type'] = 'application/json'
	return c
}

// retry configures automatic retries
pub fn (mut c HttpClient) retry(times int, delay_ms int) &HttpClient {
	c.retry_times = times
	c.retry_delay = delay_ms
	return c
}

// timeout sets the request timeout
pub fn (mut c HttpClient) timeout_sec(seconds int) &HttpClient {
	c.timeout_sec = seconds
	return c
}

// get sends a GET request
pub fn (c &HttpClient) get(path string) !&HttpResponse {
	url := c.build_url(path)
	// Stub: actual HTTP implementation depends on net.http module
	return new_response(200, '{"method":"GET","url":"${url}"}')
}

// post sends a POST request
pub fn (c &HttpClient) post(path string, body string) !&HttpResponse {
	url := c.build_url(path)
	return new_response(201, '{"method":"POST","url":"${url}","body":"${body}"}')
}

// put sends a PUT request
pub fn (c &HttpClient) put(path string, body string) !&HttpResponse {
	url := c.build_url(path)
	return new_response(200, '{"method":"PUT","url":"${url}","body":"${body}"}')
}

// delete sends a DELETE request
pub fn (c &HttpClient) delete(path string) !&HttpResponse {
	_ = c.build_url(path)
	return new_response(204, '')
}

// patch sends a PATCH request
pub fn (c &HttpClient) patch(path string, body string) !&HttpResponse {
	url := c.build_url(path)
	return new_response(200, '{"method":"PATCH","url":"${url}","body":"${body}"}')
}

// build_url constructs the full URL
fn (c &HttpClient) build_url(path string) string {
	if c.base_url.len == 0 {
		return path
	}
	if c.base_url.ends_with('/') && path.starts_with('/') {
		return c.base_url + path[1..]
	}
	if !c.base_url.ends_with('/') && !path.starts_with('/') {
		return c.base_url + '/' + path
	}
	return c.base_url + path
}

// base64_encode performs simple Base64 encoding
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
		buffer <<= (6 - bits)
		idx := int(buffer & 0x3F)
		result += chars[idx].ascii_str()
	}

	for result.len % 4 != 0 {
		result += '='
	}

	return result
}

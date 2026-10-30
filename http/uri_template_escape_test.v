module http

// URI template variables are values, not template fragments.
//
// Old behaviour (all four verified by running the previous implementation):
//   expand('/api/{x}',    {})                    => '/api/'               path silently lost a segment
//   expand('/users/{id',  {'id':'42'})           => '/users/'             unclosed placeholder swallowed
//   expand('/users/{id}', {'id':'../../admin'})  => '/users/../../admin'  path traversal from data
//   expand('/s?q={q}',    {'q':'a&role=admin'})  => '/s?q=a&role=admin'   injected query parameter
fn test_unknown_variable_stays_literal() {
	h := new_uri_template_handler()
	assert h.expand('/api/{x}', map[string]string{}) == '/api/{x}'
	assert h.expand('/api/{x}/{y}', { 'y': 'ok' }) == '/api/{x}/ok'
}

fn test_unclosed_placeholder_is_not_dropped() {
	h := new_uri_template_handler()
	assert h.expand('/users/{id', { 'id': '42' }) == '/users/{id'
}

fn test_variable_value_cannot_escape_the_path_segment() {
	h := new_uri_template_handler()
	got := h.expand('/users/{id}', { 'id': '../../admin' })
	assert got == '/users/..%2F..%2Fadmin'
	assert !got.contains('..\\/..')

	got2 := h.expand('/users/{id}', { 'id': 'a b' })
	assert got2 == '/users/a%20b'
}

fn test_variable_value_cannot_inject_query_parameters() {
	h := new_uri_template_handler()
	got := h.expand('/s?q={q}', { 'q': 'a&role=admin' })
	// '=' is a safe sub-delim (kept); '/' 'assert got == '/s?q=a%26role%3Dadmin'' '?' '#' are not.
	assert got == '/s?q=a%26role=admin'
	// The '&' is gone, so 'role=admin' can no longer be a separate parameter.
	assert !got.contains('&role')
}

fn test_ordinary_values_are_untouched() {
	h := new_uri_template_handler()
	assert h.expand('/api/users/{id}/posts/{post_id}', {
		'id':      '42'
		'post_id': '7'
	}) == '/api/users/42/posts/7'
	// Unreserved characters and the safe sub-delims survive encoding.
	assert h.expand('/f/{name}', { 'name': 'a-b_c.d~e,f;g=h:i@j' }) == '/f/a-b_c.d~e,f;g=h:i@j'
}

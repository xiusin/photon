module web

// problem_detail_test.v - Tests for ProblemDetail (RFC 7807)

fn test_new_problem_detail() {
	pd := new_problem_detail(404, 'User Not Found')
	assert pd.status == 404
	assert pd.title == 'User Not Found'
	assert pd.type_ == 'about:blank'
	assert pd.errors.len == 0
}

fn test_problem_detail_builder() {
	mut pd := new_problem_detail(422, 'Validation Failed')
	pd.set_type('https://example.com/errors/validation')
	pd.set_detail('Email field is required')
	pd.set_instance('/api/users/42')
	pd.add_error('email', 'must be a valid email address')
	pd.add_error('password', 'must be at least 8 characters')

	assert pd.type_ == 'https://example.com/errors/validation'
	assert pd.detail == 'Email field is required'
	assert pd.instance_ == '/api/users/42'
	assert pd.errors.len == 2
	assert pd.errors[0].field == 'email'
	assert pd.errors[0].message == 'must be a valid email address'
	assert pd.errors[1].field == 'password'
}

fn test_problem_detail_not_found() {
	pd := problem_detail_not_found('Resource Not Found')
	assert pd.status == 404
	assert pd.title == 'Resource Not Found'
}

fn test_problem_detail_bad_request() {
	pd := problem_detail_bad_request('Bad Request')
	assert pd.status == 400
}

fn test_problem_detail_validation() {
	pd := problem_detail_validation('Validation Failed')
	assert pd.status == 422
}

fn test_problem_detail_internal_error() {
	pd := problem_detail_internal_error('Internal Server Error')
	assert pd.status == 500
}

fn test_problem_detail_unauthorized() {
	pd := problem_detail_unauthorized('Unauthorized')
	assert pd.status == 401
}

fn test_problem_detail_forbidden() {
	pd := problem_detail_forbidden('Forbidden')
	assert pd.status == 403
}

fn test_problem_detail_conflict() {
	pd := problem_detail_conflict('Conflict')
	assert pd.status == 409
}

fn test_problem_detail_too_many_requests() {
	pd := problem_detail_too_many_requests('Too Many Requests')
	assert pd.status == 429
}

fn test_problem_detail_to_json() {
	mut pd := new_problem_detail(404, 'User Not Found')
	pd.set_type('https://example.com/errors/user-not-found')
	pd.set_detail('User with ID 42 does not exist')
	pd.set_instance('/api/users/42')

	json_str := pd.to_json()

	// Verify the JSON contains expected fields
	assert json_str.contains('"type":"https://example.com/errors/user-not-found"')
	assert json_str.contains('"title":"User Not Found"')
	assert json_str.contains('"status":404')
	assert json_str.contains('"detail":"User with ID 42 does not exist"')
	assert json_str.contains('"instance":"/api/users/42"')
}

fn test_problem_detail_to_json_with_errors() {
	mut pd := new_problem_detail(422, 'Validation Failed')
	pd.add_error('email', 'must be a valid email address')
	pd.add_error('password', 'must be at least 8 characters')

	json_str := pd.to_json()

	assert json_str.contains('"errors":[')
	assert json_str.contains('"field":"email"')
	assert json_str.contains('"message":"must be a valid email address"')
	assert json_str.contains('"field":"password"')
}

fn test_problem_detail_to_json_minimal() {
	pd := new_problem_detail(500, 'Internal Server Error')

	json_str := pd.to_json()

	assert json_str.contains('"type":"about:blank"')
	assert json_str.contains('"title":"Internal Server Error"')
	assert json_str.contains('"status":500')
	// detail and instance should not be present when not set
	assert !json_str.contains('"detail"')
	assert !json_str.contains('"instance"')
}

fn test_from_http_exception() {
	e := new_http_exception(404, 'User Not Found')
	pd := from_http_exception(e)

	assert pd.status == 404
	assert pd.title == 'User Not Found'
}

fn test_from_http_exception_with_details() {
	mut details := map[string]string{}
	details['field'] = 'email'
	e := new_http_exception_with_details(422, 'Validation Failed', details)
	pd := from_http_exception(e)

	assert pd.status == 422
	assert pd.errors.len == 1
	assert pd.errors[0].field == 'field'
	assert pd.errors[0].message == 'email'
}

fn test_problem_detail_handler() {
	handler := new_problem_detail_handler()
	err := error('test error')

	pd := handler.handle(err, 400)
	assert pd.status == 400
	assert pd.detail == 'test error'
}

fn test_problem_detail_handler_http_exception() {
	handler := new_problem_detail_handler()
	e := new_http_exception(403, 'Forbidden')

	pd := handler.handle_http_exception(e)
	assert pd.status == 403
	assert pd.title == 'Forbidden'
}

fn test_field_error_struct() {
	fe := FieldError{
		field: 'username'
		message: 'already exists'
	}
	assert fe.field == 'username'
	assert fe.message == 'already exists'
}

fn test_add_errors_bulk() {
	mut pd := new_problem_detail(422, 'Validation Failed')
	errors := [
		FieldError{ field: 'name', message: 'is required' },
		FieldError{ field: 'email', message: 'is invalid' },
	]
	pd.add_errors(errors)

	assert pd.errors.len == 2
	assert pd.errors[0].field == 'name'
	assert pd.errors[1].field == 'email'
}

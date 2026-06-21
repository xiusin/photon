module web

// result_test.v - Tests for Result and PageResult

fn test_result_success() {
	r := success('{"id":1}')
	assert r.success == true
	assert r.code == 200
	assert r.message == 'OK'
	assert r.data == '{"id":1}'
}

fn test_result_success_with_msg() {
	r := success_with_msg('{"id":1}', 'Created successfully')
	assert r.success == true
	assert r.code == 200
	assert r.message == 'Created successfully'
}

fn test_result_fail() {
	r := fail(500, 'error occurred')
	assert r.success == false
	assert r.code == 500
	assert r.message == 'error occurred'
}

fn test_result_ok() {
	r := ok('data')
	assert r.success == true
	assert r.code == 200
}

fn test_result_created() {
	r := created('{"id":2}')
	assert r.success == true
	assert r.code == 201
	assert r.message == 'Created'
}

fn test_result_no_content() {
	r := no_content()
	assert r.success == true
	assert r.code == 204
}

fn test_result_bad_request() {
	r := bad_request('invalid input')
	assert r.success == false
	assert r.code == 400
	assert r.message.contains('invalid')
}

fn test_result_not_found() {
	r := not_found('user not found')
	assert r.success == false
	assert r.code == 404
}

fn test_result_internal_error() {
	r := internal_error('server error')
	assert r.success == false
	assert r.code == 500
}

fn test_result_unauthorized() {
	r := unauthorized('access denied')
	assert r.success == false
	assert r.code == 401
}

fn test_result_forbidden() {
	r := forbidden('no permission')
	assert r.success == false
	assert r.code == 403
}

fn test_result_conflict() {
	r := conflict('duplicate')
	assert r.success == false
	assert r.code == 409
}

fn test_page_result() {
	pr := page('["item1","item2","item3"]', 1, 10, 30)
	assert pr.success == true
	assert pr.code == 200
	assert pr.pagination.total == 30
	assert pr.pagination.page == 1
	assert pr.pagination.page_size == 10
	assert pr.pagination.total_pages == 3
	assert pr.pagination.has_next == true
	assert pr.pagination.has_prev == false
}

fn test_page_result_last_page() {
	pr := page('["item1"]', 3, 10, 25)
	assert pr.pagination.has_next == false
	assert pr.pagination.has_prev == true
}

fn test_page_result_only_page() {
	pr := page('["item1"]', 1, 10, 5)
	assert pr.pagination.has_next == false
	assert pr.pagination.has_prev == false
}

module main

// tests/exception_test.v — 异常处理器测试
//
// 测试覆盖：
//   - ExceptionHandlerRegistry 默认处理器注册
//   - 各 HttpException 子类型状态码映射（400/401/403/404/409/422/429/500/503）
//   - 自定义异常处理器注册与覆盖
//   - 默认处理器回退机制
//   - 未知异常回退到 500
//   - HttpException 构造函数与状态码字段

import photon.web

// ═══════════════════════════════════════════════════════════
// ExceptionHandlerRegistry 基础测试
// ═══════════════════════════════════════════════════════════

fn test_exception_handler_creation() {
	mut handler := web.new_exception_handler()
	assert !isnil(handler)
}

fn test_exception_handler_default_handlers_registered() {
	// 默认应注册所有常见 HttpException 处理器
	mut handler := web.new_exception_handler()
	assert 'BadRequestException' in handler.handlers
	assert 'UnauthorizedException' in handler.handlers
	assert 'ForbiddenException' in handler.handlers
	assert 'NotFoundException' in handler.handlers
	assert 'ConflictException' in handler.handlers
	assert 'ValidationException' in handler.handlers
	assert 'RateLimitExceededException' in handler.handlers
	assert 'InternalServerErrorException' in handler.handlers
	assert 'ServiceUnavailableException' in handler.handlers
}

fn test_exception_handler_register_custom() {
	mut handler := web.new_exception_handler()
	handler.register('MyCustomError', fn (err IError) string {
		return '{"code":418,"message":"I am a teapot"}'
	})

	assert 'MyCustomError' in handler.handlers
	body := handler.handle(error('test'))
	// 没匹配到自定义错误，但应正常返回（fallback 到默认处理）
	assert body.len > 0
}

fn test_exception_handler_register_default() {
	mut handler := web.new_exception_handler()
	handler.register_default_handler(fn (err IError) string {
		return '{"code":999,"message":"fallback"}'
	})

	assert !isnil(handler.default_handler)
	body := handler.handle(error('unknown'))
	assert body.contains('999')
}

// ═══════════════════════════════════════════════════════════
// HttpException 状态码提取测试
// ═══════════════════════════════════════════════════════════

fn test_extract_status_bad_request() {
	err := web.new_bad_request('invalid input')
	assert web.extract_status(err) == 400
}

fn test_extract_status_unauthorized() {
	err := web.new_unauthorized('please login')
	assert web.extract_status(err) == 401
}

fn test_extract_status_forbidden() {
	err := web.new_forbidden('access denied')
	assert web.extract_status(err) == 403
}

fn test_extract_status_not_found() {
	err := web.new_not_found('resource missing')
	assert web.extract_status(err) == 404
}

fn test_extract_status_method_not_allowed() {
	err := web.new_method_not_allowed('GET not allowed')
	assert web.extract_status(err) == 405
}

fn test_extract_status_conflict() {
	err := web.new_conflict('resource exists')
	assert web.extract_status(err) == 409
}

fn test_extract_status_validation() {
	err := web.new_validation_exception('invalid', {'field': ['required']})
	assert web.extract_status(err) == 422
}

fn test_extract_status_rate_limit() {
	err := web.new_rate_limit_exceeded('too many requests')
	assert web.extract_status(err) == 429
}

fn test_extract_status_internal_error() {
	err := web.new_internal_error('server error')
	assert web.extract_status(err) == 500
}

fn test_extract_status_service_unavailable() {
	err := web.new_service_unavailable('maintenance')
	assert web.extract_status(err) == 503
}

fn test_extract_status_unknown_error() {
	// 未知错误类型应返回 0
	plain_err := error('something went wrong')
	assert web.extract_status(plain_err) == 0
}

// ═══════════════════════════════════════════════════════════
// handle_with_status 测试
// ═══════════════════════════════════════════════════════════

fn test_handle_with_status_bad_request() {
	mut handler := web.new_exception_handler()
	err := web.new_bad_request('字段无效 / field invalid')
	status, body := handler.handle_with_status(err)

	assert status == 400
	assert body.contains('字段无效')
}

fn test_handle_with_status_not_found() {
	mut handler := web.new_exception_handler()
	err := web.new_not_found('用户不存在 / user not found')
	status, body := handler.handle_with_status(err)

	assert status == 404
	assert body.contains('用户不存在')
}

fn test_handle_with_status_unauthorized() {
	mut handler := web.new_exception_handler()
	err := web.new_unauthorized('请先登录 / please login')
	status, body := handler.handle_with_status(err)

	assert status == 401
	assert body.contains('请先登录')
}

fn test_handle_with_status_forbidden() {
	mut handler := web.new_exception_handler()
	err := web.new_forbidden('权限不足 / no permission')
	status, body := handler.handle_with_status(err)

	assert status == 403
	assert body.contains('权限不足')
}

fn test_handle_with_status_validation() {
	mut handler := web.new_exception_handler()
	err := web.new_validation_exception('校验失败', {'username': ['required']})
	status, body := handler.handle_with_status(err)

	assert status == 422
	assert body.contains('校验失败')
}

fn test_handle_with_status_rate_limit() {
	mut handler := web.new_exception_handler()
	err := web.new_rate_limit_exceeded('请求过于频繁 / too many requests')
	status, body := handler.handle_with_status(err)

	assert status == 429
	assert body.contains('过于频繁')
}

fn test_handle_with_status_internal_error() {
	mut handler := web.new_exception_handler()
	err := web.new_internal_error('服务器错误 / server error')
	status, body := handler.handle_with_status(err)

	assert status == 500
	assert body.contains('服务器错误')
}

fn test_handle_with_status_unknown_error_falls_back_to_500() {
	mut handler := web.new_exception_handler()
	err := error('未知错误 / unknown error')
	status, body := handler.handle_with_status(err)

	assert status == 500
	assert body.contains('未知错误')
}

fn test_handle_with_status_unknown_error_with_default_handler() {
	mut handler := web.new_exception_handler()
	handler.register_default_handler(fn (err IError) string {
		return '{"code":999,"message":"custom fallback"}'
	})
	err := error('test')
	status, body := handler.handle_with_status(err)

	assert status == 500
	assert body.contains('999')
}

// ═══════════════════════════════════════════════════════════
// HttpException 构造与字段测试
// ═══════════════════════════════════════════════════════════

fn test_http_exception_creation() {
	exc := web.new_http_exception(418, "I'm a teapot")
	assert exc.status_code == 418
	assert exc.message == "I'm a teapot"
}

fn test_http_exception_with_details() {
	details := map[string]string{
		'field':   'username'
		'reason':  'required'
	}
	exc := web.new_http_exception_with_details(422, '校验失败', details)
	assert exc.status_code == 422
	assert exc.message == '校验失败'
	assert exc.details['field'] == 'username'
	assert exc.details['reason'] == 'required'
}

fn test_validation_exception_errors() {
	errors := {
		'username': ['required', 'min_len:3']
		'email':    ['email']
	}
	exc := web.new_validation_exception('校验失败', errors)
	assert exc.status_code == 422
	assert 'required' in exc.validation_errors['username']
	assert 'min_len:3' in exc.validation_errors['username']
	assert 'email' in exc.validation_errors['email']
}

// ═══════════════════════════════════════════════════════════
// 错误响应 JSON 格式测试
// ═══════════════════════════════════════════════════════════

fn test_error_json_format() {
	json_str := web.error_json(404, '资源未找到 / not found')
	assert json_str.contains('"success":false')
	assert json_str.contains('"code":404')
	assert json_str.contains('"message":"资源未找到 / not found"')
}

fn test_handle_returns_valid_json() {
	mut handler := web.new_exception_handler()
	err := web.new_bad_request('参数错误')
	body := handler.handle(err)

	// 输出应为合法 JSON
	assert body.contains('"code":400')
	assert body.contains('"message"')
}

// ═══════════════════════════════════════════════════════════
// 服务层抛异常的集成测试
// ═══════════════════════════════════════════════════════════

fn test_service_throws_not_found_exception() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	// 查询不存在的用户，应返回错误（服务层不抛 HttpException，由控制器转换）
	result := user_svc.find_by_id(99999) or {
		// 期望错误
		assert true
		return
	}
	// 不应成功
	_ = result
	assert false
}

fn test_duplicate_registration_throws_error() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	dto := CreateUserDto{
		username: 'dup_user'
		email:    'dup@test.com'
		password: 'pass123'
	}
	user_svc.register(dto)!

	// 重复注册应抛错
	user_svc.register(dto) or {
		assert err.msg().contains('已存在') || err.msg().contains('exists')
		return
	}
	assert false
}

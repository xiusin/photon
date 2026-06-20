module main

// controller_test.v — PhotonBlog 控制器响应格式与状态码测试
//
// 测试覆盖：
//   - 统一响应格式（web.success / web.fail）
//   - 控制器辅助函数
//   - DTO 结构与序列化
//   - extract_json_field 辅助函数（已移除，相关测试已删除）

import json
import photon.web

fn test_web_success_format() {
	resp := web.success('{"id":1}')

	assert resp.success == true
	assert resp.code == 200
	assert resp.message == 'OK'
	assert resp.data == '{"id":1}'
	assert resp.timestamp > 0
}

fn test_web_fail_format() {
	resp := web.fail(404, 'Not Found')

	assert resp.success == false
	assert resp.code == 404
	assert resp.message == 'Not Found'
	assert resp.data == ''
	assert resp.timestamp > 0
}

fn test_web_success_with_nested_data() {
	data := json.encode({
		'name': 'Alice'
		'age':  '30'
	})
	resp := web.success(data)

	assert resp.success == true
	assert resp.data.contains('Alice')
}

fn test_web_fail_with_special_chars() {
	resp := web.fail(400, '用户名、邮箱、密码为必填项')

	assert resp.success == false
	assert resp.code == 400
	assert resp.message.contains('必填项')
}

fn test_web_result_to_json() {
	resp := web.success('{"id":1}')
	json_str := resp.to_json()

	// JSON 字符串应包含所有字段
	assert json_str.contains('"success":true')
	assert json_str.contains('"code":200')
	assert json_str.contains('"message":"OK"')
	assert json_str.contains('"data":"{\\"id\\":1}"')
}

fn test_web_created_helper() {
	resp := web.created('{"id":42}')

	assert resp.success == true
	assert resp.code == 201
	assert resp.message == 'Created'
}

fn test_web_bad_request_helper() {
	resp := web.bad_request('invalid input')

	assert resp.success == false
	assert resp.code == 400
	assert resp.message == 'invalid input'
}

fn test_web_not_found_helper() {
	resp := web.not_found('not found')

	assert resp.success == false
	assert resp.code == 404
}

fn test_web_unauthorized_helper() {
	resp := web.unauthorized('please login')

	assert resp.success == false
	assert resp.code == 401
}

fn test_web_forbidden_helper() {
	resp := web.forbidden('no permission')

	assert resp.success == false
	assert resp.code == 403
}

fn test_web_internal_error_helper() {
	resp := web.internal_error('server error')

	assert resp.success == false
	assert resp.code == 500
}

fn test_web_page_helper() {
	resp := web.page('{"items":[]}', 1, 20, 100)

	assert resp.success == true
	assert resp.code == 200
	assert resp.pagination.page == 1
	assert resp.pagination.page_size == 20
	assert resp.pagination.total == 100
	assert resp.pagination.total_pages == 5
	assert resp.pagination.has_next == true
	assert resp.pagination.has_prev == false
}

fn test_login_response_dto_serialization() {
	dto := LoginResponseDto{
		access_token:  'access_tok'
		token_type:    'Bearer'
		expires_in:    3600
		refresh_token: 'refresh_tok'
		user: UserProfileDto{
			id:       1
			username: 'alice'
			email:    'alice@test.com'
			role:     'USER'
			status:   1
		}
	}
	encoded := json.encode(dto)

	assert encoded.contains('access_tok')
	assert encoded.contains('Bearer')
	assert encoded.contains('3600')
	assert encoded.contains('refresh_tok')
	assert encoded.contains('alice')
}

fn test_user_profile_dto_serialization() {
	dto := UserProfileDto{
		id:       42
		username: 'bob'
		nickname: 'Bobby'
		email:    'bob@test.com'
		role:     'EDITOR'
		status:   1
	}
	encoded := json.encode(dto)

	assert encoded.contains('bob')
	assert encoded.contains('Bobby')
	assert encoded.contains('EDITOR')
}

fn test_create_post_dto_default_status() {
	dto := CreatePostDto{
		title:     'Test'
		content:   'Content'
		author_id: 1
	}
	assert dto.status == 'draft'
}

fn test_post_list_query_dto_defaults() {
	dto := PostListQueryDto{}
	assert dto.page == 1
	assert dto.page_size == 20
	assert dto.status == 'published'
	assert dto.sort == 'created_at_desc'
}

fn test_user_list_query_dto_defaults() {
	dto := UserListQueryDto{}
	assert dto.page == 1
	assert dto.page_size == 20
}

fn test_comment_list_query_dto_defaults() {
	dto := CommentListQueryDto{}
	assert dto.page == 1
	assert dto.page_size == 20
}

fn test_health_status_dto_serialization() {
	dto := HealthStatusDto{
		status:    'UP'
		version:   '0.1.0'
		uptime_ms: 5000
		timestamp: 1700000000
	}
	encoded := json.encode(dto)
	assert encoded.contains('UP')
	assert encoded.contains('0.1.0')
}

fn test_server_stats_dto_serialization() {
	dto := ServerStatsDto{
		requests:       100
		uptime_ms:      5000
		active_users:   5
		post_count:     10
		comment_count:  20
		cache_hits:     50
		cache_misses:   5
	}
	encoded := json.encode(dto)
	assert encoded.contains('100')
	assert encoded.contains('10')
}

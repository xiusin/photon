module main

// controller_test.v — PhotonBlog 控制器响应格式与状态码测试
//
// 测试覆盖：
//   - 统一响应格式（ok_resp / err_resp）
//   - 控制器辅助函数
//   - API 响应 DTO 结构
//   - extract_json_field 辅助函数

import json

fn test_ok_resp_format() {
	resp_str := ok_resp('{"id":1}')
	resp := json.decode(ApiResponseDto, resp_str)!

	assert resp.success == true
	assert resp.code == 200
	assert resp.message == 'OK'
	assert resp.data == '{"id":1}'
	assert resp.timestamp > 0
}

fn test_err_resp_format() {
	resp_str := err_resp(404, 'Not Found')
	resp := json.decode(ApiResponseDto, resp_str)!

	assert resp.success == false
	assert resp.code == 404
	assert resp.message == 'Not Found'
	assert resp.data == ''
	assert resp.timestamp > 0
}

fn test_ok_resp_with_nested_data() {
	data := json.encode({
		'name': 'Alice'
		'age':  '30'
	})
	resp_str := ok_resp(data)
	resp := json.decode(ApiResponseDto, resp_str)!

	assert resp.success == true
	assert resp.data.contains('Alice')
}

fn test_err_resp_with_special_chars() {
	resp_str := err_resp(400, '用户名、邮箱、密码为必填项')
	resp := json.decode(ApiResponseDto, resp_str)!

	assert resp.success == false
	assert resp.code == 400
	assert resp.message.contains('必填项')
}

fn test_extract_json_field_basic() {
	json_str := '{"refresh_token":"abc123def","token_type":"Bearer"}'
	assert extract_json_field(json_str, 'refresh_token') == 'abc123def'
	assert extract_json_field(json_str, 'token_type') == 'Bearer'
}

fn test_extract_json_field_missing() {
	json_str := '{"name":"Alice"}'
	assert extract_json_field(json_str, 'nonexistent') == ''
}

fn test_extract_json_field_empty_string() {
	assert extract_json_field('', 'key') == ''
}

fn test_extract_json_field_nested() {
	json_str := '{"data":{"name":"Bob"},"refresh_token":"tok123"}'
	assert extract_json_field(json_str, 'refresh_token') == 'tok123'
}

fn test_api_response_dto_success() {
	resp := success_response('{"users":[]}')
	assert resp.success == true
	assert resp.code == 200
	assert resp.data == '{"users":[]}'
}

fn test_api_response_dto_error() {
	resp := error_response(500, 'Internal Server Error')
	assert resp.success == false
	assert resp.code == 500
	assert resp.message == 'Internal Server Error'
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

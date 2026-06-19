module main

// models_test.v — PhotonBlog 实体模型与 DTO 测试
//
// 测试覆盖：
//   - User 实体创建与 is_new/touch
//   - Post 实体创建与状态
//   - Comment 实体与嵌套评论
//   - Category/Tag 实体
//   - DTO 结构校验
//   - API 响应封装

import photon.orm as phorm

fn test_user_entity_new() {
	user := User{
		username: 'alice'
		email:    'alice@test.com'
		password: 'hashed'
		role:     'USER'
		status:   1
	}
	assert user.is_new() == true
	assert user.id == 0
	assert user.username == 'alice'
	assert user.email == 'alice@test.com'
	assert user.role == 'USER'
	assert user.status == 1
}

fn test_user_entity_touch() {
	mut user := User{
		username: 'bob'
		email:    'bob@test.com'
		password: 'hashed'
		role:     'EDITOR'
		status:   1
	}
	user.touch()
	assert user.created_at > 0
	assert user.updated_at > 0
	assert user.version == 1
}

fn test_user_entity_touch_increments_version() {
	mut user := User{
		username: 'charlie'
		email:    'charlie@test.com'
		password: 'hashed'
	}
	user.touch()
	v1 := user.version
	user.touch()
	assert user.version == v1 + 1
}

fn test_post_entity() {
	post := Post{
		title:     'Test Post'
		content:   'Content here'
		author_id: 1
		status:    'draft'
	}
	assert post.is_new() == true
	assert post.id == 0
	assert post.status == 'draft'
	assert post.views == 0
}

fn test_post_entity_touch() {
	mut post := Post{
		title:     'Test Post'
		content:   'Content'
		author_id: 1
		status:    'published'
	}
	post.touch()
	assert post.version == 1
	assert post.created_at > 0
}

fn test_comment_entity() {
	comment := Comment{
		post_id:   1
		user_id:   1
		content:   'Great post!'
		parent_id: 0
		status:    'visible'
	}
	assert comment.is_new() == true
	assert comment.parent_id == 0
	assert comment.status == 'visible'
}

fn test_comment_entity_nested() {
	comment := Comment{
		post_id:   1
		user_id:   2
		content:   'Reply to comment'
		parent_id: 5
		status:    'visible'
	}
	assert comment.parent_id == 5
}

fn test_category_entity() {
	cat := Category{
		name:        'Technology'
		slug:        'technology'
		description: 'Tech articles'
	}
	assert cat.is_new() == true
	assert cat.name == 'Technology'
	assert cat.slug == 'technology'
}

fn test_tag_entity() {
	tag := Tag{
		name: 'vlang'
		slug: 'vlang'
	}
	assert tag.is_new() == true
	assert tag.name == 'vlang'
}

fn test_post_tag_entity() {
	pt := PostTag{
		post_id: 1
		tag_id:  2
	}
	assert pt.is_new() == true
}

fn test_create_user_dto() {
	dto := CreateUserDto{
		username: 'alice'
		email:    'alice@test.com'
		password: 'secret123'
		nickname: 'Alice'
		role:     'USER'
	}
	assert dto.username == 'alice'
	assert dto.role == 'USER'
}

fn test_create_user_dto_default_role() {
	dto := CreateUserDto{
		username: 'bob'
		email:    'bob@test.com'
		password: 'secret'
	}
	assert dto.role == 'USER'
}

fn test_login_dto() {
	dto := LoginDto{
		username: 'alice'
		password: 'secret'
	}
	assert dto.username == 'alice'
	assert dto.password == 'secret'
}

fn test_create_post_dto() {
	dto := CreatePostDto{
		title:     'Hello'
		content:   'World'
		author_id: 1
	}
	assert dto.status == 'draft'
	assert dto.title == 'Hello'
}

fn test_create_comment_dto() {
	dto := CreateCommentDto{
		post_id:   1
		user_id:   2
		content:   'Nice!'
		parent_id: 0
	}
	assert dto.post_id == 1
	assert dto.parent_id == 0
}

fn test_success_response() {
	resp := success_response('{"id":1}')
	assert resp.success == true
	assert resp.code == 200
	assert resp.message == 'OK'
	assert resp.data == '{"id":1}'
}

fn test_error_response() {
	resp := error_response(404, 'Not Found')
	assert resp.success == false
	assert resp.code == 404
	assert resp.message == 'Not Found'
	assert resp.data == ''
}

fn test_user_profile_dto() {
	dto := UserProfileDto{
		id:       1
		username: 'alice'
		nickname: 'Alice'
		email:    'alice@test.com'
		role:     'USER'
		status:   1
	}
	assert dto.id == 1
	assert dto.username == 'alice'
}

fn test_login_response_dto() {
	dto := LoginResponseDto{
		access_token:  'token123'
		token_type:    'Bearer'
		expires_in:    3600
		refresh_token: 'refresh456'
	}
	assert dto.token_type == 'Bearer'
	assert dto.expires_in == 3600
}

fn test_health_status_dto() {
	dto := HealthStatusDto{
		status:    'UP'
		version:   '0.1.0'
		uptime_ms: 5000
	}
	assert dto.status == 'UP'
	assert dto.version == '0.1.0'
}

fn test_server_stats_dto() {
	dto := ServerStatsDto{
		requests:      100
		active_users:  5
		post_count:    10
		comment_count: 20
	}
	assert dto.requests == 100
	assert dto.post_count == 10
}

module main

// resource_test.v — API Resource 测试
//
// 测试覆盖：
//   - UserResource 字段脱敏（不输出 password/version）
//   - PostResource 基本转换
//   - CommentResource 嵌套回复
//   - CategoryResource / TagResource
//   - ResourceCollection 分页元数据
//   - format_timestamp 辅助函数

import time

// ═══════════════════════════════════════════════════════════
// UserResource 测试
// ═══════════════════════════════════════════════════════════

fn test_user_resource_hides_password() {
	user := User{
		username: 'alice'
		email:    'alice@test.com'
		password: 'secret_hash'
		nickname: 'Alice'
		avatar:   'https://example.com/a.png'
		status:   1
		role:     'USER'
	}
	user.id = 42
	user.created_at = time.now().unix()
	user.updated_at = time.now().unix()
	user.version = 5

	resource := new_user_resource(&user)
	json_str := resource.to_json()

	// 应包含公开字段
	assert json_str.contains('"username":"alice"')
	assert json_str.contains('"email":"alice@test.com"')
	assert json_str.contains('"role":"USER"')
	assert json_str.contains('"id":42')

	// 不应包含敏感字段
	assert !json_str.contains('password')
	assert !json_str.contains('secret_hash')
	assert !json_str.contains('"version"')
}

fn test_user_resource_collection() {
	mut users := []User{}
	for i := 1; i <= 3; i++ {
		mut u := User{
			username: 'user${i}'
			email:    'u${i}@test.com'
			role:     'USER'
		}
		u.id = i
		users << u
	}

	collection := new_user_resource_collection(users, 100, 1, 20)
	json_str := collection.to_json()

	assert json_str.contains('"data":')
	assert json_str.contains('"meta":')
	assert json_str.contains('"total":100')
	assert json_str.contains('"page":1')
	assert json_str.contains('"page_size":20')
	assert json_str.contains('"has_more":true')
}

// ═══════════════════════════════════════════════════════════
// PostResource 测试
// ═══════════════════════════════════════════════════════════

fn test_post_resource_basic() {
	mut post := Post{
		title:    'Hello World'
		content:  'Body content'
		summary:  'Summary'
		status:   'published'
		views:    100
		author_id: 1
	}
	post.id = 10
	post.created_at = time.now().unix()

	resource := new_post_resource(&post)
	json_str := resource.to_json()

	assert json_str.contains('"title":"Hello World"')
	assert json_str.contains('"status":"published"')
	assert json_str.contains('"views":100')
	assert json_str.contains('"id":10')
}

fn test_post_resource_with_relations() {
	mut post := Post{
		title:     'With Author'
		status:    'published'
		author_id: 1
	}
	post.id = 1

	mut author := User{
		username: 'author1'
		email:    'author@test.com'
		role:     'EDITOR'
	}
	author.id = 1

	mut category := Category{
		name: 'Tech'
		slug: 'tech'
	}
	category.id = 1

	mut tags := []Tag{}
	mut t1 := Tag{name: 'vlang', slug: 'vlang'}
	t1.id = 1
	tags << t1

	resource := new_post_resource_with_relations(&post, &author, &category, tags)
	json_str := resource.to_json()

	// 应包含嵌套的 author
	assert json_str.contains('"author":')
	assert json_str.contains('"username":"author1"')

	// 应包含嵌套的 category
	assert json_str.contains('"category":')
	assert json_str.contains('"name":"Tech"')

	// 应包含嵌套的 tags
	assert json_str.contains('"tags":')
	assert json_str.contains('"name":"vlang"')
}

// ═══════════════════════════════════════════════════════════
// CommentResource 测试
// ═══════════════════════════════════════════════════════════

fn test_comment_resource_with_replies() {
	mut parent := Comment{
		post_id:   1
		user_id:   1
		content:   'Parent comment'
		parent_id: 0
	}
	parent.id = 1
	parent.created_at = time.now().unix()

	mut reply := Comment{
		post_id:   1
		user_id:   2
		content:   'Reply comment'
		parent_id: 1
	}
	reply.id = 2
	reply.created_at = time.now().unix()

	mut replies := []CommentResource{}
	replies << new_comment_resource(&reply)

	resource := new_comment_resource_with_replies(&parent, unsafe { nil }, replies)
	json_str := resource.to_json()

	assert json_str.contains('"content":"Parent comment"')
	assert json_str.contains('"replies":')
	assert json_str.contains('"content":"Reply comment"')
}

// ═══════════════════════════════════════════════════════════
// CategoryResource / TagResource 测试
// ═══════════════════════════════════════════════════════════

fn test_category_resource() {
	mut cat := Category{
		name:        'Programming'
		slug:        'programming'
		description: 'Programming articles'
	}
	cat.id = 1
	cat.created_at = time.now().unix()

	resource := new_category_resource(&cat)
	json_str := resource.to_json()

	assert json_str.contains('"name":"Programming"')
	assert json_str.contains('"slug":"programming"')
	assert json_str.contains('"description":"Programming articles"')
}

fn test_tag_resource() {
	mut tag := Tag{
		name: 'vlang'
		slug: 'vlang'
	}
	tag.id = 1
	tag.created_at = time.now().unix()

	resource := new_tag_resource(&tag)
	json_str := resource.to_json()

	assert json_str.contains('"name":"vlang"')
	assert json_str.contains('"slug":"vlang"')
}

// ═══════════════════════════════════════════════════════════
// 辅助函数测试
// ═══════════════════════════════════════════════════════════

fn test_format_timestamp_zero() {
	// 0 时间戳应返回空字符串
	assert format_timestamp(0) == ''
}

fn test_format_timestamp_valid() {
	ts := time.now().unix()
	formatted := format_timestamp(ts)
	assert formatted.len > 0
	// 应为 ISO 8601 格式（包含日期分隔符）
	assert formatted.contains('-')
}

fn test_new_resource_meta_has_more() {
	// 第一页，总数大于页大小 → has_more = true
	meta := new_resource_meta(100, 1, 20)
	assert meta.total == 100
	assert meta.page == 1
	assert meta.page_size == 20
	assert meta.has_more == true
}

fn test_new_resource_meta_no_more() {
	// 最后一页 → has_more = false
	meta := new_resource_meta(20, 1, 20)
	assert meta.has_more == false
}

fn test_new_resource_meta_exact_boundary() {
	// 总数正好等于页大小 → has_more = false
	meta := new_resource_meta(20, 1, 20)
	assert meta.has_more == false

	// 第二页（超出）→ has_more = false
	meta2 := new_resource_meta(20, 2, 20)
	assert meta2.has_more == false
}

// ═══════════════════════════════════════════════════════════
// ResourceLinks 测试
// ═══════════════════════════════════════════════════════════

fn test_new_resource_links_first_page() {
	links := new_resource_links('/api/v1/posts', 1, 20, 100)
	assert links.first.contains('page=1')
	assert links.last.contains('page=5') // 100/20 = 5 pages
	assert links.next.contains('page=2')
	assert links.prev == '' // 第一页无 prev
}

fn test_new_resource_links_middle_page() {
	links := new_resource_links('/api/v1/posts', 3, 20, 100)
	assert links.prev.contains('page=2')
	assert links.next.contains('page=4')
}

fn test_new_resource_links_last_page() {
	links := new_resource_links('/api/v1/posts', 5, 20, 100)
	assert links.prev.contains('page=4')
	assert links.next == '' // 最后一页无 next
}

fn test_new_resource_links_empty() {
	links := new_resource_links('/api/v1/posts', 1, 20, 0)
	assert links.self == '/api/v1/posts'
	assert links.first == '/api/v1/posts'
	assert links.last == '/api/v1/posts'
	assert links.prev == ''
	assert links.next == ''
}

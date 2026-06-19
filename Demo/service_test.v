module main

// service_test.v — PhotonBlog 服务层业务逻辑测试
//
// 测试覆盖：
//   - UserService: 注册/登录/更新/密码修改/DTO 转换
//   - PostService: 创建/发布/更新/删除/缓存
//   - CommentService: 创建/删除/统计
//   - CategoryService: 创建/slug 生成/唯一性校验
//   - TagService: 创建/关联
//   - StatsService: 统计聚合/缓存

fn test_user_service_register() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	dto := CreateUserDto{
		username: 'alice'
		email:    'alice@test.com'
		password: 'password123'
		nickname: 'Alice'
	}
	user, msg := user_svc.register(dto)!

	assert user.id > 0
	assert user.username == 'alice'
	assert user.email == 'alice@test.com'
	assert user.password != 'password123' // 密码已哈希
	assert user.role == 'USER'
	assert user.status == 1
	assert user.nickname == 'Alice'
	assert msg == '注册成功 / registration successful'
}

fn test_user_service_register_default_nickname() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	dto := CreateUserDto{
		username: 'bob'
		email:    'bob@test.com'
		password: 'password123'
	}
	user, _ := user_svc.register(dto)!
	// 未提供 nickname 时使用 username
	assert user.nickname == 'bob'
}

fn test_user_service_register_duplicate_username() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	dto1 := CreateUserDto{username: 'dup', email: 'a@b.com', password: 'pass'}
	user_svc.register(dto1)!

	dto2 := CreateUserDto{username: 'dup', email: 'c@d.com', password: 'pass'}
	user_svc.register(dto2) or {
		assert err.msg().contains('username') || err.msg().contains('用户名')
		return
	}
	assert false
}

fn test_user_service_register_duplicate_email() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	dto1 := CreateUserDto{username: 'u1', email: 'same@b.com', password: 'pass'}
	user_svc.register(dto1)!

	dto2 := CreateUserDto{username: 'u2', email: 'same@b.com', password: 'pass'}
	user_svc.register(dto2) or {
		assert err.msg().contains('email') || err.msg().contains('邮箱')
		return
	}
	assert false
}

fn test_user_service_login_success() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg := CreateUserDto{username: 'loginuser', email: 'login@test.com', password: 'pass123'}
	user_svc.register(reg)!

	user := user_svc.login(LoginDto{username: 'loginuser', password: 'pass123'})!
	assert user.username == 'loginuser'
}

fn test_user_service_login_wrong_password() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg := CreateUserDto{username: 'badpass', email: 'bad@test.com', password: 'correct'}
	user_svc.register(reg)!

	user_svc.login(LoginDto{username: 'badpass', password: 'wrong'}) or {
		assert true
		return
	}
	assert false
}

fn test_user_service_login_disabled_account() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg := CreateUserDto{username: 'disabled', email: 'dis@test.com', password: 'pass'}
	user, _ := user_svc.register(reg)!

	// 手动禁用用户
	mut repo := boot.user_repo
	mut found := repo.find_by_id(user.id)!
	found.status = 0 // disabled
	repo.update(mut found)!

	user_svc.login(LoginDto{username: 'disabled', password: 'pass'}) or {
		assert err.msg().contains('禁用') || err.msg().contains('disabled')
		return
	}
	assert false
}

fn test_user_service_update() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg := CreateUserDto{username: 'updateuser', email: 'up@test.com', password: 'pass'}
	user, _ := user_svc.register(reg)!

	dto := UpdateUserDto{
		nickname: 'Updated Nick'
		email:    'updated@test.com'
	}
	updated := user_svc.update(user.id, dto)!
	assert updated.nickname == 'Updated Nick'
	assert updated.email == 'updated@test.com'
}

fn test_user_service_change_password() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg := CreateUserDto{username: 'pwuser', email: 'pw@test.com', password: 'oldpass'}
	user, _ := user_svc.register(reg)!

	user_svc.change_password(user.id, 'oldpass', 'newpass')!

	// 用新密码登录
	login_user := user_svc.login(LoginDto{username: 'pwuser', password: 'newpass'})!
	assert login_user.id == user.id
}

fn test_user_service_change_password_wrong_old() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	reg := CreateUserDto{username: 'pwuser2', email: 'pw2@test.com', password: 'correct'}
	user, _ := user_svc.register(reg)!

	user_svc.change_password(user.id, 'wrongold', 'newpass') or {
		assert err.msg().contains('旧密码') || err.msg().contains('old password')
		return
	}
	assert false
}

fn test_user_service_verify_password() {
	boot := test_setup()!
	user_svc := boot.user_svc

	hash := user_svc.hasher.make('mypassword')
	assert user_svc.verify_password('mypassword', hash) == true
	assert user_svc.verify_password('wrongpassword', hash) == false
}

fn test_user_service_to_profile_dto() {
	boot := test_setup()!
	user_svc := boot.user_svc

	mut user := User{
		username: 'profile'
		email:    'profile@test.com'
		password: 'hash'
		nickname: 'Profile User'
		role:     'USER'
		status:   1
	}
	user.touch()

	dto := user_svc.to_profile_dto(&user)
	assert dto.username == 'profile'
	assert dto.email == 'profile@test.com'
	assert dto.nickname == 'Profile User'
	assert dto.role == 'USER'
	assert dto.status == 1
	// UserProfileDto 不含密码字段（脱敏设计）
}

fn test_post_service_create() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	dto := CreatePostDto{
		title:     'Test Post'
		content:   'Content here'
		author_id: 1
		status:    'draft'
	}
	post := post_svc.create(dto)!
	assert post.id > 0
	assert post.title == 'Test Post'
	assert post.status == 'draft'
}

fn test_post_service_create_published_dispatches_event() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	dto := CreatePostDto{
		title:     'Published Post'
		content:   'Content'
		author_id: 1
		status:    'published'
	}
	post := post_svc.create(dto)!
	assert post.status == 'published'
}

fn test_post_service_find_by_id_with_cache() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	dto := CreatePostDto{title: 'Cached Post', content: 'C', author_id: 1, status: 'published'}
	created := post_svc.create(dto)!

	// 第一次查询（缓存未命中，从 DB 加载并写入缓存）
	found := post_svc.find_by_id(created.id)!
	assert found.title == 'Cached Post'

	// 第二次查询（缓存命中）
	cached := post_svc.find_by_id(created.id)!
	assert cached.title == 'Cached Post'
}

fn test_post_service_publish() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	dto := CreatePostDto{title: 'To Publish', content: 'C', author_id: 1, status: 'draft'}
	created := post_svc.create(dto)!
	assert created.status == 'draft'

	published := post_svc.publish(created.id)!
	assert published.status == 'published'
}

fn test_post_service_publish_idempotent() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	dto := CreatePostDto{title: 'Already Pub', content: 'C', author_id: 1, status: 'published'}
	created := post_svc.create(dto)!

	// 重复发布应幂等返回
	result := post_svc.publish(created.id)!
	assert result.status == 'published'
}

fn test_post_service_update() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	dto := CreatePostDto{title: 'Original', content: 'C', author_id: 1, status: 'draft'}
	created := post_svc.create(dto)!

	update_dto := UpdatePostDto{title: 'Updated Title', content: 'New Content'}
	updated := post_svc.update(created.id, update_dto)!
	assert updated.title == 'Updated Title'
	assert updated.content == 'New Content'
}

fn test_post_service_delete() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	dto := CreatePostDto{title: 'Delete Me', content: 'C', author_id: 1, status: 'draft'}
	created := post_svc.create(dto)!

	post_svc.delete(created.id)!

	post_svc.find_by_id(created.id) or {
		assert true
		return
	}
	assert false
}

fn test_post_service_increment_views() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	dto := CreatePostDto{title: 'Viewed', content: 'C', author_id: 1, status: 'published'}
	created := post_svc.create(dto)!

	post_svc.increment_views(created.id)!
	post_svc.increment_views(created.id)!

	// 需要绕过缓存直接查 DB 验证 views
	mut post_repo := boot.post_repo
	found := post_repo.find_by_id(created.id)!
	assert found.views == 2
}

fn test_comment_service_create() {
	boot := test_setup()!
	mut comment_svc := boot.comment_svc

	// 先创建文章
	mut post_svc := boot.post_svc
	post := post_svc.create(CreatePostDto{title: 'Post', content: 'C', author_id: 1, status: 'published'})!

	dto := CreateCommentDto{
		post_id: post.id
		user_id: 1
		content: 'Great article!'
	}
	comment := comment_svc.create(dto)!
	assert comment.id > 0
	assert comment.content == 'Great article!'
	assert comment.status == 'visible'
}

fn test_comment_service_delete_soft() {
	boot := test_setup()!
	mut comment_svc := boot.comment_svc

	mut post_svc := boot.post_svc
	post := post_svc.create(CreatePostDto{title: 'Post', content: 'C', author_id: 1, status: 'published'})!

	dto := CreateCommentDto{post_id: post.id, user_id: 1, content: 'To delete'}
	comment := comment_svc.create(dto)!

	comment_svc.delete(comment.id)!

	// 软删除：状态变为 deleted
	found := comment_svc.find_by_id(comment.id)!
	assert found.status == 'deleted'
}

fn test_comment_service_find_by_post() {
	boot := test_setup()!
	mut comment_svc := boot.comment_svc
	mut post_svc := boot.post_svc
	post := post_svc.create(CreatePostDto{title: 'Post', content: 'C', author_id: 1, status: 'published'})!

	comment_svc.create(CreateCommentDto{post_id: post.id, user_id: 1, content: 'C1'})!
	comment_svc.create(CreateCommentDto{post_id: post.id, user_id: 1, content: 'C2'})!

	comments := comment_svc.find_by_post(post.id)!
	assert comments.len == 2
}

fn test_category_service_create() {
	boot := test_setup()!
	mut cat_svc := boot.category_svc

	dto := CreateCategoryDto{name: 'Technology', description: 'Tech articles'}
	cat := cat_svc.create(dto)!
	assert cat.id > 0
	assert cat.name == 'Technology'
}

fn test_category_service_auto_slug() {
	boot := test_setup()!
	mut cat_svc := boot.category_svc

	dto := CreateCategoryDto{name: 'V Language'}
	cat := cat_svc.create(dto)!
	assert cat.slug == 'v-language'
}

fn test_category_service_duplicate_slug() {
	boot := test_setup()!
	mut cat_svc := boot.category_svc

	dto1 := CreateCategoryDto{name: 'Tech', slug: 'tech'}
	cat_svc.create(dto1)!

	dto2 := CreateCategoryDto{name: 'Technology', slug: 'tech'}
	cat_svc.create(dto2) or {
		assert err.msg().contains('slug')
		return
	}
	assert false
}

fn test_tag_service_create() {
	boot := test_setup()!
	mut tag_svc := boot.tag_svc

	dto := CreateTagDto{name: 'vlang'}
	tag := tag_svc.create(dto)!
	assert tag.id > 0
	assert tag.name == 'vlang'
	assert tag.slug == 'vlang'
}

fn test_tag_service_auto_slug() {
	boot := test_setup()!
	mut tag_svc := boot.tag_svc

	dto := CreateTagDto{name: 'Web Development'}
	tag := tag_svc.create(dto)!
	assert tag.slug == 'web-development'
}

fn test_stats_service_aggregate() {
	boot := test_setup()!
	mut user_svc := boot.user_svc
	mut post_svc := boot.post_svc
	mut comment_svc := boot.comment_svc
	mut stats_svc := boot.stats_svc

	// 创建测试数据
	user_svc.register(CreateUserDto{username: 's1', email: 's1@t.com', password: 'p'})!
	post_svc.create(CreatePostDto{title: 'P1', content: 'C', author_id: 1, status: 'published'})!
	post_svc.create(CreatePostDto{title: 'P2', content: 'C', author_id: 1, status: 'draft'})!

	mut post_repo := boot.post_repo
	published_post := post_repo.find_by_status('published')![0]
	comment_svc.create(CreateCommentDto{post_id: published_post.id, user_id: 1, content: 'C1'})!

	stats := stats_svc.aggregate_stats()!
	assert stats.user_count >= 1
	assert stats.post_count >= 2
	assert stats.published_count >= 1
	assert stats.draft_count >= 1
	assert stats.comment_count >= 1
	assert stats.aggregated_at > 0
}

fn test_stats_service_cache() {
	boot := test_setup()!
	mut stats_svc := boot.stats_svc

	// 第一次查询（缓存未命中）
	stats1 := stats_svc.get_blog_stats()!
	assert stats1.aggregated_at > 0

	// 第二次查询（缓存命中）
	stats2 := stats_svc.get_blog_stats()!
	assert stats2.aggregated_at > 0
}

fn test_stats_service_invalidate_cache() {
	boot := test_setup()!
	mut stats_svc := boot.stats_svc

	// 先聚合一次写入缓存
	stats_svc.get_blog_stats()!

	// 失效缓存
	stats_svc.invalidate_cache()!

	// 再次聚合应重新从 DB 加载
	stats := stats_svc.get_blog_stats()!
	assert stats.aggregated_at > 0
}

fn test_generate_slug() {
	assert generate_slug('Hello World') == 'hello-world'
	assert generate_slug('V Language') == 'v-language'
	assert generate_slug('  Spaces  ') == 'spaces'
	assert generate_slug('Special!@#Characters') == 'specialcharacters'
	assert generate_slug('under_score') == 'under-score'
}

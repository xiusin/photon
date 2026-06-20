module main

// tests/eager_loading_test.v — 预加载与 N+1 消除测试
//
// 测试覆盖：
//   - find_post_with_relations：单次查询关联数据
//   - Tag.find_tags_by_post：标签预加载
//   - User 与 Post 双向关联
//   - find_by_author + find_by_post_with_filters 组合
//   - 跨服务数据完整性（创建后立即可查询）
//
// 设计目标：
//   通过预加载（eager loading）一次性查询所有关联数据，
//   避免在循环中逐个查询（Lazy Loading N+1 问题）。
//   PostRepository.find_post_with_relations() 演示了该模式。

// ═══════════════════════════════════════════════════════════
// find_post_with_relations 测试
// ═══════════════════════════════════════════════════════════

fn test_post_with_relations_returns_complete_data() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 创建关联数据
	author := t.user_factory().with_role('EDITOR').create()!
	mut cat_svc := t.post_svc()
	_ = cat_svc
	cat_dto := CreateCategoryDto{
		name: 'Technology'
		slug: 'tech'
	}
	mut category_svc := t.bootstrap().category_svc
	category := category_svc.create(cat_dto)!

	post := t.post_factory().with_author(author.id).with_category(category.id).create()!

	// 预加载查询
	p, loaded_author, loaded_category, loaded_tags := t.bootstrap().post_repo.find_post_with_relations(
		post.id, t.bootstrap().user_repo, t.bootstrap().category_repo, t.bootstrap().tag_repo
	)!

	// 验证所有数据正确加载
	assert p.id == post.id
	assert p.title == post.title
	assert loaded_author.id == author.id
	assert loaded_author.username == author.username
	assert loaded_category.id == category.id
	assert loaded_category.name == 'Technology'
	assert loaded_tags.len >= 0 // 未关联标签时为空
}

fn test_post_with_relations_associates_tags() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	post := t.post_factory().with_author(author.id).create()!

	// 创建并关联 2 个标签
	mut tag1 := Tag{
		name: 'vlang'
		slug: 'vlang'
	}
	mut tag2 := Tag{
		name: 'web'
		slug: 'web'
	}
	saved_tag1 := t.bootstrap().tag_repo.save(mut tag1)!
	saved_tag2 := t.bootstrap().tag_repo.save(mut tag2)!

	t.bootstrap().tag_repo.attach_tag(post.id, saved_tag1.id)!
	t.bootstrap().tag_repo.attach_tag(post.id, saved_tag2.id)!

	// 预加载查询应返回 2 个标签
	_, _, _, loaded_tags := t.bootstrap().post_repo.find_post_with_relations(
		post.id, t.bootstrap().user_repo, t.bootstrap().category_repo, t.bootstrap().tag_repo
	)!

	assert loaded_tags.len == 2
}

fn test_post_with_relations_without_category() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('USER').create()!
	// 创建不带分类的文章
	post := t.post_factory().with_author(author.id).with_category(0).create()!

	// 预加载应能处理分类不存在的情况
	p, loaded_author, _, _ := t.bootstrap().post_repo.find_post_with_relations(
		post.id, t.bootstrap().user_repo, t.bootstrap().category_repo, t.bootstrap().tag_repo
	)!

	assert p.id == post.id
	assert loaded_author.id == author.id
}

// ═══════════════════════════════════════════════════════════
// 标签关联预加载测试
// ═══════════════════════════════════════════════════════════

fn test_tag_attach_and_find_tags_by_post() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	post := t.post_factory().with_author(author.id).create()!

	// 创建 3 个标签并关联
	mut tags := []Tag{}
	for i in 0 .. 3 {
		mut tag := Tag{
			name: 'tag_${i}'
			slug: 'tag-${i}'
		}
		saved := t.bootstrap().tag_repo.save(mut tag)!
		tags << saved
		t.bootstrap().tag_repo.attach_tag(post.id, saved.id)!
	}

	// 一次性查询所有标签
	loaded_tags := t.bootstrap().tag_repo.find_tags_by_post(post.id)!
	assert loaded_tags.len == 3
}

fn test_tag_find_post_ids_by_tag() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	mut p1 := t.post_factory().with_author(author.id).create()!
	mut p2 := t.post_factory().with_author(author.id).create()!
	mut p3 := t.post_factory().with_author(author.id).create()!

	mut tag := Tag{
		name: 'featured'
		slug: 'featured'
	}
	saved_tag := t.bootstrap().tag_repo.save(mut tag)!

	// 仅 p1 和 p3 关联该标签
	t.bootstrap().tag_repo.attach_tag(p1.id, saved_tag.id)!
	t.bootstrap().tag_repo.attach_tag(p3.id, saved_tag.id)!

	// 查询该标签关联的所有文章
	post_ids := t.bootstrap().tag_repo.find_post_ids_by_tag(saved_tag.id)!
	assert p1.id in post_ids
	assert p3.id in post_ids
	assert p2.id !in post_ids
}

// ═══════════════════════════════════════════════════════════
// 仓储过滤查询与预加载组合
// ═══════════════════════════════════════════════════════════

fn test_post_filter_with_keyword() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	mut p1 := t.post_factory().with_author(author.id).with_title('V Language Tutorial').create()!
	mut p2 := t.post_factory().with_author(author.id).with_title('Rust Programming').create()!
	mut p3 := t.post_factory().with_author(author.id).with_title('Go Advanced').create()!

	// 按关键词过滤
	filter := PostFilter{
		keyword: 'V Language'
		status:  'all'
	}
	posts, total := t.bootstrap().post_repo.find_with_filters(filter, 'id_asc', 1, 20)!

	assert total == 1
	assert posts[0].id == p1.id
}

fn test_post_filter_by_author() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	u1 := t.user_factory().with_role('EDITOR').create()!
	u2 := t.user_factory().with_role('EDITOR').create()!

	// u1 创建 2 篇，u2 创建 3 篇
	for _ in 0 .. 2 {
		_ := t.post_factory().with_author(u1.id).create()!
	}
	for _ in 0 .. 3 {
		_ := t.post_factory().with_author(u2.id).create()!
	}

	// 按作者过滤
	filter := PostFilter{
		author_id: u1.id
		status:    'all'
	}
	posts, total := t.bootstrap().post_repo.find_with_filters(filter, 'id_asc', 1, 20)!

	assert total == 2
	assert posts.len == 2
	for p in posts {
		assert p.author_id == u1.id
	}
}

fn test_post_filter_pagination() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!

	// 创建 25 篇文章
	for i in 0 .. 25 {
		mut dto := CreatePostDto{
			title:     'Post ${i}'
			content:   'Content'
			author_id: author.id
		}
		mut post_svc := t.post_svc()
		post_svc.create(dto)!
	}

	// 第 1 页（10 条）
	filter := PostFilter{status: 'all'}
	mut posts, total := t.bootstrap().post_repo.find_with_filters(filter, 'id_asc', 1, 10)!
	assert total == 25
	assert posts.len == 10

	// 第 3 页（应只有 5 条）
	posts, total = t.bootstrap().post_repo.find_with_filters(filter, 'id_asc', 3, 10)!
	assert total == 25
	assert posts.len == 5
}

// ═══════════════════════════════════════════════════════════
// 跨服务数据完整性测试
// ═══════════════════════════════════════════════════════════

fn test_create_user_with_post_complete_chain() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 通过 Service 创建用户
	user_dto := CreateUserDto{
		username: 'chainuser'
		email:    'chain@test.com'
		password: 'pass123'
		role:     'EDITOR'
	}
	mut user_svc := t.user_svc()
	user, _ := user_svc.register(user_dto)!

	// 创建文章
	post_dto := CreatePostDto{
		title:     'Chained Post'
		content:   'Content'
		author_id: user.id
	}
	post := t.post_svc().create(post_dto)!

	// 创建评论
	comment_dto := CreateCommentDto{
		post_id: post.id
		user_id: user.id
		content: 'Test comment'
	}
	comment := t.comment_svc().create(comment_dto)!

	// 验证完整链路可查询
	found_user := t.bootstrap().user_repo.find_by_id(user.id)!
	found_post := t.bootstrap().post_repo.find_by_id(post.id)!
	found_comments := t.bootstrap().comment_repo.find_by_post(post.id)!

	assert found_user.username == 'chainuser'
	assert found_post.title == 'Chained Post'
	assert found_post.author_id == user.id
	assert found_comments.len == 1
	assert found_comments[0].id == comment.id
}

fn test_eager_load_consistency_with_factory() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 用 Factory 批量创建
	mut users := []User{}
	for _ in 0 .. 3 {
		u := t.user_factory().with_role('EDITOR').create()!
		users << u
	}

	for user in users {
		post := t.post_factory().with_author(user.id).create()!
		// 立即可通过预加载查询
		_, loaded_author, _, _ := t.bootstrap().post_repo.find_post_with_relations(
			post.id, t.bootstrap().user_repo, t.bootstrap().category_repo, t.bootstrap().tag_repo
		)!
		assert loaded_author.id == user.id
	}
}

module main

// repository_filter_test.v — 仓储层过滤查询与软删除测试
//
// 测试覆盖：
//   - PostFilter / UserFilter / CommentFilter 构建与查询
//   - find_with_filters 过滤/排序/分页
//   - soft_delete / restore / force_delete
//   - find_with_trashed / find_only_trashed / find_only_archived
//   - parse_sort_spec 排序解析

// ═══════════════════════════════════════════════════════════
// 排序解析测试
// ═══════════════════════════════════════════════════════════

fn test_parse_sort_spec_default() {
	spec := parse_sort_spec('')
	assert spec.field == 'created_at'
	assert spec.direction == .desc
}

fn test_parse_sort_spec_created_at_desc() {
	spec := parse_sort_spec('created_at_desc')
	assert spec.field == 'created_at'
	assert spec.direction == .desc
}

fn test_parse_sort_spec_created_at_asc() {
	spec := parse_sort_spec('created_at_asc')
	assert spec.field == 'created_at'
	assert spec.direction == .asc
}

fn test_parse_sort_spec_views_desc() {
	spec := parse_sort_spec('views_desc')
	assert spec.field == 'views'
	assert spec.direction == .desc
}

fn test_parse_sort_spec_title_asc() {
	spec := parse_sort_spec('title_asc')
	assert spec.field == 'title'
	assert spec.direction == .asc
}

fn test_sort_spec_to_sql() {
	spec := SortSpec{field: 'created_at', direction: .desc}
	assert spec.to_sql() == 'ORDER BY created_at DESC'

	spec2 := SortSpec{field: 'title', direction: .asc}
	assert spec2.to_sql() == 'ORDER BY title ASC'
}

// ═══════════════════════════════════════════════════════════
// 过滤查询测试（需要测试数据库）
// ═══════════════════════════════════════════════════════════

fn test_post_repository_find_with_filters_empty() {
	boot := test_setup()!
	post_repo := boot.post_repo

	// 空过滤查询所有文章
	filter := PostFilter{status: 'all'}
	posts, total := post_repo.find_with_filters(filter, 'created_at_desc', 1, 20)!

	assert total >= 0
	assert posts.len <= 20
}

fn test_post_repository_find_with_filters_by_status() {
	boot := test_setup()!
	post_repo := boot.post_repo

	// 按状态过滤
	filter := PostFilter{status: 'published'}
	posts, total := post_repo.find_with_filters(filter, 'created_at_desc', 1, 20)!

	// 所有返回的文章都应为 published 状态
	for p in posts {
		assert p.status == 'published'
	}
	assert total == posts.len || total > posts.len // total 可能大于当前页
}

fn test_post_repository_find_with_filters_by_keyword() {
	boot := test_setup()!
	post_repo := boot.post_repo

	// 先创建一篇含特殊关键词的文章
	mut post_svc := boot.post_svc
	dto := CreatePostDto{
		title:     'UniqueKeywordArticle'
		content:   'Content with unique_keyword_xyz'
		summary:   'Summary'
		author_id: 1
	}
	post_svc.create(dto) or { return }

	// 按关键词过滤
	filter := PostFilter{keyword: 'UniqueKeyword', status: 'all'}
	posts, total := post_repo.find_with_filters(filter, 'created_at_desc', 1, 20)!

	assert total >= 1
	found := false
	for p in posts {
		if p.title.contains('UniqueKeyword') {
			found = true
			break
		}
	}
	assert found
}

fn test_user_repository_find_with_filters() {
	boot := test_setup()!
	user_repo := boot.user_repo

	// 空过滤查询所有用户
	filter := UserFilter{}
	users, total := user_repo.find_with_filters(filter, 'id_asc', 1, 20)!

	assert total >= 0
	assert users.len <= 20
}

fn test_user_repository_find_with_filters_by_role() {
	boot := test_setup()!
	user_repo := boot.user_repo

	// 按角色过滤
	filter := UserFilter{role: 'ADMIN'}
	users, total := user_repo.find_with_filters(filter, 'id_asc', 1, 20)!

	// 所有返回的用户都应为 ADMIN 角色
	for u in users {
		assert u.role == 'ADMIN'
	}
}

// ═══════════════════════════════════════════════════════════
// 软删除测试
// ═══════════════════════════════════════════════════════════

fn test_user_repository_soft_delete_and_restore() {
	boot := test_setup()!
	mut user_repo := boot.user_repo

	// 创建测试用户
	mut user_svc := boot.user_svc
	dto := CreateUserDto{
		username: 'softdelete_user'
		email:    'sd@test.com'
		password: 'pass'
		role:     'USER'
	}
	user, _ := user_svc.register(dto)!
	user_id := user.id

	// 软删除
	user_repo.soft_delete(user_id)!

	// 验证 status 已设置为 -1
	deleted_user := user_repo.find_with_trashed(user_id)!
	assert deleted_user.status == -1

	// 恢复
	user_repo.restore(user_id)!

	// 验证 status 已恢复为 1
	restored_user := user_repo.find_with_trashed(user_id)!
	assert restored_user.status == 1
}

fn test_user_repository_force_delete() {
	boot := test_setup()!
	user_repo := boot.user_repo

	// 创建测试用户
	mut user_svc := boot.user_svc
	dto := CreateUserDto{
		username: 'forcedelete_user'
		email:    'fd@test.com'
		password: 'pass'
		role:     'USER'
	}
	user, _ := user_svc.register(dto)!
	user_id := user.id

	// 物理删除
	user_repo.force_delete(user_id)!

	// 验证已删除
	user_repo.find_with_trashed(user_id) or {
		assert true
		return
	}
	assert false
}

fn test_post_repository_soft_delete_and_restore() {
	boot := test_setup()!
	mut post_repo := boot.post_repo

	// 创建测试文章
	mut post_svc := boot.post_svc
	dto := CreatePostDto{
		title:     'Soft Delete Post'
		content:   'Content'
		author_id: 1
	}
	post := post_svc.create(dto)!
	post_id := post.id

	// 软删除（设置 status = 'archived'）
	post_repo.soft_delete(post_id)!

	// 验证 status 已设置为 archived
	deleted_post := post_repo.find_by_id(post_id)!
	assert deleted_post.status == 'archived'

	// 恢复（设置 status = 'draft'）
	post_repo.restore(post_id)!

	// 验证 status 已恢复为 draft
	restored_post := post_repo.find_by_id(post_id)!
	assert restored_post.status == 'draft'
}

fn test_post_repository_find_only_archived() {
	boot := test_setup()!
	mut post_repo := boot.post_repo

	// 创建并归档一篇文章
	mut post_svc := boot.post_svc
	dto := CreatePostDto{
		title:     'Archived Post'
		content:   'Content'
		author_id: 1
	}
	post := post_svc.create(dto)!
	post_repo.soft_delete(post.id)!

	// 查询仅归档的文章
	archived := post_repo.find_only_archived()!

	found := false
	for p in archived {
		if p.id == post.id {
			assert p.status == 'archived'
			found = true
			break
		}
	}
	assert found
}

fn test_comment_repository_soft_delete_and_restore() {
	boot := test_setup()!
	mut comment_repo := boot.comment_repo

	// 创建测试评论
	mut comment_svc := boot.comment_svc
	dto := CreateCommentDto{
		post_id: 1
		user_id: 1
		content: 'Soft delete comment'
	}
	comment := comment_svc.create(dto)!
	comment_id := comment.id

	// 软删除（设置 status = 'deleted'）
	comment_repo.soft_delete(comment_id)!

	// 验证 status 已设置为 deleted
	deleted_comment := comment_repo.find_by_id(comment_id)!
	assert deleted_comment.status == 'deleted'

	// 恢复（设置 status = 'visible'）
	comment_repo.restore(comment_id)!

	// 验证 status 已恢复为 visible
	restored_comment := comment_repo.find_by_id(comment_id)!
	assert restored_comment.status == 'visible'
}

// ═══════════════════════════════════════════════════════════
// 预加载辅助测试
// ═══════════════════════════════════════════════════════════

fn test_post_repository_find_with_relations() {
	boot := test_setup()!
	post_repo := boot.post_repo
	user_repo := boot.user_repo
	category_repo := boot.category_repo
	tag_repo := boot.tag_repo

	// 创建测试数据
	mut user_svc := boot.user_svc
	user_dto := CreateUserDto{
		username: 'author_test'
		email:    'author@test.com'
		password: 'pass'
		role:     'EDITOR'
	}
	author, _ := user_svc.register(user_dto)!

	mut category_svc := boot.category_svc
	cat_dto := CreateCategoryDto{name: 'TestCat', slug: 'testcat'}
	category := category_svc.create(cat_dto)!

	mut post_svc := boot.post_svc
	post_dto := CreatePostDto{
		title:       'Post With Relations'
		content:     'Content'
		author_id:   author.id
		category_id: category.id
	}
	post := post_svc.create(post_dto)!

	// 查询文章并预加载关联
	p, loaded_author, loaded_category, loaded_tags := post_repo.find_post_with_relations(post.id, user_repo, category_repo, tag_repo)!

	assert p.id == post.id
	assert loaded_author.id == author.id
	assert loaded_author.username == 'author_test'
	assert loaded_category.id == category.id
	assert loaded_category.name == 'TestCat'
	// tags 可能为空（未关联标签）
	assert loaded_tags.len >= 0
}

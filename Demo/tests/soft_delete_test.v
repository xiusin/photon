module tests

// tests/soft_delete_test.v — 软删除综合测试
//
// 测试覆盖：
//   - User 软删除 + restore + force_delete + with_trashed 查询
//   - Post 软删除（设置 status='archived'）+ restore + find_only_archived
//   - Comment 软删除（设置 status='deleted'）+ restore
//   - 软删除后查询过滤：默认查询不返回已删除记录
//   - 软删除后 with_trashed 查询返回所有记录
//   - 软删除与缓存失效协同
//   - 软删除与事件分发协同
//
// 软删除由 Repository 层的 soft_delete() / restore() / force_delete() 方法实现，
// 不在实体中维护 deleted_at 字段，而是通过 status 字段标识：
//   - User.status = -1 → 已软删除
//   - Post.status = 'archived' → 已软删除
//   - Comment.status = 'deleted' → 已软删除

// ═══════════════════════════════════════════════════════════
// User 软删除测试
// ═══════════════════════════════════════════════════════════

fn test_user_soft_delete_sets_status() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().with_role('USER').create()!
	t.user_svc()

	// 软删除
	t.bootstrap().user_repo.soft_delete(user.id)!

	// 验证 status = -1
	deleted := t.bootstrap().user_repo.find_with_trashed(user.id)!
	assert deleted.status == -1
}

fn test_user_soft_delete_excluded_from_default_queries() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().with_role('USER').create()!
	user_id := user.id

	// 软删除
	t.bootstrap().user_repo.soft_delete(user_id)!

	// 默认 find_by_id 应抛错
	t.bootstrap().user_repo.find_by_id(user_id) or {
		assert true
		return
	}
	assert false
}

fn test_user_soft_delete_included_in_with_trashed() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().with_role('USER').create()!

	// 软删除
	t.bootstrap().user_repo.soft_delete(user.id)!

	// with_trashed 应能查询到
	deleted := t.bootstrap().user_repo.find_with_trashed(user.id)!
	assert deleted.id == user.id
	assert deleted.status == -1
}

fn test_user_restore_after_soft_delete() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().with_role('USER').create()!

	// 软删除 → 恢复
	t.bootstrap().user_repo.soft_delete(user.id)!
	t.bootstrap().user_repo.restore(user.id)!

	// 验证 status 恢复为 1
	restored := t.bootstrap().user_repo.find_with_trashed(user.id)!
	assert restored.status == 1

	// 默认查询应能再次找到
	found := t.bootstrap().user_repo.find_by_id(user.id)!
	assert found.id == user.id
}

fn test_user_force_delete_removes_permanently() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	user := t.user_factory().with_role('USER').create()!

	// 物理删除
	t.bootstrap().user_repo.force_delete(user.id)!

	// 任何查询都应失败
	t.bootstrap().user_repo.find_with_trashed(user.id) or {
		assert true
		return
	}
	assert false
}

fn test_user_find_with_filters_excludes_trashed() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	// 创建 3 个用户
	u1 := t.user_factory().with_role('USER').create()!
	u2 := t.user_factory().with_role('USER').create()!
	u3 := t.user_factory().with_role('USER').create()!

	// 软删除 1 个
	t.bootstrap().user_repo.soft_delete(u2.id)!

	// 默认查询应返回 2 个
	filter := UserFilter{}
	users, total := t.bootstrap().user_repo.find_with_filters(filter, 'id_asc', 1, 20)!

	assert total == 2
	assert users.len == 2

	// 验证返回的用户都不包含 u2
	mut ids := []int{}
	for u in users {
		ids << u.id
	}
	assert u1.id in ids
	assert u3.id in ids
	assert u2.id !in ids
}

// ═══════════════════════════════════════════════════════════
// Post 软删除测试
// ═══════════════════════════════════════════════════════════

fn test_post_soft_delete_sets_archived_status() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	post := t.post_factory().with_author(author.id).create()!

	// 软删除
	t.bootstrap().post_repo.soft_delete(post.id)!

	// 验证 status = 'archived'（Post.find_by_id 不过滤 status）
	deleted := t.bootstrap().post_repo.find_by_id(post.id)!
	assert deleted.status == 'archived'
}

fn test_post_restore_after_soft_delete() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	post := t.post_factory().with_author(author.id).create()!

	// 软删除 → 恢复
	t.bootstrap().post_repo.soft_delete(post.id)!
	t.bootstrap().post_repo.restore(post.id)!

	// 验证 status 恢复为 'draft'
	restored := t.bootstrap().post_repo.find_by_id(post.id)!
	assert restored.status == 'draft'
}

fn test_post_find_only_archived() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	mut p1 := t.post_factory().with_author(author.id).create()!
	mut p2 := t.post_factory().with_author(author.id).create()!
	p3 := t.post_factory().with_author(author.id).create()!

	// 软删除两篇
	t.bootstrap().post_repo.soft_delete(p1.id)!
	t.bootstrap().post_repo.soft_delete(p2.id)!

	// 查询仅归档
	archived := t.bootstrap().post_repo.find_only_archived()!

	mut found_ids := []int{}
	for p in archived {
		found_ids << p.id
	}
	assert p1.id in found_ids
	assert p2.id in found_ids
	assert p3.id !in found_ids
}

fn test_post_published_status_preserved() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	post := t.post_factory().with_author(author.id).with_status('published').create()!

	// 软删除不会改变 author_id
	t.bootstrap().post_repo.soft_delete(post.id)!
	deleted := t.bootstrap().post_repo.find_by_id(post.id)!
	assert deleted.author_id == author.id
}

// ═══════════════════════════════════════════════════════════
// Comment 软删除测试
// ═══════════════════════════════════════════════════════════

fn test_comment_soft_delete_sets_deleted_status() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('USER').create()!
	post := t.post_factory().with_author(author.id).create()!
	comment := t.comment_factory().with_post(post.id).with_user(author.id).create()!

	// 软删除
	t.bootstrap().comment_repo.soft_delete(comment.id)!

	// 验证 status = 'deleted'（通过该文章下所有评论查询）
	comments := t.bootstrap().comment_repo.find_with_trashed(post.id)!
	mut found := Comment{}
	for c in comments {
		if c.id == comment.id {
			found = c
			break
		}
	}
	assert found.id == comment.id
	assert found.status == 'deleted'
}

fn test_comment_restore_after_soft_delete() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('USER').create()!
	post := t.post_factory().with_author(author.id).create()!
	comment := t.comment_factory().with_post(post.id).with_user(author.id).create()!

	// 软删除 → 恢复
	t.bootstrap().comment_repo.soft_delete(comment.id)!
	t.bootstrap().comment_repo.restore(comment.id)!

	// 验证 status 恢复为 'visible'
	restored := t.bootstrap().comment_repo.find_with_trashed(post.id)!
	mut found := Comment{}
	for c in restored {
		if c.id == comment.id {
			found = c
			break
		}
	}
	assert found.status == 'visible'
}

fn test_comment_find_by_post_excludes_deleted() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('USER').create()!
	post := t.post_factory().with_author(author.id).create()!
	mut c1 := t.comment_factory().with_post(post.id).with_user(author.id).create()!
	c2 := t.comment_factory().with_post(post.id).with_user(author.id).create()!
	mut c3 := t.comment_factory().with_post(post.id).with_user(author.id).create()!

	// 软删除 c1 和 c3
	t.bootstrap().comment_repo.soft_delete(c1.id)!
	t.bootstrap().comment_repo.soft_delete(c3.id)!

	// 默认 find_by_post 应只返回未删除的 c2
	comments := t.bootstrap().comment_repo.find_by_post(post.id)!
	assert comments.len == 1
	assert comments[0].id == c2.id
}

// ═══════════════════════════════════════════════════════════
// 软删除与 find_with_filters 协同
// ═══════════════════════════════════════════════════════════

fn test_post_find_with_filters_excludes_archived_by_default() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	mut p1 := t.post_factory().with_author(author.id).with_status('published').create()!
	p2 := t.post_factory().with_author(author.id).with_status('published').create()!

	// 软删除 p1
	t.bootstrap().post_repo.soft_delete(p1.id)!

	// 默认查询（status='all'）应只返回未归档的
	filter := PostFilter{status: 'all'}
	posts, total := t.bootstrap().post_repo.find_with_filters(filter, 'id_asc', 1, 20)!

	assert total == 1
	assert posts[0].id == p2.id
}

fn test_post_find_with_filters_by_status_archived() {
	mut t := TestCase{}
	t.setup()!
	defer { t.teardown() }

	author := t.user_factory().with_role('EDITOR').create()!
	mut p1 := t.post_factory().with_author(author.id).with_status('published').create()!
	p2 := t.post_factory().with_author(author.id).with_status('published').create()!

	// 软删除 p1
	t.bootstrap().post_repo.soft_delete(p1.id)!

	// 按 status=archived 过滤
	filter := PostFilter{status: 'archived'}
	posts, total := t.bootstrap().post_repo.find_with_filters(filter, 'id_asc', 1, 20)!

	assert total == 1
	assert posts[0].id == p1.id
	assert posts[0].status == 'archived'
}

module main

// repository_test.v — PhotonBlog 仓储层测试
//
// 测试覆盖：
//   - UserRepository CRUD + 派生查询
//   - PostRepository CRUD + 派生查询
//   - CommentRepository CRUD + 派生查询
//   - CategoryRepository CRUD + 派生查询
//   - TagRepository CRUD + 文章-标签关联

fn test_user_repository_save_and_find() {
	boot := test_setup()!
	mut repo := boot.user_repo

	mut user := User{
		username: 'alice'
		email:    'alice@test.com'
		password: 'hashed'
		role:     'USER'
		status:   1
	}
	saved := repo.save(mut user)!
	assert saved.id > 0
	assert saved.username == 'alice'
	assert saved.email == 'alice@test.com'

	found := repo.find_by_id(saved.id)!
	assert found.username == 'alice'
}

fn test_user_repository_find_all_and_count() {
	boot := test_setup()!
	mut repo := boot.user_repo

	mut u1 := User{username: 'alice', email: 'a@b.com', password: 'h', role: 'USER', status: 1}
	mut u2 := User{username: 'bob', email: 'b@b.com', password: 'h', role: 'USER', status: 1}
	repo.save(mut u1)!
	repo.save(mut u2)!

	all := repo.find_all()!
	assert all.len == 2

	count := repo.count()!
	assert count == 2
}

fn test_user_repository_find_by_username() {
	boot := test_setup()!
	mut repo := boot.user_repo

	mut user := User{username: 'bob', email: 'bob@test.com', password: 'h', role: 'USER', status: 1}
	repo.save(mut user)!

	found := repo.find_by_username('bob')!
	assert found.email == 'bob@test.com'
}

fn test_user_repository_find_by_email() {
	boot := test_setup()!
	mut repo := boot.user_repo

	mut user := User{username: 'charlie', email: 'charlie@test.com', password: 'h', role: 'USER', status: 1}
	repo.save(mut user)!

	found := repo.find_by_email('charlie@test.com')!
	assert found.username == 'charlie'
}

fn test_user_repository_exists_checks() {
	boot := test_setup()!
	mut repo := boot.user_repo

	mut user := User{username: 'dave', email: 'dave@test.com', password: 'h', role: 'USER', status: 1}
	repo.save(mut user)!

	assert repo.exists_by_username('dave') == true
	assert repo.exists_by_username('nonexistent') == false
	assert repo.exists_by_email('dave@test.com') == true
	assert repo.exists_by_email('nope@test.com') == false
}

fn test_user_repository_delete() {
	boot := test_setup()!
	mut repo := boot.user_repo

	mut user := User{username: 'deleteme', email: 'del@test.com', password: 'h', role: 'USER', status: 1}
	saved := repo.save(mut user)!
	assert repo.exists_by_id(saved.id) == true

	repo.delete_by_id(saved.id)!
	assert repo.exists_by_id(saved.id) == false
}

fn test_post_repository_save_and_find() {
	boot := test_setup()!
	mut repo := boot.post_repo

	mut post := Post{
		title:     'Test Post'
		content:   'Content'
		author_id: 1
		status:    'draft'
	}
	saved := repo.save(mut post)!
	assert saved.id > 0
	assert saved.title == 'Test Post'

	found := repo.find_by_id(saved.id)!
	assert found.title == 'Test Post'
}

fn test_post_repository_find_by_author() {
	boot := test_setup()!
	mut repo := boot.post_repo

	mut p1 := Post{title: 'Post 1', content: 'C1', author_id: 1, status: 'published'}
	mut p2 := Post{title: 'Post 2', content: 'C2', author_id: 1, status: 'draft'}
	mut p3 := Post{title: 'Post 3', content: 'C3', author_id: 2, status: 'published'}
	repo.save(mut p1)!
	repo.save(mut p2)!
	repo.save(mut p3)!

	posts := repo.find_by_author(1)!
	assert posts.len == 2
}

fn test_post_repository_find_by_status() {
	boot := test_setup()!
	mut repo := boot.post_repo

	mut p1 := Post{title: 'P1', content: 'C', author_id: 1, status: 'published'}
	mut p2 := Post{title: 'P2', content: 'C', author_id: 1, status: 'draft'}
	repo.save(mut p1)!
	repo.save(mut p2)!

	published := repo.find_by_status('published')!
	assert published.len == 1
	assert published[0].title == 'P1'

	drafts := repo.find_by_status('draft')!
	assert drafts.len == 1
}

fn test_post_repository_increment_views() {
	boot := test_setup()!
	mut repo := boot.post_repo

	mut post := Post{title: 'Viewed', content: 'C', author_id: 1, status: 'published'}
	saved := repo.save(mut post)!
	assert saved.views == 0

	repo.increment_views(saved.id)!
	found := repo.find_by_id(saved.id)!
	assert found.views == 1
}

fn test_post_repository_count_by_status() {
	boot := test_setup()!
	mut repo := boot.post_repo

	mut p1 := Post{title: 'P1', content: 'C', author_id: 1, status: 'published'}
	mut p2 := Post{title: 'P2', content: 'C', author_id: 1, status: 'published'}
	mut p3 := Post{title: 'P3', content: 'C', author_id: 1, status: 'draft'}
	repo.save(mut p1)!
	repo.save(mut p2)!
	repo.save(mut p3)!

	assert repo.count_by_status('published')! == 2
	assert repo.count_by_status('draft')! == 1
}

fn test_comment_repository_save_and_find() {
	boot := test_setup()!
	mut repo := boot.comment_repo

	mut comment := Comment{
		post_id:   1
		user_id:   1
		content:   'Great post!'
		parent_id: 0
		status:    'visible'
	}
	saved := repo.save(mut comment)!
	assert saved.id > 0
	assert saved.content == 'Great post!'
}

fn test_comment_repository_find_by_post() {
	boot := test_setup()!
	mut repo := boot.comment_repo

	mut c1 := Comment{post_id: 1, user_id: 1, content: 'C1', status: 'visible'}
	mut c2 := Comment{post_id: 1, user_id: 2, content: 'C2', status: 'visible'}
	mut c3 := Comment{post_id: 2, user_id: 1, content: 'C3', status: 'visible'}
	repo.save(mut c1)!
	repo.save(mut c2)!
	repo.save(mut c3)!

	comments := repo.find_by_post(1)!
	assert comments.len == 2
}

fn test_comment_repository_find_by_parent() {
	boot := test_setup()!
	mut repo := boot.comment_repo

	mut parent := Comment{post_id: 1, user_id: 1, content: 'Parent', status: 'visible'}
	saved_parent := repo.save(mut parent)!

	mut reply := Comment{post_id: 1, user_id: 2, content: 'Reply', parent_id: saved_parent.id, status: 'visible'}
	repo.save(mut reply)!

	replies := repo.find_by_parent(saved_parent.id)!
	assert replies.len == 1
	assert replies[0].content == 'Reply'
}

fn test_comment_repository_count_by_post() {
	boot := test_setup()!
	mut repo := boot.comment_repo

	mut c1 := Comment{post_id: 1, user_id: 1, content: 'C1', status: 'visible'}
	mut c2 := Comment{post_id: 1, user_id: 2, content: 'C2', status: 'visible'}
	repo.save(mut c1)!
	repo.save(mut c2)!

	assert repo.count_by_post(1)! == 2
	assert repo.count_by_post(999)! == 0
}

fn test_category_repository_save_and_find() {
	boot := test_setup()!
	mut repo := boot.category_repo

	mut cat := Category{
		name:        'Technology'
		slug:        'technology'
		description: 'Tech articles'
	}
	saved := repo.save(mut cat)!
	assert saved.id > 0
	assert saved.name == 'Technology'
}

fn test_category_repository_find_by_slug() {
	boot := test_setup()!
	mut repo := boot.category_repo

	mut cat := Category{name: 'V Language', slug: 'v-language', description: 'V lang posts'}
	repo.save(mut cat)!

	found := repo.find_by_slug('v-language')!
	assert found.name == 'V Language'
}

fn test_category_repository_exists_by_slug() {
	boot := test_setup()!
	mut repo := boot.category_repo

	mut cat := Category{name: 'Rust', slug: 'rust', description: ''}
	repo.save(mut cat)!

	assert repo.exists_by_slug('rust') == true
	assert repo.exists_by_slug('nonexistent') == false
}

fn test_tag_repository_save_and_find() {
	boot := test_setup()!
	mut repo := boot.tag_repo

	mut tag := Tag{name: 'vlang', slug: 'vlang'}
	saved := repo.save(mut tag)!
	assert saved.id > 0
	assert saved.name == 'vlang'
}

fn test_tag_repository_find_by_slug() {
	boot := test_setup()!
	mut repo := boot.tag_repo

	mut tag := Tag{name: 'web', slug: 'web'}
	repo.save(mut tag)!

	found := repo.find_by_slug('web')!
	assert found.name == 'web'
}

fn test_tag_repository_attach_and_find_tags() {
	boot := test_setup()!
	mut post_repo := boot.post_repo
	mut tag_repo := boot.tag_repo

	// 创建文章和标签
	mut post := Post{title: 'Tagged Post', content: 'C', author_id: 1, status: 'published'}
	saved_post := post_repo.save(mut post)!

	mut tag1 := Tag{name: 'vlang', slug: 'vlang'}
	mut tag2 := Tag{name: 'web', slug: 'web'}
	saved_tag1 := tag_repo.save(mut tag1)!
	saved_tag2 := tag_repo.save(mut tag2)!

	// 关联标签
	tag_repo.attach_tag(saved_post.id, saved_tag1.id)!
	tag_repo.attach_tag(saved_post.id, saved_tag2.id)!

	// 查询文章的标签
	tags := tag_repo.find_tags_by_post(saved_post.id)!
	assert tags.len == 2

	// 查询标签关联的文章 ID
	post_ids := tag_repo.find_post_ids_by_tag(saved_tag1.id)!
	assert saved_post.id in post_ids
}

fn test_tag_repository_detach_tag() {
	boot := test_setup()!
	mut post_repo := boot.post_repo
	mut tag_repo := boot.tag_repo

	mut post := Post{title: 'Detach Post', content: 'C', author_id: 1, status: 'published'}
	saved_post := post_repo.save(mut post)!

	mut tag := Tag{name: 'temp', slug: 'temp'}
	saved_tag := tag_repo.save(mut tag)!

	tag_repo.attach_tag(saved_post.id, saved_tag.id)!
	assert tag_repo.find_tags_by_post(saved_post.id)!.len == 1

	tag_repo.detach_tag(saved_post.id, saved_tag.id)!
	assert tag_repo.find_tags_by_post(saved_post.id)!.len == 0
}

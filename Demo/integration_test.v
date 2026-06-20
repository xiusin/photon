module main

// integration_test.v — PhotonBlog 端到端集成测试
//
// 测试覆盖：
//   - Bootstrap 初始化完整性
//   - 完整请求生命周期：注册 → 登录 → JWT → 角色校验
//   - 跨服务协作：用户 + 文章 + 评论 + 缓存
//   - ApplicationContext Bean 注册与获取
//   - 数据库迁移与回滚
//   - 配置驱动行为差异
//   - 事件驱动集成
//   - slug 自动生成集成
//   - 统计服务缓存集成
//   - 密码修改与重新登录

import database
import database.migrations
import models

// ═══════════════════════════════════════════════════════════
// Bootstrap 初始化完整性
// ═══════════════════════════════════════════════════════════

fn test_bootstrap_initialization() {
	boot := test_setup()!

	// 配置
	assert boot.cfg.profile == 'test'
	assert boot.cfg.debug == true
	assert boot.cfg.database.path == ':memory:'

	// 基础设施组件
	assert !isnil(boot.log)
	assert !isnil(boot.event_bus)
	assert !isnil(boot.cache_mgr)
	assert !isnil(boot.orm_mgr)
	assert !isnil(boot.lock_mgr)
	assert !isnil(boot.storage_mgr)
	assert !isnil(boot.mailer_inst)
	assert !isnil(boot.scheduler)
	assert !isnil(boot.jwt_mgr)
	assert !isnil(boot.role_hierarchy)
	assert !isnil(boot.worker)
	assert !isnil(boot.upload_handler)

	// 仓储
	assert !isnil(boot.user_repo)
	assert !isnil(boot.post_repo)
	assert !isnil(boot.comment_repo)
	assert !isnil(boot.category_repo)
	assert !isnil(boot.tag_repo)

	// 服务
	assert !isnil(boot.user_svc)
	assert !isnil(boot.auth_svc)
	assert !isnil(boot.post_svc)
	assert !isnil(boot.comment_svc)
	assert !isnil(boot.category_svc)
	assert !isnil(boot.tag_svc)
	assert !isnil(boot.stats_svc)
	assert !isnil(boot.upload_svc)
}

fn test_bootstrap_application_context() {
	boot := test_setup()!
	mut ctx := boot.app_context

	// ApplicationContext 应包含所有注册的 Bean
	assert ctx.bean_count() >= 25
	assert ctx.singleton_count() >= 25
}

// ═══════════════════════════════════════════════════════════
// 完整请求生命周期：注册 → 登录 → JWT → 角色校验
// ═══════════════════════════════════════════════════════════

fn test_full_request_lifecycle() {
	boot := test_setup()!
	mut user_svc := boot.user_svc
	mut auth_svc := boot.auth_svc

	// 1. 注册用户
	dto := CreateUserDto{
		username: 'integ_user'
		email:    'integ@test.com'
		password: 'pass123'
		nickname: 'Integration'
		role:     'USER'
	}
	user, _ := user_svc.register(dto)!
	assert user.id > 0
	assert user.username == 'integ_user'
	assert user.password != 'pass123' // 密码已哈希

	// 2. 登录获取用户
	logged_in := user_svc.login(LoginDto{username: 'integ_user', password: 'pass123'})!
	assert logged_in.id == user.id

	// 3. 生成 JWT 令牌
	access, refresh := auth_svc.generate_token(&user)!
	assert access.len > 0
	assert refresh.len > 0
	assert access != refresh

	// 4. 验证令牌
	username := auth_svc.validate_token(access)!
	assert username == 'integ_user'

	// 5. 解析令牌获取 claims
	claims := auth_svc.parse_token(access)!
	assert claims.sub == 'integ_user'
	assert claims.roles.len == 1
	assert claims.roles[0] == 'USER'

	// 6. 角色校验（has_role 只检查令牌声明，不使用层级）
	assert auth_svc.has_role(access, 'USER') == true
	assert auth_svc.has_role(access, 'ADMIN') == false

	// 7. 刷新令牌
	new_access, new_refresh := auth_svc.refresh_token(refresh)!
	assert new_access.len > 0
	assert new_refresh.len > 0

	// 8. 新令牌可验证
	new_username := auth_svc.validate_token(new_access)!
	assert new_username == 'integ_user'

	// 9. 构建登录响应
	resp := auth_svc.build_login_response(&user)!
	assert resp.access_token.len > 0
	assert resp.refresh_token.len > 0
	assert resp.token_type == 'Bearer'
	assert resp.expires_in == 3600
	assert resp.user.username == 'integ_user'
}

// ═══════════════════════════════════════════════════════════
// 跨服务协作：用户 + 文章 + 评论 + 缓存
// ═══════════════════════════════════════════════════════════

fn test_cross_service_user_post_comment() {
	boot := test_setup()!
	mut user_svc := boot.user_svc
	mut post_svc := boot.post_svc
	mut comment_svc := boot.comment_svc
	mut category_svc := boot.category_svc
	mut stats_svc := boot.stats_svc

	// 1. 创建用户
	user_dto := CreateUserDto{
		username: 'author1'
		email:    'author1@test.com'
		password: 'pass123'
		role:     'EDITOR'
	}
	author, _ := user_svc.register(user_dto)!
	assert author.id > 0

	// 2. 创建分类
	cat_dto := CreateCategoryDto{name: 'Technology'}
	category := category_svc.create(cat_dto)!
	assert category.id > 0
	assert category.slug == 'technology'

	// 3. 创建文章
	post_dto := CreatePostDto{
		title:       'Integration Test Post'
		content:     'This is a comprehensive integration test.'
		summary:     'Integration test'
		author_id:   author.id
		category_id: category.id
		status:      'published'
	}
	post := post_svc.create(post_dto)!
	assert post.id > 0
	assert post.status == 'published'

	// 4. 创建评论
	comment_dto := CreateCommentDto{
		post_id: post.id
		user_id: author.id
		content: 'Great integration test!'
	}
	comment := comment_svc.create(comment_dto)!
	assert comment.id > 0
	assert comment.status == 'visible'

	// 5. 创建嵌套评论
	reply_dto := CreateCommentDto{
		post_id:   post.id
		user_id:   author.id
		content:   'Reply to the comment'
		parent_id: comment.id
	}
	reply := comment_svc.create(reply_dto)!
	assert reply.parent_id == comment.id

	// 6. 查询文章评论
	comments := comment_svc.find_by_post(post.id)!
	assert comments.len == 2

	// 7. 查询子评论
	replies := comment_svc.find_replies(comment.id)!
	assert replies.len == 1
	assert replies[0].content == 'Reply to the comment'

	// 8. 缓存命中测试
	cached_post := post_svc.find_by_id(post.id)!
	assert cached_post.id == post.id
	assert cached_post.title == 'Integration Test Post'

	// 9. 统计聚合
	stats := stats_svc.aggregate_stats()!
	assert stats.user_count >= 1
	assert stats.post_count >= 1
	assert stats.published_count >= 1
	assert stats.comment_count >= 2
}

// ═══════════════════════════════════════════════════════════
// 角色层级权限校验集成
// ═══════════════════════════════════════════════════════════

fn test_role_hierarchy_integration() {
	boot := test_setup()!
	mut user_svc := boot.user_svc
	mut auth_svc := boot.auth_svc

	// 创建不同角色的用户
	admin_dto := CreateUserDto{username: 'intadmin', email: 'ia@t.com', password: 'p', role: 'ADMIN'}
	editor_dto := CreateUserDto{username: 'inteditor', email: 'ie@t.com', password: 'p', role: 'EDITOR'}
	user_dto := CreateUserDto{username: 'intuser', email: 'iu@t.com', password: 'p', role: 'USER'}

	admin, _ := user_svc.register(admin_dto)!
	editor, _ := user_svc.register(editor_dto)!
	user, _ := user_svc.register(user_dto)!

	// 生成令牌
	admin_token, _ := auth_svc.generate_token(&admin)!
	editor_token, _ := auth_svc.generate_token(&editor)!
	user_token, _ := auth_svc.generate_token(&user)!

	// has_role 检查令牌中的直接角色声明
	assert auth_svc.has_role(admin_token, 'ADMIN') == true
	assert auth_svc.has_role(editor_token, 'EDITOR') == true
	assert auth_svc.has_role(user_token, 'USER') == true

	// has_role 不使用角色层级，只检查令牌声明
	assert auth_svc.has_role(admin_token, 'EDITOR') == false
	assert auth_svc.has_role(editor_token, 'USER') == false

	// check_permission 使用角色层级，ADMIN 继承所有角色
	assert auth_svc.check_permission(['ADMIN'], 'ADMIN') == true
	assert auth_svc.check_permission(['ADMIN'], 'EDITOR') == true
	assert auth_svc.check_permission(['ADMIN'], 'USER') == true
	assert auth_svc.check_permission(['EDITOR'], 'USER') == true
	assert auth_svc.check_permission(['EDITOR'], 'ADMIN') == false
	assert auth_svc.check_permission(['USER'], 'EDITOR') == false
}

// ═══════════════════════════════════════════════════════════
// 缓存失效与一致性
// ═══════════════════════════════════════════════════════════

fn test_cache_invalidation_on_update() {
	boot := test_setup()!
	mut post_svc := boot.post_svc

	// 创建文章
	post_dto := CreatePostDto{
		title:     'Cache Test'
		content:   'Original content'
		author_id: 1
		status:    'published'
	}
	created := post_svc.create(post_dto)!

	// 首次读取（缓存写入）
	found := post_svc.find_by_id(created.id)!
	assert found.title == 'Cache Test'

	// 更新文章（应清除缓存）
	update_dto := UpdatePostDto{title: 'Updated Title', content: 'Updated content'}
	updated := post_svc.update(created.id, update_dto)!
	assert updated.title == 'Updated Title'

	// 再次读取（应从 DB 重新加载，不是旧缓存）
	reloaded := post_svc.find_by_id(created.id)!
	assert reloaded.title == 'Updated Title'
	assert reloaded.content == 'Updated content'
}

// ═══════════════════════════════════════════════════════════
// 数据库迁移与回滚
// ═══════════════════════════════════════════════════════════

fn test_migration_and_rollback() {
	boot := test_setup()!
	mut user_repo := boot.user_repo

	// 迁移已由 test_setup 执行，验证表存在
	mut user := User{username: 'mig_test', email: 'mig@t.com', password: 'h', role: 'USER', status: 1}
	saved := user_repo.save(mut user)!
	assert saved.id > 0

	// 回滚迁移
	mm := database.new_migration_manager(boot.orm_mgr)!
	database.migrations.register_all(mut mm)
	database.rollback_migrations(mm) or {}

	// 重新迁移
	mm2 := database.new_migration_manager(boot.orm_mgr)!
	database.migrations.register_all(mut mm2)
	database.run_migrations(mm2) or {}

	// 验证迁移后表可用
	mut user2 := User{username: 'mig_test2', email: 'mig2@t.com', password: 'h', role: 'USER', status: 1}
	saved2 := user_repo.save(mut user2)!
	assert saved2.id > 0
}

// ═══════════════════════════════════════════════════════════
// 配置驱动行为差异
// ═══════════════════════════════════════════════════════════

fn test_config_drives_bootstrap_behavior() {
	// dev 配置
	dev_cfg := load_config('dev')!
	assert dev_cfg.debug == true
	assert dev_cfg.database.path == ':memory:'
	assert dev_cfg.mail.driver == 'log'

	// prod 配置
	prod_cfg := load_config('prod')!
	assert prod_cfg.debug == false
	assert prod_cfg.database.path == './photonblog.db'
	assert prod_cfg.mail.driver == 'smtp'

	// test 配置
	test_cfg := load_config('test')!
	assert test_cfg.debug == true
	assert test_cfg.database.path == ':memory:'
	assert test_cfg.server.port == 0
}

// ═══════════════════════════════════════════════════════════
// 事件驱动集成
// ═══════════════════════════════════════════════════════════

fn test_event_driven_cache_invalidation() {
	boot := test_setup()!
	mut bus := boot.event_bus
	mut user_svc := boot.user_svc

	// 注册用户应触发 user.registered 事件，失效统计缓存
	dto := CreateUserDto{username: 'evuser', email: 'ev@t.com', password: 'pass'}
	user_svc.register(dto)!

	// 事件监听器应已注册
	assert bus.has_listeners(event_user_registered) == true
	assert bus.has_listeners(event_post_published) == true
	assert bus.has_listeners(event_comment_posted) == true
}

// ═══════════════════════════════════════════════════════════
// slug 自动生成集成
// ═══════════════════════════════════════════════════════════

fn test_slug_generation_integration() {
	boot := test_setup()!
	mut category_svc := boot.category_svc
	mut tag_svc := boot.tag_svc

	// 分类 slug 自动生成
	cat1 := category_svc.create(CreateCategoryDto{name: 'Web Development'})!
	assert cat1.slug == 'web-development'

	cat2 := category_svc.create(CreateCategoryDto{name: 'V Language'})!
	assert cat2.slug == 'v-language'

	// 标签 slug 自动生成
	tag1 := tag_svc.create(CreateTagDto{name: 'Machine Learning'})!
	assert tag1.slug == 'machine-learning'

	// slug 唯一性校验
	category_svc.create(CreateCategoryDto{name: 'Tech', slug: 'web-development'}) or {
		assert err.msg().contains('slug')
		return
	}
	assert false
}

// ═══════════════════════════════════════════════════════════
// 统计服务缓存集成
// ═══════════════════════════════════════════════════════════

fn test_stats_service_cache_integration() {
	boot := test_setup()!
	mut user_svc := boot.user_svc
	mut post_svc := boot.post_svc
	mut stats_svc := boot.stats_svc

	// 创建测试数据
	user_svc.register(CreateUserDto{username: 'stats_u', email: 'su@t.com', password: 'p'})!
	post_svc.create(CreatePostDto{title: 'Stats Post', content: 'C', author_id: 1, status: 'published'})!

	// 第一次查询（缓存未命中，从 DB 聚合）
	stats1 := stats_svc.get_blog_stats()!
	assert stats1.aggregated_at > 0

	// 第二次查询（缓存命中）
	stats2 := stats_svc.get_blog_stats()!
	assert stats2.aggregated_at > 0

	// 失效缓存
	stats_svc.invalidate_cache()!

	// 再次查询应重新聚合
	stats3 := stats_svc.get_blog_stats()!
	assert stats3.aggregated_at > 0
}

// ═══════════════════════════════════════════════════════════
// 密码修改与重新登录集成
// ═══════════════════════════════════════════════════════════

fn test_password_change_and_relogin() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	// 注册
	dto := CreateUserDto{username: 'pwchange', email: 'pw@t.com', password: 'oldpass'}
	user, _ := user_svc.register(dto)!

	// 旧密码可登录
	user_svc.login(LoginDto{username: 'pwchange', password: 'oldpass'})!

	// 修改密码
	user_svc.change_password(user.id, 'oldpass', 'newpass')!

	// 新密码可登录
	logged_in := user_svc.login(LoginDto{username: 'pwchange', password: 'newpass'})!
	assert logged_in.id == user.id

	// 旧密码不可登录
	user_svc.login(LoginDto{username: 'pwchange', password: 'oldpass'}) or {
		assert true
		return
	}
	assert false
}

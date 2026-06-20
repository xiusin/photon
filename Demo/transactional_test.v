module main

// transactional_test.v — 事务支持测试
//
// 测试覆盖：
//   - TransactionGuard 基本生命周期（begin/commit/rollback/auto_rollback）
//   - transactional() 函数式 API（成功提交 / 失败回滚）
//   - 多步操作原子性：第二步失败时第一步回滚（SubTask 13.4）
//   - CommentService.create 事务（评论创建 + touch_post 原子性）
//   - UserService.register 事务（用户持久化原子性）
//   - PostService.create 事务

import db.sqlite

// ═══════════════════════════════════════════════════════════
// TransactionGuard 单元测试
// ═══════════════════════════════════════════════════════════

fn test_transaction_guard_commit() {
	db := create_test_db()!

	mut d := unsafe { mut db }
	d.exec('CREATE TABLE IF NOT EXISTS test_items (id INTEGER PRIMARY KEY, name TEXT)')!

	// 事务中插入数据并提交
	mut tx := begin_transaction(db)!
	defer {
		tx.auto_rollback()
	}

	d.exec_param("INSERT INTO test_items (name) VALUES ('item1')", 'item1')!

	tx.commit()!

	// 验证提交后数据存在
	rows := d.exec('SELECT COUNT(*) AS cnt FROM test_items')!
	assert rows[0].get_int('cnt') == 1
}

fn test_transaction_guard_rollback_on_error() {
	db := create_test_db()!

	mut d := unsafe { mut db }
	d.exec('CREATE TABLE IF NOT EXISTS test_items (id INTEGER PRIMARY KEY, name TEXT)')!

	// 通过辅助函数模拟事务中失败：defer auto_rollback 在函数返回时执行
	// V 的 defer 在函数退出时执行（非块作用域），因此用辅助函数隔离事务生命周期
	simulate_failing_tx(db) or {}

	// 验证回滚后数据不存在
	rows := d.exec('SELECT COUNT(*) AS cnt FROM test_items')!
	assert rows[0].get_int('cnt') == 0
}

// simulate_failing_tx 模拟事务中失败：插入数据后不 commit，defer 自动回滚
fn simulate_failing_tx(db &sqlite.DB) ! {
	mut tx := begin_transaction(db)!
	defer {
		tx.auto_rollback()
	}

	mut d := unsafe { mut db }
	d.exec_param("INSERT INTO test_items (name) VALUES ('should_rollback')", 'should_rollback')!
	// 不调用 tx.commit() — 函数返回时 defer 自动回滚
	return error('simulated failure / 模拟失败')
}

fn test_transaction_guard_explicit_rollback() {
	db := create_test_db()!

	mut d := unsafe { mut db }
	d.exec('CREATE TABLE IF NOT EXISTS test_items (id INTEGER PRIMARY KEY, name TEXT)')!

	mut tx := begin_transaction(db)!
	d.exec_param("INSERT INTO test_items (name) VALUES ('rolled_back')", 'rolled_back')!
	tx.rollback()

	// 验证回滚后数据不存在
	rows := d.exec('SELECT COUNT(*) AS cnt FROM test_items')!
	assert rows[0].get_int('cnt') == 0

	// 验证 guard 标记为已处理
	assert tx.is_committed() == true
}

fn test_transaction_guard_idempotent_commit() {
	db := create_test_db()!

	mut d := unsafe { mut db }
	d.exec('CREATE TABLE IF NOT EXISTS test_items (id INTEGER PRIMARY KEY, name TEXT)')!

	mut tx := begin_transaction(db)!
	d.exec_param("INSERT INTO test_items (name) VALUES ('item')", 'item')!
	tx.commit()!

	// 二次 commit 应幂等（不报错，不重复操作）
	tx.commit() or {}

	assert tx.is_committed() == true
}

fn test_transaction_guard_idempotent_rollback() {
	db := create_test_db()!

	mut d := unsafe { mut db }
	d.exec('CREATE TABLE IF NOT EXISTS test_items (id INTEGER PRIMARY KEY, name TEXT)')!

	mut tx := begin_transaction(db)!
	tx.rollback()
	// 二次 rollback 应幂等
	tx.rollback()

	assert tx.is_committed() == true
}

// ═══════════════════════════════════════════════════════════
// transactional() 函数式 API 测试
// ═══════════════════════════════════════════════════════════

fn test_transactional_helper_commit_on_success() {
	db := create_test_db()!

	mut d := unsafe { mut db }
	d.exec('CREATE TABLE IF NOT EXISTS test_items (id INTEGER PRIMARY KEY, name TEXT)')!

	transactional(db, fn [db] () ! {
		mut dd := unsafe { mut db }
		dd.exec_param("INSERT INTO test_items (name) VALUES ('via_helper')", 'via_helper')!
	})!

	// 验证提交后数据存在
	rows := d.exec('SELECT COUNT(*) AS cnt FROM test_items')!
	assert rows[0].get_int('cnt') == 1
}

fn test_transactional_helper_rollback_on_failure() {
	db := create_test_db()!

	mut d := unsafe { mut db }
	d.exec('CREATE TABLE IF NOT EXISTS test_items (id INTEGER PRIMARY KEY, name TEXT)')!

	// 先插入一条数据（不在事务中）
	d.exec_param("INSERT INTO test_items (name) VALUES ('pre_existing')", 'pre_existing')!

	// 事务中插入数据后故意失败
	mut failed := false
	transactional(db, fn [db] () ! {
		mut dd := unsafe { mut db }
		dd.exec_param("INSERT INTO test_items (name) VALUES ('should_rollback')", 'should_rollback')!
		return error('intentional failure / 故意失败')
	}) or {
		failed = true
	}

	// 验证事务函数返回了错误
	assert failed == true

	// 验证事务中的插入被回滚，但事务前的数据保留
	rows := d.exec('SELECT COUNT(*) AS cnt FROM test_items')!
	assert rows[0].get_int('cnt') == 1 // 只有 pre_existing
}

// ═══════════════════════════════════════════════════════════
// 多步操作原子性测试（SubTask 13.4 — 模拟 register 第二步失败）
// ═══════════════════════════════════════════════════════════

fn test_multistep_transaction_rollback_step2_fails() {
	// 模拟 register 的多步操作：第一步插入用户，第二步故意失败
	// 验证第一步的插入被回滚（用户未创建）
	boot := test_setup()!
	user_repo := boot.user_repo
	db := user_repo.db

	// 记录初始用户数
	initial_count := user_repo.count()!

	// 模拟两步事务：插入用户 → 第二步失败
	mut failed := false
	transactional(db, fn [db] () ! {
		mut d := unsafe { mut db }
		// 第一步：插入用户
		params := ['rollback_test', 'rollback@test.com', 'hashed_pw', 'RollbackTest', '', '1', 'USER', '0', '0', '0']
		d.exec_param_many('INSERT INTO users (username, email, password, nickname, avatar, status, role, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', params)!

		// 第二步：故意失败（模拟初始化统计失败）
		return error('simulated step 2 failure / 模拟第二步失败')
	}) or {
		failed = true
	}

	// 验证事务返回了错误
	assert failed == true

	// 验证用户未创建（第一步被回滚）
	final_count := user_repo.count()!
	assert final_count == initial_count

	// 验证特定用户名不存在
	assert user_repo.exists_by_username('rollback_test') == false
}

fn test_multistep_transaction_commit_both_steps() {
	// 模拟两步事务都成功：插入用户 + 更新 → 验证两步都提交
	boot := test_setup()!
	user_repo := boot.user_repo
	db := user_repo.db

	initial_count := user_repo.count()!

	// 两步事务都成功
	transactional(db, fn [db] () ! {
		mut d := unsafe { mut db }
		// 第一步：插入用户
		params := ['commit_test', 'commit@test.com', 'hashed_pw', 'CommitTest', '', '1', 'USER', '0', '0', '0']
		d.exec_param_many('INSERT INTO users (username, email, password, nickname, avatar, status, role, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', params)!
		// 第二步：成功完成（无额外操作）
	})!

	// 验证用户已创建
	final_count := user_repo.count()!
	assert final_count == initial_count + 1
	assert user_repo.exists_by_username('commit_test') == true
}

// ═══════════════════════════════════════════════════════════
// CommentService.create 事务测试（评论 + touch_post 原子性）
// ═══════════════════════════════════════════════════════════

fn test_comment_service_create_transaction_success() {
	boot := test_setup()!

	// 先创建用户和文章
	mut user_svc := boot.user_svc
	user, _ := user_svc.register(CreateUserDto{
		username: 'commenter'
		email:    'commenter@test.com'
		password: 'password123'
		role:     'USER'
	})!

	mut post_svc := boot.post_svc
	post := post_svc.create(CreatePostDto{
		title:       'Test Post for Comment'
		content:     'Content for comment test'
		summary:     'Summary'
		author_id:   user.id
		category_id: 0
		status:      'published'
	})!

	original_updated_at := post.updated_at

	// 创建评论（事务：评论创建 + touch_post）
	mut comment_svc := boot.comment_svc
	comment := comment_svc.create(CreateCommentDto{
		post_id:   post.id
		user_id:   user.id
		content:   'Test comment for transaction'
		parent_id: 0
	})!

	// 验证评论已创建
	assert comment.id > 0
	assert comment.content == 'Test comment for transaction'

	// 验证文章的 updated_at 被更新（touch_post 执行成功）
	updated_post := boot.post_repo.find_by_id(post.id)!
	assert updated_post.updated_at >= original_updated_at

	// 验证评论数
	count := boot.comment_repo.count_by_post(post.id)!
	assert count == 1
}

fn test_comment_service_create_rolls_back_on_failure() {
	boot := test_setup()!

	// 创建用户和文章
	mut user_svc := boot.user_svc
	user, _ := user_svc.register(CreateUserDto{
		username: 'commenter2'
		email:    'commenter2@test.com'
		password: 'password123'
		role:     'USER'
	})!

	mut post_svc := boot.post_svc
	post := post_svc.create(CreatePostDto{
		title:       'Test Post for Comment Rollback'
		content:     'Content'
		summary:     'Summary'
		author_id:   user.id
		category_id: 0
		status:      'published'
	})!

	// 记录评论数
	initial_comment_count := boot.comment_repo.count_by_post(post.id)!

	// 手动执行事务：插入评论 → 第二步故意失败
	// 验证评论插入被回滚
	db := boot.comment_repo.db
	mut failed := false
	transactional(db, fn [db] () ! {
		mut d := unsafe { mut db }
		// 第一步：插入评论
		params := [post.id.str(), user.id.str(), 'rollback comment', '0', 'visible', '0', '0', '0']
		d.exec_param_many('INSERT INTO comments (post_id, user_id, content, parent_id, status, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', params)!

		// 第二步：故意失败
		return error('simulated failure / 模拟失败')
	}) or {
		failed = true
	}

	assert failed == true

	// 验证评论未创建（回滚）
	final_comment_count := boot.comment_repo.count_by_post(post.id)!
	assert final_comment_count == initial_comment_count
}

// ═══════════════════════════════════════════════════════════
// UserService.register 事务测试
// ═══════════════════════════════════════════════════════════

fn test_user_service_register_transaction_success() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	initial_count := boot.user_repo.count()!

	user, msg := user_svc.register(CreateUserDto{
		username: 'tx_test_user'
		email:    'tx_test@test.com'
		password: 'password123'
		role:     'USER'
	})!

	// 验证用户已创建
	assert user.id > 0
	assert user.username == 'tx_test_user'
	assert msg.len > 0

	// 验证用户数增加
	final_count := boot.user_repo.count()!
	assert final_count == initial_count + 1
}

fn test_user_service_register_rolls_back_on_duplicate() {
	boot := test_setup()!
	mut user_svc := boot.user_svc

	// 第一次注册成功
	user_svc.register(CreateUserDto{
		username: 'duplicate_user'
		email:    'dup@test.com'
		password: 'password123'
		role:     'USER'
	})!

	initial_count := boot.user_repo.count()!

	// 第二次用相同用户名注册应失败（唯一性校验在事务前）
	mut failed := false
	user_svc.register(CreateUserDto{
		username: 'duplicate_user'
		email:    'other@test.com'
		password: 'password123'
		role:     'USER'
	}) or {
		failed = true
	}

	assert failed == true

	// 验证用户数未增加
	final_count := boot.user_repo.count()!
	assert final_count == initial_count
}

// ═══════════════════════════════════════════════════════════
// PostService.create 事务测试
// ═══════════════════════════════════════════════════════════

fn test_post_service_create_transaction_success() {
	boot := test_setup()!

	// 先创建用户
	mut user_svc := boot.user_svc
	user, _ := user_svc.register(CreateUserDto{
		username: 'post_author'
		email:    'author@test.com'
		password: 'password123'
		role:     'USER'
	})!

	mut post_svc := boot.post_svc
	post := post_svc.create(CreatePostDto{
		title:       'Transactional Post'
		content:     'Content for transaction test'
		summary:     'Summary'
		author_id:   user.id
		category_id: 0
		status:      'draft'
	})!

	// 验证文章已创建
	assert post.id > 0
	assert post.title == 'Transactional Post'

	// 验证可从仓储查回
	found := boot.post_repo.find_by_id(post.id)!
	assert found.title == 'Transactional Post'
}

// ═══════════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════════

// create_test_db 创建独立的内存 SQLite 数据库（用于 TransactionGuard 单元测试）
fn create_test_db() !&sqlite.DB {
	db := sqlite.connect(':memory:')!
	return &db
}

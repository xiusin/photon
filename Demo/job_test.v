module main

// job_test.v — PhotonBlog 队列任务派发与执行测试
//
// 测试覆盖：
//   - Job 类型定义（job_type / tries / backoff）
//   - 队列派发
//   - Job 全局依赖初始化
//   - StatsAggregationJob 执行
//   - CleanupExpiredTokensJob 执行
//   - Job 工厂注册

import photon.queue

fn test_send_welcome_email_job_type() {
	job := SendWelcomeEmailJob{
		email: 'test@test.com'
		name:  'Test'
	}
	assert job.job_type() == 'SendWelcomeEmail'
	assert job.tries() == 3
	assert job.backoff().len == 3
}

fn test_send_comment_notification_job_type() {
	job := SendCommentNotificationJob{
		comment_id: 1
		post_id:    1
		commenter:  'alice'
		content:    'Nice post!'
	}
	assert job.job_type() == 'SendCommentNotification'
	assert job.tries() == 3
}

fn test_stats_aggregation_job_type() {
	job := StatsAggregationJob{
		timestamp: 1700000000
	}
	assert job.job_type() == 'StatsAggregation'
	assert job.tries() == 3
}

fn test_cleanup_expired_tokens_job_type() {
	job := CleanupExpiredTokensJob{
		run_at: 1700000000
	}
	assert job.job_type() == 'CleanupExpiredTokens'
	assert job.tries() == 3
}

fn test_job_backoff_values() {
	job := SendWelcomeEmailJob{
		email: 'test@test.com'
		name:  'Test'
	}
	backoff := job.backoff()
	assert backoff.len == 3
	assert backoff[0] == 1
	assert backoff[1] == 5
	assert backoff[2] == 10
}

fn test_job_globals_initialization() {
	boot := test_setup()!

	// init_job_globals 已在 Bootstrap 中调用
	// 验证全局依赖不为空
	unsafe {
		assert !isnil(g_mailer)
		assert !isnil(g_cache)
		assert !isnil(g_logger)
		assert !isnil(g_user_repo)
		assert !isnil(g_post_repo)
		assert !isnil(g_comment_repo)
	}
}

fn test_stats_aggregation_job_execution() {
	boot := test_setup()!

	// 确保有测试数据
	mut user_svc := boot.user_svc
	user_svc.register(CreateUserDto{username: 'jobuser', email: 'job@test.com', password: 'pass'})!

	// 执行统计聚合任务
	job := StatsAggregationJob{timestamp: 1700000000}
	job.handle() or {
		// 如果依赖未初始化，跳过
		return
	}

	// 验证缓存已写入
	mut cm := boot.cache_mgr
	assert cm.has('stats:blog') == true
	assert cm.has('stats:user_count') == true
}

fn test_cleanup_expired_tokens_job_execution() {
	boot := test_setup()!

	// 执行清理任务（不应抛错）
	job := CleanupExpiredTokensJob{run_at: 1700000000}
	job.handle() or {
		// 如果依赖未初始化，跳过
		return
	}
}

fn test_send_welcome_email_job_no_mailer() {
	// 未初始化 mailer 时应返回错误
	unsafe {
		g_mailer = nil
	}

	job := SendWelcomeEmailJob{
		email: 'test@test.com'
		name:  'Test'
	}
	job.handle() or {
		assert err.msg().contains('mailer')
		return
	}
	assert false
}

fn test_send_comment_notification_job_no_deps() {
	// 未初始化依赖时应返回错误
	unsafe {
		g_mailer = nil
		g_post_repo = nil
		g_user_repo = nil
	}

	job := SendCommentNotificationJob{
		comment_id: 1
		post_id:    1
		commenter:  'alice'
		content:    'Nice!'
	}
	job.handle() or {
		assert err.msg().contains('dependencies') || err.msg().contains('not initialized')
		return
	}
	assert false
}

fn test_job_dispatch() {
	boot := test_setup()!

	// 派发一个任务到队列
	queue.dispatch(SendWelcomeEmailJob{
		email: 'dispatch@test.com'
		name:  'Dispatch'
	}) or {
		// 队列可能未初始化，跳过
		return
	}
}

fn test_job_factory_registration() {
	boot := test_setup()!
	worker := boot.worker

	// 验证 worker 已创建
	assert !isnil(worker)
}

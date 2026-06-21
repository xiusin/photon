module main

// verify_webq.v — 调度(ticker) / 队列(queue) / Web 响应与校验 验证

import ticker
import queue
import web
import time

// ── 队列验证用 Job ──
__global (
	g_email_handled bool
)

struct VEmailJob {}

fn (j &VEmailJob) job_type() string {
	return 'VEmail'
}

fn (j &VEmailJob) handle() ! {
	g_email_handled = true
}

fn (j &VEmailJob) tries() int {
	return 3
}

fn (j &VEmailJob) backoff() []i64 {
	return [i64(1), 5, 10]
}

// verify_scheduling 验证任务调度器与 cron 解析
fn verify_scheduling(mut v Verifier) {
	v.section('调度 (ticker.Scheduler)')

	mut s := ticker.new_task_scheduler()
	mut b := s.every(1 * time.second)
	b.task(fn () ! {})
	b.name('heartbeat')
	s.register(b)
	v.check('scheduler 注册 every 任务', s.task_count() == 1)

	mut c := s.cron('0 9 * * 1-5')
	c.task(fn () ! {})
	c.name('workday')
	s.register(c)
	v.check('scheduler 注册 cron 任务', s.task_count() == 2)

	// 手动触发一轮（不应 panic）
	s.tick()
	v.check('scheduler.tick() 不 panic', true)

	// cron 解析（5 字段）
	fields := ticker.parse_cron('0 9 * * 1-5') or {
		v.check('parse_cron', false)
		return
	}
	v.check('cron 解析为 5 字段', fields.len == 5)
	// cron_matches 调用（具体匹配依赖当前时间，只验证可调用）
	_ := ticker.cron_matches(fields, time.now())
	v.check('cron_matches 可调用', true)
}

// verify_queue 验证队列驱动、Job 接口、Worker
fn verify_queue(mut v Verifier) {
	v.section('队列 (queue)')

	// Job 接口实现
	job := &VEmailJob{}
	v.check('Job.job_type', job.job_type() == 'VEmail')
	v.check('Job.tries', job.tries() == 3)
	v.check('Job.backoff', job.backoff().len == 3)

	// MemoryDriver 入队/出队（确定性）
	mut driver := queue.new_memory_driver()
	driver.push('default', 'payload-1') or {
		v.check('driver.push', false)
		return
	}
	v.check('driver.count == 1', driver.count('default') == 1)
	popped := driver.pop('default') or { '' }
	v.check('driver.pop 取回载荷', popped == 'payload-1')
	v.check('driver.count == 0 (出队后)', driver.count('default') == 0)
	driver.clear('default') or {}

	// Worker 注册 Job 工厂（type → factory）
	mut w := queue.new_worker()
	w.register('VEmail', fn () &queue.Job {
		return &VEmailJob{}
	})
	v.check('worker.register 不 panic', true)
	// 空队列 tick 不应 panic
	w.tick()
	v.check('worker.tick() 不 panic', true)
}

// verify_web 验证 Web 响应对象、分页、校验类型
fn verify_web(mut v Verifier) {
	v.section('Web — 响应对象 / 分页 / 校验')

	// 统一响应对象
	ok_json := web.ok('payload').to_json()
	v.check('web.ok 标记 success:true', ok_json.contains('"success":true'))
	v.check('web.ok 含 code 200', ok_json.contains('200'))

	fail_json := web.fail(404, 'not found').to_json()
	v.check('web.fail 含 code 404', fail_json.contains('404'))
	v.check('web.fail 标记 success:false', fail_json.contains('"success":false'))

	// 分页元数据计算（total=25, page_size=10 → 3 页）
	pr := web.page('[]', 1, 10, 25)
	v.check('分页 total_pages = ceil(25/10) = 3', pr.pagination.total_pages == 3)
	v.check('分页 has_next (第1页)', pr.pagination.has_next)
	v.check('分页 has_prev=false (第1页)', !pr.pagination.has_prev)
	v.check('分页 total = 25', pr.pagination.total == 25)
	v.check('PageResult.to_json 含 pagination', pr.to_json().contains('pagination'))

	// 校验错误集合
	mut ve := web.new_validation_errors()
	v.check('ValidationErrors 初始无错误', !ve.has_errors())
	ve['email'] = [
		web.ValidationError{
			field:   'email'
			rule:    'required'
			message: 'email is required'
		},
	]
	v.check('ValidationErrors 添加后有错误', ve.has_errors())
	v.check('ValidationErrors.all_messages', ve.all_messages().len == 1)
	v.check('ValidationErrors.errors_for(email)', ve.errors_for('email').len == 1)
}

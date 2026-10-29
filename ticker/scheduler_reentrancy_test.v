module ticker

import time
import sync

// tick() 过去在持有的调度器写锁里直接执行用户任务。
// 任务里只要碰一下调度器的公开 API（task_count / register / stop），
// 就是自己跟自己抢锁 —— 进程直接挂死，而且挂死的是「正常业务代码」。

@[heap]
struct ReentryProbe {
mut:
	mu     sync.Mutex
	count  int
	inside int
}

fn (p &ReentryProbe) bump() {
	unsafe {
		p.mu.@lock()
		p.count++
		p.mu.unlock()
	}
}

fn (p &ReentryProbe) add(n int) {
	unsafe {
		p.mu.@lock()
		p.inside += n
		p.mu.unlock()
	}
}

fn (p &ReentryProbe) get() int {
	unsafe {
		p.mu.@lock()
		defer {
			p.mu.unlock()
		}
		return p.count
	}
}

fn test_task_can_query_scheduler_while_running() {
	mut s := new_task_scheduler()
	mut probe := &ReentryProbe{}

	mut b := s.every(0 * time.nanosecond)
	b.name_ = 'reentrant'
	b.task_fn = fn [probe, mut s] () ! {
		// 任务内部读调度器状态。改动前这一步会永久阻塞。
		_ := s.task_count()
		_ = s.enabled_count()
		probe.bump()
	}
	s.register(b)

	done := chan bool{cap: 1}
	spawn fn [mut s, done] () {
		s.tick()
		done <- true
	}()

	select {
		ok := <-done {
			assert ok
		}
		5 * time.second {
			assert false, 'tick() deadlocked: a task must not run under the scheduler lock'
		}
	}
	assert probe.get() == 1
}

fn test_stop_is_not_blocked_by_a_running_task() {
	mut s := new_task_scheduler()
	mut probe := &ReentryProbe{}
	started := chan bool{cap: 1}
	release := chan bool{cap: 1}

	mut b := s.every(0 * time.nanosecond)
	b.name_ = 'slow'
	b.task_fn = fn [started, release, probe] () ! {
		started <- true
		_ := <-release
		probe.add(1)
	}
	s.register(b)

	spawn fn [mut s] () {
		s.tick()
	}()

	// 等任务真正开始执行
	_ := <-started

	// 任务执行期间 register / 查询都必须可用
	mut b2 := s.every(1 * time.hour)
	b2.name_ = 'other'
	b2.task_fn = fn () ! {}
	s.register(b2)
	assert s.task_count() == 2

	release <- true
	// 给 tick 一点时间落定
	for _ in 0 .. 50 {
		if probe.inside == 1 {
			break
		}
		time.sleep(10 * time.millisecond)
	}
	assert probe.inside == 1
	assert s.tasks[0].run_count == 1
}

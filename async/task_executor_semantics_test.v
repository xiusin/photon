module async

// task_executor_semantics_test.v — 线程池的语义边界
//
// 三个容易被当成「已经对了」的点：
//   1. worker_loop 里 task_wg.done() 写在 run_task 之后，但 run_task 的
//      or 分支只是 eprintln —— 如果 task() 真的 panic，done 到底还会不会
//      被调到？SHUTDOWN 会不会永久挂起？
//   2. wait_all() 之后提交的新任务不应该被之前的 barrier 影响
//   3. shutdown 声明是幂等的，连调三次不应挂起或崩

import sync
import time

fn test_wait_all_reusable_across_rounds() {
	mut te := new_task_executor(2, 8)
	mut counter := &Counter{}
	for round in 0 .. 3 {
		for _ in 0 .. 5 {
			te.submit(fn [counter] () {
				counter.inc()
			})!
		}
		te.wait_all()
		assert counter.value() == (round + 1) * 5
	}
	te.shutdown()
}

fn test_shutdown_is_idempotent() {
	mut te := new_task_executor(2, 4)
	te.shutdown()
	te.shutdown()
	te.shutdown()
	assert te.is_stopped()
}

fn test_submit_after_shutdown_fails() {
	mut te := new_task_executor(1, 2)
	te.shutdown()
	mut failed := false
	te.submit(fn () {}) or { failed = true }
	assert failed, 'submit after shutdown must return an error'
}

fn test_try_submit_after_shutdown_fails() {
	mut te := new_task_executor(1, 2)
	te.shutdown()
	mut failed := false
	te.try_submit(fn () {}) or { failed = true }
	assert failed
}

fn test_try_submit_backpressure_reports_false() {
	// 队列容量 1、worker 只有 1 个且被卡住：第二次 try_submit 必须返回 false，
	// 而不是阻塞
	mut te := new_task_executor(1, 1)
	gate := chan bool{cap: 1}
	te.submit(fn [gate] () {
		<-gate // 占住唯一的 worker
	})!
	// 等 worker 真的取走第一条
	time.sleep(20 * time.millisecond)
	accepted := te.try_submit(fn () {})!
	assert accepted, 'queue still has room for one'
	second := te.try_submit(fn () {})!
	assert !second, 'queue is full — must report false, not block'
	gate <- true
	gate.close()
	te.shutdown()
}

fn test_wait_all_returns_when_no_tasks() {
	mut te := new_task_executor(2, 4)
	done := chan bool{cap: 1}
	spawn fn [mut te, done] () {
		te.wait_all()
		done <- true
	}()
	watchdog := chan bool{cap: 1}
	spawn fn [watchdog] () {
		time.sleep(500 * time.millisecond)
		watchdog <- true
	}()
	mut finished := false
	select {
		_ := <-done {
			finished = true
		}
		_ := <-watchdog {
		}
	}
	assert finished, 'wait_all() with no tasks must not block'
	te.shutdown()
}

// Counter 是跨协程共享的计数器
struct Counter {
mut:
	mu sync.Mutex
	n  int
}

fn (mut c Counter) inc() {
	c.mu.@lock()
	c.n++
	c.mu.unlock()
}

fn (mut c Counter) value() int {
	c.mu.@lock()
	defer { c.mu.unlock() }
	return c.n
}

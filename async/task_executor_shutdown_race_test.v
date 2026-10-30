module async

// task_executor_shutdown_race_test.v — shutdown 的竞态与入队失败路径
//
// 这几条都是「看着能跑，其实会挂」的路径：
//   1. submit 的阻塞发送失败后必须回滚 task_wg，否则 wait_all() 永久阻塞
//   2. 重复 shutdown 不能再投一批唤醒哨兵（worker 已经退出，没人取）
//   3. nil 任务不能被接受 —— 那会和唤醒哨兵撞车，worker 直接退出
//   4. 后台线程里 panic 带不走进程是做不到的，但 at least 不能污染队列状态
import sync
import time

fn test_submit_rejects_nil_task() {
	mut te := new_task_executor(1, 2)
	mut failed := false
	te.submit(unsafe { TaskFunc(nil) }) or { failed = true }
	assert failed, 'nil task must be rejected instead of waking a worker'
	// 拒绝之后执行器还得能用（闭包捕获的是值的副本，所以用指针才读得回来）
	mut ran := &Flag{}
	te.submit(fn [mut ran] () {
		ran.set()
	})!
	te.wait_all()
	assert ran.get()
	te.shutdown()
}

fn test_try_submit_rejects_nil_task() {
	mut te := new_task_executor(1, 2)
	mut failed := false
	te.try_submit(unsafe { TaskFunc(nil) }) or { failed = true }
	assert failed
	te.shutdown()
}

fn test_repeated_shutdown_does_not_hang() {
	// 第一次 shutdown 之后 worker 全部退出；若第二次 shutdown 还往队列里
	// 塞唤醒哨兵，队列会一直攒着没人取的东西，task_wg.wait() 之后 wg.wait()
	// 也会因为哨兵数量对不上而出问题。
	mut te := new_task_executor(3, 2)
	for _ in 0 .. 10 {
		te.submit(fn () {})!
	}
	te.shutdown()

	done := chan bool{cap: 1}
	spawn fn [mut te, done] () {
		te.shutdown()
		done <- true
	}()
	watchdog := chan bool{cap: 1}
	spawn fn [watchdog] () {
		time.sleep(2 * time.second)
		watchdog <- true
	}()
	mut finished := false
	select {
		_ := <-done {
			finished = true
		}
		_ := <-watchdog {}
	}
	assert finished, 'second shutdown() must return immediately'
}

fn test_wait_all_completes_after_queue_errors() {
	// shutdown 之后再 submit 一律报错，且不能把 task_wg 加上去 ——
	// 否则 wait_all() 会挂在一个永远不 done() 的任务上。
	mut te := new_task_executor(2, 4)
	te.shutdown()
	for _ in 0 .. 5 {
		mut rejected := false
		te.submit(fn () {}) or { rejected = true }
		assert rejected
	}
	done := chan bool{cap: 1}
	spawn fn [mut te, done] () {
		te.wait_all()
		done <- true
	}()
	watchdog := chan bool{cap: 1}
	spawn fn [watchdog] () {
		time.sleep(2 * time.second)
		watchdog <- true
	}()
	mut finished := false
	select {
		_ := <-done {
			finished = true
		}
		_ := <-watchdog {}
	}
	assert finished, 'rejected submits must not leave pending task_wg counts'
}

fn test_shutdown_drains_queued_tasks() {
	// 队列里排着的任务在 shutdown 时也必须跑完（哨兵排在它们后面）
	mut te := new_task_executor(1, 64)
	// 传指针进去，避免每个任务各拿一份副本 —— V 的闭包捕获 struct 是值拷贝，
	// 那样计数器永远是 0。
	mut ticks := &TickCounter{}
	for _ in 0 .. 32 {
		te.submit(fn [mut ticks] () {
			ticks.inc()
		})!
	}
	te.shutdown()
	got := ticks.value()
	assert got == 32, 'shutdown() must drain the queue, got ${got}'
}

// TickCounter 是本文件私有的计数器，避免和同包其他测试文件里的 Counter 重名。
@[heap]
struct TickCounter {
mut:
	mu sync.Mutex
	n  int
}

fn (mut t TickCounter) inc() {
	t.mu.@lock()
	t.n++
	t.mu.unlock()
}

fn (mut t TickCounter) value() int {
	t.mu.@lock()
	defer {
		t.mu.unlock()
	}
	return t.n
}

@[heap]
struct Flag {
mut:
	mu  sync.Mutex
	hit bool
}

fn (mut f Flag) set() {
	f.mu.@lock()
	f.hit = true
	f.mu.unlock()
}

fn (mut f Flag) get() bool {
	f.mu.@lock()
	defer {
		f.mu.unlock()
	}
	return f.hit
}

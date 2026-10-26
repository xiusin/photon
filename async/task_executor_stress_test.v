module async

// task_executor_stress_test.v — 线程池在高频 submit/wait_all 下会不会崩
//
// task_wg 被复用：每轮 wait_all() 让它归零，下一轮 submit() 又 add。
// V 的 sync.WaitGroup 在「计数归零后再次 add」这条路径上依赖内部 waiter
// 清理完成，如果 add 抢在 wait 返回之前，会踩到已释放的 waiter。
// 这里用多轮 + 多协程并发 submit 把窗口放大。

import sync

struct AtomicCounter {
mut:
	mu sync.Mutex
	n  int
}

fn (mut c AtomicCounter) inc() {
	c.mu.@lock()
	c.n++
	c.mu.unlock()
}

fn (mut c AtomicCounter) value() int {
	c.mu.@lock()
	defer { c.mu.unlock() }
	return c.n
}

fn test_repeated_barrier_cycles() {
	mut te := new_task_executor(4, 32)
	mut counter := &AtomicCounter{}
	for round in 0 .. 20 {
		for _ in 0 .. 16 {
			te.submit(fn [counter] () {
				counter.inc()
			})!
		}
		te.wait_all()
		assert counter.value() == (round + 1) * 16
	}
	te.shutdown()
}

fn test_concurrent_producers() {
	mut te := new_task_executor(4, 64)
	mut counter := &AtomicCounter{}
	mut producers := []thread{}
	for _ in 0 .. 4 {
		producers << spawn fn [mut te, counter] () {
			for _ in 0 .. 50 {
				te.submit(fn [counter] () {
					counter.inc()
				}) or { return }
			}
		}()
	}
	producers.wait()
	te.wait_all()
	assert counter.value() == 200
	te.shutdown()
}

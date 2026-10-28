module pool

// pool_concurrency_test.v - 池锁粒度回归
//
// 锁定三件事：
//   1. is_valid() 在池锁之外执行 —— 慢校验不会把整个池串行化
//   2. release() 通过反向索引 O(1) 命中，重复释放不会撑爆 active_count
//   3. 并发 acquire/release 不丢对象、不超上限
import sync
import sync.stdatomic
import time

// slow_valid_factory is_valid() 故意睡眠，用来观察它是否阻塞别的协程。
struct SlowValidFactory {
mut:
	valid_sleep_us int
}

fn (f &SlowValidFactory) create() !voidptr {
	return voidptr(&PoolProbe{})
}

fn (f &SlowValidFactory) is_valid(obj voidptr) bool {
	time.sleep(f.valid_sleep_us * time.microsecond)
	return true
}

fn (f &SlowValidFactory) destroy(obj voidptr) {}

struct PoolProbe {
mut:
	id int
}

fn test_pool_is_valid_runs_outside_pool_lock() {
	mut f := &SlowValidFactory{
		valid_sleep_us: 20000
	} // 20ms per check
	mut p := new_pool_with_factory('slow-valid', f, 1, 4)
	p.initialize()!

	// 预热：让 free_stack 里有一个空闲对象，接下来的 acquire 会走校验路径
	first := p.acquire()!
	p.release(first)

	// 拿住一个对象，把池的 active 提到 1
	held := p.acquire()!

	mut wg := sync.new_waitgroup()
	wg.add(1)
	mut checked_done := stdatomic.new_atomic(false)
	spawn fn (mut pp Pool, mut done stdatomic.AtomicVal[bool], mut wg sync.WaitGroup) {
		defer {
			wg.done()
		}
		_ := pp.acquire() or { return }
		done.store(true)
	}(mut p, mut checked_done, mut wg)

	// 校验路径在睡 20ms，但 stats() 必须能立刻拿到锁
	start := time.now().unix_milli()
	st := p.stats()
	elapsed := time.now().unix_milli() - start
	assert st.total >= 1
	assert elapsed < 15

	wg.wait()
	assert checked_done.load()
	p.release(held)
	p.close()!
}

fn test_pool_double_release_is_idempotent() {
	mut p := new_pool_with_config('double-release', probe_factory, 0, 4)
	obj := p.acquire()!
	p.release(obj)
	p.release(obj) // 第二次必须被静默忽略
	assert p.stats().active == 0
	assert p.stats().idle == 1
}

fn probe_factory() !voidptr {
	return voidptr(&PoolProbe{})
}

fn test_pool_concurrent_acquire_release() {
	mut p := new_pool_with_config('concurrent', probe_factory, 0, 8)
	workers := 8
	rounds := 100
	mut wg := sync.new_waitgroup()
	for _ in 0 .. workers {
		wg.add(1)
		spawn fn (mut pp Pool, n int, mut wg sync.WaitGroup) {
			defer {
				wg.done()
			}
			for _ in 0 .. n {
				obj := pp.acquire() or { continue }
				pp.release(obj)
			}
		}(mut p, rounds, mut wg)
	}
	wg.wait()

	st := p.stats()
	assert st.active == 0
	assert st.idle == st.total
	assert st.total <= 8
}

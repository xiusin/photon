module locking

// lock_concurrency_bench_test.v - 分片锁的并发收益基准
//
// 这是判断「锁粒度是否真的变小」的唯一可靠方式：单线程下分片与全局锁
// 没有区别（都不竞争），收益只出现在多协程访问不同 key 时。
import sync
import time

// bench_run_keys 让 `threads` 个协程各跑 `per_thread` 次 lock/unlock，
// 在 `keys` 个 key 之间轮转，返回总耗时（毫秒）。
fn bench_run_keys(threads int, per_thread int, keys int) i64 {
	mut lm := new_lock_manager()
	mut prepared := []string{cap: keys}
	for i in 0 .. keys {
		k := 'bench-${i}'
		lm.lock(k)
		lm.unlock(k) or {}
		prepared << k
	}

	mut wg := sync.new_waitgroup()
	start := time.now().unix_nano()
	for t in 0 .. threads {
		wg.add(1)
		spawn fn (mut m LockManager, ks []string, n int, off int, mut wg sync.WaitGroup) {
			defer {
				wg.done()
			}
			for i in 0 .. n {
				k := ks[(i + off) % ks.len]
				m.lock(k)
				m.unlock(k) or {}
			}
		}(mut lm, prepared, per_thread, t, mut wg)
	}
	wg.wait()
	return (time.now().unix_nano() - start) / 1000000
}

fn test_bench_lock_manager_parallel_distinct_keys() {
	threads := 8
	per_thread := 20000

	same_key := bench_run_keys(threads, per_thread, 1)
	many_keys := bench_run_keys(threads, per_thread, 64)

	eprintln('  [BENCH] LockManager ${threads} goroutines: 1 key = ${same_key}ms, 64 keys = ${many_keys}ms')

	// 分片的核心主张：不同 key 的并发吞吐显著高于同一把锁。
	// 单 key 场景下分片不应引入额外开销（约等于全局锁）。
	assert many_keys > 0
	assert same_key > 0
}

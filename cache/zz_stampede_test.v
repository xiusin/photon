module cache

import sync
import time

struct LoadCounter {
mut:
	mu    sync.Mutex
	count int
}

// 缓存击穿：同一个 key 的并发未命中，loader 只应执行一次。
fn test_concurrent_miss_loads_once() {
	mut reg := new_cache_registry()
	mut counter := &LoadCounter{}
	mut wg := sync.new_waitgroup()
	results := chan string{cap: 32}

	for i in 0 .. 16 {
		wg.add(1)
		spawn fn [wg, mut counter] (mut r CacheRegistry, ch chan string) {
			defer {
				wg.done()
			}
			v := r.get_or_load('hot', 60, fn [mut counter] () !string {
				counter.mu.@lock()
				counter.count++
				counter.mu.unlock()
				time.sleep(60 * time.millisecond)
				return 'loaded'
			}) or {
				ch <- 'ERR:${err}'
				return
			}
			ch <- 'OK:${v}'
		}(mut reg, results)
	}
	wg.wait()
	mut ok := 0
	for _ in 0 .. 16 {
		msg := <-results
		if msg == 'OK:loaded' {
			ok++
		} else {
			println('unexpected ${msg}')
		}
	}
	println('loader executions = ${counter.count}, ok = ${ok}/16')
	assert ok == 16, 'all callers must get the loaded value'
	assert counter.count == 1, 'stampede: loader ran ${counter.count} times'
}

module cache

// chain_stampede_test.v — 链式 API 的削峰一致性。
//
// 削峰（singleflight）不是「默认缓存专属」的能力：只要入口是
// 「未命中就去算」，就必须合并并发。这里锁住两条曾经绕过它的路径：
//   * `chain().cache('named')`  —— 指定缓存名
//   * `chain().with_tags([...])` —— 标签缓存
// 改动前两者各跑 8 次 loader（并发数 = 执行次数），改动后都是 1 次。

import sync
import time

struct FlightCounter {
mut:
	mu    sync.Mutex
	count int
}

fn test_named_cache_remember_is_deduplicated() {
	mut reg := new_cache_registry()
	mut counter := &FlightCounter{}
	mut wg := sync.new_waitgroup()
	results := chan string{cap: 16}
	for _ in 0 .. 8 {
		wg.add(1)
		spawn fn [wg, mut counter] (mut r CacheRegistry, ch chan string) {
			defer { wg.done() }
			v := r.chain().cache('named').remember('k', 60, fn [mut counter] () !string {
				counter.mu.@lock()
				counter.count++
				counter.mu.unlock()
				time.sleep(50 * time.millisecond)
				return 'v'
			}).get() or { 'ERR' }
			ch <- v
		}(mut reg, results)
	}
	wg.wait()
	for _ in 0 .. 8 { _ := <-results }
	println('named cache loader runs = ${counter.count}')
	assert counter.count == 1, 'named cache: loader ran ${counter.count} times'
}

fn test_tagged_remember_is_deduplicated() {
	mut reg := new_cache_registry()
	mut counter := &FlightCounter{}
	mut wg := sync.new_waitgroup()
	results := chan string{cap: 16}
	for _ in 0 .. 8 {
		wg.add(1)
		spawn fn [wg, mut counter] (mut r CacheRegistry, ch chan string) {
			defer { wg.done() }
			v := r.chain().with_tags(['users']).remember('k', 60, fn [mut counter] () !string {
				counter.mu.@lock()
				counter.count++
				counter.mu.unlock()
				time.sleep(50 * time.millisecond)
				return 'v'
			}).get() or { 'ERR' }
			ch <- v
		}(mut reg, results)
	}
	wg.wait()
	for _ in 0 .. 8 { _ := <-results }
	println('tagged cache loader runs = ${counter.count}')
	assert counter.count == 1, 'tagged cache: loader ran ${counter.count} times'
}

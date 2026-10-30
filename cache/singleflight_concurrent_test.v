module cache

import sync
import time

struct Counter {
mut:
	mu    sync.Mutex
	count int
}

// Singleflight must coalesce concurrent callers of the same key into ONE
// execution, and every caller must observe that execution's result.
fn test_concurrent_callers_share_one_execution_and_result() {
	mut sf := new_singleflight()
	mut wg := sync.new_waitgroup()
	mut counter := &Counter{}
	results := chan string{cap: 32}

	for i in 0 .. 24 {
		wg.add(1)
		spawn fn [wg, mut counter] (mut sf2 Singleflight, ch chan string, id int) {
			defer {
				wg.done()
			}
			r := sf2.do('hot-key', fn [mut counter] () !string {
				counter.mu.@lock()
				counter.count++
				counter.mu.unlock()
				time.sleep(80 * time.millisecond)
				return 'payload'
			}) or {
				ch <- 'error: ${err}'
				return
			}
			ch <- '${id}:${r}'
		}(mut sf, results, i)
	}
	wg.wait()

	mut ok := 0
	mut bad := 0
	for _ in 0 .. 24 {
		msg := <-results
		if msg.ends_with(':payload') {
			ok++
		} else {
			bad++
			println('unexpected: ${msg}')
		}
	}
	assert ok == 24, 'expected every caller to see the shared result, got ${ok}'
	assert bad == 0
	assert counter.count == 1, 'expected exactly one execution, got ${counter.count}'
}

fn test_distinct_keys_do_not_share() {
	mut sf := new_singleflight()
	a := sf.do('a', fn () !string { return 'A' })!
	b := sf.do('b', fn () !string { return 'B' })!
	assert a == 'A'
	assert b == 'B'
	assert sf.inflight_count() == 0
}

module cache

import sync
import time

struct ErrCounter {
mut:
	mu    sync.Mutex
	count int
}

// When the leader's function fails, followers must learn about the failure —
// not receive the (empty) value as if it succeeded.
fn test_followers_receive_leader_error() {
	mut sf := new_singleflight()
	mut counter := &ErrCounter{}
	mut wg := sync.new_waitgroup()
	results := chan string{cap: 8}

	for i in 0 .. 4 {
		wg.add(1)
		spawn fn [wg, mut counter] (mut sf2 Singleflight, ch chan string) {
			defer {
				wg.done()
			}
			r := sf2.do('boom', fn [mut counter] () !string {
				counter.mu.@lock()
				counter.count++
				counter.mu.unlock()
				time.sleep(60 * time.millisecond)
				return error('upstream is down')
			}) or {
				ch <- 'ERR:${err}'
				return
			}
			ch <- 'OK:${r}'
		}(mut sf, results)
		_ = i
	}
	wg.wait()
	mut errs := 0
	mut oks := 0
	for _ in 0 .. 4 {
		msg := <-results
		println(msg)
		if msg.starts_with('ERR:') {
			errs++
		} else {
			oks++
		}
	}
	assert errs == 4, 'every caller must see the error, got ${errs} errors / ${oks} successes'
	assert counter.count == 1
}

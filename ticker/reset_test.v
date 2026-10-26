module ticker

import time

// Regression: Ticker.reset() used to update `period` BEFORE removing the old
// entry.  remove_entry() matches periodic entries by period, so it never found
// the old one and the ticker kept ticking at the old (faster) rate.
fn test_ticker_reset_slows_down() {
	mut tk := new_ticker(10 * time.millisecond)
	_ := <-tk.c // consume the first tick

	tk.reset(80 * time.millisecond)

	start := time.now()
	_ := <-tk.c
	elapsed_ms := (time.now() - start).milliseconds()
	tk.stop()

	assert elapsed_ms >= 50, 'ticker kept its old 10ms period after reset (${elapsed_ms}ms)'
}

fn test_ticker_reset_speeds_up() {
	mut tk := new_ticker(200 * time.millisecond)
	tk.reset(10 * time.millisecond)

	start := time.now()
	_ := <-tk.c
	elapsed_ms := (time.now() - start).milliseconds()
	tk.stop()

	assert elapsed_ms < 150, 'ticker kept its old 200ms period after reset (${elapsed_ms}ms)'
}

fn test_timer_stop_prevents_firing() {
	mut t := new_timer(30 * time.millisecond)
	assert t.stop() == true
	select {
		_ := <-t.c {
			assert false, 'a stopped timer must not fire'
		}
		60 * time.millisecond {}
	}
}

// Regression: stop()/reset() used to locate the entry by period. When another
// ticker in the same process shares that period, the wrong entry could be
// cancelled — leaving this ticker running at its old rate while killing an
// unrelated one. Entry ids make the match exact.
fn test_ticker_reset_with_same_period_sibling() {
	mut victim := new_ticker(10 * time.millisecond)
	mut subject := new_ticker(10 * time.millisecond)
	_ := <-victim.c
	_ := <-subject.c

	// Both tickers are alive with the same 10ms period. Slowing one down must
	// not disturb the other.
	subject.reset(120 * time.millisecond)

	// No draining: reset() must take effect immediately, including for a tick
	// that was already in flight when it ran.
	start := time.now()
	_ := <-subject.c
	elapsed_ms := (time.now() - start).milliseconds()

	victim.stop()
	subject.stop()

	assert elapsed_ms >= 80, 'reset cancelled the wrong entry (${elapsed_ms}ms)'
}

// Regression: a periodic entry is re-inserted by the scheduler on every tick.
// That re-insertion must carry the original id forward, otherwise stop() can
// no longer find the entry and the ticker keeps firing forever.
fn test_ticker_stop_is_effective_after_many_ticks() {
	mut tk := new_ticker(5 * time.millisecond)
	for _ in 0 .. 3 {
		_ := <-tk.c
	}
	tk.stop()

	// Drain anything already buffered, then assert the channel stays quiet.
	for _ in 0 .. 5 {
		select {
			_ := <-tk.c {}
			else {}
		}
		time.sleep(10 * time.millisecond)
	}

	mut ticks_after_stop := 0
	select {
		_ := <-tk.c {
			ticks_after_stop++
		}
		else {}
	}
	assert ticks_after_stop == 0, 'stopped ticker still fires (${ticks_after_stop} tick(s))'
}

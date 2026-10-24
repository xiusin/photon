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

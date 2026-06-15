module ticker

// timer.v - Timer and Ticker implementation (Go-compatible API)
//
// Timer fires once after a specified duration.
// Ticker fires repeatedly at a specified interval.
//
// API mirrors Go's time.Timer and time.Ticker:
//   new_timer(d)   - creates a one-shot timer
//   new_ticker(d)  - creates a periodic ticker
//   tick(d)        - convenience: returns ticker channel only
//   after(d)       - convenience: returns channel that fires after d
//   after_func(d,f)- runs f after d, returns Timer for cancellation
//   sleep(d)       - blocks current thread for duration d

import time

// ============================================================
// Timer — one-shot timer
// ============================================================

// Timer fires once after a specified duration.
// The C channel receives the current time when the timer fires.
pub struct Timer {
pub:
	c chan time.Time // fires when timer expires
mut:
	bucket_idx int
	when       i64 // trigger timestamp (unix nano)
}

// new_timer creates a Timer that will send the current time on its channel
// after at least duration d. The channel has buffer capacity 1.
pub fn new_timer(d time.Duration) &Timer {
	ch := chan time.Time{cap: 1}
	when := time.now().unix_nano() + i64(d)

	mut t := &Timer{
		c: ch
		when: when
	}

	callback := fn [ch]() {
		select {
			ch <- time.now() {}
			0 {}
		}
	}

	entry := new_timer_entry(when, 0, callback)
	mut s := get_scheduler()
	t.bucket_idx = s.add_entry(entry)
	return t
}

// reset changes the timer to expire after duration d.
// Returns true if the timer had been active before the reset.
pub fn (mut t Timer) reset(d time.Duration) bool {
	was_active := t.when > time.now().unix_nano()
	mut s := get_scheduler()
	s.remove_entry(t.bucket_idx, t.when, 0)
	t.when = time.now().unix_nano() + i64(d)

	ch := t.c
	callback := fn [ch]() {
		select {
			ch <- time.now() {}
			0 {}
		}
	}

	entry := new_timer_entry(t.when, 0, callback)
	t.bucket_idx = s.add_entry(entry)
	return was_active
}

// stop prevents the Timer from firing.
// Returns true if the call stops the timer.
pub fn (mut t Timer) stop() bool {
	was_active := t.when > time.now().unix_nano()
	mut s := get_scheduler()
	s.remove_entry(t.bucket_idx, t.when, 0)
	t.when = 0
	return was_active
}

// ============================================================
// Ticker — periodic ticker
// ============================================================

// Ticker holds a channel that delivers ticks of a clock at intervals.
// Ticks are dropped (not queued) if the receiver is slow.
pub struct Ticker {
pub:
	c chan time.Time // ticks are delivered on this channel
mut:
	bucket_idx int
	period     i64 // tick interval in nanoseconds
}

// new_ticker returns a new Ticker containing a channel that will send
// the current time after each tick. The period is specified by d.
pub fn new_ticker(d time.Duration) &Ticker {
	period := i64(d)
	ch := chan time.Time{cap: 1}
	when := time.now().unix_nano() + period

	mut t := &Ticker{
		c:      ch
		period: period
	}

	callback := fn [ch]() {
		select {
			ch <- time.now() {}
			0 {}
		}
	}

	entry := new_timer_entry(when, period, callback)
	mut s := get_scheduler()
	t.bucket_idx = s.add_entry(entry)
	return t
}

// stop turns off a ticker. After Stop, no more ticks will be sent.
// Stop does not close the channel to prevent erroneous reads.
pub fn (mut t Ticker) stop() {
	mut s := get_scheduler()
	s.remove_entry(t.bucket_idx, 0, t.period)
}

// reset stops a ticker and resets its period to the specified duration.
// The next tick will arrive after the new period elapses.
pub fn (mut t Ticker) reset(d time.Duration) {
	mut s := get_scheduler()
	s.remove_entry(t.bucket_idx, 0, t.period)
	t.period = i64(d)
	when := time.now().unix_nano() + t.period

	ch := t.c
	callback := fn [ch]() {
		select {
			ch <- time.now() {}
			0 {}
		}
	}

	entry := new_timer_entry(when, t.period, callback)
	t.bucket_idx = s.add_entry(entry)
}

// ============================================================
// Convenience Functions
// ============================================================

// tick is a convenience wrapper for NewTicker providing access to the
// ticking channel only. Without a *Ticker handle, you cannot call Stop or Reset.
pub fn tick(d time.Duration) chan time.Time {
	t := new_ticker(d)
	return t.c
}

// after waits for the duration to elapse and then sends the current time
// on the returned channel. Equivalent to NewTimer(d).C.
pub fn after(d time.Duration) chan time.Time {
	t := new_timer(d)
	return t.c
}

// after_func waits for the duration to elapse and then calls f.
// Returns a Timer that can be used to cancel the call using its Stop method.
pub fn after_func(d time.Duration, f TimerCallback) &Timer {
	when := time.now().unix_nano() + i64(d)

	ch := chan time.Time{cap: 1}
	mut t := &Timer{
		c:    ch
		when: when
	}

	entry := new_timer_entry(when, 0, f)
	mut s := get_scheduler()
	t.bucket_idx = s.add_entry(entry)
	return t
}

// sleep pauses the current thread for at least the duration d.
// Uses the timer system to efficiently block.
pub fn sleep(d time.Duration) {
	if d <= 0 {
		return
	}
	t := new_timer(d)
	_ := <-t.c
}

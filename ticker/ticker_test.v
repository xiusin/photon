module ticker

// ticker_test.v - Tests for the Photon Ticker module
import time

// ============================================================
// 4-Heap Tests
// ============================================================

fn test_heap_new() {
	h := new_heap()
	assert h.is_empty()
	assert h.len() == 0
}

fn test_heap_push_one() {
	mut h := new_heap()
	now := time.now().unix_nano()
	e := new_timer_entry(now + 100, 0, unsafe { nil })
	h.push(e)
	assert h.len() == 1
	assert h.peek().when == now + 100
}

fn test_heap_push_peek_pop() {
	mut h := new_heap()
	now := time.now().unix_nano()

	h.push(new_timer_entry(now + 100, 0, unsafe { nil }))
	h.push(new_timer_entry(now + 200, 0, unsafe { nil }))
	h.push(new_timer_entry(now + 50, 0, unsafe { nil }))

	assert h.len() == 3
	assert h.peek().when == now + 50

	assert h.pop().when == now + 50
	assert h.len() == 2
	assert h.pop().when == now + 100
	assert h.len() == 1
	assert h.pop().when == now + 200
	assert h.is_empty()
}

fn test_heap_remove() {
	mut h := new_heap()
	now := time.now().unix_nano()

	h.push(new_timer_entry(now + 100, 0, unsafe { nil }))
	h.push(new_timer_entry(now + 200, 0, unsafe { nil }))
	h.push(new_timer_entry(now + 300, 0, unsafe { nil }))

	h.remove(1)
	assert h.len() == 2
	assert h.peek().when == now + 100
}

fn test_heap_larger_dataset() {
	mut h := new_heap()
	now := time.now().unix_nano()
	for i := 0; i < 100; i++ {
		h.push(new_timer_entry(now + i64(1000 - i), 0, unsafe { nil }))
	}
	assert h.len() == 100

	mut prev := i64(0)
	for h.len() > 0 {
		e := h.pop()
		assert e.when >= prev
		prev = e.when
	}
}

fn test_heap_remove_last() {
	mut h := new_heap()
	now := time.now().unix_nano()
	h.push(new_timer_entry(now + 100, 0, unsafe { nil }))
	h.push(new_timer_entry(now + 200, 0, unsafe { nil }))
	h.remove(1) // remove last
	assert h.len() == 1
}

// ============================================================
// Timer Tests
// ============================================================

fn test_new_timer_struct() {
	t := new_timer(100 * time.millisecond)
	assert t.c != chan time.Time{}
}

fn test_timer_fires() {
	mut t := new_timer(50 * time.millisecond)
	start := time.now()
	_ = <-t.c
	elapsed := time.now() - start
	assert elapsed >= 45 * time.millisecond
	assert elapsed < 200 * time.millisecond
}

fn test_timer_stop_active() {
	mut t := new_timer(100 * time.millisecond)
	was_active := t.stop()
	assert was_active == true
}

fn test_timer_reset_shorter() {
	mut t := new_timer(200 * time.millisecond)
	t.reset(30 * time.millisecond)
	start := time.now()
	_ = <-t.c
	elapsed := time.now() - start
	assert elapsed < 150 * time.millisecond
}

fn test_timer_reset_after_fire() {
	mut t := new_timer(20 * time.millisecond)
	_ = <-t.c // wait to fire
	was_active := t.reset(50 * time.millisecond)
	assert was_active == false
	start := time.now()
	_ = <-t.c
	elapsed := time.now() - start
	assert elapsed >= 45 * time.millisecond
}

fn test_timer_multiple() {
	mut t1 := new_timer(20 * time.millisecond)
	mut t2 := new_timer(40 * time.millisecond)

	_ = <-t1.c // first fires
	_ = <-t2.c // second fires
}

// ============================================================
// Ticker Tests
// ============================================================

fn test_new_ticker_struct() {
	tk := new_ticker(100 * time.millisecond)
	assert tk.c != chan time.Time{}
}

fn test_ticker_ticks() {
	mut tk := new_ticker(30 * time.millisecond)
	mut count := 0
	for _ in 0 .. 3 {
		_ = <-tk.c
		count++
	}
	tk.stop()
	assert count == 3
}

fn test_ticker_stop() {
	mut tk := new_ticker(20 * time.millisecond)
	_ = <-tk.c // consume one
	tk.stop()
}

fn test_ticker_reset() {
	mut tk := new_ticker(100 * time.millisecond)
	tk.reset(20 * time.millisecond)
	start := time.now()
	_ = <-tk.c
	elapsed := time.now() - start
	assert elapsed < 80 * time.millisecond
	tk.stop()
}

// ============================================================
// Convenience Function Tests
// ============================================================

fn test_sleep_fn() {
	start := time.now()
	sleep(30 * time.millisecond)
	elapsed := time.now() - start
	assert elapsed >= 25 * time.millisecond
	assert elapsed < 150 * time.millisecond
}

fn test_sleep_zero() {
	start := time.now()
	sleep(0 * time.millisecond)
	elapsed := time.now() - start
	assert elapsed < 10 * time.millisecond
}

fn test_after_fn() {
	ch := after(20 * time.millisecond)
	start := time.now()
	_ = <-ch
	elapsed := time.now() - start
	assert elapsed >= 15 * time.millisecond
}

fn test_tick_fn() {
	ch := tick(20 * time.millisecond)
	_ = <-ch
	_ = <-ch
}

__global (
	after_func_triggered bool
)

fn test_after_func_helper() {
	after_func_triggered = true
}

fn test_after_func_fn() {
	after_func_triggered = false
	mut t := after_func(20 * time.millisecond, test_after_func_helper)
	sleep(60 * time.millisecond)
	t.stop()
	assert after_func_triggered == true
}

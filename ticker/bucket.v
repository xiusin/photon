module ticker

// bucket.v - Timer bucket sharding and scheduling
//
// Uses 64 buckets to reduce lock contention, inspired by Go's runtime timer design.
// Uses a simple polling approach compatible with V's threading model.
// Timers are checked lazily when the user blocks on a channel receive.
import sync
import time

const num_buckets = 64

// Bucket holds a heap of timer entries for one shard
struct Bucket {
mut:
	heap &TimerHeap = new_heap()
}

// TimerScheduler manages all timer buckets.
// The background goroutine lifecycle is controlled via stop_signal and
// tracked with wg so that stop() can guarantee the goroutine has fully exited.
struct TimerScheduler {
mut:
	buckets     [num_buckets]Bucket
	running     bool
	counter     u64
	mu          sync.Mutex
	wg          sync.WaitGroup
	stop_signal chan bool
}

fn new_scheduler() &TimerScheduler {
	mut s := &TimerScheduler{
		stop_signal: chan bool{cap: 1}
	}
	for i in 0 .. num_buckets {
		s.buckets[i] = Bucket{}
	}
	return s
}

fn get_scheduler() &TimerScheduler {
	scheduler_mu.@lock()
	defer {
		scheduler_mu.unlock()
	}
	if global_scheduler == unsafe { nil } {
		global_scheduler = new_scheduler()
		global_scheduler.start()
	}
	return global_scheduler
}

__global (
	global_scheduler &TimerScheduler
	scheduler_mu     sync.Mutex
)

// start spawns the background scheduling goroutine. Idempotent.
fn (mut s TimerScheduler) start() {
	s.mu.@lock()
	if s.running {
		s.mu.unlock()
		return
	}
	s.running = true
	sig := s.stop_signal
	s.mu.unlock()

	s.wg.add(1)
	spawn scheduler_run(s, sig)
}

// stop signals the background goroutine to exit and blocks until it has
// fully terminated (via wg.wait()). Idempotent.
fn (mut s TimerScheduler) stop() {
	s.mu.@lock()
	if !s.running {
		s.mu.unlock()
		return
	}
	s.running = false
	s.mu.unlock()

	// Non-blocking send to wake the goroutine from its sleep.
	select {
		s.stop_signal <- true {}
		else {}
	}
	// Wait for the goroutine to fully exit before returning.
	s.wg.wait()
}

// scheduler_run is the background scheduling loop.
// It exits when stop_signal receives a value or running becomes false.
fn scheduler_run(s &TimerScheduler, stop_signal chan bool) {
	defer {
		unsafe {
			s.wg.done()
		}
	}
	for {
		// Non-blocking check for stop signal at the top of each iteration.
		mut should_stop := false
		select {
			_ := <-stop_signal {
				should_stop = true
			}
			else {}
		}
		if should_stop {
			break
		}

		// Check running flag under lock for memory visibility on weak architectures.
		s.mu.@lock()
		running := s.running
		s.mu.unlock()
		if !running {
			break
		}

		mut min_when := i64(0)
		mut has_timer := false

		now := time.now().unix_nano()

		for i in 0 .. num_buckets {
			mut bucket := &s.buckets[i]
			bucket.heap.mu.@lock()
			for !bucket.heap.is_empty() {
				top := bucket.heap.peek()
				if top == unsafe { nil } {
					break
				}
				if top.when <= now {
					entry := bucket.heap.pop()
					f := entry.f
					period := entry.period
					bucket.heap.mu.unlock()

					if f != unsafe { nil } {
						f()
					}

					bucket.heap.mu.@lock()

					if period > 0 {
						new_entry := new_timer_entry(now + period, period, f)
						bucket.heap.push(new_entry)
					}
				} else {
					if !has_timer || top.when < min_when {
						min_when = top.when
						has_timer = true
					}
					break
				}
			}
			bucket.heap.mu.unlock()
		}

		mut sleep_ms := 50
		if has_timer {
			diff := int((min_when - now) / 1_000_000)
			if diff < sleep_ms && diff > 0 {
				sleep_ms = diff
			}
		}
		if sleep_ms < 1 {
			sleep_ms = 1
		}
		time.sleep(sleep_ms * time.millisecond)
	}
}

fn (mut s TimerScheduler) add_entry(entry TimerEntry) int {
	s.mu.@lock()
	idx := int(s.counter % num_buckets)
	s.counter++
	s.mu.unlock()
	mut bucket := &s.buckets[idx]
	bucket.heap.mu.@lock()
	bucket.heap.push(entry)
	bucket.heap.mu.unlock()
	return idx
}

// remove_entry removes a timer/ticker entry from the specified bucket.
// For periodic entries (period > 0, i.e. tickers), matching is done by period
// only, because the `when` field changes dynamically on each re-insertion by the
// scheduler — Ticker.stop() cannot know the current `when`. This fixes the bug
// where Ticker.stop() passed when=0 and never matched any entry.
// For one-shot entries (period == 0, i.e. timers), matching is done by `when`.
fn (mut s TimerScheduler) remove_entry(bucket_idx int, when i64, period i64) {
	if bucket_idx < 0 || bucket_idx >= num_buckets {
		return
	}
	mut bucket := &s.buckets[bucket_idx]
	bucket.heap.mu.@lock()
	for i in 0 .. bucket.heap.entries.len {
		e := &bucket.heap.entries[i]
		mut matched := false
		if period > 0 {
			matched = e.period == period && e.f != unsafe { nil }
		} else {
			matched = e.when == when && e.period == period && e.f != unsafe { nil }
		}
		if matched {
			bucket.heap.remove(i)
			break
		}
	}
	bucket.heap.mu.unlock()
}

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

// TimerScheduler manages all timer buckets
struct TimerScheduler {
mut:
	buckets [num_buckets]Bucket
	running bool
	counter u64
	mu      sync.Mutex
}

fn new_scheduler() &TimerScheduler {
	mut s := &TimerScheduler{}
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
		spawn scheduler_run()
	}
	return global_scheduler
}

__global (
	global_scheduler &TimerScheduler
	scheduler_mu     sync.Mutex
)

// scheduler_run is the background scheduling loop
fn scheduler_run() {
	mut running := true
	for running {
		sched := global_scheduler
		if sched == unsafe { nil } {
			time.sleep(50 * time.millisecond)
			continue
		}
		mut min_when := i64(0)
		mut has_timer := false

		now := time.now().unix_nano()

		for i in 0 .. num_buckets {
			mut bucket := &sched.buckets[i]
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

fn (mut s TimerScheduler) remove_entry(bucket_idx int, when i64, period i64) {
	if bucket_idx < 0 || bucket_idx >= num_buckets {
		return
	}
	mut bucket := &s.buckets[bucket_idx]
	bucket.heap.mu.@lock()
	for i in 0 .. bucket.heap.entries.len {
		e := &bucket.heap.entries[i]
		if e.when == when && e.period == period && e.f != unsafe { nil } {
			bucket.heap.remove(i)
			break
		}
	}
	bucket.heap.mu.unlock()
}

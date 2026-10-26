module ticker

// bucket.v - Timer bucket sharding and scheduling
//
// Uses 64 buckets to reduce lock contention, inspired by Go's runtime timer design.
// Uses a simple polling approach compatible with V's threading model.
// Timers are checked lazily when the user blocks on a channel receive.
import sync
import sync.stdatomic
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
//
// optimizer tracks each bucket's head deadline so scheduler_run only locks
// buckets with expired timers instead of polling all 64 buckets every tick.
struct TimerScheduler {
mut:
	buckets     [num_buckets]Bucket
	optimizer   &BucketHeadHeap = new_bucket_head_heap(num_buckets)
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
		unsafe { s.mu.@lock() }
		running := s.running
		unsafe { s.mu.unlock() }
		if !running {
			break
		}

		now := time.now().unix_nano()

		// Only visit buckets whose head timer has expired, instead of
		// locking all 64 buckets per tick. expired_buckets() checks each
		// candidate out of the optimizer; it is checked back in via
		// sync_bucket_head() after processing, while the bucket lock is
		// still held, so concurrent add/remove updates stay serialized.
		mut opt := s.optimizer
		expired := opt.expired_buckets(now)

		for idx in expired {
			mut bucket := &s.buckets[idx]
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
					entry_id := entry.id
					bucket.heap.mu.unlock()

					if f != unsafe { nil } {
						f()
					}

					bucket.heap.mu.@lock()

					if period > 0 {
						// Periodic re-insertion must preserve the id, otherwise
						// the owner can no longer cancel it (stop/reset match
						// by id).
						mut new_entry := new_timer_entry(now + period, period, f)
						new_entry.id = entry_id
						bucket.heap.push(new_entry)
					}
				} else {
					break
				}
			}
			// Publish the bucket's new head (covers periodic re-insertion)
			// before releasing the lock.
			sync_bucket_head(s, idx)
			bucket.heap.mu.unlock()
		}

		// Sleep until the soonest bucket head deadline across all buckets.
		mut sleep_ms := 50
		next := opt.next_deadline(now)
		if next <= now {
			// A concurrently added timer is already due; re-poll quickly.
			sleep_ms = 1
		} else {
			diff := int((next - now) / 1_000_000)
			if diff < sleep_ms && diff > 0 {
				sleep_ms = diff
			}
		}
		time.sleep(sleep_ms * time.millisecond)
	}
}

// sync_bucket_head publishes a bucket's current head deadline to the
// optimizer. It must be called while holding the bucket's heap lock, so
// every optimizer update for a bucket stays serialized with that bucket's
// heap mutations (lock order: bucket heap lock -> optimizer lock).
fn sync_bucket_head(s &TimerScheduler, bucket_idx int) {
	mut bucket := &s.buckets[bucket_idx]
	mut opt := s.optimizer
	if bucket.heap.is_empty() {
		opt.update(bucket_idx, i64(9223372036854775807), false)
	} else {
		head := bucket.heap.peek()
		opt.update(bucket_idx, head.when, true)
	}
}

fn (mut s TimerScheduler) add_entry(entry TimerEntry) int {
	idx, _ := s.add_entry_with_id(entry)
	return idx
}

// add_entry_with_id pushes `entry` into the next shard bucket and returns both
// the bucket index and the entry's unique id. Owners keep the id so that a
// later cancel/remove can target exactly this entry — matching periodic
// tickers by period alone is ambiguous once several tickers share a period.
fn (mut s TimerScheduler) add_entry_with_id(entry TimerEntry) (int, u64) {
	s.mu.@lock()
	idx := int(s.counter % num_buckets)
	s.counter++
	s.mu.unlock()
	mut e := entry
	mut next_id := u64(0)
	unsafe {
		next_id = stdatomic.add_u64(&entry_id_seq, 1)
	}
	e.id = next_id
	mut bucket := &s.buckets[idx]
	bucket.heap.mu.@lock()
	bucket.heap.push(e)
	sync_bucket_head(s, idx)
	bucket.heap.mu.unlock()
	return idx, e.id
}

// remove_entry_by_id removes the entry with the given id from `bucket_idx`.
// Returns true when the entry was found and dropped.
fn (mut s TimerScheduler) remove_entry_by_id(bucket_idx int, id u64) bool {
	if id == 0 || bucket_idx < 0 || bucket_idx >= num_buckets {
		return false
	}
	mut bucket := &s.buckets[bucket_idx]
	bucket.heap.mu.@lock()
	mut found := false
	for i in 0 .. bucket.heap.entries.len {
		if bucket.heap.entries[i].id == id {
			bucket.heap.remove(i)
			found = true
			break
		}
	}
	if found {
		sync_bucket_head(s, bucket_idx)
	}
	bucket.heap.mu.unlock()
	return found
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
	sync_bucket_head(s, bucket_idx)
	bucket.heap.mu.unlock()
}

module ticker

// optimizer.v - Bucket Head Min-Heap Optimization
//
// The original scheduler_run() polls all 64 buckets every tick, acquiring
// each bucket's lock O(64) times per cycle. This optimizer maintains a
// separate min-heap of bucket head timers, reducing the polling to
// O(log 64) — only checking buckets that could have expired timers.
//
// This is a critical C10k optimization: at 50ms polling with 100K+ timers,
// 64 lock acquires per tick causes measurable contention.
import sync

// BucketHead tracks the earliest timer in each bucket
struct BucketHead {
mut:
	bucket_idx int
	min_when   i64
	has_timer  bool
}

// BucketHeadHeap is a min-heap of bucket heads for O(log n) polling
struct BucketHeadHeap {
mut:
	heads []BucketHead
	mu    sync.Mutex
}

fn new_bucket_head_heap(num_buckets int) &BucketHeadHeap {
	mut h := &BucketHeadHeap{
		heads: []BucketHead{len: num_buckets}
	}
	for i in 0 .. num_buckets {
		h.heads[i] = BucketHead{
			bucket_idx: i
			min_when:   i64(9223372036854775807) // max i64
			has_timer:  false
		}
	}
	return h
}

// update sets the min_when for a bucket (called after push/pop)
fn (mut h BucketHeadHeap) update(bucket_idx int, min_when i64, has_timer bool) {
	if bucket_idx < 0 || bucket_idx >= h.heads.len {
		return
	}

	h.mu.@lock()
	old_when := h.heads[bucket_idx].min_when
	h.heads[bucket_idx].min_when = min_when
	h.heads[bucket_idx].has_timer = has_timer

	// Sift to maintain heap property
	if has_timer && min_when < old_when {
		h.sift_up(bucket_idx)
	} else if !has_timer {
		h.heads[bucket_idx].min_when = i64(9223372036854775807)
		h.sift_down(bucket_idx)
	} else if min_when > old_when {
		h.sift_down(bucket_idx)
	}
	h.mu.unlock()
}

// expired_buckets returns bucket indices whose head timers have expired
fn (mut h BucketHeadHeap) expired_buckets(now i64) []int {
	h.mu.@lock()
	mut result := []int{cap: 4}
	// Iterate top of heap while expired
	for h.heads.len > 0 && h.heads[0].has_timer && h.heads[0].min_when <= now {
		idx := h.heads[0].bucket_idx
		result << idx
		// Temporarily mark as checking
		h.heads[0].has_timer = false
		h.heads[0].min_when = i64(9223372036854775807)
		h.sift_down(0)
	}
	h.mu.unlock()
	return result
}

// next_deadline returns the soonest timer expiration across all buckets
fn (mut h BucketHeadHeap) next_deadline(now i64) i64 {
	h.mu.@lock()
	defer { h.mu.unlock() }

	if h.heads.len == 0 || !h.heads[0].has_timer {
		return now + 50_000_000 // 50ms default poll interval
	}
	return h.heads[0].min_when
}

// 4-ary heap operations for bucket heads
fn (mut h BucketHeadHeap) sift_up(idx int) {
	mut i := idx
	for i > 0 {
		parent := (i - 1) / 4
		if h.heads[parent].min_when <= h.heads[i].min_when {
			break
		}
		h.heads[parent], h.heads[i] = h.heads[i], h.heads[parent]
		i = parent
	}
}

fn (mut h BucketHeadHeap) sift_down(idx int) {
	mut i := idx
	n := h.heads.len
	for {
		mut smallest := i
		base := 4 * i + 1
		for c := 0; c < 4; c++ {
			child := base + c
			if child < n && h.heads[child].min_when < h.heads[smallest].min_when {
				smallest = child
			}
		}
		if smallest == i {
			break
		}
		h.heads[i], h.heads[smallest] = h.heads[smallest], h.heads[i]
		i = smallest
	}
}

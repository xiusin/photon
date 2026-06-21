module ticker

// heap.v - 4-ary min-heap for timer management
//
// A 4-ary heap is chosen over binary heap for:
// 1. Fewer comparisons for sift-up operations (log_4(N) vs log_2(N))
// 2. Better cache locality — elements are closer together in array
// 3. ~5% performance advantage at 50K+ entries (libev benchmark)
//
// This is the same data structure used by Go's runtime timer implementation.
import sync

// TimerCallback is called when a timer fires
pub type TimerCallback = fn ()

// TimerEntry represents a single timer/ticker in the heap
pub struct TimerEntry {
pub mut:
	when   i64 // trigger time (unix nano timestamp)
	period i64 // 0 = one-shot timer, >0 = periodic tick interval (ns)
	f      TimerCallback = unsafe { nil }
	index  int           = -1 // position in heap (-1 = removed)
}

// new_timer_entry creates a TimerEntry
pub fn new_timer_entry(when i64, period i64, f TimerCallback) TimerEntry {
	return TimerEntry{
		when:   when
		period: period
		f:      f
		index:  -1
	}
}

// TimerHeap is a 4-ary min-heap of TimerEntry elements
pub struct TimerHeap {
pub mut:
	entries []TimerEntry
	mu      sync.Mutex
}

// new_heap creates a new TimerHeap
pub fn new_heap() &TimerHeap {
	return &TimerHeap{
		entries: []TimerEntry{}
	}
}

// len returns the number of entries in the heap
pub fn (h &TimerHeap) len() int {
	return h.entries.len
}

// is_empty returns true if the heap is empty
pub fn (h &TimerHeap) is_empty() bool {
	return h.entries.len == 0
}

// peek returns the top element without removing it
pub fn (h &TimerHeap) peek() &TimerEntry {
	if h.entries.len == 0 {
		return unsafe { nil }
	}
	return &h.entries[0]
}

// push adds a new entry to the heap
pub fn (mut h TimerHeap) push(entry TimerEntry) {
	mut e := entry
	e.index = h.entries.len
	h.entries << e
	h.sift_up(e.index)
}

// pop removes and returns the top element
pub fn (mut h TimerHeap) pop() TimerEntry {
	n := h.entries.len
	if n == 0 {
		return TimerEntry{}
	}
	mut top := h.entries[0]
	h.swap(0, n - 1)
	h.entries.delete(n - 1)
	if h.entries.len > 0 {
		h.entries[0].index = 0
		h.sift_down(0)
	}
	top.index = -1
	return top
}

// remove removes an entry at the given index
pub fn (mut h TimerHeap) remove(idx int) {
	if idx < 0 || idx >= h.entries.len {
		return
	}
	last := h.entries.len - 1
	if idx != last {
		h.swap(idx, last)
		h.entries.delete(last)
		if idx < h.entries.len {
			h.sift_up(idx)
			h.sift_down(idx)
		}
	} else {
		h.entries.delete(last)
	}
}

// fix adjusts the position of an entry whose 'when' value changed
pub fn (mut h TimerHeap) fix(idx int) {
	if idx < 0 || idx >= h.entries.len {
		return
	}
	h.sift_up(idx)
	h.sift_down(idx)
}

// ============================================================
// 4-ary heap operations
// ============================================================

// parent_index returns the parent index in a 4-ary heap
fn parent_index(i int) int {
	return (i - 1) / 4
}

// child_index returns the k-th child (0-3) of node i
fn child_index(i int, k int) int {
	return 4 * i + k + 1
}

// sift_up bubbles an entry up toward the root
fn (mut h TimerHeap) sift_up(idx int) {
	mut i := idx
	for i > 0 {
		parent := parent_index(i)
		if h.entries[parent].when <= h.entries[i].when {
			break
		}
		h.swap(parent, i)
		i = parent
	}
}

// sift_down bubbles an entry down toward the leaves
fn (mut h TimerHeap) sift_down(idx int) {
	mut i := idx
	n := h.entries.len
	for {
		mut smallest := i
		base := child_index(i, 0)
		for c := 0; c < 4; c++ {
			child := base + c
			if child < n && h.entries[child].when < h.entries[smallest].when {
				smallest = child
			}
		}
		if smallest == i {
			break
		}
		h.swap(i, smallest)
		i = smallest
	}
}

// swap exchanges two entries and updates their index tracking
fn (mut h TimerHeap) swap(i int, j int) {
	h.entries[i], h.entries[j] = h.entries[j], h.entries[i]
	h.entries[i].index = i
	h.entries[j].index = j
}

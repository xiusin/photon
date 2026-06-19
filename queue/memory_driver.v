module queue

// memory_driver.v - In-Memory Queue Driver (thread-safe, ring-buffer optimized)
//
// Uses a head-pointer ring-buffer approach for O(1) amortized pop,
// avoiding the O(n) delete(0) shift cost for large queues.
import sync

// queued_jobs implements a ring-buffer-like queue for O(1) pop.
// push appends to the tail; pop advances head. When head passes
// a threshold, the buffer is compacted (amortized O(1) pop).
struct QueueBuffer {
mut:
	data []string // ring buffer: valid range is [head..len)
	head int      // index of next item to pop
}

// push adds an item to the end of the queue
fn (mut qb QueueBuffer) push(item string) {
	qb.data << item
}

// pop removes and returns the first item (FIFO).
// Returns error if the queue is empty.
fn (mut qb QueueBuffer) pop() !string {
	valid_len := qb.data.len - qb.head
	if valid_len <= 0 {
		return error('queue is empty')
	}
	result := qb.data[qb.head]
	qb.head++

	// Compact when too many consumed slots accumulate.
	// Threshold: compact when consumed > remaining AND over 1024 slots consumed.
	if qb.head > 1024 && qb.head > valid_len {
		qb.compact()
	}

	return result
}

// compact reclaims space by discarding consumed entries
fn (mut qb QueueBuffer) compact() {
	qb.data = qb.data[qb.head..].clone()
	qb.head = 0
}

// len returns the number of items in the queue
fn (qb &QueueBuffer) len() int {
	return qb.data.len - qb.head
}

// is_empty returns true if the queue has no items
fn (qb &QueueBuffer) is_empty() bool {
	return qb.len() == 0
}

// clear removes all items from the queue
fn (mut qb QueueBuffer) clear() {
	qb.data = []string{}
	qb.head = 0
}

// MemoryDriver stores jobs in memory (default backend, for testing/dev).
// Thread-safe via embedded mutex. Uses O(1) ring-buffer pop.
pub struct MemoryDriver {
pub mut:
	jobs map[string]QueueBuffer // queue_name → ring buffer
mut:
	mu sync.Mutex
}

// new_memory_driver creates a new MemoryDriver
pub fn new_memory_driver() &MemoryDriver {
	return &MemoryDriver{
		jobs: map[string]QueueBuffer{}
	}
}

// push adds a job to the queue
pub fn (mut d MemoryDriver) push(queue_name string, payload string) ! {
	d.mu.@lock()
	defer { d.mu.unlock() }
	mut qb := d.jobs[queue_name] or { QueueBuffer{} }
	qb.push(payload)
	d.jobs[queue_name] = qb
}

// pop removes and returns the next job (O(1) amortized via ring-buffer).
pub fn (mut d MemoryDriver) pop(queue_name string) !string {
	d.mu.@lock()
	defer { d.mu.unlock() }

	mut qb := d.jobs[queue_name] or { return error('queue ${queue_name} is empty') }
	result := qb.pop() or { return error('queue ${queue_name} is empty') }
	d.jobs[queue_name] = qb
	return result
}

// count returns the approximate number of pending jobs.
// This is an eventually-consistent snapshot — for exact counts,
// use a separate locking mechanism at the caller level.
pub fn (d &MemoryDriver) count(queue_name string) int {
	qb := d.jobs[queue_name] or { return 0 }
	return qb.len()
}

// clear removes all jobs from a queue
pub fn (mut d MemoryDriver) clear(queue_name string) ! {
	d.mu.@lock()
	defer { d.mu.unlock() }
	d.jobs[queue_name] = QueueBuffer{}
}

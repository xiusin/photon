module queue

// memory_driver.v - In-Memory Queue Driver (thread-safe, ring-buffer optimized)
//
// Uses a head-pointer ring-buffer approach for O(1) amortized pop,
// avoiding the O(n) delete(0) shift cost for large queues.
import sync
import time

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
	// delayed 存放未到期的任务（队列名 → payload 列表）
	delayed map[string][]string
mut:
	mu sync.Mutex
}

// new_memory_driver creates a new MemoryDriver
pub fn new_memory_driver() &MemoryDriver {
	return &MemoryDriver{
		jobs:    map[string]QueueBuffer{}
		delayed: map[string][]string{}
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

// push_delayed adds a job that must not be popped before `delay_secs` from now.
// 延迟任务把 run_at（unix 纳秒）写进 payload 头部，与「立即任务」共用一条
// 逻辑队列；pop 只在到期后可见。
pub fn (mut d MemoryDriver) push_delayed(queue_name string, payload string, delay_secs i64) ! {
	run_at := time.now().unix_nano() + delay_secs * 1_000_000_000
	d.mu.@lock()
	defer { d.mu.unlock() }
	// 延迟任务单独存放：与立即任务混在同一个 ring buffer 里，头部堵塞
	// 会让后面的立即任务也取不出来。
	mut list := d.delayed[queue_name] or { []string{} }
	list << '${run_at}||${payload}'
	d.delayed[queue_name] = list
}

// pop removes and returns the next job (O(1) amortized via ring-buffer).
//
// 每次 pop 前先把到期的延迟任务搬进主缓冲区，保证「到期即可见」，
// 同时避免延迟任务长期占用内存。
pub fn (mut d MemoryDriver) pop(queue_name string) !string {
	d.mu.@lock()
	defer { d.mu.unlock() }

	d.promote_ready_delayed(queue_name)

	mut qb := d.jobs[queue_name] or { return error('queue ${queue_name} is empty') }
	result := qb.pop() or { return error('queue ${queue_name} is empty') }
	d.jobs[queue_name] = qb
	return result
}

// promote_ready_delayed 把已到期的延迟任务搬进主缓冲区（调用方需持锁）。
fn (mut d MemoryDriver) promote_ready_delayed(queue_name string) {
	mut pending := d.delayed[queue_name] or { return }
	if pending.len == 0 {
		return
	}
	now := time.now().unix_nano()
	mut still_waiting := []string{cap: pending.len}
	mut ready := []string{}
	for p in pending {
		if is_delay_ready(p, now) {
			ready << p
		} else {
			still_waiting << p
		}
	}
	if ready.len == 0 {
		d.delayed[queue_name] = still_waiting
		return
	}
	mut qb := d.jobs[queue_name] or { QueueBuffer{} }
	for p in ready {
		qb.push(p)
	}
	d.jobs[queue_name] = qb
	if still_waiting.len == 0 {
		d.delayed.delete(queue_name)
	} else {
		d.delayed[queue_name] = still_waiting
	}
}

// count returns the approximate number of pending jobs.
// Acquires the mutex for a consistent snapshot of the map.
pub fn (mut d MemoryDriver) count(queue_name string) int {
	d.mu.@lock()
	defer { d.mu.unlock() }
	qb := d.jobs[queue_name] or { QueueBuffer{} }
	waiting := d.delayed[queue_name] or { []string{} }
	return qb.len() + waiting.len
}

// clear removes all jobs from a queue
pub fn (mut d MemoryDriver) clear(queue_name string) ! {
	d.mu.@lock()
	defer { d.mu.unlock() }
	d.jobs[queue_name] = QueueBuffer{}
	d.delayed.delete(queue_name)
}

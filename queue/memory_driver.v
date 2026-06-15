module queue

// memory_driver.v - In-Memory Queue Driver (thread-safe)

import sync

// MemoryDriver stores jobs in memory (default backend, for testing/dev)
// Thread-safe via embedded mutex.
pub struct MemoryDriver {
pub mut:
	jobs map[string][]string // queue_name → [payload...]
mut:
	mu sync.Mutex
}

// new_memory_driver creates a new MemoryDriver
pub fn new_memory_driver() &MemoryDriver {
	return &MemoryDriver{
		jobs: map[string][]string{}
	}
}

// push adds a job to the queue
pub fn (mut d MemoryDriver) push(queue_name string, payload string) ! {
	d.mu.@lock()
	defer { d.mu.unlock() }
	d.jobs[queue_name] << payload
}

// pop removes and returns the next job
pub fn (mut d MemoryDriver) pop(queue_name string) !string {
	d.mu.@lock()
	defer { d.mu.unlock() }

	mut list := d.jobs[queue_name] or { return error('queue ${queue_name} is empty') }
	if list.len == 0 {
		return error('queue ${queue_name} is empty')
	}
	result := list[0]
	list.delete(0)
	d.jobs[queue_name] = list
	return result
}

// count returns the number of pending jobs
pub fn (d &MemoryDriver) count(queue_name string) int {
	list := d.jobs[queue_name] or { return 0 }
	return list.len
}

// clear removes all jobs from a queue
pub fn (mut d MemoryDriver) clear(queue_name string) ! {
	d.mu.@lock()
	defer { d.mu.unlock() }
	d.jobs[queue_name] = []string{}
}

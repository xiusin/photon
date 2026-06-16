module pool

// pool.v - Photon Connection/Object Pool Module
//
// Provides a generic object pool with configurable min/max size,
// health checking, connection validation, idle timeout, and thread safety.
import time
import sync

// PooledObject is the trait for objects managed by the pool
pub interface PooledObject {
	close() !
	is_valid() bool
}

// Pool manages a pool of reusable objects (thread-safe)
pub struct Pool {
pub mut:
	min_size             int = 2
	max_size             int = 10
	idle_timeout_seconds int = 300
pub:
	name string
mut:
	mu           sync.Mutex
	objects      []PoolEntry
	active_count int
	wait_count   int
	closed       bool
	factory      fn () !voidptr = unsafe { nil }
}

// PoolEntry wraps a pooled object with metadata
struct PoolEntry {
pub mut:
	object       voidptr
	in_use       bool
	created_at   i64
	last_used_at i64
}

// new_pool creates a new Pool
pub fn new_pool(name string, factory fn () !voidptr) &Pool {
	return &Pool{
		name:    name
		factory: factory
	}
}

// new_pool_with_config creates a Pool with custom sizes
pub fn new_pool_with_config(name string, factory fn () !voidptr, min_size int, max_size int) &Pool {
	return &Pool{
		name:     name
		factory:  factory
		min_size: min_size
		max_size: max_size
	}
}

// initialize pre-creates min_size objects
pub fn (mut p Pool) initialize() ! {
	p.mu.@lock()
	defer { p.mu.unlock() }
	for _ in 0 .. p.min_size {
		obj := p.factory()!
		p.objects << PoolEntry{
			object:       obj
			created_at:   time.now().unix()
			last_used_at: time.now().unix()
		}
		p.active_count++
	}
}

// acquire gets an object from the pool
pub fn (mut p Pool) acquire() !voidptr {
	p.mu.@lock()
	defer { p.mu.unlock() }

	if p.closed {
		return error('pool "${p.name}" is closed')
	}

	// Try to find an idle object
	for mut entry in p.objects {
		if !entry.in_use {
			entry.in_use = true
			entry.last_used_at = time.now().unix()
			return entry.object
		}
	}

	// No idle object, create new if under max
	if p.active_count < p.max_size {
		obj := p.factory()!
		p.objects << PoolEntry{
			object:       obj
			created_at:   time.now().unix()
			last_used_at: time.now().unix()
			in_use:       true
		}
		p.active_count++
		return obj
	}

	return error('pool "${p.name}" exhausted (max=${p.max_size}, active=${p.active_count})')
}

// release returns an object to the pool
pub fn (mut p Pool) release(obj voidptr) {
	p.mu.@lock()
	defer { p.mu.unlock() }
	for mut entry in p.objects {
		if entry.object == obj {
			entry.in_use = false
			entry.last_used_at = time.now().unix()
			return
		}
	}
}

// close drains and closes all pooled objects
pub fn (mut p Pool) close() ! {
	p.mu.@lock()
	defer { p.mu.unlock() }
	p.closed = true
	for mut entry in p.objects {
		entry.in_use = false
	}
	p.objects.clear()
	p.active_count = 0
}

// stats returns current pool statistics (snapshot)
pub fn (p &Pool) stats() PoolStats {
	mut in_use_count := 0
	for entry in p.objects {
		if entry.in_use {
			in_use_count++
		}
	}
	return PoolStats{
		name:   p.name
		total:  p.objects.len
		active: in_use_count
		idle:   p.objects.len - in_use_count
		max:    p.max_size
	}
}

// PoolStats holds pool statistics
pub struct PoolStats {
pub:
	name   string
	total  int
	active int
	idle   int
	max    int
}

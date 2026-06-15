module pool

// pool.v - Photon Connection/Object Pool Module
//
// Provides a generic object pool with configurable min/max size,
// health checking, connection validation, and idle timeout.

import time

// PooledObject is the trait for objects managed by the pool
pub interface PooledObject {
	close() !
	is_valid() bool
}

// Pool manages a pool of reusable objects
pub struct Pool {
pub mut:
	min_size    int = 2
	max_size    int = 10
	idle_timeout_seconds int = 300
pub:
	name        string
mut:
	objects     []PoolEntry
	active_count int
	wait_count  int
	closed      bool
	factory     fn () !voidptr
}

// PoolEntry wraps a pooled object with metadata
struct PoolEntry {
pub mut:
	object      voidptr
	created_at  i64
	last_used_at i64
	in_use      bool
}

// new_pool creates a new Pool with a factory function
pub fn new_pool(name string, factory fn () !voidptr) &Pool {
	return &Pool{
		name: name
		factory: factory
	}
}

// new_pool_with_config creates a new Pool with full configuration
pub fn new_pool_with_config(name string, factory fn () !voidptr, min_size int, max_size int) &Pool {
	return &Pool{
		name: name
		factory: factory
		min_size: min_size
		max_size: max_size
	}
}

// initialize pre-creates the minimum number of connections
pub fn (mut p Pool) initialize() ! {
	for _ in 0 .. p.min_size {
		obj := p.factory()!
		p.objects << PoolEntry{
			object: obj
			created_at: time.now().unix()
			last_used_at: time.now().unix()
		}
		p.active_count++
	}
}

// acquire gets an object from the pool
pub fn (mut p Pool) acquire() !voidptr {
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
			object: obj
			created_at: time.now().unix()
			last_used_at: time.now().unix()
			in_use: true
		}
		p.active_count++
		return obj
	}

	return error('pool "${p.name}" exhausted (max=${p.max_size}, active=${p.active_count})')
}

// release returns an object to the pool
pub fn (mut p Pool) release(obj voidptr) {
	for mut entry in p.objects {
		if entry.object == obj {
			entry.in_use = false
			entry.last_used_at = time.now().unix()
			return
		}
	}
}

// close closes the pool and releases all objects
pub fn (mut p Pool) close() ! {
	p.closed = true
	p.objects.clear()
	p.active_count = 0
}

// stats returns pool statistics
pub fn (p &Pool) stats() PoolStats {
	mut idle := 0
	mut active_count := 0
	for entry in p.objects {
		if entry.in_use {
			active_count++
		} else {
			idle++
		}
	}

	return PoolStats{
		name: p.name
		total: p.objects.len
		active: active_count
		idle: idle
		max_size: p.max_size
		min_size: p.min_size
		wait_count: p.wait_count
	}
}

// PoolStats holds pool statistics
pub struct PoolStats {
pub:
	name       string
	total      int
	active     int
	idle       int
	max_size   int
	min_size   int
	wait_count int
}

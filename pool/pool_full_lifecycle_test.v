module pool

// pool_full_lifecycle_test.v - Comprehensive end-to-end lifecycle tests
//
// Verifies the complete seven-stage resource pool lifecycle:
//   factory -> validate(is_valid) -> acquire -> use -> release
//           -> idle_timeout -> max_lifetime -> close
//
// Tests run with -enable-globals (matching CI) because V interfaces
// require immutable receivers, so per-instance mutable state is tracked
// via module-level __global counters (separate from pool_lifecycle_test.v).
import sync
import time

// __global counters for FullLifecycleFactory.
// Tracked separately from pool_lifecycle_test.v's mock_* counters so the
// two test files do not interfere with each other.
__global (
	fl_create_count   int
	fl_destroy_count  int
	fl_is_valid_count int
	fl_reject_id      i64 // 0 = accept all; non-zero = reject this id
)

// FullLifecycleFactory implements Factory with full operation tracking.
// Each create() returns a unique voidptr id (1, 2, 3, ...).
// is_valid() returns false when the object's id equals fl_reject_id and
// increments a call counter so tests can assert validation happened.
// destroy() increments fl_destroy_count.
struct FullLifecycleFactory {}

pub fn (f &FullLifecycleFactory) create() !voidptr {
	unsafe {
		fl_create_count++
		return voidptr(fl_create_count)
	}
}

pub fn (f &FullLifecycleFactory) is_valid(obj voidptr) bool {
	unsafe {
		fl_is_valid_count++
	}
	if fl_reject_id != 0 && i64(obj) == fl_reject_id {
		return false
	}
	return true
}

pub fn (f &FullLifecycleFactory) destroy(obj voidptr) {
	unsafe {
		fl_destroy_count++
	}
}

// fl_reset zeroes the global counters before each test.
fn fl_reset() {
	unsafe {
		fl_create_count = 0
		fl_destroy_count = 0
		fl_is_valid_count = 0
		fl_reject_id = 0
	}
}

// ============================================================
// SubTask 17.2: Full end-to-end lifecycle
// factory -> validate -> acquire -> use -> release
//          -> idle_timeout -> acquire(new) -> close
// ============================================================

fn test_full_lifecycle_end_to_end() {
	fl_reset()
	mut p := new_pool_with_factory('lifecycle', &FullLifecycleFactory{}, 0, 10)

	// Stage 1-3: factory.create() -> acquire (creates new object)
	obj1 := p.acquire()!
	assert fl_create_count == 1
	assert obj1 == voidptr(1)

	// Stage 4: use (simulated by holding the reference)
	// Stage 5: release -> returns to idle pool, updates last_used_at
	p.release(obj1)
	stats := p.stats()
	assert stats.idle == 1
	assert stats.active == 0

	// Acquire again -> should reuse the same object (is_valid passes)
	obj1b := p.acquire()!
	assert obj1b == obj1
	assert fl_create_count == 1 // no new create
	p.release(obj1b)

	// Stage 6: idle_timeout -> background GC evicts the idle object
	p.idle_timeout_seconds = 1
	p.gc_interval_seconds = 1
	p.start_gc()
	// GC sweeps every ~1s; idle_timeout=1 evicts after >1s idle.
	time.sleep(3 * time.second)
	assert fl_destroy_count == 1
	assert p.stats().total == 0

	// Acquire again -> should create a new object (old one evicted)
	obj2 := p.acquire()!
	assert fl_create_count == 2
	assert obj2 != obj1
	p.release(obj2)

	// Stage 8: close -> destroys all idle objects, stops GC
	p.close()!
	assert fl_destroy_count == 2
	assert p.stats().total == 0
}

// ============================================================
// is_valid rejection: factory returns false -> acquire recreates
// ============================================================

fn test_is_valid_rejection_recreates() {
	fl_reset()
	mut p := new_pool_with_factory('valid', &FullLifecycleFactory{}, 0, 10)

	obj1 := p.acquire()!
	p.release(obj1)

	// Mark the released object as invalid.
	unsafe {
		fl_reject_id = i64(obj1)
	}
	valid_calls_before := fl_is_valid_count
	// Next acquire should detect the stale object, destroy it, create new.
	obj2 := p.acquire()!
	valid_calls_after := fl_is_valid_count

	// is_valid should have been called at least once during acquire.
	assert valid_calls_after > valid_calls_before
	// A new object should have been created.
	assert fl_create_count == 2
	// The invalid object should have been destroyed.
	assert fl_destroy_count == 1
	// The new object should be different from the rejected one.
	assert obj2 != obj1

	// Reset reject flag and clean up.
	unsafe {
		fl_reject_id = 0
	}
	p.release(obj2)
	p.close()!
}

// ============================================================
// max_lifetime: objects older than max_lifetime are evicted by GC
// ============================================================

fn test_max_lifetime_eviction() {
	fl_reset()
	mut p := new_pool_with_factory('maxlife', &FullLifecycleFactory{}, 0, 10)
	p.max_lifetime_seconds = 1
	p.gc_interval_seconds = 1

	obj1 := p.acquire()!
	p.release(obj1)
	assert fl_destroy_count == 0

	p.start_gc()
	// max_lifetime=1 evicts after >1s since creation.
	time.sleep(3 * time.second)
	assert fl_destroy_count == 1
	assert p.stats().total == 0

	// Acquire again -> should create a new object.
	obj2 := p.acquire()!
	assert fl_create_count == 2
	p.release(obj2)

	p.close()!
}

// ============================================================
// close() releases all idle objects
// ============================================================

fn test_close_releases_all_objects() {
	fl_reset()
	mut p := new_pool_with_factory('closeall', &FullLifecycleFactory{}, 0, 10)

	// Create and hold multiple objects.
	mut objs := []voidptr{}
	for _ in 0 .. 5 {
		obj := p.acquire()!
		objs << obj
	}
	assert fl_create_count == 5

	// Release all -> they go back to idle.
	for obj in objs {
		p.release(obj)
	}
	stats := p.stats()
	assert stats.idle == 5
	assert stats.active == 0

	// Close -> all idle objects should be destroyed via factory.destroy().
	p.close()!
	assert fl_destroy_count == 5
	assert p.stats().total == 0
}

// ============================================================
// close() is idempotent -> calling twice doesn't panic
// ============================================================

fn test_close_is_idempotent() {
	fl_reset()
	mut p := new_pool_with_factory('idempotent', &FullLifecycleFactory{}, 2, 10)
	p.initialize()!
	assert fl_create_count == 2

	p.close()!
	assert fl_destroy_count == 2

	// Calling close again should not panic or double-destroy.
	p.close()!
	assert fl_destroy_count == 2 // unchanged
}

// ============================================================
// GC stops on close -> no goroutine leak
// close() calls wg.wait(); if GC doesn't exit, close() hangs.
// ============================================================

fn test_gc_stops_on_close() {
	fl_reset()
	mut p := new_pool_with_factory('gcstop', &FullLifecycleFactory{}, 0, 10)
	p.idle_timeout_seconds = 1
	p.gc_interval_seconds = 1

	obj := p.acquire()!
	p.release(obj)

	p.start_gc()
	// Give GC time to start its loop.
	time.sleep(200 * time.millisecond)

	// close() sends stop signal and calls wg.wait().
	// If the GC goroutine does not exit, this call hangs and the test
	// times out -> proving the goroutine leak. Reaching the next line
	// proves the GC exited.
	p.close()!

	// The idle object should have been destroyed by close().
	assert fl_destroy_count == 1

	// Wait past several GC intervals; no additional destroys should
	// happen because the GC goroutine has exited.
	time.sleep(2 * time.second)
	assert fl_destroy_count == 1
}

// ============================================================
// Concurrent acquire/release -> no race, no leak
// ============================================================

fn test_concurrent_acquire_release() {
	fl_reset()
	mut p := new_pool_with_factory('concurrent', &FullLifecycleFactory{}, 0, 10)

	mut wg := sync.new_waitgroup()

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut gp Pool, mut gwg sync.WaitGroup) {
			defer {
				gwg.done()
			}
			for _ in 0 .. 10 {
				obj := gp.acquire() or { continue }
				gp.release(obj)
			}
		}(mut p, mut wg)
	}
	wg.wait()

	// All objects should be returned to idle (no leak, no active).
	stats := p.stats()
	assert stats.active == 0
	assert stats.total > 0
	assert stats.total <= 10

	// Close should destroy all remaining objects.
	p.close()!
	assert p.stats().total == 0
	assert p.stats().active == 0
}

// ============================================================
// Pool stats accuracy -> idle, active, total counts
// ============================================================

fn test_pool_stats_accuracy() {
	fl_reset()
	mut p := new_pool_with_factory('stats', &FullLifecycleFactory{}, 2, 10)
	p.initialize()!

	// After init: 2 idle, 0 active, 2 total, max 10.
	stats := p.stats()
	assert stats.total == 2
	assert stats.idle == 2
	assert stats.active == 0
	assert stats.max == 10

	// Acquire 1 -> 1 idle, 1 active.
	obj1 := p.acquire()!
	stats2 := p.stats()
	assert stats2.total == 2
	assert stats2.idle == 1
	assert stats2.active == 1

	// Acquire 2 -> 0 idle, 2 active.
	obj2 := p.acquire()!
	stats3 := p.stats()
	assert stats3.total == 2
	assert stats3.idle == 0
	assert stats3.active == 2

	// Release obj1 -> 1 idle, 1 active.
	p.release(obj1)
	stats4 := p.stats()
	assert stats4.total == 2
	assert stats4.idle == 1
	assert stats4.active == 1

	// Acquire again -> reuses idle obj1 -> 0 idle, 2 active.
	obj3 := p.acquire()!
	assert obj3 == obj1
	stats5 := p.stats()
	assert stats5.total == 2
	assert stats5.idle == 0
	assert stats5.active == 2

	// Acquire 3rd -> creates new -> 0 idle, 3 active, 3 total.
	obj4 := p.acquire()!
	stats6 := p.stats()
	assert stats6.total == 3
	assert stats6.idle == 0
	assert stats6.active == 3

	p.release(obj2)
	p.release(obj3)
	p.release(obj4)
	stats7 := p.stats()
	assert stats7.total == 3
	assert stats7.idle == 3
	assert stats7.active == 0

	p.close()!
	assert p.stats().total == 0
}

module pool

// pool_lifecycle_test.v - Lifecycle tests for Photon Pool Module
//
// Verifies the fixes for:
//   - CRITICAL #3: close() destroys pooled objects via factory.destroy()
//   - HIGH #13:    acquire() validates objects via factory.is_valid()
//   - HIGH #14:    idle_timeout / max_lifetime eviction by background GC
//   - SubTask 2.6: release() on closed pool destroys the object directly
//
// V interfaces require immutable receivers, so MockFactory cannot mutate
// struct fields. Operation counts are tracked via module-level __global
// counters (compiled with -enable-globals, matching CI).
import time

// __global counters shared across all MockFactory instances.
__global mock_create_count int
__global mock_destroy_count int
__global mock_reject_id i64
// 0 = accept all; non-zero = reject this id

// MockFactory implements Factory for lifecycle testing.
// Each create() returns a unique voidptr id (1, 2, 3, ...).
// is_valid() returns false when the object's id equals mock_reject_id.
// destroy() increments mock_destroy_count.
struct MockFactory {}

pub fn (f &MockFactory) create() !voidptr {
	unsafe {
		mock_create_count++
		return voidptr(mock_create_count)
	}
}

pub fn (f &MockFactory) is_valid(obj voidptr) bool {
	if mock_reject_id != 0 && i64(obj) == mock_reject_id {
		return false
	}
	return true
}

pub fn (f &MockFactory) destroy(obj voidptr) {
	unsafe {
		mock_destroy_count++
	}
}

// reset_mock_state zeroes the global counters before each test.
fn reset_mock_state() {
	unsafe {
		mock_create_count = 0
		mock_destroy_count = 0
		mock_reject_id = 0
	}
}

// ============================================================
// close() destroys idle objects (CRITICAL #3, SubTask 2.1)
// ============================================================

fn test_pool_close_destroys_idle_objects() {
	reset_mock_state()
	mut p := new_pool_with_factory('test', &MockFactory{}, 3, 10)
	p.initialize()!
	assert mock_create_count == 3
	assert mock_destroy_count == 0

	p.close()!
	// All 3 idle objects should have been destroyed via factory.destroy().
	assert mock_destroy_count == 3
	assert p.stats().total == 0
}

// ============================================================
// release() on a closed pool destroys the object (SubTask 2.6)
// ============================================================

fn test_pool_release_on_closed_pool_destroys() {
	reset_mock_state()
	mut p := new_pool_with_factory('test', &MockFactory{}, 0, 10)
	obj := p.acquire()!
	assert mock_create_count == 1

	// Close while object is in use — it is retained, not destroyed.
	p.close()!
	assert mock_destroy_count == 0

	// Releasing on a closed pool destroys the object directly.
	p.release(obj)
	assert mock_destroy_count == 1
}

// ============================================================
// acquire() validates via is_valid() and evicts stale objects (HIGH #13)
// ============================================================

fn test_pool_acquire_validates_is_valid() {
	reset_mock_state()
	mut p := new_pool_with_factory('test', &MockFactory{}, 0, 10)
	obj1 := p.acquire()!
	assert mock_create_count == 1
	p.release(obj1)

	// Mark the released object as invalid.
	unsafe {
		mock_reject_id = i64(obj1)
	}
	// Next acquire should detect the stale object, destroy it, and create a new one.
	obj2 := p.acquire()!
	assert mock_create_count == 2
	assert mock_destroy_count == 1
	assert obj2 != obj1

	p.close()!
}

// ============================================================
// Background GC evicts idle objects after idle_timeout (HIGH #14)
// ============================================================

fn test_pool_idle_timeout_cleanup() {
	reset_mock_state()
	mut p := new_pool_with_factory('test', &MockFactory{}, 0, 10)
	p.idle_timeout_seconds = 1
	p.gc_interval_seconds = 1

	obj := p.acquire()!
	p.release(obj)
	assert mock_destroy_count == 0

	p.start_gc()
	// GC sweeps every ~1s; idle_timeout=1 evicts after >1s idle.
	// Wait 3s to ensure at least one sweep catches the expired object.
	time.sleep(3 * time.second)

	assert mock_destroy_count == 1
	assert p.stats().total == 0

	p.close()!
}

// ============================================================
// Background GC evicts objects exceeding max_lifetime (HIGH #14)
// ============================================================

fn test_pool_max_lifetime_cleanup() {
	reset_mock_state()
	mut p := new_pool_with_factory('test', &MockFactory{}, 0, 10)
	p.max_lifetime_seconds = 1
	p.gc_interval_seconds = 1

	obj := p.acquire()!
	p.release(obj)
	assert mock_destroy_count == 0

	p.start_gc()
	// max_lifetime=1 evicts after >1s since creation.
	time.sleep(3 * time.second)

	assert mock_destroy_count == 1
	assert p.stats().total == 0

	p.close()!
}

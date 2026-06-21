module locking

// locking_lifecycle_test.v - Lifecycle tests for LockManager
//
// Verifies fixes for:
//   - HIGH #17: unlock_and_cleanup() race condition (ref_count-based safe deletion)
//   - Background GC goroutine starts/stops cleanly (no goroutine leak)
//   - cleanup_unused_locks() removes entries with ref_count == 0
//   - ref_count correctly tracks concurrent references

// ============================================================
// unlock_and_cleanup() — ref_count-based safe deletion (HIGH #17)
// ============================================================

fn test_locking_lifecycle_unlock_and_cleanup_removes_entry() {
	mut lm := new_lock_manager()
	lm.lock('temp-key')
	assert lm.lock_count() == 1

	lm.unlock_and_cleanup('temp-key') or { assert false }
	// Entry should be removed since ref_count reached 0
	assert lm.lock_count() == 0
}

fn test_locking_lifecycle_unlock_keeps_entry() {
	mut lm := new_lock_manager()
	lm.lock('reusable-key')
	lm.unlock('reusable-key') or { assert false }
	// unlock() does NOT delete — entry retained for reuse
	assert lm.lock_count() == 1
}

fn test_locking_lifecycle_unlock_and_cleanup_unknown_key() {
	mut lm := new_lock_manager()
	lm.unlock_and_cleanup('nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

// ============================================================
// ref_count tracking — try_lock failure decrements ref (HIGH #17)
// ============================================================

fn test_locking_lifecycle_try_lock_failure_decrements_ref() {
	mut lm := new_lock_manager()
	// lock() → ref_count = 1, mutex held
	lm.lock('held-key')
	// try_lock() increments ref_count to 2, then fails (mutex held),
	// decrement_ref brings ref_count back to 1
	acquired := lm.try_lock('held-key')
	assert acquired == false

	// unlock_and_cleanup should still work: ref_count 1 → 0 → deleted
	lm.unlock_and_cleanup('held-key') or { assert false }
	assert lm.lock_count() == 0
}

fn test_locking_lifecycle_try_lock_success_then_cleanup() {
	mut lm := new_lock_manager()
	acquired := lm.try_lock('free-key')
	assert acquired == true
	// ref_count = 1 (from get_or_create_mutex)
	lm.unlock_and_cleanup('free-key') or { assert false }
	assert lm.lock_count() == 0
}

// ============================================================
// ref_count tracking — lock_with_timeout failure decrements ref
// ============================================================

fn test_locking_lifecycle_timeout_failure_decrements_ref() {
	mut lm := new_lock_manager()
	// lock() → ref_count = 1, mutex held
	lm.lock('contended')
	// lock_with_timeout increments ref_count to 2, polls, times out,
	// decrement_ref brings ref_count back to 1
	acquired := lm.lock_with_timeout('contended', 50) or { false }
	assert acquired == false

	// unlock_and_cleanup: ref_count 1 → 0 → deleted
	lm.unlock_and_cleanup('contended') or { assert false }
	assert lm.lock_count() == 0
}

fn test_locking_lifecycle_timeout_success_then_cleanup() {
	mut lm := new_lock_manager()
	acquired := lm.lock_with_timeout('free-timeout', 100) or { false }
	assert acquired == true
	lm.unlock_and_cleanup('free-timeout') or { assert false }
	assert lm.lock_count() == 0
}

// ============================================================
// cleanup_unused_locks() — removes entries with ref_count == 0
// ============================================================

fn test_locking_lifecycle_cleanup_removes_unused() {
	mut lm := new_lock_manager()
	// Create and release locks (unlock keeps entries, ref_count → 0)
	lm.lock('a')
	lm.lock('b')
	lm.unlock('a') or { assert false }
	lm.unlock('b') or { assert false }
	assert lm.lock_count() == 2

	removed := lm.cleanup_unused_locks()
	assert removed == 2
	assert lm.lock_count() == 0
}

fn test_locking_lifecycle_cleanup_keeps_in_use_locks() {
	mut lm := new_lock_manager()
	lm.lock('held') // ref_count = 1, still held
	lm.lock('released')
	lm.unlock('released') or { assert false } // ref_count = 0

	removed := lm.cleanup_unused_locks()
	assert removed == 1 // only 'released' removed
	assert lm.lock_count() == 1

	// Clean up the held lock
	lm.unlock_and_cleanup('held') or { assert false }
	assert lm.lock_count() == 0
}

fn test_locking_lifecycle_cleanup_on_empty_manager() {
	mut lm := new_lock_manager()
	removed := lm.cleanup_unused_locks()
	assert removed == 0
}

// ============================================================
// Background GC goroutine — start/stop lifecycle (no leak)
// ============================================================

fn test_locking_lifecycle_gc_starts_and_stops() {
	mut lm := new_lock_manager()
	lm.start_gc()
	// start_gc is idempotent — second call is a no-op
	lm.start_gc()
	// close() stops the GC goroutine and waits via wg.wait()
	// If this hangs, the GC goroutine is not responding to stop signal
	lm.close()
	// close() is idempotent
	lm.close()
}

fn test_locking_lifecycle_gc_close_without_start() {
	mut lm := new_lock_manager()
	// close() without start_gc() should be a safe no-op
	lm.close()
}

fn test_locking_lifecycle_gc_cleanup_after_unlock() {
	mut lm := new_lock_manager()
	lm.start_gc()

	// Create a lock and release it (ref_count → 0, entry retained)
	lm.lock('gc-target')
	lm.unlock('gc-target') or { assert false }
	assert lm.lock_count() == 1

	// Manually trigger cleanup (the GC does this every 60s, but we
	// call it directly for a fast test)
	removed := lm.cleanup_unused_locks()
	assert removed == 1
	assert lm.lock_count() == 0

	lm.close()
}

// ============================================================
// lock_count() — monitoring helper
// ============================================================

fn test_locking_lifecycle_lock_count_tracks_entries() {
	mut lm := new_lock_manager()
	assert lm.lock_count() == 0

	lm.lock('k1')
	assert lm.lock_count() == 1

	lm.lock('k2')
	assert lm.lock_count() == 2

	lm.unlock_and_cleanup('k1') or { assert false }
	assert lm.lock_count() == 1

	lm.unlock_and_cleanup('k2') or { assert false }
	assert lm.lock_count() == 0
}

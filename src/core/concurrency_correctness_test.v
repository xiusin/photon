module core

// concurrency_correctness_test.v - Tests for Phase 3 concurrency fixes
//
// Validates the fixes for:
//   H5 — queue/dispatcher.v double-checked locking (read-lock fast path)
//   H4 — core/di_enhanced.v DeferredProvider.get() double-checked locking
//   M9 — core/lifecycle.v SmartLifecycleManager missing lock
//   M26 — core/lifecycle.v stop_all() missing timeout
//   L4 — core/sharded_lock.v bitwise-AND shard selection
//   M8 — ticker/schedule.v task_count/enabled_count thread safety
//
// These tests spawn many goroutines to exercise the concurrent code paths.
// V's `select { else {} }` is non-blocking, so completion is tracked via
// buffered channels.
import time
import support
import queue
import ticker

// ── Test helper: SmartLifecycle implementation ──

// ConcurrentTestLifecycle is a minimal SmartLifecycle implementation used by
// the concurrency tests. The `running` field controls is_running() so that
// start_all/stop_all can be exercised deterministically.
struct ConcurrentTestLifecycle {
pub:
	phase_val int
	running   bool
}

pub fn (ctl &ConcurrentTestLifecycle) is_running() bool {
	return ctl.running
}

pub fn (ctl &ConcurrentTestLifecycle) start() ! {
}

pub fn (ctl &ConcurrentTestLifecycle) stop() ! {
}

pub fn (ctl &ConcurrentTestLifecycle) phase() int {
	return ctl.phase_val
}

// ═══════════════════════════════════════════════════════════
// H5: Concurrent get_dispatcher() — double-checked locking
// ═══════════════════════════════════════════════════════════

// test_concurrent_get_dispatcher exercises the double-checked locking in
// queue.get_dispatcher() by issuing many concurrent count() calls (each
// internally calls get_dispatcher()). Whether the global dispatcher is
// already initialized (read-lock fast path) or not (write-lock init path),
// all calls must complete without crashing or returning inconsistent state.
fn test_concurrent_get_dispatcher() {
	done := chan bool{cap: 50}

	for _ in 0 .. 50 {
		spawn fn (d chan bool) {
			// count() internally calls get_dispatcher() which uses
			// double-checked locking with a read lock on the fast path.
			_ = queue.count()
			d <- true
		}(done)
	}

	mut completed := 0
	for _ in 0 .. 50 {
		_ = <-done
		completed++
	}
	assert completed == 50
}

// ═══════════════════════════════════════════════════════════
// H4: DeferredProvider concurrent get() — double-checked locking
// ═══════════════════════════════════════════════════════════

// test_deferred_provider_concurrent_get spawns many goroutines that all call
// DeferredProvider.get() simultaneously. The first goroutine to acquire the
// write lock resolves and caches the bean; the rest hit the read-lock fast
// path or the write-lock double-check. All must return successfully and the
// provider must end up marked as resolved.
fn test_deferred_provider_concurrent_get() {
	mut c := new_container()
	c.register_instance('TestService', unsafe { voidptr(42) }) or { assert false }

	mut dp := c.create_deferred_provider('TestService')

	done := chan bool{cap: 50}

	for _ in 0 .. 50 {
		spawn fn (d &DeferredProvider, done_chan chan bool) {
			mut ok := true
			unsafe {
				d.get() or { ok = false }
			}
			done_chan <- ok
		}(dp, done)
	}

	mut successes := 0
	for _ in 0 .. 50 {
		v := <-done
		if v {
			successes++
		}
	}
	assert successes == 50
	assert dp.is_resolved() == true
}

// ═══════════════════════════════════════════════════════════
// M9: SmartLifecycleManager concurrent access
// ═══════════════════════════════════════════════════════════

// test_smart_lifecycle_manager_concurrent_access concurrently registers
// lifecycles and reads entry_count(). Without the mutex (M9), concurrent
// appends to `entries` and reads of `entries.len` would be a data race.
fn test_smart_lifecycle_manager_concurrent_access() {
	mut mgr := new_smart_lifecycle_manager()

	done := chan bool{cap: 100}

	// Half the goroutines register lifecycles
	for i in 0 .. 50 {
		spawn fn (m &SmartLifecycleManager, idx int, d chan bool) {
			tsl := &ConcurrentTestLifecycle{
				phase_val: idx
			}
			unsafe {
				m.register('lifecycle_${idx}', &SmartLifecycle(tsl))
			}
			d <- true
		}(mgr, i, done)
	}

	// Half the goroutines read entry_count concurrently
	for _ in 0 .. 50 {
		spawn fn (m &SmartLifecycleManager, d chan bool) {
			unsafe {
				_ = m.entry_count()
			}
			d <- true
		}(mgr, done)
	}

	for _ in 0 .. 100 {
		_ := <-done
	}

	assert mgr.entry_count() == 50
}

// test_smart_lifecycle_stop_all_completes verifies that stop_all() returns
// promptly when lifecycles stop quickly (well under the 5-second timeout).
fn test_smart_lifecycle_stop_all_completes() {
	mut mgr := new_smart_lifecycle_manager()

	// Register lifecycles that are "running" so stop() will be called.
	mgr.register('svc_a', &SmartLifecycle(&ConcurrentTestLifecycle{
		phase_val: 1
		running:   true
	}))
	mgr.register('svc_b', &SmartLifecycle(&ConcurrentTestLifecycle{
		phase_val: 2
		running:   true
	}))

	start := time.now()
	mgr.stop_all()
	elapsed := time.now().unix_nano() - start.unix_nano()

	// Should complete in well under 5 seconds (the timeout is 5s).
	assert elapsed < i64(5 * time.second)
}

// ═══════════════════════════════════════════════════════════
// L4: ShardedRwMutex shard distribution
// ═══════════════════════════════════════════════════════════

// test_sharded_rw_mutex_power_of_two verifies that shard_count is a power
// of 2, which is required for the bitwise-AND shard selection to be correct.
fn test_sharded_rw_mutex_power_of_two() {
	assert shard_count > 0
	// A power of 2 has exactly one bit set, so n & (n-1) == 0.
	assert (shard_count & (shard_count - 1)) == 0
}

// test_sharded_rw_mutex_shard_distribution verifies that the bitwise-AND
// shard selection `hash & (shard_count - 1)` produces identical results to
// the modulo `hash % shard_count` (equivalent only for power-of-2), that all
// indices are in range, and that keys distribute across all shards.
fn test_sharded_rw_mutex_shard_distribution() {
	mut all_in_range := true
	mut distinct_shards := map[int]bool{}

	for i in 0 .. 1000 {
		key := 'key_${i}'
		hash := support.fnv1a_str(key)
		idx_bitwise := int(hash & u64(shard_count - 1))
		idx_modulo := int(hash % u64(shard_count))
		assert idx_bitwise == idx_modulo
		if idx_bitwise < 0 || idx_bitwise >= shard_count {
			all_in_range = false
		}
		distinct_shards[idx_bitwise] = true
	}
	assert all_in_range
	// With 1000 keys and 16 shards, all shards should be represented.
	assert distinct_shards.len == shard_count
}

// test_sharded_rw_mutex_concurrent_access exercises concurrent lock/unlock
// operations on different keys (different shards) to verify no deadlock or
// crash under contention.
fn test_sharded_rw_mutex_concurrent_access() {
	mut sm := new_sharded_rw_mutex()

	done := chan bool{cap: 50}

	for i in 0 .. 50 {
		spawn fn (s &ShardedRwMutex, idx int, d chan bool) {
			key := 'concurrent_key_${idx}'
			unsafe {
				s.rlock(key)
				s.runlock(key)
				s.@lock(key)
				s.unlock(key)
			}
			d <- true
		}(sm, i, done)
	}

	for _ in 0 .. 50 {
		_ := <-done
	}
	assert true
}

// ═══════════════════════════════════════════════════════════
// M8: Schedule task_count/enabled_count thread safety
// ═══════════════════════════════════════════════════════════

// test_schedule_concurrent_task_count issues many concurrent task_count()
// and enabled_count() calls on a Scheduler. These methods read the tasks
// slice under a read lock (M8 fix); without the lock, concurrent reads
// during register/sort would be a data race.
fn test_schedule_concurrent_task_count() {
	mut s := ticker.new_task_scheduler()

	// Register some tasks first (sequential — registration is not the
	// concurrent part under test here).
	for i in 0 .. 10 {
		mut b := s.every(1 * time.second)
		b.task_fn = fn () ! {
		}
		b.name_ = 'task_${i}'
		s.register(b)
	}

	done := chan bool{cap: 100}

	// Concurrent reads of task_count and enabled_count
	for _ in 0 .. 50 {
		spawn fn (sc &ticker.Scheduler, d chan bool) {
			unsafe {
				_ = sc.task_count()
				_ = sc.enabled_count()
			}
			d <- true
		}(s, done)
	}

	for _ in 0 .. 50 {
		_ := <-done
	}

	assert s.task_count() == 10
	assert s.enabled_count() == 10
}

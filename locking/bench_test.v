module locking

// bench_test.v - Lock Module Performance Benchmarks
// Comprehensive performance testing for all locking primitives.
//
// Metrics measured:
//   - Throughput (ops/sec): lock/unlock cycles per second
//   - Latency (µs/op): average time per operation
//   - Contention impact: performance under concurrent access
import time

const bench_warmup_iters = 100
const bench_measure_iters = 1000

// bench_report prints a formatted benchmark result
fn bench_report(name string, iters int, elapsed_ns i64) {
	ns_per_op := f64(elapsed_ns) / f64(iters)
	ops_per_sec := f64(iters) / (f64(elapsed_ns) / 1_000_000_000.0)
	eprintln('  [BENCH] ${name}: ${iters} ops, ${ns_per_op:.2f} ns/op, ${ops_per_sec:.0f} ops/sec')
}

// ============================================================
// 1. LocalMutex — Raw Lock/Unlock Throughput
// ============================================================

fn test_bench_local_mutex_lock_unlock() {
	mut mu := new_mutex()
	warmup := bench_warmup_iters
	measure := bench_measure_iters

	// Warmup
	for _ in 0 .. warmup {
		mu.lock()
		mu.unlock()
	}

	// Measure
	start := time.ticks()
	for _ in 0 .. measure {
		mu.lock()
		mu.unlock()
	}
	elapsed := time.ticks() - start

	bench_report('LocalMutex.lock/unlock', measure, elapsed * 1000000)
	assert true
}

// ============================================================
// 2. LocalMutex — TryLock Throughput (Uncontended)
// ============================================================

fn test_bench_local_mutex_try_lock() {
	mut mu := new_mutex()
	measure := bench_measure_iters

	start := time.ticks()
	for _ in 0 .. measure {
		assert mu.try_lock() == true
		mu.unlock()
	}
	elapsed := time.ticks() - start

	bench_report('LocalMutex.try_lock (uncontended)', measure, elapsed * 1000000)
}

// ============================================================
// 3. LocalMutex — TryLock Failure Path (Contended)
// ============================================================

fn test_bench_local_mutex_try_lock_contended() {
	mut mu := new_mutex()
	mu.lock()
	measure := bench_measure_iters

	start := time.ticks()
	for _ in 0 .. measure {
		_ = mu.try_lock() // held — always fails
	}
	elapsed := time.ticks() - start
	mu.unlock()

	bench_report('LocalMutex.try_lock (contended)', measure, elapsed * 1000000)
	assert true
}

// ============================================================
// 4. LockManager — Single Key Throughput
// ============================================================

fn test_bench_lock_manager_single_key() {
	mut lm := new_lock_manager()
	warmup := bench_warmup_iters
	measure := bench_measure_iters

	for _ in 0 .. warmup {
		lm.lock('resource')
		lm.unlock('resource') or {}
	}

	start := time.ticks()
	for _ in 0 .. measure {
		lm.lock('resource')
		lm.unlock('resource') or {}
	}
	elapsed := time.ticks() - start

	bench_report('LockManager.lock/unlock (single key)', measure, elapsed * 1000000)
}

// ============================================================
// 5. LockManager — Multi-Key Throughput (10 distinct keys)
// ============================================================

fn test_bench_lock_manager_multi_key() {
	mut lm := new_lock_manager()
	keys := ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']
	loops := bench_measure_iters / 10

	start := time.ticks()
	for _ in 0 .. loops {
		for key in keys {
			lm.lock(key)
			lm.unlock(key) or {}
		}
	}
	elapsed := time.ticks() - start

	ops := loops * keys.len
	bench_report('LockManager.lock/unlock (10 keys)', ops, elapsed * 1000000)
}

// ============================================================
// 6. LockManager — TryLock (Uncontended)
// ============================================================

fn test_bench_lock_manager_try_lock() {
	mut lm := new_lock_manager()
	measure := bench_measure_iters

	start := time.ticks()
	for _ in 0 .. measure {
		assert lm.try_lock('bench-key') == true
		lm.unlock('bench-key') or {}
	}
	elapsed := time.ticks() - start

	bench_report('LockManager.try_lock (uncontended)', measure, elapsed * 1000000)
}

// ============================================================
// 7. LockManager — TryLock (Contended)
// ============================================================

fn test_bench_lock_manager_try_lock_contended() {
	mut lm := new_lock_manager()
	lm.lock('held')
	measure := bench_measure_iters

	start := time.ticks()
	for _ in 0 .. measure {
		_ = lm.try_lock('held') // held — always fails
	}
	elapsed := time.ticks() - start
	lm.unlock('held') or {}

	bench_report('LockManager.try_lock (contended)', measure, elapsed * 1000000)
	assert true
}

// ============================================================
// 8. LockGuard — Create & Release
// ============================================================

fn test_bench_lock_guard() {
	mut lm := new_lock_manager()
	warmup := bench_warmup_iters
	measure := bench_measure_iters

	for _ in 0 .. warmup {
		mut guard := new_lock_guard(mut lm, 'guard-bench')
		guard.unlock()
	}

	start := time.ticks()
	for _ in 0 .. measure {
		mut guard := new_lock_guard(mut lm, 'guard-bench')
		guard.unlock()
	}
	elapsed := time.ticks() - start

	bench_report('LockGuard.create/unlock', measure, elapsed * 1000000)
}

// ============================================================
// 9. guarded_lock — Full Cycle (lock + fn + defer unlock)
// ============================================================

fn test_bench_guarded_lock() {
	mut lm := new_lock_manager()
	warmup := bench_warmup_iters
	measure := bench_measure_iters

	for _ in 0 .. warmup {
		guarded_lock(mut lm, 'g-bench', fn [mut lm] () !int {
			return 42
		}) or {}
	}

	start := time.ticks()
	for _ in 0 .. measure {
		guarded_lock(mut lm, 'g-bench', fn [mut lm] () !int {
			return 42
		}) or {}
	}
	elapsed := time.ticks() - start

	bench_report('guarded_lock (lock+fn+unlock)', measure, elapsed * 1000000)
}

// ============================================================
// 10. lock_with_timeout — Immediate Acquisition
// ============================================================

fn test_bench_lock_with_timeout_immediate() {
	mut lm := new_lock_manager()
	measure := bench_measure_iters

	start := time.ticks()
	for _ in 0 .. measure {
		result := lm.lock_with_timeout('timeout-bench', 100)!
		assert result == true
		lm.unlock('timeout-bench') or {}
	}
	elapsed := time.ticks() - start

	bench_report('lock_with_timeout (immediate) ', measure, elapsed * 1000000)
}

// ============================================================
// 11. lock_with_timeout — Expired Timeout Path
// ============================================================

fn test_bench_lock_with_timeout_expired() {
	mut lm := new_lock_manager()
	lm.lock('held-timeout')
	measure := bench_measure_iters / 20 // fewer — polling with sleep

	start := time.ticks()
	for _ in 0 .. measure {
		result := lm.lock_with_timeout('held-timeout', 1)!
		assert result == false
	}
	elapsed := time.ticks() - start
	lm.unlock('held-timeout') or {}

	bench_report('lock_with_timeout (1ms expired)', measure, elapsed * 1000000)
}

// ============================================================
// 12. LockManager — New Key Creation Throughput
// ============================================================

fn test_bench_lock_manager_key_creation() {
	mut lm := new_lock_manager()
	measure := 500 // fewer iterations — creates map entries

	start := time.ticks()
	for i in 0 .. measure {
		lm.lock('new-key-${i}')
		lm.unlock('new-key-${i}') or {}
	}
	elapsed := time.ticks() - start

	bench_report('LockManager.new key (map insert)', measure, elapsed * 1000000)
}

// ============================================================
// 13. LockManager — Fast Path (pre-existing mutex in map)
// ============================================================

fn test_bench_lock_manager_fast_path() {
	mut lm := new_lock_manager()
	lm.lock('fast-key')
	lm.unlock('fast-key') or {}

	measure := bench_measure_iters

	start := time.ticks()
	for _ in 0 .. measure {
		lm.lock('fast-key')
		lm.unlock('fast-key') or {}
	}
	elapsed := time.ticks() - start

	bench_report('LockManager.lock (fast path, pre-existing key)', measure, elapsed * 1000000)
}

// ============================================================
// 14. DistLock — Nil Backend Error Path
// ============================================================

fn test_bench_dist_lock_nil_backend() {
	mut lm := new_lock_manager()
	measure := bench_measure_iters

	start := time.ticks()
	for _ in 0 .. measure {
		_ = lm.dist_lock('dist-key', 100) or { false }
	}
	elapsed := time.ticks() - start

	bench_report('dist_lock (nil backend error path)', measure, elapsed * 1000000)
}

// ============================================================
// 15. LockManager — Memory Retention (keys survive unlock)
// ============================================================

fn test_bench_lock_manager_memory_retention() {
	mut lm := new_lock_manager()
	num_keys := 1000

	for i in 0 .. num_keys {
		lm.lock('mem-key-${i}')
	}

	assert lm.local_locks.len == num_keys

	for i in 0 .. num_keys {
		lm.unlock('mem-key-${i}') or {}
	}

	// Mutexes are retained in map after unlock (cached for reuse)
	assert lm.local_locks.len == num_keys
	eprintln('  [BENCH] LockManager memory: ${num_keys} keys created, all ${lm.local_locks.len} retained after unlock')
}

// ============================================================
// 16. Comparative Analysis — LocalMutex vs LockManager Overhead
// ============================================================

fn test_bench_comparative_analysis() {
	mut mu := new_mutex()
	mut lm := new_lock_manager()

	iters := bench_measure_iters

	// LocalMutex raw
	start1 := time.ticks()
	for _ in 0 .. iters {
		mu.lock()
		mu.unlock()
	}
	e1 := time.ticks() - start1

	// LockManager (same-key, pre-existing)
	lm.lock('cmp')
	lm.unlock('cmp') or {}
	start2 := time.ticks()
	for _ in 0 .. iters {
		lm.lock('cmp')
		lm.unlock('cmp') or {}
	}
	e2 := time.ticks() - start2

	overhead := f64(e2 - e1) / f64(e1) * 100.0
	eprintln('  [BENCH] LockManager overhead vs LocalMutex: ${overhead:.1f}%')
	assert true
}

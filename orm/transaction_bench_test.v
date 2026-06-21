module orm

// transaction_bench_test.v - Transaction Module Performance Benchmarks
//
// Measures throughput for TransactionManager propagation, nesting, and
// begin/commit lifecycle operations.
import time

fn bench_report(name string, iters int, elapsed_ns i64) {
	ns_per_op := f64(elapsed_ns) / f64(iters)
	ops_per_sec := f64(iters) / (f64(elapsed_ns) / 1_000_000_000.0)
	eprintln('  [BENCH] ${name}: ${iters} ops, ${ns_per_op:.2f} ns/op, ${ops_per_sec:.0f} ops/sec')
}

fn test_bench_transaction_execute_required() {
	mut tm := new_transaction_manager()
	measure := 10000

	start := time.ticks()
	for _ in 0 .. measure {
		tm.execute(.required, fn () ! {}) or {}
	}
	elapsed := time.ticks() - start

	bench_report('TransactionManager.execute(.required) x10000', measure, elapsed * 1000000)
}

fn test_bench_transaction_nested_required() {
	mut tm := new_transaction_manager()
	measure := 1000

	start := time.ticks()
	for _ in 0 .. measure {
		tm.execute(.required, fn [mut tm] () ! {
			tm.execute(.required, fn () ! {}) or {}
		}) or {}
	}
	elapsed := time.ticks() - start

	bench_report('TransactionManager nested .required x1000', measure, elapsed * 1000000)
}

fn test_bench_transaction_begin_commit() {
	mut tm := new_transaction_manager()
	measure := 10000

	start := time.ticks()
	for _ in 0 .. measure {
		tm.begin() or {}
		tm.commit() or {}
	}
	elapsed := time.ticks() - start

	bench_report('TransactionManager begin+commit x10000', measure, elapsed * 1000000)
}

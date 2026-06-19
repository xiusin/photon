module cache

// cache_bench_test.v - Cache Module Performance Benchmarks
//
// Measures throughput and latency for MemoryCache and CacheRegistry operations.
import time

fn bench_report(name string, iters int, elapsed_ns i64) {
	ns_per_op := f64(elapsed_ns) / f64(iters)
	ops_per_sec := f64(iters) / (f64(elapsed_ns) / 1_000_000_000.0)
	eprintln('  [BENCH] ${name}: ${iters} ops, ${ns_per_op:.2f} ns/op, ${ops_per_sec:.0f} ops/sec')
}

fn test_bench_cache_set() {
	mut c := new_memory_cache('bench')
	measure := 10000

	start := time.ticks()
	for i in 0 .. measure {
		c.set('key${i}', 'value${i}', 0) or {}
	}
	elapsed := time.ticks() - start

	bench_report('MemoryCache.set x10000', measure, elapsed * 1000000)
}

fn test_bench_cache_get() {
	mut c := new_memory_cache('bench')
	for i in 0 .. 1000 {
		c.set('key${i}', 'value${i}', 0) or {}
	}
	measure := 10000

	start := time.ticks()
	for i in 0 .. measure {
		c.get('key${i % 1000}') or {}
	}
	elapsed := time.ticks() - start

	bench_report('MemoryCache.get x10000', measure, elapsed * 1000000)
}

fn test_bench_cache_get_or_load() {
	mut cm := new_cache_registry()
	measure := 1000

	start := time.ticks()
	for i in 0 .. measure {
		cm.get_or_load('key${i}', 60, fn [i] () !string {
			return 'value${i}'
		}) or {}
	}
	elapsed := time.ticks() - start

	bench_report('CacheRegistry.get_or_load x1000', measure, elapsed * 1000000)
}

fn test_bench_cache_delete() {
	mut c := new_memory_cache('bench')
	for i in 0 .. 10000 {
		c.set('key${i}', 'value${i}', 0) or {}
	}
	measure := 10000

	start := time.ticks()
	for i in 0 .. measure {
		c.delete('key${i}') or {}
	}
	elapsed := time.ticks() - start

	bench_report('MemoryCache.delete x10000', measure, elapsed * 1000000)
}

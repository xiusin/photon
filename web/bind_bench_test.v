module web

// bind_bench_test.v - Web Bind Module Performance Benchmarks
//
// Measures throughput for struct binding (query/form), JSON body binding,
// and raw JSON decoding — the core paths exercised by bind[T] and bind_json[T].
import veb
import json
import time

struct BenchLoginDto {
	username string
	password string
	remember bool
}

struct BenchCreateUserDto {
	name  string
	email string
	age   int
}

fn bench_report(name string, iters int, elapsed_ns i64) {
	ns_per_op := f64(elapsed_ns) / f64(iters)
	ops_per_sec := f64(iters) / (f64(elapsed_ns) / 1_000_000_000.0)
	eprintln('  [BENCH] ${name}: ${iters} ops, ${ns_per_op:.2f} ns/op, ${ops_per_sec:.0f} ops/sec')
}

fn test_bench_bind_struct() {
	mut ctx := &veb.Context{}
	ctx.req.url = '/test?username=bench&password=pass&remember=true'
	ctx.query['username'] = 'bench'
	ctx.query['password'] = 'pass'
	ctx.query['remember'] = 'true'
	measure := 10000

	start := time.ticks()
	for _ in 0 .. measure {
		_ = bind[BenchLoginDto](ctx) or { BenchLoginDto{} }
	}
	elapsed := time.ticks() - start

	bench_report('bind[BenchLoginDto] x10000', measure, elapsed * 1000000)
}

fn test_bench_bind_json() {
	mut ctx := &veb.Context{}
	ctx.req.data = '{"name":"user","email":"user@test.com","age":25}'
	measure := 10000

	start := time.ticks()
	for _ in 0 .. measure {
		_ = bind_json[BenchCreateUserDto](ctx) or { BenchCreateUserDto{} }
	}
	elapsed := time.ticks() - start

	bench_report('bind_json[BenchCreateUserDto] x10000', measure, elapsed * 1000000)
}

fn test_bench_json_decode() {
	measure := 10000

	start := time.ticks()
	for i in 0 .. measure {
		body := '{"name":"user${i}","email":"user${i}@test.com","age":25}'
		_ := json.decode(BenchCreateUserDto, body) or { BenchCreateUserDto{} }
	}
	elapsed := time.ticks() - start

	bench_report('json.decode(BenchCreateUserDto) x10000', measure, elapsed * 1000000)
}

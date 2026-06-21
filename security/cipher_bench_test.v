module security

// cipher_bench_test.v - Security Cipher Module Performance Benchmarks
//
// Measures throughput for AES-256-CBC encrypt/decrypt and BcryptHasher
// make/check. BcryptHasher uses low rounds (4) to keep benchmark runtime bounded.
import time

fn bench_report(name string, iters int, elapsed_ns i64) {
	ns_per_op := f64(elapsed_ns) / f64(iters)
	ops_per_sec := f64(iters) / (f64(elapsed_ns) / 1_000_000_000.0)
	eprintln('  [BENCH] ${name}: ${iters} ops, ${ns_per_op:.2f} ns/op, ${ops_per_sec:.0f} ops/sec')
}

fn test_bench_aes_encrypt() {
	cipher := new_aes_cipher('0123456789abcdef0123456789abcdef') or {
		eprintln('AES cipher init failed')
		return
	}
	plaintext := 'Hello, World! This is a benchmark test message.'
	measure := 1000

	start := time.ticks()
	for _ in 0 .. measure {
		cipher.encrypt(plaintext) or {}
	}
	elapsed := time.ticks() - start

	bench_report('AesCipher.encrypt x1000', measure, elapsed * 1000000)
}

fn test_bench_aes_decrypt() {
	cipher := new_aes_cipher('0123456789abcdef0123456789abcdef') or {
		eprintln('AES cipher init failed')
		return
	}
	plaintext := 'Hello, World! This is a benchmark test message.'
	encrypted := cipher.encrypt(plaintext) or { return }
	measure := 1000

	start := time.ticks()
	for _ in 0 .. measure {
		cipher.decrypt(encrypted) or {}
	}
	elapsed := time.ticks() - start

	bench_report('AesCipher.decrypt x1000', measure, elapsed * 1000000)
}

fn test_bench_bcrypt_make() {
	h := BcryptHasher{
		rounds: 4
	}
	measure := 10

	start := time.ticks()
	for _ in 0 .. measure {
		_ = h.make('benchmark_password')
	}
	elapsed := time.ticks() - start

	bench_report('BcryptHasher.make(rounds=4) x10', measure, elapsed * 1000000)
}

fn test_bench_bcrypt_check() {
	h := BcryptHasher{
		rounds: 4
	}
	hash := h.make('benchmark_password')
	measure := 10

	start := time.ticks()
	for _ in 0 .. measure {
		_ = h.check('benchmark_password', hash)
	}
	elapsed := time.ticks() - start

	bench_report('BcryptHasher.check(rounds=4) x10', measure, elapsed * 1000000)
}

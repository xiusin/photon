module support

// hash.v - Zero-allocation hashing utilities
//
// Provides hash functions that operate directly on string bytes,
// avoiding the per-call []u8 allocation of `string.bytes()`.

// fnv1a_str computes the FNV-1a 64-bit hash of a string by iterating
// over its bytes directly. This avoids the `s.bytes()` allocation that
// would otherwise occur on every call, making it suitable for hot paths
// such as shard selection in rate limiters and sharded locks.
pub fn fnv1a_str(s string) u64 {
	mut hash := u64(14695981039346656037) // FNV offset basis
	for i in 0 .. s.len {
		hash = hash ^ u64(s[i])
		hash = hash * u64(1099511628211) // FNV prime
	}
	return hash
}

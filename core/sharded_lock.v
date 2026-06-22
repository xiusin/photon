module core

// sharded_lock.v - Sharded Lock for Fine-Grained Concurrency
//
// Replaces the single global RwMutex in the Container with a sharded approach.
// This significantly reduces lock contention in high-concurrency scenarios by
// partitioning the lock space based on key hashes.
//
// Spring equivalent: ConcurrentHashMap segment locking
// Go equivalent: sync.Map's internal sharding
//
// Performance characteristics:
//   - Single global RwMutex: all operations serialize on one lock
//   - Sharded (16 segments): operations on different keys proceed in parallel
//   - Read-heavy workloads (typical for DI): near-zero contention
//
// Also provides:
//   - Per-bean locking for safe singleton instantiation
//   - Lock auto-cleanup to prevent memory leaks
import sync
import support

// shard_count is the number of lock segments.
// 16 is a good balance between concurrency and memory overhead.
pub const shard_count = 16

// ShardedRwMutex provides fine-grained locking by sharding keys across
// multiple RwMutex instances. Operations on different shards proceed
// concurrently without blocking each other.
@[heap]
pub struct ShardedRwMutex {
pub mut:
	shards []sync.RwMutex
}

// new_sharded_rw_mutex creates a ShardedRwMutex with the configured number of shards.
pub fn new_sharded_rw_mutex() &ShardedRwMutex {
	// shard_count MUST be a power of 2 so that `& (shard_count - 1)` is
	// equivalent to `% shard_count` (see shard_index). This assert catches
	// accidental changes to a non-power-of-2 value at startup.
	assert shard_count > 0 && (shard_count & (shard_count - 1)) == 0
	mut shards := []sync.RwMutex{len: int(shard_count)}
	return &ShardedRwMutex{
		shards: shards
	}
}

// shard_index returns the shard index for a given key.
// Uses a simple hash to distribute keys across shards.
//
// L4: uses bitwise AND `& (shard_count - 1)` instead of modulo
// `% shard_count`. This is equivalent when shard_count is a power of 2 (enforced
// by new_sharded_rw_mutex) but avoids the expensive integer division on every
// lock acquisition — a measurable win on hot paths like container bean lookups.
fn (sm &ShardedRwMutex) shard_index(key string) int {
	// FNV-1a 64-bit hash, zero-allocation via support.fnv1a_str
	return int(support.fnv1a_str(key) & u64(shard_count - 1))
}

// rlock acquires a read lock on the shard for the given key.
pub fn (mut sm ShardedRwMutex) rlock(key string) {
	mut shard := unsafe { &sm.shards[sm.shard_index(key)] }
	shard.rlock()
}

// runlock releases a read lock on the shard for the given key.
pub fn (mut sm ShardedRwMutex) runlock(key string) {
	mut shard := unsafe { &sm.shards[sm.shard_index(key)] }
	shard.runlock()
}

// @lock acquires a write lock on the shard for the given key.
pub fn (mut sm ShardedRwMutex) @lock(key string) {
	mut shard := unsafe { &sm.shards[sm.shard_index(key)] }
	shard.@lock()
}

// unlock releases a write lock on the shard for the given key.
pub fn (mut sm ShardedRwMutex) unlock(key string) {
	mut shard := unsafe { &sm.shards[sm.shard_index(key)] }
	shard.unlock()
}

// rlock_all acquires read locks on ALL shards in ascending order (0 → shard_count-1).
// Used for operations that need to read the entire container state.
//
// 死锁安全性：rlock_all 和 lock_all 始终按升序获取分片锁，保证多个
// rlock_all/lock_all 调用之间不会死锁。rlock(key) 只获取单个分片锁，
// 不会形成循环等待，因此 rlock_all 和 rlock(key) 之间也不会死锁。
//
// Deadlock safety: rlock_all and lock_all always acquire shard locks in ascending
// order, preventing deadlocks between multiple rlock_all/lock_all calls. Since
// rlock(key) only acquires a single shard lock, it cannot form a circular wait
// with rlock_all, so no deadlock is possible between them either.
pub fn (mut sm ShardedRwMutex) rlock_all() {
	for i in 0 .. sm.shards.len {
		sm.shards[i].rlock()
	}
}

// runlock_all releases read locks on all shards.
pub fn (mut sm ShardedRwMutex) runlock_all() {
	for i in 0 .. sm.shards.len {
		sm.shards[i].runlock()
	}
}

// lock_all acquires write locks on ALL shards in ascending order (0 → shard_count-1).
// Used for operations that modify the entire container state (e.g., destroy_all).
//
// 死锁安全性：见 rlock_all 的注释。lock(key) 只获取单个分片锁，
// 不会与 lock_all 形成循环等待。
//
// ⚠️ 警告：同一线程不能先持有 rlock(key) 再调用 lock_all()，
// 因为 lock_all 会尝试获取该分片的写锁，而 RwMutex 不支持
// 同一线程在持有读锁时获取写锁（读锁升级），会导致自死锁。
//
// ⚠️ Warning: A thread must not hold rlock(key) and then call lock_all(),
// because lock_all will try to acquire a write lock on that shard, and
// RwMutex does not support lock upgrade (read→write on same thread),
// which would cause a self-deadlock.
pub fn (mut sm ShardedRwMutex) lock_all() {
	for i in 0 .. sm.shards.len {
		sm.shards[i].@lock()
	}
}

// unlock_all releases write locks on all shards.
pub fn (mut sm ShardedRwMutex) unlock_all() {
	for i in 0 .. sm.shards.len {
		sm.shards[i].unlock()
	}
}

// ── Per-Bean Lock for Singleton Instantiation ──

// BeanLock provides per-bean locking for safe singleton instantiation.
// This prevents the "thundering herd" problem when multiple goroutines
// try to resolve the same lazy singleton simultaneously.
//
// Spring equivalent: DefaultSingletonBeanRegistry's singletonObjects lock
@[heap]
pub struct BeanLock {
pub mut:
	locks map[string]&sync.Mutex
mut:
	mu sync.RwMutex
}

// new_bean_lock creates an empty BeanLock.
pub fn new_bean_lock() &BeanLock {
	return &BeanLock{
		locks: map[string]&sync.Mutex{}
	}
}

// lock acquires the per-bean mutex, creating it if necessary.
// This ensures only one goroutine can instantiate a given singleton at a time.
//
// Uses double-checked locking pattern:
//   1. Read lock → check if Mutex exists → hit: acquire it
//   2. Miss: release read lock → acquire write lock → double-check → create → release write lock
//
// Memory safety: V's sync.RwMutex provides implicit acquire/release memory
// barriers on lock/unlock operations, ensuring the double-checked locking
// pattern is safe — the write to bl.locks[bean_name] is visible to all
// threads after bl.mu.unlock(), and the read under bl.mu.rlock() sees
// the most recent value.
// 使用双检锁模式：读锁检查 → 未命中 → 写锁创建 → 双检。
// V 的 sync.RwMutex 在 lock/unlock 时提供隐式内存屏障，
// 保证双检锁模式的安全性。
pub fn (mut bl BeanLock) lock(bean_name string) {
	bl.mu.rlock()
	mut lk := bl.locks[bean_name] or {
		bl.mu.runlock()
		// Slow path: create the lock
		bl.mu.@lock()
		// Double-check after acquiring write lock
		mut new_lk := bl.locks[bean_name] or {
			created := &sync.Mutex{}
			bl.locks[bean_name] = created
			created
		}
		bl.mu.unlock()
		new_lk.@lock()
		return
	}
	bl.mu.runlock()
	lk.@lock()
}

// unlock releases the per-bean mutex.
pub fn (mut bl BeanLock) unlock(bean_name string) {
	bl.mu.rlock()
	mut lk := bl.locks[bean_name] or {
		bl.mu.runlock()
		return
	}
	bl.mu.runlock()
	lk.unlock()
}

// remove removes the per-bean lock entry (cleanup after singleton is created).
// This prevents memory leaks from accumulating lock entries for beans
// that have already been fully instantiated.
pub fn (mut bl BeanLock) remove(bean_name string) {
	bl.mu.@lock()
	defer { bl.mu.unlock() }
	bl.locks.delete(bean_name)
}

// lock_count returns the number of active per-bean locks.
pub fn (mut bl BeanLock) lock_count() int {
	bl.mu.rlock()
	defer { bl.mu.runlock() }
	return bl.locks.len
}

// cleanup removes all lock entries (called during shutdown).
pub fn (mut bl BeanLock) cleanup() {
	bl.mu.@lock()
	defer { bl.mu.unlock() }
	bl.locks = map[string]&sync.Mutex{}
}

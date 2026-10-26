module locking

// lock_sharding_test.v - LockManager 分片与无全局锁的回归验证
//
// 这些用例锁定三件事：
//   1. 分片是 key 的纯函数，同一 key 永远落在同一片
//   2. 不同分片的 key 并发时互不阻塞（这是"锁粒度最小"的可测定义）
//   3. 一次 lock/unlock 只触碰一把切片锁，ref_count 在上下界内
import time
import sync

// ============================================================
// 分片映射
// ============================================================

fn test_lock_shard_index_is_stable_and_in_range() {
	for key in ['a', 'user:123', '', 'xxxxxxxxxxxxxxxx', 'lock-key-cn'] {
		idx := lock_shard_index(key)
		assert idx >= 0
		assert idx < lock_shard_count
		assert lock_shard_index(key) == idx
	}
}

fn test_lock_shard_count_is_power_of_two() {
	assert lock_shard_count > 0
	assert (lock_shard_count & (lock_shard_count - 1)) == 0
}

// 找出分别落在两个不同分片上的两个 key。
fn two_keys_on_different_shards() (string, string) {
	base := lock_shard_index('probe-0')
	for i in 1 .. 1000 {
		k := 'probe-${i}'
		if lock_shard_index(k) != base {
			return 'probe-0', k
		}
	}
	return 'probe-0', 'probe-0'
}

// ============================================================
// 不同分片的 key 互不阻塞
// ============================================================

fn test_lock_manager_unrelated_shards_do_not_block() {
	mut lm := new_lock_manager()
	a, b := two_keys_on_different_shards()
	assert a != b

	// 持住 a 的锁，b 仍须能被立即拿到 —— 一把全局锁会在这里失败
	lm.lock(a)
	assert lm.try_lock(b) == true
	lm.unlock(b) or { assert false }
	lm.unlock(a) or { assert false }
}

fn test_lock_manager_same_key_still_excludes() {
	mut lm := new_lock_manager()
	lm.lock('shared')
	assert lm.try_lock('shared') == false
	lm.unlock('shared') or { assert false }
	assert lm.try_lock('shared') == true
	lm.unlock('shared') or { assert false }
}

// ============================================================
// 并发压力：分片后仍不丢引用
// ============================================================

fn test_lock_manager_concurrent_unrelated_keys() {
	mut lm := new_lock_manager()
	keys := 16
	rounds := 200

	mut wg := sync.new_waitgroup()
	for k in 0 .. keys {
		wg.add(1)
		spawn fn (mut m LockManager, key string, n int, mut wg sync.WaitGroup) {
			defer {
				wg.done()
			}
			for _ in 0 .. n {
				m.lock(key)
				m.unlock(key) or {}
			}
		}(mut lm, 'concurrent-${k}', rounds, mut wg)
	}
	wg.wait()

	// 所有引用归还后条目仍保留（unlock 不删），cleanup 才清掉
	assert lm.lock_count() == keys
	assert lm.cleanup_unused_locks() == keys
	assert lm.lock_count() == 0
}

// ============================================================
// 超时获取
// ============================================================

fn test_lock_manager_lock_with_timeout_fast_path() {
	mut lm := new_lock_manager()
	// 无竞争时第一次 try_lock 就成功，不走时钟轮询
	start := time.now().unix_milli()
	ok := lm.lock_with_timeout('free-key', 1000) or {
		assert false
		false
	}
	elapsed := time.now().unix_milli() - start
	assert ok == true
	assert elapsed < 50
	lm.unlock('free-key') or { assert false }
}

fn test_lock_manager_lock_with_timeout_gives_up_and_drops_ref() {
	mut lm := new_lock_manager()
	lm.lock('held')
	ok := lm.lock_with_timeout('held', 20) or {
		assert false
		false
	}
	assert ok == false
	// 超时路径必须把自己加的引用还回去，否则 unlock_and_cleanup 清不掉
	lm.unlock_and_cleanup('held') or { assert false }
	assert lm.lock_count() == 0
}

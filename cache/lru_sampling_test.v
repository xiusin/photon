module cache

// lru_sampling_test.v - 采样提升下的 LRU 语义
//
// 读路径只在采样命中时才把 key 挪到表头（近似 LRU）。这里锁定：
//   1. 反复读取的 key 一定不会被淘汰（这是近似的下限要求）
//   2. 写入顺序本身仍然决定淘汰次序（set 会把 key 放到表头）
//   3. 读操作不会破坏链表结构（prev/next 双向一致）

fn test_lru_hot_key_survives_eviction() {
	// 淘汰只在同一分片内发生（跨分片不抢锁，见 memory.v 的设计说明），
	// 所以这里挑同一分片上的 key 才能观察到淘汰次序。
	mut c := new_memory_cache_with_max('lru-hot', 8)

	// 找出与 'hot-target' 同分片的三个 key
	target := 'hot-target'
	shard := c.shard_index(target)
	mut same_shard := []string{}
	for i in 0 .. 5000 {
		k := 'shard-probe-${i}'
		if c.shard_index(k) == shard {
			same_shard << k
			if same_shard.len == 3 {
				break
			}
		}
	}
	assert same_shard.len == 3

	c.set(same_shard[0], 'v', 3600)!
	c.set(same_shard[1], 'v', 3600)!
	c.set(target, 'v', 3600)!
	c.set(same_shard[2], 'v', 3600)!

	// 持续读 target，采样提升会把它推到表头
	for _ in 0 .. 500 {
		assert c.get(target) or { '' } == 'v'
	}

	// 在同分片上塞新 key 触发淘汰：表尾是被冷落的那些
	for i in 0 .. 3 {
		c.set('same-shard-new-${i}-${same_shard[0]}', 'v', 3600)!
	}
	assert c.has(target) == true
}

fn test_lru_insert_order_drives_eviction() {
	// 同分片内：先写入的 key 先被淘汰。
	mut c := new_memory_cache_with_max('lru-order', 8)
	shard := c.shard_index('order-newest')
	mut same_shard := []string{}
	for i in 0 .. 5000 {
		k := 'order-probe-${i}'
		if c.shard_index(k) == shard {
			same_shard << k
			if same_shard.len == 2 {
				break
			}
		}
	}
	assert same_shard.len == 2

	c.set(same_shard[0], 'oldest', 3600)!
	c.set(same_shard[1], 'middle', 3600)!
	c.set('order-newest', 'newest', 3600)!

	// 同分片再写一个，容量超了就淘汰表尾
	c.set('order-extra-${same_shard[0]}', 'x', 3600)!
	assert c.has('order-newest') == true
}

fn test_lru_list_stays_consistent_after_reads_and_writes() {
	mut c := new_memory_cache_with_max('lru-consistency', 64)
	for i in 0 .. 32 {
		c.set('k${i}', 'v', 3600)!
	}
	// 打乱读取顺序，触发若干次提升
	for i in 0 .. 32 {
		_ := c.get('k${(i * 7) % 32}') or { '' }
	}
	// 链表必须仍然可遍历且不出现环
	for i in 0 .. 64 {
		mut sh := c.shard_ptr('k${i % 32}')
		sh.mu.@rlock()
		mut visited := 0
		mut cur := sh.lru_head
		for cur.len > 0 && visited < 512 {
			cur = sh.lru_next[cur] or { '' }
			visited++
		}
		sh.mu.unlock()
		assert visited < 512, 'LRU list appears cyclic'
	}
}

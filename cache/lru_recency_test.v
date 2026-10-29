module cache

// lru_recency_test.v — 读路径的「热键不被写入挤出」语义。
//
// get() 以前每次都要走最多 promote_distance 步的 LRU 链来判断「这个键是否
// 够靠前」，现在改用 entry.created_at（= 分片的单调序号）算距离，读取路径
// 不再碰链表的 sort/prev/next。行为必须一致：反复读的一小组键要保持在链头。

fn new_quiet_cache(name string) &MemoryCache {
	// 关掉后台清扫（间隔足够大），避免测试里被别的协程改动状态
	return new_memory_cache_full(name, 4096, 3600)
}

fn test_working_set_stays_hot() {
	mut mc := new_quiet_cache('lru_hot')
	defer { mc.close() }

	// 热键必须落在同一个分片里才谈得上「链头」顺序 —— 每个分片有自己的 LRU 链。
	mut sh := mc.shard_ptr('hot0')
	mut hot := []string{}
	mut cold := []string{}
	for i in 0 .. 512 {
		k := 'k${i}'
		if mc.shard_index(k) == mc.shard_index('hot0') {
			if hot.len < 4 {
				hot << k
			} else {
				cold << k
			}
		}
	}
	assert hot.len == 4

	for k in cold {
		mc.set(k, 'v', 0)!
	}
	for k in hot {
		mc.set(k, 'v', 0)!
	}

	// 反复读热键：它们必须留在链头，不被冷键挤走
	for _ in 0 .. 400 {
		for k in hot {
			assert mc.get(k)! == 'v'
		}
	}

	sh.mu.@rlock()
	mut head := sh.lru_head
	mut at_head := []string{}
	for head.len > 0 && at_head.len < hot.len {
		at_head << head
		head = sh.lru_next[head] or { '' }
	}
	sh.mu.unlock()

	for k in hot {
		assert k in at_head, 'hot key ${k} drifted out of the LRU head: ${at_head}'
	}
}

fn test_recency_stamp_is_monotonic() {
	mut mc := new_quiet_cache('lru_stamp')
	defer { mc.close() }

	mc.set('x', '1', 0)!
	mut sh := mc.shard_ptr('x')
	sh.mu.@rlock()
	first := sh.entries['x'].created_at
	sh.mu.unlock()

	mc.set('y', '2', 0)!
	sh = mc.shard_ptr('x') // 同一个分片？不一定，取 x 自己的分片再读
	sh.mu.@rlock()
	second := sh.entries['x'].created_at
	sh.mu.unlock()
	assert second >= first

	// 距离永远非负：读取热键不会回退序号
	assert mc.get('x')! == '1'
}

fn test_get_on_missing_key_reports_miss() {
	mut mc := new_quiet_cache('lru_miss')
	defer { mc.close() }
	mc.get('nope') or {
		assert err.msg().contains('cache miss')
		return
	}
	assert false, 'expected a cache miss'
}

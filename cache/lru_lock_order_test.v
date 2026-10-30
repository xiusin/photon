module cache

import time

fn same_shard_pair(mc &MemoryCache) (string, string) {
	mut seen := map[int]string{}
	for i in 0 .. 5000 {
		k := 'k${i}'
		idx := mc.shard_index(k)
		if idx in seen {
			return seen[idx], k
		}
		seen[idx] = k
	}
	return '', ''
}

// Regression guard for the lock order between the write path and LRU promotion.
//
// set()/delete()/eviction take shard.mu and then touch the LRU list; promote()
// used to take shard.lru_mu and then shard.mu — the reverse order, on the same
// shard. Two goroutines landing in those two windows deadlock the shard
// permanently, and the shard is on the read path of the whole framework.
fn test_set_vs_promote_same_shard_no_deadlock() {
	mut mc := new_memory_cache_with_max('dl', 1000000)
	hot, other := same_shard_pair(mc)
	assert mc.shard_index(hot) == mc.shard_index(other)

	for i in 0 .. 2000 {
		mc.set('filler-${i}', 'v', 60) or {}
	}
	mc.set(hot, 'v', 60) or {}

	mut mc_a := mc
	mut mc_b := mc
	done := chan bool{cap: 4}
	for _ in 0 .. 3 {
		spawn fn [mut mc_a] (ch chan bool, key string) {
			for _ in 0 .. 200000 {
				mc_a.get(key) or {}
			}
			ch <- true
		}(done, hot)
	}
	spawn fn [mut mc_b] (ch chan bool, key string) {
		for i in 0 .. 200000 {
			mc_b.set('${key}-${i}', 'v', 60) or {}
		}
		ch <- true
	}(done, other)

	mut timeout_hit := false
	for _ in 0 .. 4 {
		select {
			_ := <-done {}
			8 * time.second {
				timeout_hit = true
			}
		}
		if timeout_hit {
			break
		}
	}
	mc.clear() or {}
	assert !timeout_hit, 'ABBA deadlock: set() holds mu and wants lru_mu, promote() holds lru_mu and wants mu'
}

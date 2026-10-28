module locking

// redis_lock_integration_test.v — RedisDistributedLock + VRedisLockClient 真连真用
//
// 之前 RedisDistributedLock 完全没测过：release/renew 的实现是
// 「先 GET 拿 token，再拿 token 去比对」，token 根本不是本次 acquire
// 生成的那个 —— 任何客户端都能释放别人的锁。这里对着真 Redis 覆盖：
//   * acquire 互斥、TTL 到期自动释放
//   * 非持有者不能 release / renew
//   * 持有者 release / renew 生效
//   * LockManager 接线、guard 的 defer 释放
//
// Redis 不可达时整体 skip，不伪装成通过。
import net
import time

fn lock_redis_available() bool {
	mut conn := net.dial_tcp('127.0.0.1:6379') or { return false }
	conn.close() or {}
	return true
}

// new_test_lock_pair 返回同一 key 前缀下的两条独立客户端。
// 两条客户端 = 两个「进程」，用来验证持有者语义。
fn new_test_lock_pair() !(&VRedisLockClient, &VRedisLockClient, string) {
	if !lock_redis_available() {
		eprintln('redis_lock_integration_test: 127.0.0.1:6379 不可达，跳过')
		return error('redis not reachable')
	}
	prefix := 'photon:test:lock:${time.now().unix_nano()}:'
	c1 := new_vredis_lock_client(VRedisLockOpt{
		db:         14
		key_prefix: prefix
	})!
	c2 := new_vredis_lock_client(VRedisLockOpt{
		db:         14
		key_prefix: prefix
	})!
	return c1, c2, prefix
}

fn test_redis_lock_acquire_is_exclusive() ! {
	mut c1, mut c2, prefix := new_test_lock_pair()!
	defer {
		c1.del('${prefix}k') or {}
		c1.close()
		c2.close()
	}

	mut l1 := new_redis_lock(c1)
	mut l2 := new_redis_lock(c2)

	assert l1.acquire('${prefix}k', 5000)!
	// 同一把锁，第二个客户端必须拿不到。
	assert !l2.acquire('${prefix}k', 5000)!
	assert l2.is_locked('${prefix}k')
}

fn test_redis_lock_release_only_by_owner() ! {
	mut c1, mut c2, prefix := new_test_lock_pair()!
	defer {
		c1.del('${prefix}k') or {}
		c1.close()
		c2.close()
	}

	mut l1 := new_redis_lock(c1)
	mut l2 := new_redis_lock(c2)

	assert l1.acquire('${prefix}k', 5000)!
	// 非持有者 release 必须失败，且不能把持有者的锁删掉。
	assert !l2.release('${prefix}k')!
	assert l1.is_locked('${prefix}k')

	// 非持有者 renew 同样必须失败。
	assert !l2.renew('${prefix}k', 5000)!

	// 持有者自己释放成功。
	assert l1.release('${prefix}k')!
	assert !l1.is_locked('${prefix}k')
}

fn test_redis_lock_owner_can_renew() ! {
	mut c1, mut c2, prefix := new_test_lock_pair()!
	defer {
		c1.del('${prefix}k') or {}
		c1.close()
		c2.close()
	}

	mut l1 := new_redis_lock(c1)
	assert l1.acquire('${prefix}k', 300)!
	assert l1.renew('${prefix}k', 3000)!
	assert l1.is_locked('${prefix}k')
	assert l1.release('${prefix}k')!
}

fn test_redis_lock_ttl_expires() ! {
	mut c1, mut c2, prefix := new_test_lock_pair()!
	defer {
		c1.del('${prefix}k') or {}
		c1.close()
		c2.close()
	}

	mut l1 := new_redis_lock(c1)
	mut l2 := new_redis_lock(c2)
	assert l1.acquire('${prefix}k', 120)!
	time.sleep(200 * time.millisecond)
	// TTL 到期后锁自动消失，另一个客户端可以接手。
	assert !l1.is_locked('${prefix}k')
	assert l2.acquire('${prefix}k', 5000)!
	l2.release('${prefix}k') or {}
}

fn test_redis_lock_manager_wiring() ! {
	mut c1, mut c2, prefix := new_test_lock_pair()!
	defer {
		c1.del('${prefix}k') or {}
		c1.close()
		c2.close()
	}

	mut l1 := new_redis_lock(c1)
	mut lm := new_lock_manager()
	unsafe { lm.with_distributed_lock(l1) }

	assert lm.dist_lock('${prefix}k', 5000)!
	assert lm.dist_is_locked('${prefix}k')
	assert lm.dist_renew('${prefix}k', 5000)!
	assert lm.dist_unlock('${prefix}k')!
	assert !lm.dist_is_locked('${prefix}k')
}

fn test_redis_lock_guard_releases_on_error() ! {
	mut c1, mut c2, prefix := new_test_lock_pair()!
	defer {
		c1.del('${prefix}k') or {}
		c1.close()
		c2.close()
	}

	mut l1 := new_redis_lock(c1)
	mut lm := new_lock_manager()
	unsafe { lm.with_distributed_lock(l1) }

	// callback 返回 error，defer 必须把锁放掉。
	if _ := lm.with_distributed_lock_guard('${prefix}k', 5000, fn () ! {
		return error('boom')
	})
	{
		assert false, 'guard must propagate the callback error'
	}
	assert !lm.dist_is_locked('${prefix}k'), 'lock leaked after callback error'
}

fn test_redis_lock_missing_backend_errors() {
	mut lm := new_lock_manager()
	if _ := lm.dist_lock('k', 1000) {
		assert false, 'dist_lock without a backend must fail'
	} else {
		assert err.msg().contains('no distributed lock backend')
	}
}

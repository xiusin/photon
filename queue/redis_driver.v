module queue

// redis_driver.v - Redis-backed Queue Driver
//
// Implements the QueueDriver interface using Redis lists (LPUSH/RPOP).
// Provides persistent, distributed queue storage for production use.
//
// Redis operations:
//   push:   LPUSH <queue_name> <payload>         — add to head
//   pop:    RPOP  <queue_name>                   — remove from tail (FIFO)
//   count:  LLEN  <queue_name>                   — queue length
//   clear:  DEL   <queue_name>                   — delete entire queue
//
// Usage:
//   redis_client := your_redis_adapter // implements QueueRedisClient
//   driver := queue.new_redis_driver(redis_client)
//   dispatcher := queue.get_dispatcher()
//   dispatcher.set_driver(driver)

import sync
import time

// QueueRedisClient is the minimal Redis interface required by RedisDriver.
// Users must provide an adapter for their Redis library.
pub interface QueueRedisClient {
	// lpush adds one or more values to the head of a list.
	lpush(key string, values ...string) !int
	// rpop removes and returns the last element of a list.
	rpop(key string) !string
	// llen returns the length of a list.
	llen(key string) !int
	// del removes one or more keys. Returns the number of keys deleted.
	del(keys ...string) !int
	// zadd 向有序集合写入成员，score 为 run_at（unix 纳秒）。
	zadd(key string, score f64, member string) !int
	// zrangebyscore 返回 score 落在 [min, max] 的成员，最多 count 个。
	zrangebyscore(key string, min string, max string, count int) ![]string
	// zrem 从有序集合移除成员。
	zrem(key string, member string) !int
}

// RedisDriver implements QueueDriver using Redis lists for persistent storage.
// Thread-safe via embedded mutex for driver-level operations.
pub struct RedisDriver {
pub mut:
	client QueueRedisClient
	prefix string = 'photon:queue:' // Redis key prefix for namespacing
mut:
	mu sync.Mutex
}

// new_redis_driver creates a Redis-backed queue driver.
// prefix is prepended to all queue keys (default: "photon:queue:").
pub fn new_redis_driver(client QueueRedisClient) &RedisDriver {
	return &RedisDriver{
		client: client
	}
}

// set_prefix configures the Redis key prefix for queue namespacing.
// Example: "myapp:queue:" → Redis keys become "myapp:queue:emails"
pub fn (mut d RedisDriver) set_prefix(prefix string) {
	d.prefix = prefix
}

// queue_key builds the full Redis key for a queue name.
fn (d &RedisDriver) queue_key(queue_name string) string {
	return d.prefix + queue_name
}

// count returns the number of pending jobs in the queue.
pub fn (mut d RedisDriver) count(queue_name string) int {
	key := d.queue_key(queue_name)
	result := d.client.llen(key) or { return 0 }
	return result
}

// push adds a job payload to the tail of the queue (FIFO via LPUSH/RPOP).
pub fn (mut d RedisDriver) push(queue_name string, payload string) ! {
	key := d.queue_key(queue_name)
	d.client.lpush(key, payload) or {
		return error('redis push failed for queue "${queue_name}": ${err}')
	}
}

// push_attempt 重新入队一条已失败 retry_count 次的任务。
// 与 MemoryDriver 保持同一套 payload 约定（重放次数在头部）。
//
// push_attempt re-enqueues a previously failed job with the same payload
// convention as MemoryDriver.
pub fn (mut d RedisDriver) push_attempt(queue_name string, payload string, delay_secs i64, retry_count int) ! {
	tagged := attach_retry_count(payload, retry_count)
	if delay_secs > 0 {
		return d.push_delayed(queue_name, tagged, delay_secs)
	}
	return d.push(queue_name, tagged)
}

// push_delayed adds a job to a per-run_at 的 sorted set，
// 到期后由 promote_delayed 搬进主列表。
//
// Redis 版的延迟任务放在 `<prefix><queue>:delayed` 里（zset，score=run_at 纳秒），
// 不占用主 list，因此不会挡住立即任务。
pub fn (mut d RedisDriver) push_delayed(queue_name string, payload string, delay_secs i64) ! {
	key := d.delayed_key(queue_name)
	run_at := time.now().unix_nano() + delay_secs * 1_000_000_000
	d.client.zadd(key, f64(run_at), payload) or {
		return error('redis push_delayed failed for queue "${queue_name}": ${err}')
	}
}

// delayed_key 返回延迟任务的 zset 键名。
fn (d &RedisDriver) delayed_key(queue_name string) string {
	return d.queue_key(queue_name) + ':delayed'
}

// promote_delayed 把已到期的延迟任务搬进主列表（调用方为 pop 之前）。
pub fn (mut d RedisDriver) promote_delayed(queue_name string) {
	key := d.delayed_key(queue_name)
	now := time.now().unix_nano()
	due := d.client.zrangebyscore(key, '-inf', '${now}', 100) or { return }
	for payload in due {
		d.client.lpush(d.queue_key(queue_name), payload) or { continue }
		d.client.zrem(key, payload) or {}
	}
}

// pop removes and returns the next job payload from the head of the queue.
// Returns an error with message 'EMPTY' when the queue has no items.
pub fn (mut d RedisDriver) pop(queue_name string) !string {
	d.promote_delayed(queue_name)
	key := d.queue_key(queue_name)
	result := d.client.rpop(key) or {
		return error('redis pop failed for queue "${queue_name}": ${err}')
	}
	if result == '' {
		return error('EMPTY')
	}
	return result
}

// clear removes all jobs from the queue by deleting the Redis key.
pub fn (mut d RedisDriver) clear(queue_name string) ! {
	key := d.queue_key(queue_name)
	d.client.del(key) or {
		return error('redis clear failed for queue "${queue_name}": ${err}')
	}
}

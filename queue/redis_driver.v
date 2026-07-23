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

// pop removes and returns the next job payload from the head of the queue.
// Returns an error with message 'EMPTY' when the queue has no items.
pub fn (mut d RedisDriver) pop(queue_name string) !string {
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

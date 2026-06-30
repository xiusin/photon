module cache

import xiusin.vredis
import time

// redis_cache.v - Redis Cache Implementation
//
// Provides a Redis-backed cache that implements the Cache interface.
// Uses vredis connection pool for high-concurrency scenarios.
// Supports TTL, key scanning, and all standard cache operations.

// RedisCacheConfig configures a Redis-backed cache.
// All fields have sensible defaults matching a localhost Redis on port 6379.
@[params]
pub struct RedisCacheConfig {
pub:
	name             string = 'redis'
	host             string = '127.0.0.1'
	port             int    = 6379
	db               u32
	username         string
	password         string
	read_timeout     int = 10 // seconds
	write_timeout    int = 10 // seconds
	// Pool settings
	max_active       int = 10
	idle_timeout     int = 600 // seconds
	max_conn_life    int = 600 // seconds
	key_prefix       string   // optional prefix for all keys (e.g. 'photon:')
	test_on_borrow   bool = true // ping connection on borrow
}

// RedisStore is a Redis-backed implementation of the Cache interface.
// Uses a connection pool for concurrent access.
pub struct RedisStore {
pub:
	name       string
	key_prefix string
mut:
	pool &vredis.Pool = unsafe { nil }
}

// new_redis_cache creates a Redis-backed cache with the given configuration.
// It initializes a connection pool and validates connectivity with a ping.
pub fn new_redis_cache(config RedisCacheConfig) !&RedisStore {
	opts := vredis.ConnOpts{
		host:          config.host
		port:          config.port
		db:            config.db
		username:      config.username
		requirepass:   config.password
		read_timeout:  if config.read_timeout > 0 { time.second * config.read_timeout } else { time.second * 10 }
		write_timeout: if config.write_timeout > 0 { time.second * config.write_timeout } else { time.second * 10 }
	}

	// Verify connectivity before creating the pool.
	mut test_conn := vredis.new_client(opts)!
	defer {
		test_conn.close() or {}
	}
	if !test_conn.ping()! {
		return error('redis: ping failed for ${config.host}:${config.port}')
	}

	pool_opt := vredis.PoolOpt{
		max_active: config.max_active
		idle_timeout: config.idle_timeout
		max_conn_life_time: config.max_conn_life
		dial: fn [opts] () !&vredis.Redis {
			return vredis.new_client(opts)!
		}
		test_on_borrow: if config.test_on_borrow {
			fn (mut conn vredis.ActiveRedisConn) ! {
				conn.ping()!
			}
		} else {
			unsafe { nil }
		}
	}

	pool := vredis.new_pool(pool_opt)!

	return &RedisStore{
		name:       config.name
		key_prefix: config.key_prefix
		pool:       pool
	}
}

// prefix_key prepends the configured key prefix (if any).
fn (rc &RedisStore) prefix_key(key string) string {
	if rc.key_prefix.len == 0 {
		return key
	}
	return '${rc.key_prefix}${key}'
}

// borrow gets a connection from the pool. Caller must defer release.
@[inline]
fn (mut rc RedisStore) borrow() !&vredis.ActiveRedisConn {
	return rc.pool.get()
}

// get retrieves a value from Redis. Returns error on cache miss.
pub fn (mut rc RedisStore) get(key string) !string {
	mut conn := rc.borrow()!
	defer {
		conn.release()
	}

	full_key := rc.prefix_key(key)
	val := conn.get(full_key) or {
		if err.msg() == vredis.err_nil.msg() {
			return error('cache miss: key "${key}" not found')
		}
		return err
	}
	return val
}

// set stores a value in Redis with TTL (seconds). TTL of 0 means no expiry.
pub fn (mut rc RedisStore) set(key string, value string, ttl_seconds int) ! {
	mut conn := rc.borrow()!
	defer {
		conn.release()
	}

	full_key := rc.prefix_key(key)
	if ttl_seconds > 0 {
		conn.setex(full_key, ttl_seconds, value)!
	} else {
		conn.set(full_key, value)!
	}
}

// delete removes a key from Redis.
pub fn (mut rc RedisStore) delete(key string) ! {
	mut conn := rc.borrow()!
	defer {
		conn.release()
	}

	full_key := rc.prefix_key(key)
	conn.del(full_key)!
}

// has checks if a key exists in Redis.
pub fn (mut rc RedisStore) has(key string) bool {
	mut conn := rc.borrow() or { return false }
	defer {
		conn.release()
	}

	full_key := rc.prefix_key(key)
	exists := conn.exists(full_key) or { return false }
	return exists
}

// clear flushes the current Redis database.
// Note: this clears ALL keys in the database, not just prefixed ones.
pub fn (mut rc RedisStore) clear() ! {
	mut conn := rc.borrow()!
	defer {
		conn.release()
	}

	conn.flushdb()!
}

// keys returns all keys matching the prefix pattern.
pub fn (mut rc RedisStore) keys() []string {
	mut conn := rc.borrow() or { return []string{} }
	defer {
		conn.release()
	}

	pattern := if rc.key_prefix.len > 0 { '${rc.key_prefix}*' } else { '*' }
	all_keys := conn.keys(pattern) or { return []string{} }

	// Strip prefix from returned keys for consistency with the Cache interface.
	if rc.key_prefix.len > 0 && all_keys.len > 0 {
		mut result := []string{cap: all_keys.len}
		for k in all_keys {
			if k.starts_with(rc.key_prefix) {
				result << k[rc.key_prefix.len..]
			} else {
				result << k
			}
		}
		return result
	}
	return all_keys
}

// size returns the number of keys in the current Redis database.
pub fn (mut rc RedisStore) size() int {
	mut conn := rc.borrow() or { return 0 }
	defer {
		conn.release()
	}

	return conn.dbsize() or { 0 }
}

// close shuts down the connection pool. After calling close, the cache
// is no longer usable.
pub fn (mut rc RedisStore) close() {
	rc.pool.close()
}

// ping checks connectivity to the Redis server.
pub fn (mut rc RedisStore) ping() !bool {
	mut conn := rc.borrow()!
	defer {
		conn.release()
	}
	return conn.ping()!
}

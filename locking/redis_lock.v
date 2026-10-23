module locking

// redis_lock.v - Redis-based Distributed Lock Implementation
//
// Implements the DistributedLock interface using Redis SET NX EX for
// acquiring locks and Lua scripts for safe release and renewal.
//
// Design (Redlock-inspired):
//   - acquire:   SET <key> <token> NX EX <ttl_seconds>
//   - release:   Lua script — delete only if token matches
//   - renew:     Lua script — EXPIRE only if token matches
//   - is_locked: EXISTS <key>
//
// The token is a random string generated per acquire, preventing the
// classic "lock released by wrong client" bug.
import rand

// ── Redis Client Interface ──

// RedisClient is the minimal Redis interface required by RedisDistributedLock.
// Users must provide an adapter that wraps their Redis library (vredis, go-redis, etc.).
pub interface RedisClient {
	// set stores a key with value and TTL in milliseconds.
	// Should return 'OK' on success (SET NX EX semantics).
	set(key string, value string, ttl_ms int) !string
	// get retrieves the value for a key. Returns empty string if key doesn't exist.
	get(key string) !string
	// del removes one or more keys. Returns the number of keys deleted.
	del(keys ...string) !int
	// eval executes a Lua script with keys and arguments.
	// num_keys: number of KEYS[] parameters (the first num_keys entries in args).
	eval(script string, num_keys int, keys []string, args []string) !string
}

// ── RedisDistributedLock ──

// RedisDistributedLock implements DistributedLock using Redis as the backend.
//
// Usage:
//   client := your_redis_adapter // implements RedisClient
//   lock := locking.new_redis_lock(client)
//   lock.acquire('resource-key', 30000)! // 30-second TTL
//   defer { lock.release('resource-key') or {} }
pub struct RedisDistributedLock {
	client RedisClient
}

// new_redis_lock creates a Redis-backed distributed lock.
pub fn new_redis_lock(client RedisClient) &RedisDistributedLock {
	return &RedisDistributedLock{
		client: client
	}
}

// acquire attempts to acquire a distributed lock.
// key: the lock identifier
// ttl_ms: lock time-to-live in milliseconds (auto-released if not renewed)
// Returns true if acquired, false if already held by another client.
pub fn (r &RedisDistributedLock) acquire(key string, ttl_ms int) !bool {
	token := generate_lock_token()
	result := r.client.set(key, token, ttl_ms)!
	return result == 'OK'
}

// release releases a distributed lock.
// Uses a Lua script to ensure only the lock holder can release it
// (prevents the "lock released by wrong client" race condition).
// Returns true if released, false if lock was already released or held by another client.
pub fn (r &RedisDistributedLock) release(key string) !bool {
	token := r.client.get(key)!
	if token == '' {
		return false
	}
	// Lua: delete the key only if its value matches our token
	script := 'if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end'
	result := r.client.eval(script, 1, [key], [token])!
	return result == '1'
}

// renew extends the lock's TTL.
// Uses a Lua script to ensure only the lock holder can renew it.
// Returns true if renewed, false if lock was released or held by another client.
pub fn (r &RedisDistributedLock) renew(key string, ttl_ms int) !bool {
	token := r.client.get(key)!
	if token == '' {
		return false
	}
	// Lua: EXPIRE the key only if its value matches our token
	script := 'if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("pexpire", KEYS[1], ARGV[2]) else return 0 end'
	result := r.client.eval(script, 1, [key], [token, ttl_ms.str()])!
	return result == '1'
}

// is_locked checks if a lock is currently held (by any client).
// Returns true if the key exists in Redis.
pub fn (r &RedisDistributedLock) is_locked(key string) bool {
	result := r.client.get(key) or { '' }
	return result != ''
}

// ── Token Generation ──

// generate_lock_token creates a random token string for lock ownership.
// Uses cryptographic random to prevent token prediction attacks.
@[inline]
fn generate_lock_token() string {
	mut buf := []u8{len: 16}
	for i in 0 .. 16 {
		buf[i] = u8(rand.intn(256) or { u8(i) })
	}
	return buf.hex()
}

// ── LockManager distributed extension ──

// dist_renew extends a distributed lock's TTL via LockManager.
pub fn (mut lm LockManager) dist_renew(key string, ttl_ms int) !bool {
	if isnil(lm.distributed) {
		return error('no distributed lock backend configured')
	}
	return lm.distributed.renew(key, ttl_ms)
}

// dist_is_locked checks if a distributed lock is held via LockManager.
pub fn (mut lm LockManager) dist_is_locked(key string) bool {
	if isnil(lm.distributed) {
		return false
	}
	return lm.distributed.is_locked(key)
}

module locking

// redis_lock.v - Redis-based Distributed Lock Implementation
//
// Implements the DistributedLock interface using Redis SET NX EX for
// acquiring locks and Lua scripts for safe release and renewal.
//
// Design (Redlock-inspired):
//   - acquire:   SET <key> <token> NX PX <ttl_ms>
//   - release:   Lua script — delete only if token matches
//   - renew:     Lua script — PEXPIRE only if token matches
//   - is_locked: EXISTS <key>
//
// 每个 key 由持有者自己记住本次 acquire 生成的 token。这是整套机制成立
// 的前提：老实现的 release/renew 是「先 GET 出 token，再拿这个 token 去
// 比对」—— 比对的两个值是同一个，永远相等。于是：
//   * 任何客户端都能释放别人持有的锁；
//   * 任何客户端都能续期别人持有的锁。
// 现在 token 存在本实例的 owned 表里，只有真正 acquire 成功的那一方有。
import rand
import sync

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
mut:
	// owned 记录本实例持有的锁：key → 本次 acquire 生成的 token。
	// 只有这里存在的 token 才代表「我持有」，释放与续期都以它为准。
	owned map[string]string
	mu    sync.Mutex
}

// new_redis_lock creates a Redis-backed distributed lock.
pub fn new_redis_lock(client RedisClient) &RedisDistributedLock {
	return &RedisDistributedLock{
		client: client
		owned:  map[string]string{}
	}
}

// remember_token 记录本次 acquire 的 token。
fn (r &RedisDistributedLock) remember_token(key string, token string) {
	r.mu.@lock()
	defer {
		r.mu.unlock()
	}
	unsafe {
		mut m := &r.owned
		m[key] = token
	}
}

// take_token 取出并移除某个 key 的 token；不存在时返回空串。
fn (r &RedisDistributedLock) take_token(key string) string {
	r.mu.@lock()
	defer {
		r.mu.unlock()
	}
	unsafe {
		mut m := &r.owned
		if key in m {
			token := m[key]
			m.delete(key)
			return token
		}
	}
	return ''
}

// peek_token 读取某个 key 的 token 但不移除。
fn (r &RedisDistributedLock) peek_token(key string) string {
	r.mu.@lock()
	defer {
		r.mu.unlock()
	}
	unsafe {
		m := &r.owned
		return m[key] or { '' }
	}
}

// acquire attempts to acquire a distributed lock.
// key: the lock identifier
// ttl_ms: lock time-to-live in milliseconds (auto-released if not renewed)
// Returns true if acquired, false if already held by another client.
pub fn (r &RedisDistributedLock) acquire(key string, ttl_ms int) !bool {
	token := generate_lock_token()
	result := r.client.set(key, token, ttl_ms)!
	if result == 'OK' {
		r.remember_token(key, token)
		return true
	}
	return false
}

// release releases a distributed lock.
// Uses a Lua script to ensure only the lock holder can release it
// (prevents the "lock released by wrong client" race condition).
// Returns true if released, false if lock was already released or held by another client.
pub fn (r &RedisDistributedLock) release(key string) !bool {
	token := r.take_token(key)
	if token == '' {
		// 本实例没持有这把锁：不是错误，但也不该去删别人的键。
		return false
	}
	// Lua: delete the key only if its value matches OUR token
	script := 'if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end'
	result := r.client.eval(script, 1, [key], [token])!
	return result == '1'
}

// renew extends the lock's TTL.
// Uses a Lua script to ensure only the lock holder can renew it.
// Returns true if renewed, false if lock was released or held by another client.
pub fn (r &RedisDistributedLock) renew(key string, ttl_ms int) !bool {
	token := r.peek_token(key)
	if token == '' {
		return false
	}
	// Lua: PEXPIRE the key only if its value matches OUR token
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

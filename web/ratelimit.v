module web

// ratelimit.v - Rate Limiting (Laravel RateLimiter inspired)
//
// Performance design:
//   - Uses sharded locks (default 64 shards) instead of a single global lock.
//   - Each key is hashed to a shard, so different keys never contend.
//   - This allows thousands of concurrent rate-limit checks with minimal contention.
//   - Read-only operations (remaining, retry_after) use the same shard lock
//     but complete in O(1) without iterating the full map.
import time
import sync

// fnv1a_str computes the FNV-1a 64-bit hash of a string by iterating over its
// bytes directly (no `s.bytes()` allocation), for hot paths such as shard
// selection.
//
// 为什么本地实现：分片选择在每次限流判定时都要跑，逐字节扫描不必绕一层跨
// 模块调用。（历史原因是为绕开 `support` 双重身份那个构建缺陷，该缺陷已随
// 模块改名 `strutil` 从根上消掉，见 ARCHITECTURE.md 8.10。）
@[direct_array_access; inline]
fn fnv1a_str(s string) u64 {
	mut hash := u64(14695981039346656037) // FNV offset basis
	for i in 0 .. s.len {
		hash = (hash ^ u64(s[i])) * u64(1099511628211) // FNV prime
	}
	return hash
}

// shard_count is the default number of lock shards.
// Must be a power of 2 for fast modulo via bitwise AND.
const shard_count = 64

// max_attempts_per_key bounds the attempts slice per key to prevent
// unbounded memory growth from high-traffic keys.
const max_attempts_per_key = 10000

// RateLimiter implements rate limiting with attempt tracking (thread-safe).
// Uses sharded locking for high-concurrency performance.
@[heap]
pub struct RateLimiter {
pub mut:
	attempts map[string][]i64
mut:
	shards []sync.Mutex
}

// new_rate_limiter creates a new RateLimiter with sharded locks.
pub fn new_rate_limiter() &RateLimiter {
	mut shards := []sync.Mutex{len: shard_count}
	unsafe {
		for i in 0 .. shards.len {
			shards[i].init()
		}
	}
	return &RateLimiter{
		attempts: map[string][]i64{}
		shards:   shards
	}
}

// shard_for returns the shard index for a given key.
// Uses FNV-1a hash for fast, uniform distribution.
@[inline]
fn (r &RateLimiter) shard_for(key string) int {
	// FNV-1a 64-bit hash, zero-allocation (local impl, see fnv1a_str)
	return int(fnv1a_str(key) & u64(shard_count - 1))
}

// effective_decay normalizes a decay window to a positive number of seconds.
//
// 0（或负数）不该被理解成「窗口无限长」。`now - ts < 0` 恒为 false，于是
// 所有记录都被判为过期：`hit()` 记的次数一扫而空，`too_many_attempts()`
// 永远说不超限 —— 一条彻底不生效的限流，且与正常限流的表现无从区分。
// 而 `throttle_middleware(max_attempts, decay_minutes: 0)` 恰好算出 0，
// 是配置里最常见的一种笔误。这里按 1 秒处理，让限流仍然成立。
fn effective_decay(decay_seconds i64) i64 {
	return if decay_seconds > 0 { decay_seconds } else { 1 }
}

// count_within returns how many of `attempts` fall inside the decay window
// ending at `now`.
//
// 窗口是滑动的：`now - ts < decay`。原来用 `now - ts >= decay` 判过期，
// 两秒整的那一刻既不算有效、也不算刚过期，于是 `cleanup_expired()` 在
// 那个边界上一条都删不掉，已经死掉的 key 会一直留在 map 里 ——
// 一条只在整秒边界出现的泄漏。
fn count_within(attempts []i64, now i64, decay_seconds i64) int {
	mut n := 0
	for ts in attempts {
		// 负差值（时钟回拨/未来时间戳）按有效计：宁可多算一次，
		// 也不要因为时钟问题把限流整体放空。
		if now - ts < decay_seconds {
			n++
		}
	}
	return n
}

// too_many_attempts checks if the key has exceeded the max attempts
// within the decay window (in seconds). Expired attempts are automatically
// cleaned from the attempt list.
//
// Only locks the shard for this key — other keys are unaffected.
pub fn (mut r RateLimiter) too_many_attempts(key string, max_attempts int, decay_seconds i64) bool {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	mut attempts := r.attempts[key] or { return false }
	now := time.now().unix()
	decay := effective_decay(decay_seconds)

	// Filter out expired attempts (outside the decay window)
	mut valid := []i64{cap: attempts.len}
	for ts in attempts {
		if now - ts < decay {
			valid << ts
		}
	}

	if valid.len == 0 {
		r.attempts.delete(key)
		return false
	}

	r.attempts[key] = valid
	// 与 hit_and_record() 同一个边界：第 max 次仍在配额内，第 max+1 次才算超限。
	// 旧实现写 `>= max`，于是 max_attempts=3 时只放得过去两次 ——
	// 运维按配置理解会有整整一次的行为差，而且只在边界上出现。
	return valid.len > max_attempts
}

// hit records an attempt for the given key.
// Only locks the shard for this key.
// Bounds the attempts slice to prevent unbounded memory growth.
pub fn (mut r RateLimiter) hit(key string) {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	now := time.now().unix()
	mut attempts := r.attempts[key] or { []i64{} }
	attempts << now
	// Bound the slice: trim oldest entries if over threshold
	if attempts.len > max_attempts_per_key {
		attempts = attempts[attempts.len - max_attempts_per_key..].clone()
	}
	r.attempts[key] = attempts
}

// remaining returns the number of remaining attempts within the decay window.
// Only locks the shard for this key.
//
// Bug fix: previously this method counted ALL attempts (including expired ones),
// causing the remaining count to stay artificially low after the decay window
// elapsed. Now expired attempts are filtered out before counting, consistent
// with too_many_attempts().
pub fn (mut r RateLimiter) remaining(key string, max_attempts int, decay_seconds i64) int {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	// 没有记录 = 一次都没用过，剩余配额就是配额本身。
	// 这里原来写的是 `or { return 0 }` —— 和「配额已用尽」返回同一个 0，
	// 于是运维接口对一个刚上线的 key 报「已用尽」，告警直接误报。
	attempts := r.attempts[key] or { return if max_attempts > 0 { max_attempts } else { 0 } }
	now := time.now().unix()

	// Filter out expired attempts (same logic as too_many_attempts)
	valid_count := count_within(attempts, now, effective_decay(decay_seconds))

	remaining := max_attempts - valid_count
	if remaining < 0 {
		return 0
	}
	return remaining
}

// retry_after returns seconds until the earliest attempt decays.
// Only locks the shard for this key.
pub fn (mut r RateLimiter) retry_after(key string, decay_seconds i64) i64 {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	attempts := r.attempts[key] or { return 0 }
	if attempts.len == 0 {
		return 0
	}
	now := time.now().unix()
	decay := effective_decay(decay_seconds)
	// 窗口里最早的**未过期**那一条。原来取 attempts[0]，
	// 而 attempts 里存的是「按写入顺序」的全部记录，过期记录只在
	// too_many_attempts() / hit_and_record() 里被顺手清掉 ——
	// 只要有别的 key 抢着写、或者这个 key 刚跨过窗口，
	// attempts[0] 就是一条已经死掉的记录，算出来的 retry_after 是 0。
	// 于是 429 响应里写的「retry after 0s」，调用方立刻重试、立刻再被拒。
	mut earliest := i64(0)
	mut found := false
	for ts in attempts {
		if now - ts >= decay {
			continue
		}
		if !found || ts < earliest {
			earliest = ts
			found = true
		}
	}
	if !found {
		return 0
	}
	decay_time := earliest + decay
	if now >= decay_time {
		return 0
	}
	return decay_time - now
}

// clear removes rate limit data for a key.
// Only locks the shard for this key.
pub fn (mut r RateLimiter) clear(key string) {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }
	r.attempts.delete(key)
}

// clear_all removes all rate limit data.
// Acquires all shard locks in order to prevent deadlock.
pub fn (mut r RateLimiter) clear_all() {
	for i in 0 .. shard_count {
		r.shards[i].@lock()
	}
	// Clear the entire map at once
	r.attempts = map[string][]i64{}
	for i in 0 .. shard_count {
		r.shards[shard_count - 1 - i].unlock()
	}
}

// clear_expired removes expired attempts from all keys.
// Acquires all shard locks in order to prevent deadlock.
pub fn (mut r RateLimiter) clear_expired(decay_seconds i64) {
	for i in 0 .. shard_count {
		r.shards[i].@lock()
	}
	now := time.now().unix()
	mut keys_to_delete := []string{}
	decay := effective_decay(decay_seconds)
	for key, attempts in r.attempts {
		mut valid := []i64{}
		for ts in attempts {
			if now - ts < decay {
				valid << ts
			}
		}
		if valid.len == 0 {
			keys_to_delete << key
		} else {
			r.attempts[key] = valid
		}
	}
	for key in keys_to_delete {
		r.attempts.delete(key)
	}
	for i in 0 .. shard_count {
		r.shards[shard_count - 1 - i].unlock()
	}
}

// attempts returns the total number of recorded attempts for a key (including expired).
// Only locks the shard for this key.
//
// Note: this returns the raw count without expiry filtering. For the count of
// valid (non-expired) attempts, use attempts_within() instead.
pub fn (mut r RateLimiter) attempts(key string) int {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }
	a := r.attempts[key] or { return 0 }
	return a.len
}

// attempts_within returns the number of non-expired attempts for a key.
// Only locks the shard for this key.
pub fn (mut r RateLimiter) attempts_within(key string, decay_seconds i64) int {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }
	attempts := r.attempts[key] or { return 0 }
	now := time.now().unix()
	return count_within(attempts, now, effective_decay(decay_seconds))
}

// key_count returns the total number of tracked keys.
// Acquires all shard locks for a consistent snapshot.
pub fn (mut r RateLimiter) key_count() int {
	for i in 0 .. shard_count {
		r.shards[i].@lock()
	}
	count := r.attempts.len
	for i in 0 .. shard_count {
		r.shards[shard_count - 1 - i].unlock()
	}
	return count
}

// hit_and_record records a hit and checks if the limit is exceeded in one operation.
// More efficient than separate hit() + too_many_attempts() — only acquires the shard lock once.
// Bounds the attempts slice to prevent unbounded memory growth.
pub fn (mut r RateLimiter) hit_and_record(key string, max_attempts int, decay_seconds i64) bool {
	idx := r.shard_for(key)
	r.shards[idx].@lock()
	defer { r.shards[idx].unlock() }

	now := time.now().unix()
	decay := effective_decay(decay_seconds)

	// Record the hit
	mut attempts := r.attempts[key] or { []i64{} }
	attempts << now
	// Bound the slice, but never below what this window still needs to
	// remember. max_attempts_per_key 是个纯粹的防爆顶，可它原来连
	// 「窗口内还活着的记录」一起截：窗口 1 小时、max_attempts 20000 时，
	// 顶流 key 每秒 3 次，10000 条只装得下 55 分钟 —— 被截掉的那些
	// 恰恰是窗口里最老的、也是最早该失效的，于是有效计数在窗口中途
	// 回落，已经被拒的调用方重新被放行。上限至少要容得下 max_attempts
	// 本身，否则这个限流器的上限根本达不到。
	mut bound := max_attempts_per_key
	if max_attempts + 1 > bound {
		bound = max_attempts + 1
	}
	if attempts.len > bound {
		attempts = attempts[attempts.len - bound..].clone()
	}
	r.attempts[key] = attempts

	// Check if limit exceeded (filter expired)
	mut valid := []i64{cap: attempts.len}
	for ts in attempts {
		if now - ts < decay {
			valid << ts
		}
	}
	if valid.len > 0 {
		r.attempts[key] = valid
	}

	// 第 max 次许可，第 max+1 次拒绝 —— 与 too_many_attempts() 的
	// `valid.len >= max` 是同一个边界（旧实现写的是 `< max`，于是
	// 每次都少放一次：`hit_and_record(k, 1, ...)` 连第一次都过不去，
	// 而 throttle_middleware 用的正是这个函数）。
	//
	// `valid` 是「含本次」的计数，而 too_many_attempts() 判的是
	// `已记录的历史 >= max`，两者相差本次这一条。要给出互补的答案，
	// 这里必须按「扣除本次之后」的历史来判。
	//
	// 旧实现写的是 `valid.len < max_attempts`，对同一个 key 与
	// too_many_attempts() 永远差一拍：中间件已经放行的请求，在运维接口
	// 上看是「还有余量」；中间件拒掉的，在接口上看也许还没超。
	return valid.len - 1 < max_attempts
}

// resolve_rate_limit_key builds a rate limit key from prefix, user ID, and IP.
// Priority: user_id > ip > anonymous.
pub fn resolve_rate_limit_key(prefix string, user_id string, ip string) string {
	if user_id.len > 0 {
		return '${prefix}:${user_id}'
	}
	if ip.len > 0 {
		return '${prefix}:ip:${ip}'
	}
	return '${prefix}:anonymous'
}

// ── Fixed Window Rate Limiter ──

// FixedWindowEntry tracks a single fixed window.
pub struct FixedWindowEntry {
pub mut:
	count   int
	expires i64
}

// FixedWindowLimiter implements fixed-window rate limiting.
// Uses sharded locking for high-concurrency performance.
@[heap]
pub struct FixedWindowLimiter {
pub mut:
	windows map[string]FixedWindowEntry
mut:
	shards []sync.Mutex
}

// new_fixed_window_limiter creates a new FixedWindowLimiter.
pub fn new_fixed_window_limiter() &FixedWindowLimiter {
	mut shards := []sync.Mutex{len: shard_count}
	unsafe {
		for i in 0 .. shards.len {
			shards[i].init()
		}
	}
	return &FixedWindowLimiter{
		windows: map[string]FixedWindowEntry{}
		shards:  shards
	}
}

// shard_for returns the shard index for a given key.
@[inline]
fn (fw &FixedWindowLimiter) shard_for(key string) int {
	return int(fnv1a_str(key) & u64(shard_count - 1))
}

// max_windows bounds the windows map size to prevent unbounded memory
// growth from unique keys. When exceeded, expired entries are cleaned up.
const max_windows = 10000

// check returns true if the request is allowed within the rate limit.
// Only locks the shard for this key.
// Performs lazy cleanup of expired windows when the map exceeds max_windows.
pub fn (mut fw FixedWindowLimiter) check(key string, max_requests int, window_seconds i64) bool {
	idx := fw.shard_for(key)
	fw.shards[idx].@lock()

	now := time.now().unix()
	mut entry := fw.windows[key] or { FixedWindowEntry{} }

	// Reset if window expired
	//
	// 窗口长度必须为正数。原来 `window_seconds <= 0` 时 `expires = now + 0`，
	// 而下一轮 check 里 `now >= entry.expires` 立刻成立 —— 每次请求都重新
	// 开一扇新窗、计数归零，`max_requests` 形同不存在。配置里少写一个 0
	// 或者把"不限流"写成 0，得到的不是不限流，是**完全不限流且毫无提示**。
	// 这里给非正窗口回落到 1 秒，限流行为仍然成立。
	effective_window := if window_seconds > 0 { window_seconds } else { 1 }
	if now >= entry.expires {
		entry.count = 0
		entry.expires = now + effective_window
	}

	entry.count++
	result := entry.count <= max_requests
	fw.windows[key] = entry

	// Check if lazy cleanup is needed (without holding the shard lock)
	need_cleanup := fw.windows.len > max_windows

	fw.shards[idx].unlock()

	// Lazy cleanup: remove expired entries when map is too large.
	// Done outside the single-shard lock to avoid deadlock with cleanup_expired()
	// which acquires all shard locks.
	if need_cleanup {
		fw.cleanup_expired()
	}

	return result
}

// cleanup_expired removes all expired window entries.
// Acquires all shard locks in order to prevent deadlock.
pub fn (mut fw FixedWindowLimiter) cleanup_expired() {
	for i in 0 .. shard_count {
		fw.shards[i].@lock()
	}
	now := time.now().unix()
	mut keys_to_remove := []string{}
	for key, entry in fw.windows {
		if now >= entry.expires {
			keys_to_remove << key
		}
	}
	for key in keys_to_remove {
		fw.windows.delete(key)
	}
	for i in 0 .. shard_count {
		fw.shards[shard_count - 1 - i].unlock()
	}
}

// get_remaining returns the remaining requests in the current window.
// Only locks the shard for this key.
pub fn (mut fw FixedWindowLimiter) get_remaining(key string, max_requests int, window_seconds i64) int {
	idx := fw.shard_for(key)
	fw.shards[idx].@lock()
	defer { fw.shards[idx].unlock() }

	now := time.now().unix()
	entry := fw.windows[key] or { return max_requests }

	// 与 check() 一致：非正窗口按 1 秒处理，否则这里会一直报「还剩满额」，
	// 而实际请求已经被 check() 放过去了。
	if now >= entry.expires {
		return max_requests
	}
	remaining := max_requests - entry.count
	if remaining < 0 {
		return 0
	}
	return remaining
}

// clear removes rate limit data for a key.
// Only locks the shard for this key.
pub fn (mut fw FixedWindowLimiter) clear(key string) {
	idx := fw.shard_for(key)
	fw.shards[idx].@lock()
	defer { fw.shards[idx].unlock() }
	fw.windows.delete(key)
}

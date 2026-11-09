module web

// session.v - Session Management (Spring Session / Laravel Session inspired)
//
// Provides server-side session management with pluggable backends.
// Supports cookie-based session IDs and flash data.
import veb
import net.http
import crypto.sha256
import encoding.hex
import crypto.rand as crand
import sync
import time



// ── Session Interface ──

// SessionRecord 是一次会话存储读取的完整结果。
//
// 为什么不是一个裸 map：闪存（flash）是「下一次请求才能读到」的数据，
// 它和普通会话数据必须分开存放 —— 存进去的那一次请求不该读到它，
// 读出来的那一次请求之后它就该消失。用两个 map 表达这两种生命周期，
// 比在同一个 map 里靠 key 前缀区分要难出错得多。
//
// SessionRecord is the full result of a store read.
// Flash data has a one-request lifetime, so it is kept apart from the
// regular session payload instead of being encoded into its keys.
pub struct SessionRecord {
pub:
	data  map[string]string
	flash map[string]string
}

// SessionStore is the interface for session storage backends.
pub interface SessionStore {
mut:
	// read 返回会话数据与待消费的闪存。
	// read returns the session payload plus the flash entries that were
	// written by the previous request and are still waiting to be consumed.
	read(session_id string) !SessionRecord
	// write 落盘会话数据与本次请求新写入的闪存。
	// write persists the payload and the flash entries written by this request.
	write(session_id string, data map[string]string, flash map[string]string, ttl_seconds int) !
	destroy(session_id string) !
	gc(max_age_seconds int) !
}

// ── Session ──

// Session represents an HTTP session with get/set/flash operations.
pub struct Session {
pub mut:
	id          string
	data        map[string]string
	flash_data  map[string]string
	old_flash   map[string]string // flash from previous request
	is_new      bool
	is_dirty    bool
	ttl_seconds int = 1800 // default 30 min
mut:
	mu sync.RwMutex
}

// new_session creates a new Session with the given ID.
pub fn new_session(id string) &Session {
	return &Session{
		id:         id
		data:       map[string]string{}
		flash_data: map[string]string{}
		old_flash:  map[string]string{}
		is_new:     true
		is_dirty:   false
	}
}

// get 检索 session 值。
// 在 SessionLock 保护下调用，返回 map 中的原始引用。
// V string 是不可变的，直接返回引用安全（零拷贝）。
//
// get retrieves a session value.
// Called under SessionLock protection, returns the original reference from the map.
// V strings are immutable, so returning a reference is safe (zero-copy).
pub fn (s &Session) get(key string) !string {
	unsafe { s.mu.rlock() }
	defer { unsafe { s.mu.runlock() } }
	if val := s.data[key] {
		return val // 零拷贝：V string 不可变，直接返回引用安全 / Zero-copy: V string is immutable, returning reference is safe
	}
	if val := s.old_flash[key] {
		return val
	}
	return error('session key not found: ${key}')
}

// set stores a value in the session.
pub fn (mut s Session) set(key string, value string) {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.data[key] = value
	s.is_dirty = true
}

// has checks if a key exists in the session.
pub fn (s &Session) has(key string) bool {
	unsafe { s.mu.rlock() }
	defer { unsafe { s.mu.runlock() } }
	return key in s.data || key in s.old_flash
}

// delete removes a key from the session.
//
// It has to cover both maps get()/has() look at, not just `data`. A flash key
// lives in old_flash for exactly one request, and get() falls back to it — so
// deleting only from `data` left the key readable: `delete('notice')` was
// followed by `has('notice') == true` and `get('notice') == '已保存'`.
//
// delete 从会话中移除一个键。
//
// 必须同时覆盖 get()/has() 会查的两个 map，而不只是 `data`。闪存键在
// old_flash 里存活恰好一个请求，而 get() 会回落到它 —— 只删 `data` 会让
// 这个键依然可读：`delete('notice')` 之后 has('notice') 仍是 true、
// get('notice') 仍返回原值。
pub fn (mut s Session) delete(key string) {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.data.delete(key)
	s.old_flash.delete(key)
	s.is_dirty = true
}

// flash stores a value that will only be available on the next request.
pub fn (mut s Session) flash(key string, value string) {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.flash_data[key] = value
	s.is_dirty = true
}

// get_flash retrieves a flash value from the previous request.
pub fn (s &Session) get_flash(key string) !string {
	unsafe { s.mu.rlock() }
	defer { unsafe { s.mu.runlock() } }
	if val := s.old_flash[key] {
		return val
	}
	return error('flash key not found: ${key}')
}

// has_flash checks if a flash key exists from the previous request.
pub fn (s &Session) has_flash(key string) bool {
	unsafe { s.mu.rlock() }
	defer { unsafe { s.mu.runlock() } }
	return key in s.old_flash
}

// all returns all session data.
//
// Includes the flash inbox, because get()/has() already expose those keys:
// a map that disagreed with them would let `all()` report an empty session
// while get('notice') still returned a value.
// Plain data wins when a key exists in both maps (get() does the same).
//
// all 返回全部会话数据。
//
// 包含闪存收件箱：get()/has() 本来就暴露这些键，若这里不包含，就会出现
// 「all() 说会话是空的、get('notice') 还能取到值」的自相矛盾。
// 同一个键两处都有时以 data 为准（与 get() 一致）。
pub fn (s &Session) all() map[string]string {
	unsafe { s.mu.rlock() }
	defer { unsafe { s.mu.runlock() } }
	mut result := map[string]string{}
	for key, val in s.old_flash {
		result[key] = val
	}
	for key, val in s.data {
		result[key] = val
	}
	return result
}

// clear removes all session data.
//
// Same rule as delete(): "all session data" means everything a reader can
// observe. Reading goes through `data` OR `old_flash` (get/has fall back to
// the flash inbox), so clearing only `data` left the previous request's
// one-shot messages readable after a clear — the documented flash contract
// ("read once, then gone") quietly stopped holding.
// flash_data is cleared as well: pending writes are session data too.
//
// clear 清空全部会话数据。
//
// 与 delete() 同一条规则：「全部会话数据」等于读取方能观察到的一切。
// 读取走 `data` 或 `old_flash`（get/has 会回落到闪存收件箱），只清 `data`
// 会让上一个请求的一次性提示在 clear 之后依旧可读 —— 文档承诺的闪存契约
// （「读一次就消失」）会静默失效。flash_data 一并清掉：待写入的也是会话数据。
pub fn (mut s Session) clear() {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.data = map[string]string{}
	s.old_flash = map[string]string{}
	s.flash_data = map[string]string{}
	s.is_dirty = true
}

// invalidate regenerates the session ID and clears all data.
pub fn (mut s Session) invalidate() {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.id = generate_session_id()
	s.data = map[string]string{}
	s.flash_data = map[string]string{}
	s.old_flash = map[string]string{}
	s.is_new = true
	s.is_dirty = true
}

// regenerate generates a new session ID while keeping data.
pub fn (mut s Session) regenerate() {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.id = generate_session_id()
	s.is_dirty = true
}

// ── MemorySessionStore ──

// MemorySessionStore is an in-memory session store for development.
// Starts a background GC goroutine that periodically removes expired
// sessions. Call close() to stop the GC goroutine.
pub struct MemorySessionStore {
pub mut:
	sessions map[string]&MemorySessionEntry
mut:
	mu         sync.RwMutex
	stop_gc    chan bool = chan bool{cap: 1}
	gc_started bool
	wg         sync.WaitGroup
}

struct MemorySessionEntry {
pub mut:
	data       map[string]string
	flash_data map[string]string
	created_at i64
	updated_at i64
}

// new_memory_session_store creates a new MemorySessionStore and starts
// the background GC goroutine.
pub fn new_memory_session_store() &MemorySessionStore {
	mut s := &MemorySessionStore{
		sessions: map[string]&MemorySessionEntry{}
	}
	unsafe { s.mu.init() }
	s.start_gc()
	return s
}

// start_gc launches the background GC goroutine that periodically removes
// expired sessions. Safe to call multiple times; only the first call starts
// the goroutine. Called automatically by new_memory_session_store().
// 使用锁保护 gc_started 标志，防止与 close() 竞态。
//
// start_gc launches the background GC goroutine that periodically removes
// expired sessions. Uses lock to protect gc_started flag.
fn (mut s MemorySessionStore) start_gc() {
	s.mu.@lock()
	if s.gc_started {
		s.mu.unlock()
		return
	}
	s.gc_started = true
	s.stop_gc = chan bool{cap: 1}
	sig := s.stop_gc
	s.mu.unlock()

	s.wg.add(1)
	spawn fn (gs &MemorySessionStore, stop_sig chan bool) {
		defer {
			unsafe { gs.wg.done() }
		}
		mut elapsed := 0
		mut idle_empty_sweeps := 0
		// Fast idle probe: an empty store has nothing to sweep, so waiting a
		// full gc_interval_sessions before deciding to retire is pure loss.
		// Short-lived stores (per-request, per-test) pile up goroutines in the
		// meantime — threads are the scarce resource, not one extra map scan.
		// While empty we poll quickly; the first write flips this back to the
		// slow cadence.
		mut idle_poll_ms := session_gc_idle_poll_ms
		for {
			// Sleep in 100ms increments so close() can stop us promptly.
			time.sleep(100 * time.millisecond)
			elapsed += 100

			// Non-blocking check for stop signal.
			mut should_stop := false
			select {
				_ := <-stop_sig {
					should_stop = true
				}
				else {}
			}
			if should_stop {
				break
			}

			is_empty := unsafe { gs.is_empty() }
			// Sweep on the normal cadence — or immediately when the store has
			// gone empty, so retirement is decided without waiting a minute.
			if elapsed >= session_gc_interval_ms || (is_empty && elapsed >= idle_poll_ms) {
				elapsed = 0
				if !is_empty {
					unsafe {
						mut m := gs
						m.gc(1800) or {}
					}
				}
				// Retire once the store has been empty for a whole sweep:
				// there is nothing left to expire and the owner has most
				// likely dropped the store without calling close(). Without
				// this the goroutine sleeps forever, one per store.
				if is_empty {
					idle_empty_sweeps++
					if idle_empty_sweeps >= gc_idle_exit_sweeps {
						break
					}
					idle_poll_ms = session_gc_idle_poll_ms
				} else {
					idle_empty_sweeps = 0
					idle_poll_ms = session_gc_interval_ms
				}
			}
		}
	}(s, sig)
}

// gc_idle_exit_sweeps is how many consecutive empty sweeps the session
// GC goroutine tolerates before retiring.
const gc_idle_exit_sweeps = 2

// session_gc_interval_ms is the sweep cadence while the store holds sessions
// (max_age = 1800s default session TTL, so a minute is plenty).
const session_gc_interval_ms = 60000

// session_gc_idle_poll_ms is how long an EMPTY store waits before concluding
// it is unused and retiring. Kept short on purpose: one abandoned store means
// one leaked thread, and a burst of short-lived stores exhausts the process.
const session_gc_idle_poll_ms = 500

// is_empty reports whether the store currently holds no sessions.
fn (s &MemorySessionStore) is_empty() bool {
	unsafe {
		mut ms := s
		ms.mu.@rlock()
		defer { ms.mu.runlock() }
		return ms.sessions.len == 0
	}
}

// close stops the background GC goroutine and waits for it to exit.
// Safe to call multiple times. After close(), expired sessions are no
// longer swept automatically (but gc() can still be called manually).
pub fn (mut s MemorySessionStore) close() {
	s.mu.@lock()
	if !s.gc_started {
		s.mu.unlock()
		return
	}
	s.gc_started = false
	sig := s.stop_gc
	s.mu.unlock()

	select {
		sig <- true {}
		else {}
	}
	s.wg.wait()
}

// read reads session data from memory.
pub fn (mut s MemorySessionStore) read(session_id string) !SessionRecord {
	s.mu.rlock()
	defer { s.mu.runlock() }
	entry := s.sessions[session_id] or { return SessionRecord{} }
	return SessionRecord{
		data:  entry.data.clone()
		flash: entry.flash_data.clone()
	}
}

// write writes session data to memory.
pub fn (mut s MemorySessionStore) write(session_id string, data map[string]string, flash map[string]string, ttl_seconds int) ! {
	s.mu.@lock()
	defer { s.mu.unlock() }
	now_ := time.now().unix()
	mut entry := s.sessions[session_id] or {
		&MemorySessionEntry{
			data:       map[string]string{}
			flash_data: map[string]string{}
			created_at: now_
			updated_at: now_
		}
	}
	entry.data = data.clone()
	entry.flash_data = flash.clone()
	entry.updated_at = now_
	s.sessions[session_id] = entry
}

// destroy removes a session from memory.
pub fn (mut s MemorySessionStore) destroy(session_id string) ! {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.sessions.delete(session_id)
}

// gc removes expired sessions from memory.
pub fn (mut s MemorySessionStore) gc(max_age_seconds int) ! {
	s.mu.@lock()
	defer { s.mu.unlock() }
	now_ := time.now().unix()
	mut expired := []string{}
	for id, entry in s.sessions {
		if now_ - entry.updated_at > max_age_seconds {
			expired << id
		}
	}
	for id in expired {
		s.sessions.delete(id)
	}
}

// ── ShardedMemorySessionStore ──

// session_shard_count 是 Session 存储的分片数量。
// 16 个分片，每片独立 RwMutex，GC 按分片扫描，
// 避免全局写锁阻塞所有读写操作。
//
// session_shard_count is the number of shards for Session storage.
// 16 shards, each with independent RwMutex; GC scans per-shard,
// avoiding global write locks that block all read/write operations.
pub const session_shard_count = 16

// SessionShard 是分片内存 Session 存储的单个分片。
// SessionShard is a single shard of the sharded memory session store.
struct SessionShard {
pub mut:
	sessions map[string]&MemorySessionEntry
	mu       sync.RwMutex
}

// ShardStats 是分片统计信息。
// ShardStats holds statistics for a single shard.
pub struct ShardStats {
pub:
	index int
	count int // 分片中的 Session 数量 / number of sessions in the shard
}

// ShardedMemorySessionStore 是分片内存 Session 存储。
// 16 个分片，每片独立 RwMutex，GC 按分片扫描，
// 避免全局写锁阻塞所有读写操作。
//
// ShardedMemorySessionStore is a sharded in-memory Session store.
// 16 shards, each with independent RwMutex; GC scans per-shard,
// avoiding global write locks that block all read/write operations.
pub struct ShardedMemorySessionStore {
pub mut:
	shards              []SessionShard
	stop_gc             chan bool = chan bool{cap: 1}
	gc_started          bool
	wg                  sync.WaitGroup
	gc_interval_seconds int = 60
mut:
	mu sync.RwMutex // 保护 gc_started 和 stop_gc 的锁 / lock protecting gc_started and stop_gc
}

// new_sharded_memory_session_store 创建分片内存 Session 存储。
// 自动启动后台 GC 协程。
//
// new_sharded_memory_session_store creates a sharded in-memory Session store.
// Automatically starts the background GC goroutine.
pub fn new_sharded_memory_session_store() &ShardedMemorySessionStore {
	mut shards := []SessionShard{len: session_shard_count}
	mut s := &ShardedMemorySessionStore{
		shards: shards
	}
	unsafe {
		s.mu.init()
		for i in 0 .. s.shards.len {
			s.shards[i].mu.init()
		}
	}
	s.start_sharded_gc()
	return s
}

// shard_index 根据 session_id 计算分片索引。
// 使用 FNV-1a 哈希 + 位与运算（shard_count 为 2 的幂）。
//
// shard_index computes the shard index for a given session_id.
// Uses FNV-1a hash + bitwise AND (shard_count is a power of 2).
fn (s &ShardedMemorySessionStore) shard_index(session_id string) int {
	mut hash := u64(2166136261) // FNV-1a offset basis
	for b in session_id.bytes() {
		hash ^= u64(b)
		hash *= u64(16777619) // FNV-1a prime
	}
	return int(hash & u64(session_shard_count - 1))
}

// read 读取 session 数据，返回引用而非 clone。
// 调用方在 Session 锁保护下使用，无需 clone（零拷贝）。
//
// ⚠️ 安全性说明：返回内部 map 的引用依赖调用方在 SessionLock 保护下使用。
// 如果调用方未持有 SessionLock，并发 write() 可能导致数据竞争。
// 对于不使用 SessionLock 的场景，应使用 MemorySessionStore（返回 clone）。
//
// read reads session data, returning a reference instead of a clone.
// The caller uses it under SessionLock protection, so no clone is needed (zero-copy).
//
// ⚠️ Safety note: returning a reference to the internal map relies on the caller
// using it under SessionLock protection. If the caller doesn't hold SessionLock,
// concurrent write() may cause data races. For scenarios without SessionLock,
// use MemorySessionStore (which returns a clone).
pub fn (mut s ShardedMemorySessionStore) read(session_id string) !SessionRecord {
	idx := s.shard_index(session_id)
	mut shard := unsafe { &s.shards[idx] }
	shard.mu.rlock()
	defer { shard.mu.runlock() }
	entry := shard.sessions[session_id] or { return SessionRecord{} }
	// 零拷贝：返回原始数据的引用
	// 安全性由 SessionLock 保证：同一 session_id 的并发操作被串行化
	//
	// Zero-copy: returns a reference to the original data.
	// Safety guaranteed by SessionLock: concurrent operations on the same
	// session_id are serialized.
	return SessionRecord{
		data:  entry.data
		flash: entry.flash_data
	}
}

// write 写入 session 数据到对应分片。
// write writes session data to the corresponding shard.
pub fn (mut s ShardedMemorySessionStore) write(session_id string, data map[string]string, flash map[string]string, ttl_seconds int) ! {
	idx := s.shard_index(session_id)
	mut shard := unsafe { &s.shards[idx] }
	shard.mu.@lock()
	defer { shard.mu.unlock() }
	now_ := time.now().unix()
	mut entry := shard.sessions[session_id] or {
		&MemorySessionEntry{
			data:       map[string]string{}
			flash_data: map[string]string{}
			created_at: now_
			updated_at: now_
		}
	}
	entry.data = data.clone()
	entry.flash_data = flash.clone()
	entry.updated_at = now_
	shard.sessions[session_id] = entry
}

// destroy 从对应分片移除 session。
// destroy removes a session from the corresponding shard.
pub fn (mut s ShardedMemorySessionStore) destroy(session_id string) ! {
	idx := s.shard_index(session_id)
	mut shard := unsafe { &s.shards[idx] }
	shard.mu.@lock()
	defer { shard.mu.unlock() }
	shard.sessions.delete(session_id)
}

// gc 按分片执行过期清理，每次只锁定一个分片。
// 其他分片的读写操作不受阻塞。
// 使用 defer { shard.mu.unlock() } 保证锁释放。
//
// gc performs expiry cleanup per-shard, locking only one shard at a time.
// Read/write operations on other shards are not blocked.
// Uses defer { shard.mu.unlock() } to guarantee lock release.
pub fn (mut s ShardedMemorySessionStore) gc(max_age_seconds int) ! {
	now_ := time.now().unix()
	for i in 0 .. s.shards.len {
		mut shard := unsafe { &s.shards[i] }
		shard.mu.@lock()
		mut expired := []string{}
		for id, entry in shard.sessions {
			if now_ - entry.updated_at > max_age_seconds {
				expired << id
			}
		}
		for id in expired {
			shard.sessions.delete(id)
		}
		shard.mu.unlock()
		// 分片间释放锁，允许其他分片并发操作
		// Release lock between shards, allowing concurrent operations on other shards
	}
}

// start_sharded_gc 启动分片存储的后台 GC 协程。
// 使用锁保护 gc_started 标志，防止与 close() 竞态。
//
// start_sharded_gc starts the background GC goroutine for the sharded store.
// Uses lock to protect gc_started flag, preventing race with close().
fn (mut s ShardedMemorySessionStore) start_sharded_gc() {
	s.mu.@lock()
	s.stop_gc = chan bool{cap: 1}
	s.gc_started = true
	sig := s.stop_gc
	s.mu.unlock()

	s.wg.add(1)
	spawn fn (gs &ShardedMemorySessionStore, stop_sig chan bool) {
		defer {
			unsafe { gs.wg.done() }
		}
		mut elapsed := 0
		mut idle_empty_sweeps := 0
		mut idle_poll_ms := session_gc_idle_poll_ms
		for {
			// 以 100ms 递增睡眠，使 close() 能及时停止
			// Sleep in 100ms increments so close() can stop us promptly
			time.sleep(100 * time.millisecond)
			elapsed += 100

			// 非阻塞检查停止信号 / Non-blocking check for stop signal
			mut should_stop := false
			select {
				_ := <-stop_sig {
					should_stop = true
				}
				else {}
			}
			if should_stop {
				break
			}

			// 空存储用快速探测，不必等满一个扫描周期才决定退休。
			// An empty store has nothing to expire; probing it quickly is what
			// keeps a burst of short-lived stores from leaking one thread each.
			is_empty := unsafe { gs.is_empty() }
			if elapsed >= session_gc_interval_ms || (is_empty && elapsed >= idle_poll_ms) {
				elapsed = 0
				if !is_empty {
					unsafe {
						mut m := gs
						m.gc(1800) or {}
					}
				}
				// 空存储连续两轮后退出：没有可过期的数据，且持有者很可能
				// 已丢弃该实例而未调用 close()。否则协程会永久睡眠，
				// 每个实例泄漏一个线程。
				if is_empty {
					idle_empty_sweeps++
					if idle_empty_sweeps >= gc_idle_exit_sweeps {
						break
					}
					idle_poll_ms = session_gc_idle_poll_ms
				} else {
					idle_empty_sweeps = 0
					idle_poll_ms = session_gc_interval_ms
				}
			}
		}
	}(s, sig)
}

// is_empty 报告分片存储当前是否没有任何 session。
// is_empty reports whether the sharded store currently holds no sessions.
fn (s &ShardedMemorySessionStore) is_empty() bool {
	unsafe {
		mut ms := s
		for i in 0 .. ms.shards.len {
			mut shard := &ms.shards[i]
			shard.mu.@rlock()
			n := shard.sessions.len
			shard.mu.unlock()
			if n > 0 {
				return false
			}
		}
		return true
	}
}

// close 停止后台 GC 协程并等待其退出。
// 可安全多次调用。使用锁保护 gc_started 标志的读取。
//
// close stops the background GC goroutine and waits for it to exit.
// Safe to call multiple times. Uses lock to protect gc_started flag read.
pub fn (mut s ShardedMemorySessionStore) close() {
	// 加锁检查 gc_started，防止与 start_sharded_gc() 竞态
	// Lock-protected check of gc_started to prevent race with start_sharded_gc()
	s.mu.@lock()
	if !s.gc_started {
		s.mu.unlock()
		return
	}
	s.gc_started = false
	sig := s.stop_gc
	s.mu.unlock()

	select {
		sig <- true {}
		else {}
	}
	s.wg.wait()
}

// shard_stats 返回各分片的统计信息。
// shard_stats returns statistics for each shard.
pub fn (mut s ShardedMemorySessionStore) shard_stats() []ShardStats {
	mut stats := []ShardStats{}
	for i in 0 .. s.shards.len {
		mut shard := unsafe { &s.shards[i] }
		shard.mu.rlock()
		count := shard.sessions.len
		shard.mu.runlock()
		stats << ShardStats{
			index: i
			count: count
		}
	}
	return stats
}

// ── Session Manager ──

// SessionManager manages session lifecycle with a pluggable store.
pub struct SessionManager {
pub mut:
	store         &SessionStore = unsafe { nil }
	cookie_name   string        = 'PHOTON_SESSION'
	ttl_seconds   int           = 1800
	cookie_path   string        = '/'
	cookie_domain string
	secure        bool
	http_only     bool   = true
	same_site     string = 'Lax'
}

// new_session_manager creates a SessionManager with a given store.
pub fn new_session_manager(store &SessionStore) &SessionManager {
	return &SessionManager{
		store: unsafe { store }
	}
}

// start begins a session, reading from the store or creating a new one.
//
// 恢复既有会话时，存储里带着的闪存被搬进 old_flash —— 于是本次请求
// 用 get_flash() 就能读到上一次请求 flash() 写的值（这正是 flash 的
// 承诺：写进去的那次读不到，下一次读得到）。同时把 is_dirty 置位：
// 读取本身就是一次消费，必须落盘，否则同一份闪存会在之后每一次请求里
// 反复被读到，成了「永久数据」。
//
// start begins a session, reading from the store or creating a new one.
// Flash data carried over by the store is promoted to old_flash so the
// current request can read what the previous one flashed, and the session
// is marked dirty so that consumption is persisted.
pub fn (mut sm SessionManager) start(ctx &veb.Context) &Session {
	mut session_id := ctx.get_cookie(sm.cookie_name) or { '' }
	if session_id.len > 0 && !isnil(sm.store) {
		rec := sm.store.read(session_id) or { SessionRecord{} }
		// 空 payload 但仍有 flash 时也要恢复，否则「只写了一个 flash」的
		// 会话会在下一次请求里消失。
		// A session holding only flash data must still be resumed.
		if rec.data.len > 0 || rec.flash.len > 0 {
			mut sess := new_session(session_id)
			sess.data = rec.data.clone()
			sess.old_flash = rec.flash.clone()
			sess.is_new = false
			// 闪存被消费了一次 —— 即便业务没改任何值，也要写回去清空它。
			sess.is_dirty = rec.flash.len > 0
			return sess
		}
	}

	sess := new_session(generate_session_id())
	return sess
}

// start_with_flash begins a session and promotes stored flash data to old_flash.
// Call this when your store supports persisting flash data separately.
pub fn (mut sm SessionManager) start_with_flash(ctx &veb.Context, stored_flash map[string]string) &Session {
	mut sess := sm.start(ctx)
	sess.mu.@lock()
	sess.old_flash = stored_flash.clone()
	sess.mu.unlock()
	return sess
}

// save 仅在 Session.is_dirty == true 时写回存储（惰性保存）。
// 未修改的 Session 跳过 store.write()，减少无变更 I/O。
//
// save persists session data to the store only when is_dirty == true (lazy save).
// Unmodified sessions skip store.write(), reducing unnecessary I/O.
pub fn (mut sm SessionManager) save(mut ctx veb.Context, mut sess Session) ! {
	unsafe { sess.mu.rlock() }
	is_dirty := sess.is_dirty
	sess_id := sess.id
	sess_data := sess.data.clone()
	// 读一下客户端手上那个 Cookie 的值：只有和当前 ID 不同才需要重发。
	cookie_id := ctx.get_cookie(sm.cookie_name) or { '' }
	// 闪存的生命周期是「一次请求」：写完这一轮就搬去 old_flash，
	// flash_data 清空。否则用它实现的一次性提示（"保存成功"）
	// 会在每一次后续请求里重复出现，直到会话过期。
	//
	// Flash data lives for exactly one request: after being persisted it is
	// moved to old_flash and cleared, so a one-shot message cannot repeat.
	// 注意顺序：本轮 flash() 写进去的值要整份落盘（new_flash），落盘之后
	// 才把它搬进 old_flash —— 搬进去的是「已经存在存储里的那份」。
	// 原来先赋值再 clone 了一个刚清空的 map，等于每次 save() 都把存储里的
	// flash 覆盖成空 —— flash() 一次都活不到下一个请求。
	new_flash := sess.flash_data.clone()
	sess.old_flash = new_flash.clone()
	sess.flash_data = map[string]string{}
	// 落盘之后这个 Session 就不再是「新会话」了；不清零会让后续每次
	// save() 都判定需要重发 Cookie。
	sess.is_new = false
	unsafe { sess.mu.runlock() }

	if !isnil(sm.store) && is_dirty {
		sm.store.write(sess_id, sess_data, new_flash, sm.ttl_seconds)!
	}
	// Cookie 只在「新会话」「ID 变了」或「本来就要写存储」时才重发。
	// 每次响应都 set 一遍意味着：并发请求里最后写 Cookie 的那个把别人刚
	// regenerate 出来的新 ID 又盖回旧 ID（session fixation 的经典入口），
	// 而且每个静态响应都白带一个会话 Cookie。
	is_new := sess.is_new
	current_id := sess.id
	// 只是在「没给客户端发过这个 ID」时才发 Cookie：后续请求由浏览器带着
	// 同一个 ID 回来（此时 cookie_id == current_id），或者同一个响应里
	// 第二次 save（响应头里已经有这个 ID）都不再重复发。
	already_sent :=
		ctx.res.header.values(.set_cookie).any(it.starts_with('${sm.cookie_name}=${current_id}'))
	if is_new || (current_id != cookie_id && !already_sent) {
		ctx.set_cookie(sm.build_cookie(current_id, 0))
	}
}

// build_cookie 用配置构造会话 Cookie。
//
// 会话 Cookie 是整条链路里最关键的那个 Cookie —— 它一旦被脚本读到，
// 会话就被接管了。所以 SameSite / Domain 这些属性不能只存在配置字段里
// 而从不写到响应上：配置写了 `same_site: 'Strict'`、实际发出去的却是
// 浏览器默认值，这种「配置看着生效、其实没生效」是最难发现的一类。
//
// build_cookie builds the session cookie from the manager configuration.
// SessionCookie attributes must reach the wire — a configured SameSite that
// is never emitted is worse than no option at all.
fn (sm &SessionManager) build_cookie(value string, max_age int) http.Cookie {
	return http.Cookie{
		name:      sm.cookie_name
		value:     value
		path:      sm.cookie_path
		domain:    sm.cookie_domain
		secure:    sm.secure
		http_only: sm.http_only
		max_age:   max_age
		same_site: same_site_of(sm.same_site)
	}
}

// same_site_of 把配置里的字符串映射成 http.SameSite。
// 未知取值回落到 .same_site_not_set（不发该属性），而不是猜一个更宽松的值。
//
// same_site_of maps the configured string to http.SameSite. An unknown
// value falls back to emitting nothing rather than guessing a looser policy.
fn same_site_of(value string) http.SameSite {
	return match value.trim_space().to_lower() {
		'strict' { .same_site_strict_mode }
		'lax' { .same_site_lax_mode }
		'none' { .same_site_none_mode }
		else { .same_site_not_set }
	}
}

// destroy removes the session from the store and clears the cookie.
pub fn (mut sm SessionManager) destroy(mut ctx veb.Context, mut sess Session) ! {
	unsafe { sess.mu.rlock() }
	sess_id := sess.id
	unsafe { sess.mu.runlock() }

	if !isnil(sm.store) {
		sm.store.destroy(sess_id)!
	}
	// 清除 Cookie 必须与原 Cookie 的 path/domain 完全一致，否则浏览器
	// 认为这是另一个 Cookie，会话 ID 继续留在客户端。
	//
	// A clearing cookie must match the original path/domain, otherwise the
	// browser keeps the old one and the session ID never leaves the client.
	ctx.set_cookie(sm.build_cookie('', -1))
}

// ── Session Middleware ──

// session_middleware is a middleware that starts and saves sessions.
//
// Placeholder middleware. Actual session start/save lifecycle is handled by
// the SessionManager and veb's request hooks. This middleware exists for API
// compatibility with middleware chains that expect a session step. It only
// marks that a session is active in the middleware data map; it does not
// perform any session work.
pub fn session_middleware(mut ctx MiddlewareContext) !bool {
	ctx.data['_session_active'] = 'true'
	return true
}

// ── Helper Functions ──

// generate_session_id creates a cryptographically secure session ID.
// Uses 32 bytes of crypto/rand output, SHA-256 hashed, truncated to 40 hex chars (160 bit).
// The SHA-256 step prevents direct mapping from random bytes to session ID,
// adding a layer of one-wayness.
//
// ⚠️ If crypto/rand fails, the function panics — a non-random session ID
// is worse than no session ID (session fixation risk).
//
// generate_session_id 创建加密安全的 Session ID。
// 使用 32 字节 crypto/rand 输出，经 SHA-256 哈希后截断为 40 个十六进制字符（160 位）。
// SHA-256 步骤防止从随机字节直接映射到 Session ID，增加单向性。
//
// ⚠️ 如果 crypto/rand 失败，函数会 panic — 非随机的 Session ID
// 比没有 Session ID 更糟（session fixation 风险）。
fn generate_session_id() string {
	bytes := crypto_rand_bytes(32)
	hex_str := session_sha256_hex(bytes)
	return hex_str[..40]
}

// crypto_rand_bytes 返回 n 个密码学安全的随机字节。
//
// V 0.5.2 (93bf4a9) 的 `crypto.rand.read(mut buffer []u8) !` 是「填充传入的
// buffer」形态，不返回新 slice；按数量返回的入口叫 `crypto.rand.bytes(n)`。
// 随机源只留这一处：失败一律 panic。
fn crypto_rand_bytes(n int) []u8 {
	return crand.bytes(n) or {
		panic('crypto/rand failed: cannot generate secure random bytes / crypto/rand 失败：无法生成安全随机字节')
	}
}

// sha256_hex computes a SHA-256 hash and returns it as hex string.
// sha256_hex 计算 SHA-256 哈希并返回十六进制字符串。
fn session_sha256_hex(data []u8) string {
	digest := sha256.sum(data)
	// sha256.sum returns [32]u8, convert to []u8 for hex.encode
	// sha256.sum 返回 [32]u8，转换为 []u8 以供 hex.encode 使用
	mut arr := []u8{len: 32, cap: 32}
	for i in 0 .. 32 {
		arr[i] = digest[i]
	}
	return hex.encode(arr)
}

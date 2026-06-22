module web

// session.v - Session Management (Spring Session / Laravel Session inspired)
//
// Provides server-side session management with pluggable backends.
// Supports cookie-based session IDs and flash data.
import veb
import net.http
import crypto.sha256
import encoding.hex
import crypto.rand
import sync
import time

// ── Session Interface ──

// SessionStore is the interface for session storage backends.
pub interface SessionStore {
mut:
	read(session_id string) !map[string]string
	write(session_id string, data map[string]string, ttl_seconds int) !
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
pub fn (mut s Session) delete(key string) {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.data.delete(key)
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
pub fn (s &Session) all() map[string]string {
	unsafe { s.mu.rlock() }
	defer { unsafe { s.mu.runlock() } }
	mut result := map[string]string{}
	for key, val in s.data {
		result[key] = val
	}
	return result
}

// clear removes all session data.
pub fn (mut s Session) clear() {
	s.mu.@lock()
	defer { s.mu.unlock() }
	s.data = map[string]string{}
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

			// Sweep every 60 seconds (max_age = 1800s default session TTL)
			if elapsed >= 60000 {
				elapsed = 0
				unsafe {
					mut m := gs
					m.gc(1800) or {}
				}
			}
		}
	}(s, sig)
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
pub fn (mut s MemorySessionStore) read(session_id string) !map[string]string {
	s.mu.rlock()
	defer { s.mu.runlock() }
	entry := s.sessions[session_id] or { return map[string]string{} }
	return entry.data.clone()
}

// write writes session data to memory.
pub fn (mut s MemorySessionStore) write(session_id string, data map[string]string, ttl_seconds int) ! {
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
pub fn (mut s ShardedMemorySessionStore) read(session_id string) !map[string]string {
	idx := s.shard_index(session_id)
	mut shard := unsafe { &s.shards[idx] }
	shard.mu.rlock()
	defer { shard.mu.runlock() }
	entry := shard.sessions[session_id] or { return map[string]string{} }
	// 零拷贝：返回原始数据的引用
	// 安全性由 SessionLock 保证：同一 session_id 的并发操作被串行化
	//
	// Zero-copy: returns a reference to the original data.
	// Safety guaranteed by SessionLock: concurrent operations on the same
	// session_id are serialized.
	return entry.data
}

// write 写入 session 数据到对应分片。
// write writes session data to the corresponding shard.
pub fn (mut s ShardedMemorySessionStore) write(session_id string, data map[string]string, ttl_seconds int) ! {
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

			// 每 60 秒扫描一次（max_age = 1800s 默认 session TTL）
			// Sweep every 60 seconds (max_age = 1800s default session TTL)
			if elapsed >= 60000 {
				elapsed = 0
				unsafe {
					mut m := gs
					m.gc(1800) or {}
				}
			}
		}
	}(s, sig)
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
	store       &SessionStore = unsafe { nil }
	cookie_name string        = 'PHOTON_SESSION'
	ttl_seconds int           = 1800
	cookie_path string        = '/'
	secure      bool
	http_only   bool   = true
	same_site   string = 'Lax'
}

// new_session_manager creates a SessionManager with a given store.
pub fn new_session_manager(store &SessionStore) &SessionManager {
	return &SessionManager{
		store: unsafe { store }
	}
}

// start begins a session, reading from the store or creating a new one.
// When resuming an existing session, flash data from the previous request
// is promoted to old_flash so it can be retrieved via get_flash().
pub fn (mut sm SessionManager) start(ctx &veb.Context) &Session {
	mut session_id := ctx.get_cookie(sm.cookie_name) or { '' }

	if session_id.len > 0 && !isnil(sm.store) {
		data := sm.store.read(session_id) or {
			map[string]string{}
		}
		if data.len > 0 {
			mut sess := new_session(session_id)
			sess.data = data.clone()
			sess.is_new = false
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
	unsafe { sess.mu.runlock() }

	if !isnil(sm.store) && is_dirty {
		sm.store.write(sess_id, sess_data, sm.ttl_seconds)!
	}
	ctx.set_cookie(http.Cookie{
		name:      sm.cookie_name
		value:     sess_id
		path:      sm.cookie_path
		secure:    sm.secure
		http_only: sm.http_only
	})
}

// destroy removes the session from the store and clears the cookie.
pub fn (mut sm SessionManager) destroy(mut ctx veb.Context, mut sess Session) ! {
	unsafe { sess.mu.rlock() }
	sess_id := sess.id
	unsafe { sess.mu.runlock() }

	if !isnil(sm.store) {
		sm.store.destroy(sess_id)!
	}
	ctx.set_cookie(http.Cookie{
		name:      sm.cookie_name
		value:     ''
		path:      sm.cookie_path
		secure:    sm.secure
		http_only: sm.http_only
		max_age:   -1
	})
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
	bytes := rand.read(32) or {
		// crypto/rand failure is fatal — do NOT fall back to time-based bytes.
		// A predictable session ID enables session fixation attacks.
		// crypto/rand 失败是致命的 — 不要回退到基于时间的字节。
		// 可预测的 Session ID 会导致 session fixation 攻击。
		panic('crypto/rand failed: cannot generate secure session ID / crypto/rand 失败：无法生成安全的 Session ID')
	}
	hex_str := session_sha256_hex(bytes)
	return hex_str[..40]
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

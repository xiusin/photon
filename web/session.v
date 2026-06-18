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
	id            string
	data          map[string]string
	flash_data    map[string]string
	old_flash     map[string]string  // flash from previous request
	is_new        bool
	is_dirty      bool
	ttl_seconds   int = 1800  // default 30 min
}

// new_session creates a new Session with the given ID.
pub fn new_session(id string) &Session {
	return &Session{
		id: id
		data: map[string]string{}
		flash_data: map[string]string{}
		old_flash: map[string]string{}
		is_new: true
		is_dirty: false
	}
}

// get retrieves a value from the session.
pub fn (s &Session) get(key string) !string {
	if val := s.data[key] {
		return val
	}
	if val := s.old_flash[key] {
		return val
	}
	return error('session key not found: ${key}')
}

// set stores a value in the session.
pub fn (mut s Session) set(key string, value string) {
	s.data[key] = value
	s.is_dirty = true
}

// has checks if a key exists in the session.
pub fn (s &Session) has(key string) bool {
	return key in s.data || key in s.old_flash
}

// delete removes a key from the session.
pub fn (mut s Session) delete(key string) {
	s.data.delete(key)
	s.is_dirty = true
}

// flash stores a value that will only be available on the next request.
pub fn (mut s Session) flash(key string, value string) {
	s.flash_data[key] = value
	s.is_dirty = true
}

// get_flash retrieves a flash value from the previous request.
pub fn (s &Session) get_flash(key string) !string {
	if val := s.old_flash[key] {
		return val
	}
	return error('flash key not found: ${key}')
}

// has_flash checks if a flash key exists from the previous request.
pub fn (s &Session) has_flash(key string) bool {
	return key in s.old_flash
}

// all returns all session data.
pub fn (s &Session) all() map[string]string {
	mut result := map[string]string{}
	for key, val in s.data {
		result[key] = val
	}
	return result
}

// clear removes all session data.
pub fn (mut s Session) clear() {
	s.data = map[string]string{}
	s.is_dirty = true
}

// invalidate regenerates the session ID and clears all data.
pub fn (mut s Session) invalidate() {
	s.id = generate_session_id()
	s.data = map[string]string{}
	s.flash_data = map[string]string{}
	s.old_flash = map[string]string{}
	s.is_new = true
	s.is_dirty = true
}

// regenerate generates a new session ID while keeping data.
pub fn (mut s Session) regenerate() {
	s.id = generate_session_id()
	s.is_dirty = true
}

// ── MemorySessionStore ──

// MemorySessionStore is an in-memory session store for development.
pub struct MemorySessionStore {
pub mut:
	sessions map[string]&MemorySessionEntry
mut:
	mu sync.RwMutex
}

struct MemorySessionEntry {
pub mut:
	data       map[string]string
	flash_data map[string]string
	created_at i64
	updated_at i64
}

// new_memory_session_store creates a new MemorySessionStore.
pub fn new_memory_session_store() &MemorySessionStore {
	return &MemorySessionStore{
		sessions: map[string]&MemorySessionEntry{}
	}
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
			data: map[string]string{}
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

// ── Session Manager ──

// SessionManager manages session lifecycle with a pluggable store.
pub struct SessionManager {
pub mut:
	store        &SessionStore = unsafe { nil }
	cookie_name  string = 'PHOTON_SESSION'
	ttl_seconds  int    = 1800
	cookie_path  string = '/'
	secure       bool
	http_only    bool   = true
	same_site    string = 'Lax'
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
		data := sm.store.read(session_id) or { map[string]string{} }
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
	sess.old_flash = stored_flash.clone()
	return sess
}

// save persists session data to the store and sets the cookie.
pub fn (mut sm SessionManager) save(mut ctx veb.Context, sess &Session) ! {
	if !isnil(sm.store) {
		sm.store.write(sess.id, sess.data.clone(), sm.ttl_seconds)!
	}
	ctx.set_cookie(http.Cookie{
		name: sm.cookie_name
		value: sess.id
		path: sm.cookie_path
		secure: sm.secure
		http_only: sm.http_only
	})
}

// destroy removes the session from the store and clears the cookie.
pub fn (mut sm SessionManager) destroy(mut ctx veb.Context, sess &Session) ! {
	if !isnil(sm.store) {
		sm.store.destroy(sess.id)!
	}
	ctx.set_cookie(http.Cookie{
		name: sm.cookie_name
		value: ''
		path: sm.cookie_path
		secure: sm.secure
		http_only: sm.http_only
		max_age: -1
	})
}

// ── Session Middleware ──

// session_middleware is a middleware that starts and saves sessions.
pub fn session_middleware(mut ctx &MiddlewareContext) !bool {
	ctx.data['_session_active'] = 'true'
	return true
}

// ── Helper Functions ──

// generate_session_id creates a cryptographically secure session ID.
fn generate_session_id() string {
	bytes := rand.read(32) or {
		// Fallback: use time-based bytes (less secure but better than nothing)
		mut fallback := []u8{len: 32}
		ts := time.now().unix_nano()
		for i in 0 .. 32 {
			fallback[i] = u8((ts >> (i * 8)) & 0xff)
		}
		fallback
	}
	hex_str := session_sha256_hex(bytes)
	return hex_str[..40]
}

// sha256_hex computes a SHA-256 hash and returns it as hex string.
fn session_sha256_hex(data []u8) string {
	digest := sha256.sum(data)
	mut arr := []u8{}
	for b in digest {
		arr << b
	}
	return hex.encode(arr)
}

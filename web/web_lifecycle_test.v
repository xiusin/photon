module web

// web_lifecycle_test.v - Lifecycle tests for Web module
//
// Verifies fixes for:
//   - H1:   kernel frozen flag memory visibility (read under rlock)
//   - M21:  kernel unfreeze()/off() methods
//   - HIGH #10: MemorySessionStore background GC + close()
//   - HIGH #9:  UploadChunkManager background GC + close()
import time

// ============================================================
// MemorySessionStore — background GC + close (HIGH #10)
// ============================================================

fn test_web_lifecycle_session_store_gc_starts() {
	mut store := new_memory_session_store()
	// GC goroutine is started by new_memory_session_store()
	assert store.sessions.len == 0

	// close() stops the GC goroutine — if this hangs, the GC is broken
	store.close()
	// close() is idempotent
	store.close()
}

fn test_web_lifecycle_session_store_gc_removes_expired() {
	mut store := new_memory_session_store()

	mut data := map[string]string{}
	data['user_id'] = '123'
	store.write('sess-1', data, 1800) or { assert false }
	assert store.sessions.len == 1

	// gc with max_age = -1 removes all entries (now - updated_at > -1 is always true)
	store.gc(-1) or { assert false }
	assert store.sessions.len == 0

	store.close()
}

fn test_web_lifecycle_session_store_gc_keeps_recent() {
	mut store := new_memory_session_store()

	mut data := map[string]string{}
	data['key'] = 'val'
	store.write('recent', data, 1800) or { assert false }

	// gc with large max_age should keep the session
	store.gc(999999) or { assert false }
	assert store.sessions.len == 1

	store.close()
}

fn test_web_lifecycle_session_store_write_read_destroy() {
	mut store := new_memory_session_store()

	mut data := map[string]string{}
	data['k1'] = 'v1'
	data['k2'] = 'v2'
	store.write('s1', data, 1800) or { assert false }

	read := store.read('s1') or {
		assert false
		return
	}
	assert read['k1'] == 'v1'
	assert read['k2'] == 'v2'

	store.destroy('s1') or { assert false }
	read2 := store.read('s1') or {
		assert false
		return
	}
	assert read2.len == 0

	store.close()
}

// ============================================================
// HttpKernel — frozen flag + unfreeze()/off() (H1, M21)
// ============================================================

// Global flag to track if a kernel listener was called.
// V interfaces require immutable receivers, so we use a __global
// counter (compiled with -enable-globals, matching CI).
__global kernel_listener_call_count int

fn kernel_test_listener(event_name string, data voidptr) {
	unsafe {
		kernel_listener_call_count++
	}
}

fn test_web_lifecycle_kernel_on_returns_id() {
	mut k := new_http_kernel()
	id := k.on(.request, kernel_test_listener)
	assert id > 0

	// Second listener gets a different id
	id2 := k.on(.response, kernel_test_listener)
	assert id2 > id
}

fn test_web_lifecycle_kernel_off_removes_listener() {
	mut k := new_http_kernel()
	unsafe {
		kernel_listener_call_count = 0
	}
	id := k.on(.request, kernel_test_listener)
	k.off(id)

	// handle() dispatches request/controller/response events.
	// The removed listener should NOT be called.
	k.handle() or { assert false }
	assert unsafe { kernel_listener_call_count } == 0
}

fn test_web_lifecycle_kernel_listener_called_when_not_removed() {
	mut k := new_http_kernel()
	unsafe {
		kernel_listener_call_count = 0
	}
	k.on(.request, kernel_test_listener)
	k.handle() or { assert false }

	// The request event listener should have been called
	assert unsafe { kernel_listener_call_count } >= 1
}

fn test_web_lifecycle_kernel_freeze_and_unfreeze() {
	mut k := new_http_kernel()
	unsafe {
		kernel_listener_call_count = 0
	}
	k.on(.request, kernel_test_listener)
	k.freeze_listeners()

	// After freezing, dispatch uses the frozen snapshot
	k.handle() or { assert false }
	assert unsafe { kernel_listener_call_count } >= 1

	// unfreeze() clears the snapshot — dispatch falls back to live listeners
	k.unfreeze()
	unsafe {
		kernel_listener_call_count = 0
	}
	k.handle() or { assert false }
	// Live listener should still be called after unfreeze
	assert unsafe { kernel_listener_call_count } >= 1
}

fn test_web_lifecycle_kernel_off_after_freeze() {
	mut k := new_http_kernel()
	unsafe {
		kernel_listener_call_count = 0
	}
	id := k.on(.request, kernel_test_listener)
	k.freeze_listeners()

	// off() should remove from both live and frozen tables
	k.off(id)
	k.handle() or { assert false }
	assert unsafe { kernel_listener_call_count } == 0
}

fn test_web_lifecycle_kernel_handle_auto_freezes() {
	mut k := new_http_kernel()
	// handle() auto-freezes on first call if not already frozen
	k.handle() or { assert false }

	// After auto-freeze, frozen flag should be true
	k.mu.rlock()
	frozen := k.frozen
	k.mu.runlock()
	assert frozen == true
}

// ============================================================
// UploadChunkManager — background GC + close (HIGH #9)
// ============================================================

fn test_web_lifecycle_upload_gc_starts_and_stops() {
	mut cm := new_chunk_manager()
	// GC goroutine started by new_chunk_manager()
	// close() stops it — if this hangs, the GC is broken
	cm.close()
	// close() is idempotent
	cm.close()
}

fn test_web_lifecycle_upload_init_and_close() {
	mut cm := new_chunk_manager()
	upload_id := cm.init_upload('test.txt', 3, 1024)
	assert upload_id.len > 0
	assert cm.is_complete(upload_id) == false

	cm.close()
}

// ============================================================
// RateLimiter — attempts slice bounded (HIGH #15)
// ============================================================

fn test_web_lifecycle_ratelimit_many_hits_no_crash() {
	mut limiter := new_rate_limiter()
	// Hit many times — the attempts slice should be bounded internally
	// and not crash or grow unbounded
	for _ in 0 .. 1000 {
		limiter.hit('high-traffic-key')
	}
	// Verify the slice is bounded (attempts should not exceed max_attempts_per_key)
	assert limiter.attempts('high-traffic-key') <= max_attempts_per_key
	limiter.clear('high-traffic-key')
}

fn test_web_lifecycle_ratelimit_hit_and_record_bounded() {
	mut limiter := new_rate_limiter()
	for _ in 0 .. 1000 {
		_ = limiter.hit_and_record('bounded-key', 10000, 3600)
	}
	assert limiter.attempts('bounded-key') <= max_attempts_per_key
	limiter.clear('bounded-key')
}

// ============================================================
// FixedWindowLimiter — windows cleanup (HIGH #16)
// ============================================================

fn test_web_lifecycle_fixed_window_cleanup_expired() {
	mut fw := new_fixed_window_limiter()
	// Create many windows with short expiry
	for i in 0 .. 100 {
		_ = fw.check('key-${i}', 10, 1) // 1-second window
	}
	// Wait for windows to expire
	time.sleep(1500 * time.millisecond)
	// cleanup_expired should remove all expired windows
	fw.cleanup_expired()
	// All windows should be expired and removed
	assert fw.windows.len == 0
}

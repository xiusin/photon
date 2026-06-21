module web

// ── Session Tests ──

fn test_new_session() {
	sess := new_session('test-id')
	assert sess.id == 'test-id'
	assert sess.is_new
	assert !sess.is_dirty
	assert sess.data.len == 0
}

fn test_session_set_get() {
	mut sess := new_session('test-id')
	sess.set('user_id', '123')
	assert sess.is_dirty
	val := sess.get('user_id') or { '' }
	assert val == '123'
}

fn test_session_has() {
	mut sess := new_session('test-id')
	assert !sess.has('key')
	sess.set('key', 'value')
	assert sess.has('key')
}

fn test_session_delete() {
	mut sess := new_session('test-id')
	sess.set('key', 'value')
	sess.delete('key')
	assert !sess.has('key')
}

fn test_session_get_missing() {
	sess := new_session('test-id')
	result := sess.get('nonexistent') or { 'default' }
	assert result == 'default'
}

fn test_session_flash() {
	mut sess := new_session('test-id')
	sess.flash('message', 'Hello!')
	assert sess.is_dirty
	assert !sess.has_flash('message') // not in old_flash yet
}

fn test_session_get_flash() {
	mut sess := new_session('test-id')
	// Simulate flash from previous request
	sess.old_flash['message'] = 'Hello from before!'
	assert sess.has_flash('message')
	val := sess.get_flash('message') or { '' }
	assert val == 'Hello from before!'
}

fn test_session_all() {
	mut sess := new_session('test-id')
	sess.set('key1', 'val1')
	sess.set('key2', 'val2')
	all_data := sess.all()
	assert all_data.len == 2
	assert all_data['key1'] == 'val1'
	assert all_data['key2'] == 'val2'
}

fn test_session_clear() {
	mut sess := new_session('test-id')
	sess.set('key1', 'val1')
	sess.clear()
	assert sess.data.len == 0
	assert sess.is_dirty
}

fn test_session_invalidate() {
	mut sess := new_session('test-id')
	sess.set('key1', 'val1')
	sess.invalidate()
	assert sess.is_new
	assert sess.data.len == 0
	assert sess.id != 'test-id' // ID should change
}

fn test_session_regenerate() {
	mut sess := new_session('test-id')
	sess.set('key1', 'val1')
	old_id := sess.id
	sess.regenerate()
	assert sess.id != old_id
	assert sess.is_dirty
	// Data should persist
	val := sess.get('key1') or { '' }
	assert val == 'val1'
}

// ── MemorySessionStore Tests ──

fn test_new_memory_session_store() {
	store := new_memory_session_store()
	assert store.sessions.len == 0
}

fn test_memory_session_store_write_read() {
	mut store := new_memory_session_store()
	mut data := map[string]string{}
	data['user_id'] = '123'
	data['role'] = 'admin'

	store.write('sess-1', data, 1800)!
	read_data := store.read('sess-1')!
	assert read_data['user_id'] == '123'
	assert read_data['role'] == 'admin'
}

fn test_memory_session_store_read_missing() {
	mut store := new_memory_session_store()
	data := store.read('nonexistent')!
	assert data.len == 0
}

fn test_memory_session_store_destroy() {
	mut store := new_memory_session_store()
	mut data := map[string]string{}
	data['key'] = 'val'
	store.write('sess-1', data, 1800)!
	store.destroy('sess-1')!
	read_data := store.read('sess-1')!
	assert read_data.len == 0
}

fn test_memory_session_store_gc() {
	mut store := new_memory_session_store()
	mut data := map[string]string{}
	data['key'] = 'val'
	store.write('sess-1', data, 1800)!

	// GC with max_age=1 should remove entries older than 1 second
	// Since the entry was just written, use a large enough max_age to ensure cleanup
	// Actually test: gc with very small max_age after a tiny sleep, or just use >= comparison
	// The GC condition is: now - updated_at > max_age_seconds
	// With max_age = -1 (or very large), all entries qualify; with 0, only entries where time has passed
	// Let's use -1 to mean "remove everything"
	store.gc(-1)!
	read_data := store.read('sess-1')!
	assert read_data.len == 0
}

// ── SessionManager Tests ──

fn test_new_session_manager() {
	store := new_memory_session_store()
	sm := new_session_manager(store)
	assert sm.cookie_name == 'PHOTON_SESSION'
	assert sm.ttl_seconds == 1800
	assert sm.http_only
}

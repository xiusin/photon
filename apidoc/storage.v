module apidoc

// storage.v — Thread-safe API Documentation Store
//
// Stores entries by reference (map[string]&ApiDocEntry) to support
// mutable access patterns required by the example controllers.

import sync

@[heap]
pub struct ApiDocStore {
pub mut:
	entries map[string]&ApiDocEntry
mut:
	mu sync.Mutex
}

pub fn new_store() &ApiDocStore {
	return &ApiDocStore{
		entries: map[string]&ApiDocEntry{}
	}
}

__global (
	doc_store    &ApiDocStore
	doc_store_mu sync.Mutex
)

pub fn get_store() &ApiDocStore {
	unsafe {
		doc_store_mu.@lock()
		defer { doc_store_mu.unlock() }
		if isnil(doc_store) {
			doc_store = new_store()
		}
		return doc_store
	}
}

// get_entries returns all entries as copies
pub fn (mut s ApiDocStore) get_entries() []ApiDocEntry {
	s.mu.@lock()
	mut result := []ApiDocEntry{cap: s.entries.len}
	for _, ep in s.entries {
		result << *ep
	}
	s.mu.unlock()
	return result
}

// get_entry returns a mutable reference to an entry by ID
pub fn (mut s ApiDocStore) get_entry(id string) !&ApiDocEntry {
	s.mu.@lock()
	ep := s.entries[id] or {
		s.mu.unlock()
		return error('entry not found: ${id}')
	}
	s.mu.unlock()
	return ep
}

// get_or_create_entry returns existing mutable entry or creates a new one
pub fn (mut s ApiDocStore) get_or_create_entry(method string, path string) !&ApiDocEntry {
	s.mu.@lock()
	id := method.to_upper() + '::' + path
	if ep := s.entries[id] {
		s.mu.unlock()
		return ep
	}
	entry := &ApiDocEntry{
		id: id
		method: method.to_upper()
		path: path
	}
	s.entries[id] = entry
	s.mu.unlock()
	return entry
}

// update_entry updates an existing entry (no-op since entries are stored by reference)
pub fn (mut s ApiDocStore) update_entry(id string, entry &ApiDocEntry) ! {
	s.mu.@lock()
	if id !in s.entries {
		s.mu.unlock()
		return error('entry not found')
	}
	// Entry is already stored by reference — mutation is already reflected
	s.mu.unlock()
}

// delete_entry removes an entry
pub fn (mut s ApiDocStore) delete_entry(id string) ! {
	s.mu.@lock()
	if id !in s.entries {
		s.mu.unlock()
		return error('entry not found')
	}
	s.entries.delete(id)
	s.mu.unlock()
}

// lock_endpoint locks or unlocks an endpoint
pub fn (mut s ApiDocStore) lock_endpoint(id string) {
	s.mu.@lock()
	if mut ep := s.entries[id] {
		ep.locked = !ep.locked
	}
	s.mu.unlock()
}

// unlock_endpoint unlocks an endpoint
pub fn (mut s ApiDocStore) unlock_endpoint(id string) {
	s.mu.@lock()
	if mut ep := s.entries[id] {
		ep.locked = false
	}
	s.mu.unlock()
}

// reset clears all entries
pub fn (mut s ApiDocStore) reset() {
	s.mu.@lock()
	s.entries.clear()
	s.mu.unlock()
}

// export_openapi generates a simplified OpenAPI 3.0 JSON
pub fn (mut s ApiDocStore) export_openapi() string {
	s.mu.@lock()
	mut paths := ''

	for _, ep in s.entries {
		path_key := ep.path
		if path_key.len == 0 { continue }
		mut op := '"${ep.method.to_lower()}":{"summary":"${ep.summary}","operationId":"${ep.id}"'
		if ep.parameters.len > 0 {
			mut plist := []string{}
			for p in ep.parameters {
				plist << '{"name":"${p.name}","in":"${p.location}","required":${p.required},"schema":{"type":"${p.type_}"}}'
			}
			op += ',"parameters":[${plist.join(',')}]'
		}
		op += ',"responses":{"200":{"description":"OK"}}'
		op += '}'
		paths += '"${path_key}":{${op}},'
	}
	paths = paths.trim_right(',')

	s.mu.unlock()
	return '{"openapi":"3.0.0","info":{"title":"API Documentation","version":"1.0.0"},"paths":{${paths}}}'
}
